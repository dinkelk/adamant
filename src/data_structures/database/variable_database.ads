with Basic_Types;
with Variable_Serializer;
with Serializer_Types;

--
-- This package implements a constant time access database data structure meant to be used with
-- Adamant variable length packed types. To instantiate the database you must provide four generic parameters:
--    1) Id_Type - a discrete Id type which will be the database key
--    2) T - a type to store on the database (usually a packed record)
--    3) Serialized_Length - a function that when passed T will return the serialized length of T (number of bytes)
--    4) Serialized_Length - a function that when passed a serialized version of T will return the length of T (number of bytes)
--
-- To initialize the component 3 parameters must be passed
--    1) The minimum Id that the database should be able to accommodate
--    2) The maximum Id that the database should be able to accommodate
--
-- The database will be sized to have entries for each possible Id between the minimum and maximum.
--
-- Note: You should NOT use a sparse ID set when using this database data structure or you
-- will be wasting a lot of memory. This database is designed for a compact contiguous Id space to Value mapping.
--
generic
   type Id_Type is (<>); -- Any discrete type: integer, modular, or enumeration.
   type T is private;
   with function Serialized_Length (Src : in T; Num_Bytes_Serialized : out Natural) return Serializer_Types.Serialization_Status;
   with function Serialized_Length (Src : in Basic_Types.Byte_Array; Num_Bytes_Serialized : out Natural) return Serializer_Types.Serialization_Status;
package Variable_Database with SPARK_Mode => On is

   -- The contracts and ghost code in this package exist for proof with
   -- GNATprove only. The assertion policy below disables them at runtime, so
   -- the generated code and the runtime behavior of this package is
   -- identical to what it was before the SPARK conversion. The defensive
   -- pragma Assert statements in the package body are not affected by this
   -- policy. They remain compiled in and enabled under the project wide
   -- assertion policy, and they are also proved.
   pragma Assertion_Policy
      (Pre => Ignore,
       Pre'Class => Ignore,
       Post => Ignore,
       Post'Class => Ignore,
       Contract_Cases => Ignore,
       Ghost => Ignore,
       Loop_Invariant => Ignore,
       Loop_Variant => Ignore,
       Assert_And_Cut => Ignore,
       Assume => Ignore,
       Subprogram_Variant => Ignore);
   pragma Unevaluated_Use_Of_Old (Allow);

   -- Object type:
   type Instance is tagged private;

   -- The state of an entry: Empty until a value is stored, Filled once one
   -- has been, and Override while an override value is in place. An
   -- overridden entry ignores updates and returns the override value until
   -- the override is cleared, which leaves it Filled.
   type Entry_State is (Empty, Filled, Override);

   -- Ghost predicate stating that the database is in a valid, initialized
   -- state: its table has been allocated by Init. This is the precondition
   -- of every operation that touches the table. It takes a class-wide
   -- parameter so that it is not a dispatching operation, which would force
   -- every derived type to override each operation mentioning it
   -- (SPARK RM 6.1.1).
   function Is_Valid (Self : in Instance'Class) return Boolean
      with Ghost;

   -- Ghost functions giving the range of Ids the database was initialized to
   -- hold, and whether an Id is within it:
   function First_Id (Self : in Instance'Class) return Id_Type
      with Ghost,
           Pre => Is_Valid (Self);
   function Last_Id (Self : in Instance'Class) return Id_Type
      with Ghost,
           Pre => Is_Valid (Self);
   function Contains (Self : in Instance'Class; Id : in Id_Type) return Boolean is
      (Id in First_Id (Self) .. Last_Id (Self))
      with Ghost,
           Pre => Is_Valid (Self);

   -- Ghost model of the database: the state of every entry it holds, indexed
   -- by Id. The contracts below describe each operation by its effect on
   -- this model.
   type State_Array is array (Id_Type range <>) of Entry_State
      with Ghost;
   function States (Self : in Instance'Class) return State_Array
      with Ghost,
           -- The database is valid.
           Pre => Is_Valid (Self),
           -- The model covers exactly the Ids held.
           Post => States'Result'First = First_Id (Self) and then States'Result'Last = Last_Id (Self);

   -- Return types:
   type Update_Status is (Success, Id_Out_Of_Range, Serialization_Failure);
   type Fetch_Status is (Success, Id_Out_Of_Range, Data_Not_Available);
   type Clear_Override_Status is (Success, Id_Out_Of_Range);

   -- Object primitives:
   procedure Init (Self : in out Instance; Minimum_Id : in Id_Type; Maximum_Id : in Id_Type)
      with
         -- The database is valid and holds exactly the Ids from Minimum_Id to Maximum_Id.
         Post => Is_Valid (Self)
            and then (for all Id in Id_Type => Contains (Self, Id) = (Id in Minimum_Id .. Maximum_Id))
            and then (for all Id in First_Id (Self) .. Last_Id (Self) => States (Self) (Id) = Empty);
   procedure Destroy (Self : in out Instance);
   function Update (Self : in out Instance; Id : in Id_Type; Value : in T) return Update_Status
      with
         Side_Effects,
         -- The database is valid.
         Pre'Class => Is_Valid (Self),
         -- The database is still valid, holds the same Ids, and the update fails with Id_Out_Of_Range exactly when the Id is not held. No other
         -- entry changes. An overridden entry is left alone and the update reports Success. Otherwise the entry is Filled on Success and its
         -- state is unchanged on Serialization_Failure.
         Post => Is_Valid (Self)
            and then First_Id (Self) = First_Id (Self)'Old and then Last_Id (Self) = Last_Id (Self)'Old
            and then (Update'Result = Id_Out_Of_Range) = (not Contains (Self, Id))
            and then (for all I in First_Id (Self) .. Last_Id (Self) => (if I /= Id then States (Self) (I) = States (Self)'Old (I)))
            and then (if Contains (Self, Id) then
                        (if States (Self)'Old (Id) = Override then Update'Result = Success and then States (Self) (Id) = Override
                         elsif Update'Result = Success then States (Self) (Id) = Filled
                         else States (Self) (Id) = States (Self)'Old (Id)));
   function Fetch (Self : in Instance; Id : in Id_Type; Value : out T) return Fetch_Status
      with
         Side_Effects,
         -- The database is valid.
         Pre'Class => Is_Valid (Self),
         -- The fetch fails with Id_Out_Of_Range exactly when the Id is not held, with Data_Not_Available exactly when the entry is Empty, and
         -- succeeds otherwise.
         Post => (Fetch'Result = Id_Out_Of_Range) = (not Contains (Self, Id))
            and then (if Contains (Self, Id) then (Fetch'Result = Data_Not_Available) = (States (Self) (Id) = Empty));
   pragma Annotate (GNATprove, Intentional, "might not be set", "Value is only meaningful when Fetch returns Success, and callers check the status before using it. There is no value of the private type T to write on the failure paths.");

   -- Backdoor features:
   -- Same as update, but prevents any future updates from changing the underlying value. This
   -- state can be reversed using Clear_Override.
   function Override (Self : in out Instance; Id : in Id_Type; Value : in T) return Update_Status
      with
         Side_Effects,
         -- The database is valid.
         Pre'Class => Is_Valid (Self),
         -- The database is still valid, holds the same Ids, and the override fails with Id_Out_Of_Range exactly when the Id is not held. No other
         -- entry changes. On Success the entry is Override, otherwise its state is unchanged.
         Post => Is_Valid (Self)
            and then First_Id (Self) = First_Id (Self)'Old and then Last_Id (Self) = Last_Id (Self)'Old
            and then (Override'Result = Id_Out_Of_Range) = (not Contains (Self, Id))
            and then (for all I in First_Id (Self) .. Last_Id (Self) => (if I /= Id then States (Self) (I) = States (Self)'Old (I)))
            and then (if Contains (Self, Id) then
                        (if Override'Result = Success then States (Self) (Id) = Override else States (Self) (Id) = States (Self)'Old (Id)));
   -- Allow future updates to take effect again.
   function Clear_Override (Self : in out Instance; Id : in Id_Type) return Clear_Override_Status
      with
         Side_Effects,
         -- The database is valid.
         Pre'Class => Is_Valid (Self),
         -- The database is still valid, holds the same Ids, and the clear succeeds exactly when the Id is held. No other entry changes. The
         -- entry is Filled if it held a value, whether overridden or not, and stays Empty otherwise.
         Post => Is_Valid (Self)
            and then First_Id (Self) = First_Id (Self)'Old and then Last_Id (Self) = Last_Id (Self)'Old
            and then (Clear_Override'Result = Success) = Contains (Self, Id)
            and then (for all I in First_Id (Self) .. Last_Id (Self) => (if I /= Id then States (Self) (I) = States (Self)'Old (I)))
            and then (if Contains (Self, Id) then
                        States (Self) (Id) = (if States (Self)'Old (Id) = Empty then Empty else Filled));
   -- Clear_Override for all entries in the database.
   procedure Clear_Override_All (Self : in out Instance)
      with
         -- The database is valid.
         Pre'Class => Is_Valid (Self),
         -- The database is still valid and holds the same Ids, no entry is overridden any more, and every entry that held a value still does.
         Post => Is_Valid (Self) and then First_Id (Self) = First_Id (Self)'Old and then Last_Id (Self) = Last_Id (Self)'Old
            and then (for all I in First_Id (Self) .. Last_Id (Self) =>
                        States (Self) (I) = (if States (Self)'Old (I) = Empty then Empty else Filled));
   -- Returns True if any entries are currently being overridden.
   function Any_Overridden (Self : in Instance) return Boolean
      with
         -- The database is valid.
         Pre'Class => Is_Valid (Self),
         -- True exactly when some entry is overridden.
         Post => Any_Overridden'Result = (for some I in First_Id (Self) .. Last_Id (Self) => States (Self) (I) = Override);

private

   -- Instantiate the variable serializer for our type. Its declarations are in
   -- SPARK and its body, which overlays byte arrays by address, is not
   -- analyzed, so SPARK treats its operations as trusted boundary operations.
   package T_Serializer is new Variable_Serializer (T, Serialized_Length, Serialized_Length);
   -- The storage for one serialized value, sized to hold the largest T:
   subtype Entry_Bytes is T_Serializer.Byte_Array;

   -- Serialize a value into an entry's storage:
   function Store (Data : out Entry_Bytes; Value : in T) return Serializer_Types.Serialization_Status
      with Side_Effects;
   -- Deserialize a value from an entry's storage:
   function Load (Value : out T; Data : in Entry_Bytes) return Serializer_Types.Serialization_Status
      with Side_Effects;

   -- State of a data base entry:
   -- Empty - The database entry has not been stored to yet.
   -- Filled - The database entry has been stored to.
   -- Override - The database entry has been overridden.

   -- An entry into the database. It stores the value as well as the
   -- valid/invalid status. A value is valid if it has been successfully
   -- stored.
   type Database_Entry is record
      State : Entry_State := Empty;
      Data : Entry_Bytes := [others => 0];
   end record;

   -- Database table type which maps the index type (unconstrained)
   -- to a database entry type:
   type Database_Table is array (Id_Type range <>) of Database_Entry;
   type Database_Table_Access is access Database_Table;

   -- The object instance record:
   type Instance is tagged record
      Db_Table : Database_Table_Access := null;
   end record;

   -- Ghost model completions:
   function Is_Valid (Self : in Instance'Class) return Boolean is
      (Self.Db_Table /= null and then Self.Db_Table'First in Id_Type and then Self.Db_Table'Last in Id_Type);
   function First_Id (Self : in Instance'Class) return Id_Type is (Self.Db_Table'First);
   function Last_Id (Self : in Instance'Class) return Id_Type is (Self.Db_Table'Last);
   function States (Self : in Instance'Class) return State_Array is
      [for Id in Self.Db_Table'Range => Self.Db_Table (Id).State];

end Variable_Database;

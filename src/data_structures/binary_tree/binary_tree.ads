--
-- Generic binary tree package which has O(n) insertion/removal time and
-- O(log n) search time.
--
-- This binary tree package is optimized to have the fastest look
-- up time possible. It uses a sorted array of elements under the
-- hood so lookups only require integer related math to determine
-- the next index to look at, as opposed to actually traversing
-- the elements of a tree. As a result, insertions take a while because
-- the tree must remain sorted. Insertions may require a lot of
-- copies, moving elements around in the underlying array to ensure
-- the sorted property. As such, this tree is best used when insertions
-- only need to occur once at program startup, and during the rest of
-- the program execution, only look ups are used.
--
-- Removal of elements is done in a similar way to insertion, and takes
-- O(n) time.
--
-- If you need fast insertion/removal time into the binary tree, you should
-- not use this binary tree package, as these operations could get cripplingly
-- slow as the value of N gets very large.
--
-- To instantiate the generic binary tree you must define the type as
-- well as two functions the compare "less than" and "greater than" of
-- the type and return a boolean stating whether the condition is
-- True or False.
--
-- The functional correctness proof of this package assumes that "<" is a
-- strict weak ordering of Element_Type and that ">" is its converse, which
-- is what any sensible pair of comparison operators provides. Precisely:
--
--    not (A < B and then B < A)                       ("<" is asymmetric)
--    not (B < A) and not (C < B) implies not (C < A)  ("not <" is transitive)
--    (A > B) = (B < A)                                (">" is the converse)
--
-- Two elements neither of which is less than the other are equivalent, and
-- Search treats equivalent elements as matches. These properties cannot be
-- expressed as contracts on the generic formal operators, so they are stated
-- as ghost lemmas in the Binary_Tree.Lemmas child package and assumed there.
--
generic
   type Element_Type is private;
   with function "<" (Left, Right : Element_Type) return Boolean is <>;
   with function ">" (Left, Right : Element_Type) return Boolean is <>;
package Binary_Tree with SPARK_Mode => On is

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

   type Instance is tagged limited private;
   type Instance_Access is access all Instance;

   -- Maximum tree capacity supported by the proof. The binary search steps
   -- its bounds one past the probed index, so this bound keeps that
   -- arithmetic within Integer. All realistic trees are far below this bound.
   -- Trees larger than this are outside the verified domain and behave as
   -- they did before the SPARK conversion.
   Max_Tree_Size : constant := Positive'Last - 1;

   --
   -- Ghost model. Everything in this section exists for proof only and is
   -- never executed at runtime.
   --

   -- Ghost predicate stating that the tree is in a valid, initialized state:
   -- storage has been allocated by Init and the number of elements held
   -- fits within that storage. This is the precondition of every operation
   -- that touches the element storage. It takes a class-wide parameter so
   -- that it is not a dispatching operation, which would force every derived
   -- type to override each operation mentioning it (SPARK RM 6.1.1).
   function Is_Valid (Self : in Instance'Class) return Boolean
      with Ghost;

   -- The sequence of elements held by a tree, in index order. Index 1 is the
   -- first element in the tree and Get_Size (Self) is the last:
   type Element_Sequence is array (Positive range <>) of Element_Type
      with Ghost;

   -- Two elements are equivalent when neither orders before the other. This
   -- is the notion of "match" used by Search:
   function Equivalent (Left, Right : in Element_Type) return Boolean is
      (not (Left < Right) and then not (Right < Left))
      with Ghost;

   -- A sequence is sorted when no element orders before an element ahead of
   -- it. Equivalent elements may appear in any order relative to each other:
   function Is_Sorted (Sequence : in Element_Sequence) return Boolean is
      (for all I in Sequence'Range =>
         (for all J in Sequence'Range =>
            (if I < J then not (Sequence (J) < Sequence (I)))))
      with Ghost;

   -- The elements currently held by the tree, in index order:
   function Model (Self : in Instance'Class) return Element_Sequence
      with
         Ghost,
         -- The tree is valid.
         Pre => Is_Valid (Self),
         -- The sequence is indexed from 1 up to the number of elements held.
         Post => Model'Result'First = 1 and then Model'Result'Last = Get_Size (Instance (Self));

   -- Ghost predicate stating that the elements held by the tree are sorted.
   -- Init establishes this and every operation preserves it, so Search is
   -- always performed on a sorted sequence:
   function Is_Sorted (Self : in Instance'Class) return Boolean is
      (Is_Sorted (Model (Self)))
      with
         Ghost,
         -- The tree is valid.
         Pre => Is_Valid (Self);

   --
   -- Operations:
   --

   -- Allocate storage for the tree. The tree must be empty, as it is when
   -- default initialized or after Clear or Destroy.
   procedure Init (Self : in out Instance; Maximum_Size : in Positive)
      with
         -- The tree holds no elements and the requested capacity is within the verified maximum.
         Pre'Class => Get_Size (Self) = 0 and then Maximum_Size <= Max_Tree_Size,
         -- The tree is valid, still holds no elements, has the requested capacity, and is trivially sorted.
         Post => Is_Valid (Self)
            and then Get_Size (Self) = 0
            and then Get_Capacity (Self) = Maximum_Size
            and then Is_Sorted (Self);
   -- Release the tree storage when testing and empty the tree.
   procedure Destroy (Self : in out Instance)
      with
         -- The tree holds no elements.
         Post => Get_Size (Self) = 0;

   -- Add element to tree. This is done in O(n) time where n is the current size of the tree.
   -- Return: True means add was successful. False means there is no more room in the tree.
   function Add (Self : in out Instance; Element : in Element_Type) return Boolean
      with
         Side_Effects,
         -- The tree is valid and sorted.
         Pre'Class => Is_Valid (Self) and then Is_Sorted (Self),
         -- The tree is still valid and sorted with the same capacity, the add succeeds exactly when
         -- there was room, and on success the size grew by one and the element sits at some position
         -- with the elements before it unchanged and those after it moved up by one, otherwise
         -- nothing changed.
         Post => Is_Valid (Self)
            and then Get_Capacity (Self) = Get_Capacity (Self)'Old
            and then Add'Result = (Get_Size (Self)'Old < Get_Capacity (Self))
            and then (if Add'Result then Get_Size (Self) = Get_Size (Self)'Old + 1 else Get_Size (Self) = Get_Size (Self)'Old)
            and then Is_Sorted (Self)
            and then (if Add'Result then
                        (for some Position in 1 .. Get_Size (Self) =>
                           Model (Self) (Position) = Element
                              and then (for all I in 1 .. Position - 1 => Model (Self) (I) = Model (Self)'Old (I))
                              and then (for all I in Position + 1 .. Get_Size (Self) => Model (Self) (I) = Model (Self)'Old (I - 1)))
                      else Model (Self) = Model (Self)'Old);
   -- Remove element from tree. This is done in O(n) time where n is the current size of the tree.
   -- Return: True means remove was successful. False means the provided index is not found in the tree.
   function Remove (Self : in out Instance; Element_Index : in Positive) return Boolean
      with
         Side_Effects,
         -- The tree is valid and sorted.
         Pre'Class => Is_Valid (Self) and then Is_Sorted (Self),
         -- The tree is still valid and sorted with the same capacity, the remove succeeds exactly when
         -- the index was within the size, and on success the size shrank by one with the elements
         -- before the index unchanged and those after it moved down by one, otherwise nothing changed.
         Post => Is_Valid (Self)
            and then Get_Capacity (Self) = Get_Capacity (Self)'Old
            and then Remove'Result = (Element_Index <= Get_Size (Self)'Old)
            and then (if Remove'Result then Get_Size (Self) = Get_Size (Self)'Old - 1 else Get_Size (Self) = Get_Size (Self)'Old)
            and then Is_Sorted (Self)
            and then (if Remove'Result then
                        (for all I in 1 .. Element_Index - 1 => Model (Self) (I) = Model (Self)'Old (I))
                           and then (for all I in Element_Index .. Get_Size (Self) => Model (Self) (I) = Model (Self)'Old (I + 1))
                      else Model (Self) = Model (Self)'Old);
   -- Search for element in tree. This is done in O(log n) where n is the current size of the tree.
   -- Return: True means element was found. False means it was not. The element and index in the array where it was found are also returned.
   function Search (Self : in Instance; Element : in Element_Type; Element_Found : out Element_Type; Element_Index : out Positive) return Boolean
      with
         Side_Effects,
         -- The tree is valid and sorted.
         Pre'Class => Is_Valid (Self) and then Is_Sorted (Self),
         -- The search succeeds exactly when the tree holds an element equivalent to the one searched
         -- for, and on success the returned index is within the size and the returned element is the
         -- equivalent element held there, otherwise the returned index is the sentinel value 1 and
         -- the returned element is the one searched for.
         Post => Search'Result = (for some I in 1 .. Get_Size (Self) => Equivalent (Model (Self) (I), Element))
            and then (if Search'Result then
                        Element_Index <= Get_Size (Self)
                           and then Element_Found = Model (Self) (Element_Index)
                           and then Equivalent (Element_Found, Element)
                      else Element_Index = 1 and then Element_Found = Element);
   -- Get an element via its index. This can be helpful to quickly retrieve an element in O(1) time if you have already obtained its index via "search".
   function Get (Self : in Instance; Element_Index : in Positive) return Element_Type
      with
         -- The tree is valid and the index is within the size.
         Pre'Class => Is_Valid (Self) and then Element_Index <= Get_Size (Self),
         -- The result is the element held at that index.
         Post => Get'Result = Model (Self) (Element_Index);
   -- Set an element via its index. This can be helpful to quickly set an element in O(1) time if you have already obtained its index via "search".
   -- To keep the tree sorted, the new element must not order before its
   -- predecessor nor after its successor. Replacing an element with an
   -- equivalent one, which is the typical use, always satisfies this.
   procedure Set (Self : in out Instance; Element_Index : in Positive; Element : in Element_Type)
      with
         -- The tree is valid and sorted, the index is within the size, and the new element is not
         -- less than its predecessor nor greater than its successor.
         Pre'Class => Is_Valid (Self)
            and then Is_Sorted (Self)
            and then Element_Index <= Model (Self)'Last
            and then (Element_Index = 1 or else not (Element < Model (Self) (Element_Index - 1)))
            and then (Element_Index = Model (Self)'Last or else not (Model (Self) (Element_Index + 1) < Element)),
         -- The tree is still valid and sorted with the same size and capacity, the new element is
         -- held at the index, and every other element is unchanged.
         Post => Is_Valid (Self)
            and then Get_Size (Self) = Get_Size (Self)'Old
            and then Get_Capacity (Self) = Get_Capacity (Self)'Old
            and then Is_Sorted (Self)
            and then Model (Self) (Element_Index) = Element
            and then (for all I in 1 .. Get_Size (Self) => (if I /= Element_Index then Model (Self) (I) = Model (Self)'Old (I)));
   -- Clear the tree. This is done in O(1) time.
   procedure Clear (Self : in out Instance)
      with
         -- The tree is valid.
         Pre'Class => Is_Valid (Self),
         -- The tree is still valid with the same capacity, holds no elements, and is trivially sorted.
         Post => Is_Valid (Self)
            and then Get_Size (Self) = 0
            and then Get_Capacity (Self) = Get_Capacity (Self)'Old
            and then Is_Sorted (Self);
   -- Get functions:
   function Get_Size (Self : in Instance) return Natural;
   function Get_Capacity (Self : in Instance) return Positive
      with
         -- The tree is valid.
         Pre'Class => Is_Valid (Self);
   -- Functions to get the first and last index in the tree. If the tree is empty, then first returns 1 and last returns 0.
   function Get_First_Index (Self : in Instance) return Positive
      with
         -- The tree is valid.
         Pre'Class => Is_Valid (Self),
         -- The first index is always 1.
         Post => Get_First_Index'Result = 1;
   function Get_Last_Index (Self : in Instance) return Natural
      with
         -- The last index is the number of elements held.
         Post => Get_Last_Index'Result = Get_Size (Self);

private
   type Element_Array is array (Positive range <>) of Element_Type;
   type Element_Array_Access is access Element_Array;

   type Instance is tagged limited record
      Size : Natural := 0;
      -- A sorted list of elements that can be easily used for
      -- an O(log n) search.
      Tree : Element_Array_Access := null;
   end record;

   -- Ghost model completion. Storage is allocated, starts at index 1, holds
   -- at least one element and no more than the verified maximum, and the
   -- number of elements in the tree never exceeds the storage:
   function Is_Valid (Self : in Instance'Class) return Boolean is
      (Self.Tree /= null
         and then Self.Tree'First = 1
         and then Self.Tree'Last >= 1
         and then Self.Tree'Last <= Max_Tree_Size
         and then Self.Size <= Self.Tree'Last);

   -- The model is the used prefix of the storage:
   function Model (Self : in Instance'Class) return Element_Sequence is
      (Element_Sequence (Self.Tree (1 .. Self.Size)));

   -- Expression function completions, so that the proof can see through
   -- these accessors when they appear in the contracts above:
   function Get_Size (Self : in Instance) return Natural is (Self.Size);
   function Get_Capacity (Self : in Instance) return Positive is (Self.Tree'Length);

end Binary_Tree;

with Example_Array;
with Example_Array.Representation;
with Example_Array.C;
with Interfaces;

-- This example shows a generated packed array being used from SPARK code:
-- indexing, aggregates, serialization, validation, the string representation
-- and the C interface. As with packed records, the generated packages are used
-- as ordinary Ada packages and this package is proved against them.
package Spark_Packed_Array with SPARK_Mode => On is

   use type Example_Array.T;

   -- The contracts in this package exist for proof with GNATprove only. The
   -- assertion policy below disables them at runtime.
   pragma Assertion_Policy
      (Pre => Ignore,
       Post => Ignore,
       Contract_Cases => Ignore,
       Ghost => Ignore,
       Loop_Invariant => Ignore,
       Loop_Variant => Ignore,
       Assert_And_Cut => Ignore,
       Assume => Ignore);

   -- Construct an array with every element set to one value:
   function Filled (Value : in Example_Array.Short_Int) return Example_Array.T is
      ([others => Value]);

   -- Read and write elements:
   function Get (Arr : in Example_Array.T; Index : in Example_Array.Constrained_Index_Type) return Example_Array.Short_Int is (Arr (Index));
   procedure Set (Arr : in out Example_Array.T; Index : in Example_Array.Constrained_Index_Type; Value : in Example_Array.Short_Int)
      with
         -- The element is set and the others keep their values.
         Post => Arr (Index) = Value and then (for all I in Arr'Range => (if I /= Index then Arr (I) = Arr'Old (I)));

   -- Sum every element. The element range and array length bound the result.
   function Sum (Arr : in Example_Array.T) return Natural
      with
         -- The sum is no more than the length times the largest element.
         Post => Sum'Result <= Example_Array.Length * Example_Array.Short_Int'Last;

   -- Serialize the array into a byte array:
   function To_Bytes (Arr : in Example_Array.T) return Example_Array.Serialization.Byte_Array is
      (Example_Array.Serialization.To_Byte_Array (Arr));

   -- Validate a byte array and deserialize it if it holds a valid array:
   procedure From_Bytes (Bytes : in Example_Array.Serialization.Byte_Array; Arr : out Example_Array.T; Valid : out Boolean; Errant_Field : out Interfaces.Unsigned_32)
      with
         -- A valid byte array deserializes to the array it holds.
         Post => (if Valid then Arr = Example_Array.Serialization.From_Byte_Array (Bytes));

   -- Human readable form of the array:
   function Image (Arr : in Example_Array.T) return String is
      (Example_Array.Representation.Image (Arr));

   -- Convert to the C compatible array and back:
   function To_C (Arr : in Example_Array.T) return Example_Array.C.U_C is
      (Example_Array.C.Unpack (Arr));
   function From_C (Arr : in Example_Array.C.U_C) return Example_Array.T is
      (Example_Array.C.Pack (Arr));

end Spark_Packed_Array;

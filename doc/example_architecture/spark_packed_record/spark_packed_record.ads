with Example_Record;
with Example_Record.Validation;
with Example_Record.Representation;
with Example_Record.C;
with Example_Variable_Record;
with Basic_Types;
with Serializer_Types;
with Interfaces;

-- This example shows every part of a generated packed record being used from
-- SPARK code: the record itself, endianness conversion, serialization and
-- deserialization, validation, the string representation, the C interface
-- and the variable length record serializer. The generated Assertion package
-- is also callable from SPARK, but it depends on the unit test framework, so
-- it belongs in SPARK test code rather than here. The
-- generated packages are not themselves analyzed by GNATprove (their bodies
-- overlay byte arrays, which is outside the SPARK memory model), so they are
-- used as ordinary Ada packages whose declarations are in SPARK, and this
-- package is proved against them.
package Spark_Packed_Record with SPARK_Mode => On is

   use type Example_Record.T;
   use type Example_Record.My_Color;
   use type Example_Record.Five_Bit_Integer;

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

   -------------------------------------------------------------------------
   -- The record itself: construction, field access, comparison
   -------------------------------------------------------------------------

   -- Read a field of the packed record:
   function Get_Color (Item : in Example_Record.T) return Example_Record.My_Color is (Item.Value_3);

   -- Construct a packed record with an aggregate:
   function Make (Value_1 : in Example_Record.Five_Bit_Integer; Value_2 : in Example_Record.Three_Bit_Signed_Integer; Color : in Example_Record.My_Color; Value_4 : in Short_Float) return Example_Record.T is
      ((Value_1 => Value_1, Value_2 => Value_2, Value_3 => Color, Value_4 => Value_4));

   -- Update one field, leaving the rest untouched:
   procedure Set_Color (Item : in out Example_Record.T; Color : in Example_Record.My_Color)
      with
         -- The color is set and the other fields keep their values.
         Post => Item.Value_3 = Color and then Item.Value_1 = Item.Value_1'Old and then Item.Value_2 = Item.Value_2'Old;

   -------------------------------------------------------------------------
   -- Packing and endianness
   -------------------------------------------------------------------------

   -- Convert between the packed (T) and unpacked (U) forms and back:
   function Repack (Item : in Example_Record.T) return Example_Record.T is
      (Example_Record.Pack (Example_Record.Unpack (Item)));

   -- Convert to the little endian form and back:
   function Round_Trip_Endianness (Item : in Example_Record.T) return Example_Record.T is
      (Example_Record.Swap_Endianness (Example_Record.Swap_Endianness (Item)));

   -------------------------------------------------------------------------
   -- Serialization and validation
   -------------------------------------------------------------------------

   -- Serialize the record into a byte array:
   function To_Bytes (Item : in Example_Record.T) return Example_Record.Serialization.Byte_Array;

   -- Validate a byte array and deserialize it if it holds a valid record:
   procedure From_Bytes (Bytes : in Example_Record.Serialization.Byte_Array; Item : out Example_Record.T; Valid : out Boolean; Errant_Field : out Interfaces.Unsigned_32)
      with
         -- A valid byte array deserializes to the record it holds.
         Post => (if Valid then Item = Example_Record.Serialization.From_Byte_Array (Bytes));

   -- Serialize into a caller provided buffer that may be larger than the record, returning the
   -- number of bytes written:
   procedure To_Bytes_Unchecked (Item : in Example_Record.T; Dest : out Basic_Types.Byte_Array; Num_Bytes : out Natural)
      with
         -- The buffer is large enough to hold the record.
         Pre => Dest'Length >= Example_Record.Size_In_Bytes;

   -- The number of bytes the record serializes to, as reported by the generated length function:
   function Serialized_Length (Item : in Example_Record.T) return Natural
      with Side_Effects;

   -- Extract one field of a serialized record as a poly type, without deserializing the rest:
   function Get_Field (Bytes : in Example_Record.Serialization.Byte_Array; Field : in Interfaces.Unsigned_32) return Basic_Types.Poly_Type is
      (Example_Record.Validation.Get_Field (Bytes, Field));

   -------------------------------------------------------------------------
   -- Representation
   -------------------------------------------------------------------------

   -- Human readable forms of the record:
   function Image (Item : in Example_Record.T) return String is
      (Example_Record.Representation.Image (Item));
   function To_Tuple_String (Item : in Example_Record.T) return String is
      (Example_Record.Representation.To_Tuple_String (Item));
   function To_Byte_String (Item : in Example_Record.T) return String is
      (Example_Record.Representation.To_Byte_String (Item));

   -------------------------------------------------------------------------
   -- C interface
   -------------------------------------------------------------------------

   -- Convert to the C compatible record and back:
   function To_C (Item : in Example_Record.T) return Example_Record.C.U_C is
      (Example_Record.C.Unpack (Item));
   function From_C (Item : in Example_Record.C.U_C) return Example_Record.T is
      (Example_Record.C.Pack (Item));

   -------------------------------------------------------------------------
   -- Variable length records
   -------------------------------------------------------------------------

   -- The number of bytes a variable length record serializes to, which depends on its
   -- Length field:
   function Variable_Serialized_Length (Item : in Example_Variable_Record.T; Num_Bytes : out Natural) return Serializer_Types.Serialization_Status
      with Side_Effects;

   -- Serialize a variable length record into a caller provided buffer:
   function Variable_To_Bytes (Item : in Example_Variable_Record.T; Dest : out Basic_Types.Byte_Array; Num_Bytes : out Natural) return Serializer_Types.Serialization_Status
      with Side_Effects;

   -- Deserialize a variable length record from a byte array:
   function Variable_From_Bytes (Bytes : in Basic_Types.Byte_Array; Item : out Example_Variable_Record.T; Num_Bytes : out Natural) return Serializer_Types.Serialization_Status
      with Side_Effects;

end Spark_Packed_Record;

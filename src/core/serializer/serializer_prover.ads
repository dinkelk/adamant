-- GNATprove analyzes a generic only through an instantiation, so this
-- package exists to give Serializer and Variable_Serializer instances to
-- analyze, which verifies that their declarations are legal SPARK and can
-- be called from SPARK code. It is not used by any other code.
with Basic_Types;
with Serializer;
with Variable_Serializer;
with Serializer_Types;

package Serializer_Prover with SPARK_Mode => On is

   -- The contracts in this package exist for proof with GNATprove only. The
   -- assertion policy below disables them at runtime.
   pragma Assertion_Policy (Pre => Ignore, Post => Ignore);

   -- A simple fixed size type to serialize:
   -- The size clauses matter: SPARK accepts an overlay of a value only when the
   -- size of its type is known at compile time, as it is for generated packed types.
   type Example_Record is record
      A : Basic_Types.Byte;
      B : Basic_Types.Byte;
   end record
      with Size => 16, Object_Size => 16;

   package Example_Serializer is new Serializer (Example_Record);

   -- Serialize a value and deserialize it again:
   function Round_Trip (Value : in Example_Record) return Example_Record;

   -- Serialize into a caller provided buffer that may be larger than the value:
   procedure Store (Value : in Example_Record; Dest : out Basic_Types.Byte_Array; Num_Bytes : out Natural)
      with
         -- The buffer is exactly one serialized value long.
         Pre => Dest'Length = Example_Serializer.Serialized_Length;

   -- The length functions a variable length type provides. This example type
   -- always serializes to its full size.
   function Example_Length (Src : in Example_Record; Num_Bytes_Serialized : out Natural) return Serializer_Types.Serialization_Status
      with Side_Effects;
   function Example_Length (Src : in Basic_Types.Byte_Array; Num_Bytes_Serialized : out Natural) return Serializer_Types.Serialization_Status
      with Side_Effects;

   package Example_Variable_Serializer is new Variable_Serializer (Example_Record, Example_Length, Example_Length);

   -- Serialize a value with the variable length serializer:
   function Variable_Store (Value : in Example_Record; Dest : out Basic_Types.Byte_Array; Num_Bytes : out Natural) return Serializer_Types.Serialization_Status
      with Side_Effects, Relaxed_Initialization => Dest;

   -- Deserialize a value with the variable length serializer:
   function Variable_Load (Bytes : in Basic_Types.Byte_Array; Value : out Example_Record; Num_Bytes : out Natural) return Serializer_Types.Serialization_Status
      with Side_Effects;

end Serializer_Prover;

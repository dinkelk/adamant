with Double_Buffer_Store;
with Double_Buffer_Store_Typed;
with Double_Buffer_Store_Types;
with Packed_U32;

-- This package exists solely so that GNATprove analyzes an instance of the generic
-- Double_Buffer_Store and Double_Buffer_Store_Typed packages, since GNATprove
-- analyzes generics only at their instantiation points. Real instantiations elsewhere
-- in a project are verified at their own instantiation points when they occur in
-- SPARK analyzed code. Nothing references this package, so it contributes no code to
-- any build.
package Double_Buffer_Store_Prover with SPARK_Mode => On is

   -- Representative copies for a byte level store of eight bytes of data. Bounds are
   -- static so the objects may live at library level under Ravenscar:
   Bytes_Copy_A : Double_Buffer_Store_Types.Persistent_Bytes (0 .. Double_Buffer_Store_Types.Header_Length + 8 - 1) := [others => 0];
   Bytes_Copy_B : Double_Buffer_Store_Types.Persistent_Bytes (0 .. Double_Buffer_Store_Types.Header_Length + 8 - 1) := [others => 0];
   package Example_Bytes_Store is new Double_Buffer_Store (
      Region_A => Bytes_Copy_A,
      Region_B => Bytes_Copy_B,
      Layout_Id => 16#0000_0001#,
      Data_Length => 8
   );

   -- Representative copies for a typed store over a packed record, the shape that
   -- components store:
   Typed_Copy_A : Double_Buffer_Store_Types.Persistent_Bytes (0 .. Double_Buffer_Store_Types.Header_Length + Packed_U32.Size_In_Bytes - 1) := [others => 0];
   Typed_Copy_B : Double_Buffer_Store_Types.Persistent_Bytes (0 .. Double_Buffer_Store_Types.Header_Length + Packed_U32.Size_In_Bytes - 1) := [others => 0];
   package Example_Typed_Store is new Double_Buffer_Store_Typed (
      Region_A => Typed_Copy_A,
      Region_B => Typed_Copy_B,
      T => Packed_U32.T,
      Serialized_Length => Packed_U32.Size_In_Bytes,
      To_Byte_Array => Packed_U32.Serialization.To_Byte_Array,
      From_Byte_Array => Packed_U32.Serialization.From_Byte_Array,
      Layout_Version => 1
   );

end Double_Buffer_Store_Prover;

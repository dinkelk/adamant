with Double_Buffer_Store.Typed;
with Packed_U32;

-- This package exists solely so that GNATprove analyzes an instance of the
-- generic Double_Buffer_Store.Typed package, since GNATprove analyzes generics
-- only at their instantiation points. Real instantiations elsewhere in a project
-- are verified at their own instantiation points when they occur in SPARK
-- analyzed code. Nothing references this package, so it contributes no code to
-- any build.
package Double_Buffer_Store_Prover with SPARK_Mode => On is

   -- A representative instantiation on a packed record, the shape that components
   -- store:
   package Example_Store is new Double_Buffer_Store.Typed (
      T => Packed_U32.T,
      Serialized_Length => Packed_U32.Size_In_Bytes,
      To_Byte_Array => Packed_U32.Serialization.To_Byte_Array,
      From_Byte_Array => Packed_U32.Serialization.From_Byte_Array,
      Layout_Version => 1
   );

end Double_Buffer_Store_Prover;

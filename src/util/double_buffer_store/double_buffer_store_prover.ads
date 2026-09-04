with Double_Buffer_Store;
with Packed_U32;

-- This package exists solely so that GNATprove analyzes an instance of the generic
-- Double_Buffer_Store package and its inner Bound generic, since GNATprove analyzes
-- generics only at their instantiation points. Real instantiations elsewhere in a
-- project are verified at their own instantiation points when they occur in SPARK
-- analyzed code. Nothing references this package, so it contributes no code to any
-- build.
package Double_Buffer_Store_Prover with SPARK_Mode => On is

   -- A representative store over a packed record, the shape that components store,
   -- bound to two regions standing in for persistent memory:
   package Example_Layout is new Double_Buffer_Store (Packed_U32.T);
   Region_A : Example_Layout.Persistent_Copy;
   Region_B : Example_Layout.Persistent_Copy;
   package Example_Store is new Example_Layout.Bound (Region_A, Region_B);

end Double_Buffer_Store_Prover;

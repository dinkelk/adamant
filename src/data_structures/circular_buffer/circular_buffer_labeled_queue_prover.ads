with Circular_Buffer.Labeled_Queue;
with Interfaces;

-- This package exists solely so that GNATprove analyzes an instance of the
-- generic Circular_Buffer.Labeled_Queue package, since GNATprove analyzes
-- generics only at their instantiation points. Real instantiations elsewhere
-- in a project are verified at their own instantiation points when they
-- occur in SPARK analyzed code. Nothing references this package, so it
-- contributes no code to any build.
package Circular_Buffer_Labeled_Queue_Prover with SPARK_Mode => On is

   -- A representative label, similar in shape to the packed record types
   -- that labeled queues typically store:
   type Example_Label is record
      Id : Interfaces.Unsigned_16 := 0;
      Kind : Interfaces.Unsigned_16 := 0;
   end record;

   package Example_Labeled_Queue is new Circular_Buffer.Labeled_Queue (Example_Label);

end Circular_Buffer_Labeled_Queue_Prover;

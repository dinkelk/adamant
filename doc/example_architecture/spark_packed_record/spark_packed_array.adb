with Example_Array.Validation;

package body Spark_Packed_Array with SPARK_Mode => On is

   procedure Set (Arr : in out Example_Array.T; Index : in Example_Array.Constrained_Index_Type; Value : in Example_Array.Short_Int) is
   begin
      Arr (Index) := Value;
   end Set;

   function Sum (Arr : in Example_Array.T) return Natural is
      Total : Natural := 0;
   begin
      for Index in Arr'Range loop
         -- The running total is bounded by the elements added so far.
         pragma Loop_Invariant (Total <= Index * Example_Array.Short_Int'Last);
         Total := Total + Natural (Arr (Index));
      end loop;
      return Total;
   end Sum;

   procedure From_Bytes (Bytes : in Example_Array.Serialization.Byte_Array; Arr : out Example_Array.T; Valid : out Boolean; Errant_Field : out Interfaces.Unsigned_32) is
   begin
      Valid := Example_Array.Validation.Valid (Bytes, Errant_Field);
      if Valid then
         Arr := Example_Array.Serialization.From_Byte_Array (Bytes);
      else
         Arr := [others => Example_Array.Short_Int'First];
      end if;
   end From_Bytes;

end Spark_Packed_Array;

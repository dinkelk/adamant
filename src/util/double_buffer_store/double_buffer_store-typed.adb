with Byte_Array_Util;

package body Double_Buffer_Store.Typed with SPARK_Mode => On is

   -- The serialized form of T, sized by the instantiator's Serialized_Length:
   subtype Data_Index_Type is Natural range 0 .. Serialized_Length - 1;
   subtype Data_Type is Basic_Types.Byte_Array (Data_Index_Type);

   function Is_Valid (Copy : in Basic_Types.Byte_Array) return Boolean is
   begin
      return Is_Valid (Copy, Layout_Id, Serialized_Length);
   end Is_Valid;

   procedure Save (
      Bytes_A : in out Basic_Types.Byte_Array;
      Bytes_B : in out Basic_Types.Byte_Array;
      Value : in T;
      Save_Time : in Sys_Time.T;
      Info : out Copy_Info
   ) is
      -- Copy the serialized value into a buffer of the declared length. This keeps
      -- the length passed to the store fixed even if the instantiator's serialization
      -- function returns a differently sized array by mistake.
      Data : Data_Type := [others => 0];
   begin
      Byte_Array_Util.Safe_Left_Copy (Data, To_Byte_Array (Value));
      Save (Bytes_A, Bytes_B, Data, Layout_Id, Save_Time, Info);
   end Save;

   procedure Restore (
      Bytes_A : in Basic_Types.Byte_Array;
      Bytes_B : in Basic_Types.Byte_Array;
      Value : out T;
      Status : out Restore_Status;
      Info : out Copy_Info
   ) is
      Data : Data_Type;
   begin
      Restore (Bytes_A, Bytes_B, Layout_Id, Data, Status, Info);
      Value := From_Byte_Array (Data);
   end Restore;

end Double_Buffer_Store.Typed;

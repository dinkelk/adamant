with Byte_Array_Util;
with Double_Buffer_Store;

package body Double_Buffer_Store_Typed with SPARK_Mode => On is

   -- The byte level store over the same two copies:
   package Bytes_Store is new Double_Buffer_Store (
      Region_A => Region_A,
      Region_B => Region_B,
      Layout_Id => Layout_Id,
      Data_Length => Serialized_Length
   );

   -- The serialized form of T, sized by the instantiator's Serialized_Length:
   subtype Data_Index_Type is Natural range 0 .. Serialized_Length - 1;
   subtype Data_Type is Basic_Types.Byte_Array (Data_Index_Type);

   procedure Save (Value : in T; Save_Time : in Sys_Time.T; Info : out Copy_Info) is
      -- Copy the serialized value into a buffer of the declared length. This keeps
      -- the length passed to the store fixed even if the instantiator's serialization
      -- function returns a differently sized array by mistake.
      Data : Data_Type := [others => 0];
   begin
      Byte_Array_Util.Safe_Left_Copy (Data, To_Byte_Array (Value));
      Bytes_Store.Save (Data, Save_Time, Info);
   end Save;

   procedure Restore (Value : out T; Status : out Restore_Status; Info : out Copy_Info) is
      Data : Data_Type;
   begin
      Bytes_Store.Restore (Data, Status, Info);
      Value := From_Byte_Array (Data);
   end Restore;

   function Is_Valid (Copy : in Copy_Type) return Boolean is (Bytes_Store.Is_Valid (Copy));

   function Save_Counter (Copy : in Copy_Type) return Unsigned_32 is (Bytes_Store.Save_Counter (Copy));

   function Save_Time (Copy : in Copy_Type) return Sys_Time.T is (Bytes_Store.Save_Time (Copy));

end Double_Buffer_Store_Typed;

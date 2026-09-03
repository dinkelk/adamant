with Crc_16;

package body Double_Buffer_Store with SPARK_Mode => On is

   use Basic_Types;

   -- The last byte of the serialized save time relative to the first byte of a copy:
   Save_Time_Last_Offset : constant Natural := Save_Time_Offset + Sys_Time.Size_In_Bytes - 1;

   -- The CRC of a copy covers everything after the CRC itself:
   function Compute_Crc (Copy : in Byte_Array; Data_Length : in Data_Length_Type) return Crc_16.Crc_16_Type
      with Global => null,
           Pre => Fits (Copy, Data_Length)
   is
      First : constant Natural := Copy'First;
      Store_Last : constant Natural := First + Store_Length (Data_Length) - 1;
   begin
      return Crc_16.Compute_Crc_16 (Copy (First + Save_Time_Offset .. Store_Last));
   end Compute_Crc;

   function Is_Valid (Copy : in Byte_Array; Data_Length : in Data_Length_Type) return Boolean is
      First : constant Natural := Copy'First;
   begin
      return Copy (First + Crc_Offset .. First + Crc_Offset + 1) = Compute_Crc (Copy, Data_Length);
   end Is_Valid;

   function Read_Save_Time (Copy : in Byte_Array) return Sys_Time.T is
   begin
      return Sys_Time.Serialization.From_Byte_Array (
         Copy (Copy'First + Save_Time_Offset .. Copy'First + Save_Time_Last_Offset)
      );
   end Read_Save_Time;

   -- Find the copy to restore from: the valid one, or the one with the later save
   -- time if both are valid. Copy A wins a tie.
   procedure Find_Valid (
      Bytes_A : in Byte_Array;
      Bytes_B : in Byte_Array;
      Data_Length : in Data_Length_Type;
      Valid_Found : out Boolean;
      Source : out Copy_Type
   )
      with Global => null,
           Pre => Fits (Bytes_A, Data_Length) and then Fits (Bytes_B, Data_Length)
   is
      A_Valid : constant Boolean := Is_Valid (Bytes_A, Data_Length);
      B_Valid : constant Boolean := Is_Valid (Bytes_B, Data_Length);
   begin
      Valid_Found := A_Valid or else B_Valid;
      if A_Valid and then B_Valid then
         Source := (if Is_Later (Read_Save_Time (Bytes_B), Than => Read_Save_Time (Bytes_A)) then Copy_B else Copy_A);
      elsif B_Valid then
         Source := Copy_B;
      else
         Source := Copy_A;
      end if;
   end Find_Valid;

   -- Write the save time and data into a copy, then its CRC last:
   procedure Write_Copy (Copy : in out Byte_Array; Data : in Byte_Array; Save_Time : in Sys_Time.T)
      with Global => null,
           Pre => Data'Length <= Max_Data_Length and then Fits (Copy, Data'Length)
   is
      First : constant Natural := Copy'First;
      Data_First : constant Natural := First + Header_Length;
   begin
      Copy (First + Save_Time_Offset .. First + Save_Time_Last_Offset) := Sys_Time.Serialization.To_Byte_Array (Save_Time);
      Copy (Data_First .. Data_First + Data'Length - 1) := Data;
      Copy (First + Crc_Offset .. First + Crc_Offset + 1) := Compute_Crc (Copy, Data'Length);
   end Write_Copy;

   -- Invalidate a copy by zeroing its save time, which no longer matches its CRC:
   procedure Invalidate (Copy : in out Byte_Array)
      with Global => null,
           Pre => Copy'Length >= Header_Length
   is
      First : constant Natural := Copy'First;
   begin
      Copy (First + Save_Time_Offset .. First + Save_Time_Last_Offset) := [others => 0];
   end Invalidate;

   procedure Save (
      Bytes_A : in out Byte_Array;
      Bytes_B : in out Byte_Array;
      Data : in Byte_Array;
      Save_Time : in Sys_Time.T;
      Written : out Copy_Type
   ) is
      Valid_Found : Boolean;
      Source : Copy_Type;
   begin
      -- Write the copy that does not hold the current data, so that a reboot during
      -- the write can never destroy the only good copy. If no copy is valid the store
      -- has never been written, so copy A is written first.
      Find_Valid (Bytes_A, Bytes_B, Data'Length, Valid_Found, Source);
      Written := (if Valid_Found then Other_Copy (Source) else Copy_A);

      case Written is
         when Copy_A =>
            Write_Copy (Bytes_A, Data, Save_Time);
            Invalidate (Bytes_B);
         when Copy_B =>
            Write_Copy (Bytes_B, Data, Save_Time);
            Invalidate (Bytes_A);
      end case;
   end Save;

   procedure Restore (
      Bytes_A : in Byte_Array;
      Bytes_B : in Byte_Array;
      Data : out Byte_Array;
      Status : out Restore_Status;
      Source : out Copy_Type
   ) is
      Valid_Found : Boolean;
   begin
      Find_Valid (Bytes_A, Bytes_B, Data'Length, Valid_Found, Source);

      if not Valid_Found then
         Data := [others => 0];
         Status := No_Valid_Copy;
         return;
      end if;

      case Source is
         when Copy_A =>
            Data := Bytes_A (Bytes_A'First + Header_Length .. Bytes_A'First + Header_Length + Data'Length - 1);
         when Copy_B =>
            Data := Bytes_B (Bytes_B'First + Header_Length .. Bytes_B'First + Header_Length + Data'Length - 1);
      end case;
      Status := Restored;
   end Restore;

end Double_Buffer_Store;

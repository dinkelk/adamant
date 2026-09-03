with Crc_16;

package body Double_Buffer_Store with SPARK_Mode => On is

   use Basic_Types;

   -- The data begins right after the header:
   Data_Offset : constant Natural := Header_Length;
   -- The last byte of the serialized save time relative to its offset:
   Save_Time_Last_Offset : constant Natural := Save_Time_Offset + Sys_Time.Size_In_Bytes - 1;

   -------------------------------------------------------------------------
   -- Byte order helpers. All header fields are most significant byte first.
   -------------------------------------------------------------------------

   function Read_U16 (Bytes : in Byte_Array; Index : in Natural) return Unsigned_16
      with Global => null,
           Pre => Index in Bytes'Range and then Bytes'Last - Index >= 1
   is
   begin
      return Shift_Left (Unsigned_16 (Bytes (Index)), 8) or Unsigned_16 (Bytes (Index + 1));
   end Read_U16;

   function Read_U32 (Bytes : in Byte_Array; Index : in Natural) return Unsigned_32
      with Global => null,
           Pre => Index in Bytes'Range and then Bytes'Last - Index >= 3
   is
   begin
      return Shift_Left (Unsigned_32 (Bytes (Index)), 24)
         or Shift_Left (Unsigned_32 (Bytes (Index + 1)), 16)
         or Shift_Left (Unsigned_32 (Bytes (Index + 2)), 8)
         or Unsigned_32 (Bytes (Index + 3));
   end Read_U32;

   procedure Write_U16 (Bytes : in out Byte_Array; Index : in Natural; Value : in Unsigned_16)
      with Global => null,
           Pre => Index in Bytes'Range and then Bytes'Last - Index >= 1
   is
   begin
      Bytes (Index) := Byte (Shift_Right (Value, 8) and 16#FF#);
      Bytes (Index + 1) := Byte (Value and 16#FF#);
   end Write_U16;

   procedure Write_U32 (Bytes : in out Byte_Array; Index : in Natural; Value : in Unsigned_32)
      with Global => null,
           Pre => Index in Bytes'Range and then Bytes'Last - Index >= 3
   is
   begin
      Bytes (Index) := Byte (Shift_Right (Value, 24) and 16#FF#);
      Bytes (Index + 1) := Byte (Shift_Right (Value, 16) and 16#FF#);
      Bytes (Index + 2) := Byte (Shift_Right (Value, 8) and 16#FF#);
      Bytes (Index + 3) := Byte (Value and 16#FF#);
   end Write_U32;

   -------------------------------------------------------------------------
   -- Header access:
   -------------------------------------------------------------------------

   function Read_Save_Counter (Copy : in Byte_Array) return Unsigned_32 is
   begin
      return Read_U32 (Copy, Copy'First + Save_Counter_Offset);
   end Read_Save_Counter;

   function Read_Save_Time (Copy : in Byte_Array) return Sys_Time.T is
   begin
      return Sys_Time.Serialization.From_Byte_Array (
         Copy (Copy'First + Save_Time_Offset .. Copy'First + Save_Time_Last_Offset)
      );
   end Read_Save_Time;

   -------------------------------------------------------------------------
   -- Validity:
   -------------------------------------------------------------------------

   function Is_Valid (Copy : in Byte_Array; Layout_Id : in Unsigned_32; Data_Length : in Data_Length_Type) return Boolean is
      First : constant Natural := Copy'First;
      -- The last byte of the store within this copy. Fits guarantees this is within
      -- the array.
      Store_Last : constant Natural := First + Store_Length (Data_Length) - 1;
   begin
      -- Check the layout id and data length before spending time on the CRC:
      if Read_U32 (Copy, First + Layout_Id_Offset) /= Layout_Id then
         return False;
      end if;
      if Natural (Read_U16 (Copy, First + Data_Length_Offset)) /= Data_Length then
         return False;
      end if;

      -- The CRC covers every byte after itself, through the end of the data:
      return Crc_16.Compute_Crc_16 (Copy (First + Save_Counter_Offset .. Store_Last)) =
         Copy (First + Crc_Offset .. First + Crc_Offset + 1);
   end Is_Valid;

   procedure Find_Newest_Valid (
      Bytes_A : in Byte_Array;
      Bytes_B : in Byte_Array;
      Layout_Id : in Unsigned_32;
      Data_Length : in Data_Length_Type;
      Valid_Found : out Boolean;
      Newest : out Copy_Type
   ) is
      A_Valid : constant Boolean := Is_Valid (Bytes_A, Layout_Id, Data_Length);
      B_Valid : constant Boolean := Is_Valid (Bytes_B, Layout_Id, Data_Length);
   begin
      Valid_Found := A_Valid or else B_Valid;
      if A_Valid and then B_Valid then
         -- Both copies are valid, so the one holding the newer save counter wins.
         -- Copy A wins a tie, which cannot occur through this package's own saves.
         Newest := (if Is_Newer (Read_Save_Counter (Bytes_B), Than => Read_Save_Counter (Bytes_A)) then Copy_B else Copy_A);
      elsif B_Valid then
         Newest := Copy_B;
      else
         Newest := Copy_A;
      end if;
   end Find_Newest_Valid;

   -------------------------------------------------------------------------
   -- Save:
   -------------------------------------------------------------------------

   -- Write one complete copy: header fields, data, then the CRC last.
   procedure Write_Copy (
      Copy : in out Byte_Array;
      Data : in Byte_Array;
      Layout_Id : in Unsigned_32;
      Save_Time : in Sys_Time.T;
      Save_Counter : in Unsigned_32
   )
      with Global => null,
           Pre => Data'Length <= Max_Data_Length and then Fits (Copy, Data'Length)
   is
      First : constant Natural := Copy'First;
      Data_First : constant Natural := First + Data_Offset;
      -- The last byte of the store within this copy, which is also the last data byte:
      Store_Last : constant Natural := First + Store_Length (Data'Length) - 1;
   begin
      Write_U32 (Copy, First + Save_Counter_Offset, Save_Counter);
      Copy (First + Save_Time_Offset .. First + Save_Time_Last_Offset) :=
         Sys_Time.Serialization.To_Byte_Array (Save_Time);
      Write_U32 (Copy, First + Layout_Id_Offset, Layout_Id);
      Write_U16 (Copy, First + Data_Length_Offset, Unsigned_16 (Data'Length));
      Copy (Data_First .. Store_Last) := Data;

      -- The CRC is written last. A reboot before this write leaves this copy invalid
      -- and the other copy untouched.
      Copy (First + Crc_Offset .. First + Crc_Offset + 1) :=
         Crc_16.Compute_Crc_16 (Copy (First + Save_Counter_Offset .. Store_Last));
   end Write_Copy;

   procedure Save (
      Bytes_A : in out Byte_Array;
      Bytes_B : in out Byte_Array;
      Data : in Byte_Array;
      Layout_Id : in Unsigned_32;
      Save_Time : in Sys_Time.T;
      Info : out Copy_Info
   ) is
      Valid_Found : Boolean;
      Newest : Copy_Type;
      Target : Copy_Type;
      New_Counter : Unsigned_32;
   begin
      Find_Newest_Valid (Bytes_A, Bytes_B, Layout_Id, Data'Length, Valid_Found, Newest);

      -- Write the copy that does not hold the newest valid save, so that a reboot
      -- during the write can never destroy the only good copy. If no copy is valid
      -- the store has never been written, so copy A is written first with counter one.
      if Valid_Found then
         Target := Other_Copy (Newest);
         New_Counter := (case Newest is
            when Copy_A => Read_Save_Counter (Bytes_A),
            when Copy_B => Read_Save_Counter (Bytes_B)) + 1;
      else
         Target := Copy_A;
         New_Counter := 1;
      end if;

      case Target is
         when Copy_A =>
            Write_Copy (Bytes_A, Data, Layout_Id, Save_Time, New_Counter);
         when Copy_B =>
            Write_Copy (Bytes_B, Data, Layout_Id, Save_Time, New_Counter);
      end case;

      Info := (Copy => Target, Save_Counter => New_Counter);
   end Save;

   -------------------------------------------------------------------------
   -- Restore:
   -------------------------------------------------------------------------

   -- Copy the data region of a copy into Data.
   procedure Read_Copy (Copy : in Byte_Array; Data : out Byte_Array)
      with Global => null,
           Pre => Data'Length <= Max_Data_Length and then Fits (Copy, Data'Length)
   is
      Data_First : constant Natural := Copy'First + Data_Offset;
      Store_Last : constant Natural := Copy'First + Store_Length (Data'Length) - 1;
   begin
      Data := Copy (Data_First .. Store_Last);
   end Read_Copy;

   procedure Restore (
      Bytes_A : in Byte_Array;
      Bytes_B : in Byte_Array;
      Layout_Id : in Unsigned_32;
      Data : out Byte_Array;
      Status : out Restore_Status;
      Info : out Copy_Info
   ) is
      Valid_Found : Boolean;
      Newest : Copy_Type;
   begin
      Find_Newest_Valid (Bytes_A, Bytes_B, Layout_Id, Data'Length, Valid_Found, Newest);

      if not Valid_Found then
         Data := [others => 0];
         Status := No_Valid_Copy;
         Info := (Copy => Copy_A, Save_Counter => 0);
         return;
      end if;

      case Newest is
         when Copy_A =>
            Read_Copy (Bytes_A, Data);
            Info := (Copy => Copy_A, Save_Counter => Read_Save_Counter (Bytes_A));
         when Copy_B =>
            Read_Copy (Bytes_B, Data);
            Info := (Copy => Copy_B, Save_Counter => Read_Save_Counter (Bytes_B));
      end case;
      Status := Restored;
   end Restore;

end Double_Buffer_Store;

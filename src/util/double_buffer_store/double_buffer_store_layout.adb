with Crc_16;

package body Double_Buffer_Store_Layout with SPARK_Mode => On is

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
         -- Copy A wins a tie, which cannot occur through the store's own saves.
         Newest := (if Is_Newer (Read_Save_Counter (Bytes_B), Than => Read_Save_Counter (Bytes_A)) then Copy_B else Copy_A);
      elsif B_Valid then
         Newest := Copy_B;
      else
         Newest := Copy_A;
      end if;
   end Find_Newest_Valid;

   -------------------------------------------------------------------------
   -- Encode and decode:
   -------------------------------------------------------------------------

   procedure Encode (
      Copy : out Byte_Array;
      Data : in Byte_Array;
      Layout_Id : in Unsigned_32;
      Save_Time : in Sys_Time.T;
      Save_Counter : in Unsigned_32
   ) is
      First : constant Natural := Copy'First;
      Data_First : constant Natural := First + Data_Offset;
   begin
      Copy := [others => 0];
      Write_U32 (Copy, First + Save_Counter_Offset, Save_Counter);
      Copy (First + Save_Time_Offset .. First + Save_Time_Last_Offset) :=
         Sys_Time.Serialization.To_Byte_Array (Save_Time);
      Write_U32 (Copy, First + Layout_Id_Offset, Layout_Id);
      Write_U16 (Copy, First + Data_Length_Offset, Unsigned_16 (Data'Length));
      Copy (Data_First .. Copy'Last) := Data;

      -- The CRC covers every byte after itself:
      Copy (First + Crc_Offset .. First + Crc_Offset + 1) :=
         Crc_16.Compute_Crc_16 (Copy (First + Save_Counter_Offset .. Copy'Last));
   end Encode;

   procedure Decode (Copy : in Byte_Array; Data : out Byte_Array) is
      Data_First : constant Natural := Copy'First + Data_Offset;
      Store_Last : constant Natural := Copy'First + Store_Length (Data'Length) - 1;
   begin
      Data := Copy (Data_First .. Store_Last);
   end Decode;

end Double_Buffer_Store_Layout;

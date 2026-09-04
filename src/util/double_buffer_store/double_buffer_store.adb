with Double_Buffer_Store_Layout;

package body Double_Buffer_Store with SPARK_Mode => On is

   use Basic_Types;
   package Layout renames Double_Buffer_Store_Layout;

   -- The contents of one copy, read out of memory into an ordinary byte array:
   subtype Copy_Index_Type is Natural range 0 .. Store_Length_In_Bytes - 1;
   subtype Copy_Contents is Byte_Array (Copy_Index_Type);

   function Read_Copy (Copy : in Copy_Type) return Copy_Contents
      with Global => (Input => (Region_A, Region_B)),
           Pre => Fits
   is
   begin
      case Copy is
         when Copy_A =>
            return Byte_Array (Region_A (Region_A'First .. Region_A'First + Store_Length_In_Bytes - 1));
         when Copy_B =>
            return Byte_Array (Region_B (Region_B'First .. Region_B'First + Store_Length_In_Bytes - 1));
      end case;
   end Read_Copy;

   -- Write the contents of a copy into memory. Everything after the CRC is written
   -- first and the CRC last, so a reboot part way through leaves the copy invalid and
   -- the other copy untouched.
   procedure Write_Copy (Copy : in Copy_Type; Contents : in Copy_Contents)
      with Global => (In_Out => (Region_A, Region_B)),
           Pre => Fits
   is
      Body_First : constant Copy_Index_Type := Save_Counter_Offset;
   begin
      case Copy is
         when Copy_A =>
            declare
               First : constant Natural := Region_A'First;
            begin
               Region_A (First + Body_First .. First + Copy_Contents'Last) := Persistent_Bytes (Contents (Body_First .. Copy_Contents'Last));
               Region_A (First + Crc_Offset) := Contents (Crc_Offset);
               Region_A (First + Crc_Offset + 1) := Contents (Crc_Offset + 1);
            end;
         when Copy_B =>
            declare
               First : constant Natural := Region_B'First;
            begin
               Region_B (First + Body_First .. First + Copy_Contents'Last) := Persistent_Bytes (Contents (Body_First .. Copy_Contents'Last));
               Region_B (First + Crc_Offset) := Contents (Crc_Offset);
               Region_B (First + Crc_Offset + 1) := Contents (Crc_Offset + 1);
            end;
      end case;
   end Write_Copy;

   procedure Save (Data : in Basic_Types.Byte_Array; Save_Time : in Sys_Time.T; Info : out Copy_Info) is
      Current_A : constant Copy_Contents := Read_Copy (Copy_A);
      Current_B : constant Copy_Contents := Read_Copy (Copy_B);
      Contents : Copy_Contents;
      Valid_Found : Boolean;
      Newest : Copy_Type;
      Target : Copy_Type;
      New_Counter : Unsigned_32;
   begin
      Layout.Find_Newest_Valid (Current_A, Current_B, Layout_Id, Data_Length, Valid_Found, Newest);

      -- Write the copy that does not hold the newest valid save, so that a reboot
      -- during the write can never destroy the only good copy. If no copy is valid
      -- the store has never been written, so copy A is written first with counter one.
      if Valid_Found then
         Target := Other_Copy (Newest);
         New_Counter := (case Newest is
            when Copy_A => Layout.Read_Save_Counter (Current_A),
            when Copy_B => Layout.Read_Save_Counter (Current_B)) + 1;
      else
         Target := Copy_A;
         New_Counter := 1;
      end if;

      Layout.Encode (Contents, Data, Layout_Id, Save_Time, New_Counter);
      Write_Copy (Target, Contents);
      Info := (Copy => Target, Save_Counter => New_Counter);
   end Save;

   procedure Restore (Data : out Basic_Types.Byte_Array; Status : out Restore_Status; Info : out Copy_Info) is
      Current_A : constant Copy_Contents := Read_Copy (Copy_A);
      Current_B : constant Copy_Contents := Read_Copy (Copy_B);
      Valid_Found : Boolean;
      Newest : Copy_Type;
   begin
      Layout.Find_Newest_Valid (Current_A, Current_B, Layout_Id, Data_Length, Valid_Found, Newest);

      if not Valid_Found then
         Data := [others => 0];
         Status := No_Valid_Copy;
         Info := (Copy => Copy_A, Save_Counter => 0);
         return;
      end if;

      case Newest is
         when Copy_A =>
            Layout.Decode (Current_A, Data);
            Info := (Copy => Copy_A, Save_Counter => Layout.Read_Save_Counter (Current_A));
         when Copy_B =>
            Layout.Decode (Current_B, Data);
            Info := (Copy => Copy_B, Save_Counter => Layout.Read_Save_Counter (Current_B));
      end case;
      Status := Restored;
   end Restore;

   function Is_Valid (Copy : in Copy_Type) return Boolean is
      (Layout.Is_Valid (Read_Copy (Copy), Layout_Id, Data_Length));

   function Save_Counter (Copy : in Copy_Type) return Unsigned_32 is
      (Layout.Read_Save_Counter (Read_Copy (Copy)));

   function Save_Time (Copy : in Copy_Type) return Sys_Time.T is
      (Layout.Read_Save_Time (Read_Copy (Copy)));

begin
   -- Both copies must hold the whole store. This is checked once, when the instance
   -- elaborates, so that the store never writes past a copy.
   pragma Assert (Fits);
end Double_Buffer_Store;

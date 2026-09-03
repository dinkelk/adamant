--------------------------------------------------------------------------------
-- Double_Buffer_Store Tests Body
--------------------------------------------------------------------------------

with Basic_Types; use Basic_Types;
with Basic_Assertions; use Basic_Assertions;
with Crc_16;
with Double_Buffer_Store; use Double_Buffer_Store;
with Double_Buffer_Store.Typed;
with Interfaces; use Interfaces;
with Packed_U32;
with Packed_U32.Assertion; use Packed_U32.Assertion;
with Smart_Assert;
with Sys_Time;
with Sys_Time.Assertion; use Sys_Time.Assertion;

package body Double_Buffer_Store_Tests.Implementation is

   -------------------------------------------------------------------------
   -- Assertion packages:
   -------------------------------------------------------------------------

   package Copy_Type_Assert is new Smart_Assert.Basic (Copy_Type, Copy_Type'Image);
   package Restore_Status_Assert is new Smart_Assert.Basic (Restore_Status, Restore_Status'Image);

   -------------------------------------------------------------------------
   -- Test helpers:
   -------------------------------------------------------------------------

   -- The data block used by most tests:
   Test_Data_Length : constant Data_Length_Type := 8;
   subtype Test_Data_Type is Byte_Array (0 .. Test_Data_Length - 1);
   Test_Store_Length : constant Natural := Store_Length (Test_Data_Length);
   subtype Test_Copy_Type is Byte_Array (0 .. Test_Store_Length - 1);

   Test_Layout_Id : constant Unsigned_32 := 16#0102_0304#;
   Test_Time : constant Sys_Time.T := (Seconds => 1_234, Subseconds => 5_678);

   -- Produce a distinguishable data block from a seed:
   function Make_Data (Seed : in Byte) return Test_Data_Type is
      Data : Test_Data_Type;
   begin
      for Idx in Data'Range loop
         Data (Idx) := Seed + Byte (Idx);
      end loop;
      return Data;
   end Make_Data;

   -- Fill a byte array with a garbage pattern that is not a valid store:
   procedure Fill_Garbage (Bytes : in out Byte_Array) is
   begin
      for Idx in Bytes'Range loop
         Bytes (Idx) := Byte ((Idx * 37 + 11) mod 256);
      end loop;
   end Fill_Garbage;

   -- Check that a restore of the test store returns the expected status, copy,
   -- counter and data:
   procedure Check_Restore (
      Copy_A : in Byte_Array;
      Copy_B : in Byte_Array;
      Expected_Status : in Restore_Status;
      Expected_Copy : in Copy_Type;
      Expected_Counter : in Unsigned_32;
      Expected_Data : in Test_Data_Type
   ) is
      Data : Test_Data_Type := [others => 16#EE#];
      Status : Restore_Status;
      Info : Copy_Info;
   begin
      Restore (Copy_A, Copy_B, Test_Layout_Id, Data, Status, Info);
      Restore_Status_Assert.Eq (Status, Expected_Status);
      if Expected_Status = Restored then
         Copy_Type_Assert.Eq (Info.Copy, Expected_Copy);
         Unsigned_32_Assert.Eq (Info.Save_Counter, Expected_Counter);
      end if;
      Byte_Array_Assert.Eq (Data, Expected_Data);
   end Check_Restore;

   -------------------------------------------------------------------------
   -- Fixtures:
   -------------------------------------------------------------------------

   overriding procedure Set_Up_Test (Self : in out Instance) is
   begin
      null;
   end Set_Up_Test;

   overriding procedure Tear_Down_Test (Self : in out Instance) is
   begin
      null;
   end Tear_Down_Test;

   -------------------------------------------------------------------------
   -- Tests:
   -------------------------------------------------------------------------

   overriding procedure Test_No_Valid_Copy_On_First_Boot (Self : in out Instance) is
      Ignore : Instance renames Self;
      Copy_A_Bytes : Test_Copy_Type;
      Copy_B_Bytes : Test_Copy_Type;
      Valid_Found : Boolean;
      Ignore_Newest : Copy_Type;
   begin
      -- Garbage in both copies:
      Fill_Garbage (Copy_A_Bytes);
      Fill_Garbage (Copy_B_Bytes);
      Boolean_Assert.Eq (Is_Valid (Copy_A_Bytes, Test_Layout_Id, Test_Data_Length), False);
      Boolean_Assert.Eq (Is_Valid (Copy_B_Bytes, Test_Layout_Id, Test_Data_Length), False);
      Find_Newest_Valid (Copy_A_Bytes, Copy_B_Bytes, Test_Layout_Id, Test_Data_Length, Valid_Found, Ignore_Newest);
      Boolean_Assert.Eq (Valid_Found, False);
      Check_Restore (Copy_A_Bytes, Copy_B_Bytes, No_Valid_Copy, Copy_A, 0, [others => 0]);

      -- All zeros in both copies is also not a valid store, since the CRC of the
      -- zeroed contents is not zero:
      Copy_A_Bytes := [others => 0];
      Copy_B_Bytes := [others => 0];
      Boolean_Assert.Eq (Is_Valid (Copy_A_Bytes, Test_Layout_Id, Test_Data_Length), False);
      Check_Restore (Copy_A_Bytes, Copy_B_Bytes, No_Valid_Copy, Copy_A, 0, [others => 0]);

      -- All ones, the erased state of many nonvolatile memories, is not valid either:
      Copy_A_Bytes := [others => 16#FF#];
      Copy_B_Bytes := [others => 16#FF#];
      Check_Restore (Copy_A_Bytes, Copy_B_Bytes, No_Valid_Copy, Copy_A, 0, [others => 0]);
   end Test_No_Valid_Copy_On_First_Boot;

   overriding procedure Test_Save_And_Restore_Alternate_Copies (Self : in out Instance) is
      Ignore : Instance renames Self;
      Copy_A_Bytes : Test_Copy_Type;
      Copy_B_Bytes : Test_Copy_Type;
      Info : Copy_Info;
   begin
      Fill_Garbage (Copy_A_Bytes);
      Fill_Garbage (Copy_B_Bytes);

      -- First save goes to copy A with counter one:
      Save (Copy_A_Bytes, Copy_B_Bytes, Make_Data (1), Test_Layout_Id, Test_Time, Info);
      Copy_Type_Assert.Eq (Info.Copy, Copy_A);
      Unsigned_32_Assert.Eq (Info.Save_Counter, 1);
      Boolean_Assert.Eq (Is_Valid (Copy_A_Bytes, Test_Layout_Id, Test_Data_Length), True);
      Boolean_Assert.Eq (Is_Valid (Copy_B_Bytes, Test_Layout_Id, Test_Data_Length), False);
      Unsigned_32_Assert.Eq (Read_Save_Counter (Copy_A_Bytes), 1);
      Sys_Time_Assert.Eq (Read_Save_Time (Copy_A_Bytes), Test_Time);
      Check_Restore (Copy_A_Bytes, Copy_B_Bytes, Restored, Copy_A, 1, Make_Data (1));

      -- Second save goes to copy B with counter two, copy A untouched:
      Save (Copy_A_Bytes, Copy_B_Bytes, Make_Data (2), Test_Layout_Id, (Seconds => 2, Subseconds => 0), Info);
      Copy_Type_Assert.Eq (Info.Copy, Copy_B);
      Unsigned_32_Assert.Eq (Info.Save_Counter, 2);
      Boolean_Assert.Eq (Is_Valid (Copy_A_Bytes, Test_Layout_Id, Test_Data_Length), True);
      Boolean_Assert.Eq (Is_Valid (Copy_B_Bytes, Test_Layout_Id, Test_Data_Length), True);
      Unsigned_32_Assert.Eq (Read_Save_Counter (Copy_A_Bytes), 1);
      Unsigned_32_Assert.Eq (Read_Save_Counter (Copy_B_Bytes), 2);
      Sys_Time_Assert.Eq (Read_Save_Time (Copy_B_Bytes), (Seconds => 2, Subseconds => 0));
      Check_Restore (Copy_A_Bytes, Copy_B_Bytes, Restored, Copy_B, 2, Make_Data (2));

      -- Third save goes back to copy A with counter three:
      Save (Copy_A_Bytes, Copy_B_Bytes, Make_Data (3), Test_Layout_Id, Test_Time, Info);
      Copy_Type_Assert.Eq (Info.Copy, Copy_A);
      Unsigned_32_Assert.Eq (Info.Save_Counter, 3);
      Unsigned_32_Assert.Eq (Read_Save_Counter (Copy_B_Bytes), 2);
      Check_Restore (Copy_A_Bytes, Copy_B_Bytes, Restored, Copy_A, 3, Make_Data (3));

      -- Fourth save goes to copy B with counter four:
      Save (Copy_A_Bytes, Copy_B_Bytes, Make_Data (4), Test_Layout_Id, Test_Time, Info);
      Copy_Type_Assert.Eq (Info.Copy, Copy_B);
      Unsigned_32_Assert.Eq (Info.Save_Counter, 4);
      Check_Restore (Copy_A_Bytes, Copy_B_Bytes, Restored, Copy_B, 4, Make_Data (4));

      -- Check the header layout directly on copy B: CRC, counter, save time, layout
      -- id, length, data.
      Natural_Assert.Eq (Header_Length, 12 + Sys_Time.Size_In_Bytes);
      Byte_Array_Assert.Eq (Copy_B_Bytes (Crc_Offset .. Crc_Offset + 1), Crc_16.Compute_Crc_16 (Copy_B_Bytes (Save_Counter_Offset .. Copy_B_Bytes'Last)));
      Byte_Array_Assert.Eq (Copy_B_Bytes (Save_Counter_Offset .. Save_Counter_Offset + 3), [0, 0, 0, 4]);
      Byte_Array_Assert.Eq (Copy_B_Bytes (Save_Time_Offset .. Save_Time_Offset + Sys_Time.Size_In_Bytes - 1), Sys_Time.Serialization.To_Byte_Array (Test_Time));
      Byte_Array_Assert.Eq (Copy_B_Bytes (Layout_Id_Offset .. Layout_Id_Offset + 3), [16#01#, 16#02#, 16#03#, 16#04#]);
      Byte_Array_Assert.Eq (Copy_B_Bytes (Data_Length_Offset .. Data_Length_Offset + 1), [0, 8]);
      Byte_Array_Assert.Eq (Copy_B_Bytes (Header_Length .. Header_Length + 7), Make_Data (4));
   end Test_Save_And_Restore_Alternate_Copies;

   overriding procedure Test_Restore_From_Older_Copy_When_Newest_Corrupt (Self : in out Instance) is
      Ignore : Instance renames Self;
      Copy_A_Bytes : Test_Copy_Type;
      Copy_B_Bytes : Test_Copy_Type;
      Info : Copy_Info;
   begin
      Fill_Garbage (Copy_A_Bytes);
      Fill_Garbage (Copy_B_Bytes);
      Save (Copy_A_Bytes, Copy_B_Bytes, Make_Data (1), Test_Layout_Id, Test_Time, Info);
      Copy_Type_Assert.Eq (Info.Copy, Copy_A);
      Save (Copy_A_Bytes, Copy_B_Bytes, Make_Data (2), Test_Layout_Id, Test_Time, Info);
      Copy_Type_Assert.Eq (Info.Copy, Copy_B);
      Check_Restore (Copy_A_Bytes, Copy_B_Bytes, Restored, Copy_B, 2, Make_Data (2));

      -- Flip a data bit in the newest copy (B). The restore falls back to A.
      Copy_B_Bytes (Header_Length + 3) := Copy_B_Bytes (Header_Length + 3) xor 16#01#;
      Boolean_Assert.Eq (Is_Valid (Copy_B_Bytes, Test_Layout_Id, Test_Data_Length), False);
      Check_Restore (Copy_A_Bytes, Copy_B_Bytes, Restored, Copy_A, 1, Make_Data (1));

      -- The next save rewrites the invalid copy B, not the only good copy A:
      Save (Copy_A_Bytes, Copy_B_Bytes, Make_Data (3), Test_Layout_Id, Test_Time, Info);
      Copy_Type_Assert.Eq (Info.Copy, Copy_B);
      Unsigned_32_Assert.Eq (Info.Save_Counter, 2);
      Check_Restore (Copy_A_Bytes, Copy_B_Bytes, Restored, Copy_B, 2, Make_Data (3));

      -- Flip a header bit (the counter) in the newest copy. Falls back to A again.
      Copy_B_Bytes (Save_Counter_Offset + 3) := Copy_B_Bytes (Save_Counter_Offset + 3) xor 16#80#;
      Check_Restore (Copy_A_Bytes, Copy_B_Bytes, Restored, Copy_A, 1, Make_Data (1));

      -- Flip a CRC bit in copy A as well. Now nothing is valid.
      Copy_A_Bytes (Crc_Offset) := Copy_A_Bytes (Crc_Offset) xor 16#10#;
      Check_Restore (Copy_A_Bytes, Copy_B_Bytes, No_Valid_Copy, Copy_A, 0, [others => 0]);

      -- Emulate a reboot in the middle of a save. Start from a good store with the
      -- newest save in A, then write everything except the CRC into B, as an
      -- interrupted save would. The restore must still come from A.
      Fill_Garbage (Copy_A_Bytes);
      Fill_Garbage (Copy_B_Bytes);
      Save (Copy_A_Bytes, Copy_B_Bytes, Make_Data (7), Test_Layout_Id, Test_Time, Info);
      Copy_Type_Assert.Eq (Info.Copy, Copy_A);
      declare
         Interrupted : Test_Copy_Type := Copy_B_Bytes;
      begin
         -- Perform a real save into scratch copies to obtain the bytes an interrupted
         -- save would have written, then copy all but the CRC into B:
         declare
            Scratch_A : Test_Copy_Type := Copy_A_Bytes;
            Scratch_B : Test_Copy_Type := Copy_B_Bytes;
         begin
            Save (Scratch_A, Scratch_B, Make_Data (8), Test_Layout_Id, Test_Time, Info);
            Copy_Type_Assert.Eq (Info.Copy, Copy_B);
            -- The save into the scratch copies left copy A alone:
            Byte_Array_Assert.Eq (Scratch_A, Copy_A_Bytes);
            Interrupted (Save_Counter_Offset .. Interrupted'Last) := Scratch_B (Save_Counter_Offset .. Scratch_B'Last);
         end;
         Copy_B_Bytes := Interrupted;
      end;
      Boolean_Assert.Eq (Is_Valid (Copy_B_Bytes, Test_Layout_Id, Test_Data_Length), False);
      Check_Restore (Copy_A_Bytes, Copy_B_Bytes, Restored, Copy_A, 1, Make_Data (7));

      -- Completing the save (rewriting B in full) recovers normally:
      Save (Copy_A_Bytes, Copy_B_Bytes, Make_Data (8), Test_Layout_Id, Test_Time, Info);
      Copy_Type_Assert.Eq (Info.Copy, Copy_B);
      Unsigned_32_Assert.Eq (Info.Save_Counter, 2);
      Check_Restore (Copy_A_Bytes, Copy_B_Bytes, Restored, Copy_B, 2, Make_Data (8));
   end Test_Restore_From_Older_Copy_When_Newest_Corrupt;

   overriding procedure Test_Save_Counter_Wraparound (Self : in out Instance) is
      Ignore : Instance renames Self;
      Copy_A_Bytes : Test_Copy_Type;
      Copy_B_Bytes : Test_Copy_Type;
      Info : Copy_Info;
   begin
      -- Is_Newer is wraparound-aware:
      Boolean_Assert.Eq (Is_Newer (1, Than => 0), True);
      Boolean_Assert.Eq (Is_Newer (0, Than => 1), False);
      Boolean_Assert.Eq (Is_Newer (5, Than => 5), False);
      Boolean_Assert.Eq (Is_Newer (0, Than => Unsigned_32'Last), True);
      Boolean_Assert.Eq (Is_Newer (Unsigned_32'Last, Than => 0), False);
      Boolean_Assert.Eq (Is_Newer (2 ** 31 - 1, Than => 0), True);
      Boolean_Assert.Eq (Is_Newer (2 ** 31, Than => 0), False);

      -- Build a store whose newest copy holds the maximum counter. Save once so
      -- copy A is valid, then poke the counter bytes to the maximum and recompute
      -- the CRC by hand.
      Fill_Garbage (Copy_A_Bytes);
      Fill_Garbage (Copy_B_Bytes);
      Save (Copy_A_Bytes, Copy_B_Bytes, Make_Data (1), Test_Layout_Id, Test_Time, Info);
      Copy_Type_Assert.Eq (Info.Copy, Copy_A);
      Copy_A_Bytes (Save_Counter_Offset .. Save_Counter_Offset + 3) := [16#FF#, 16#FF#, 16#FF#, 16#FF#];
      Copy_A_Bytes (Crc_Offset .. Crc_Offset + 1) := Crc_16.Compute_Crc_16 (Copy_A_Bytes (Save_Counter_Offset .. Copy_A_Bytes'Last));
      Boolean_Assert.Eq (Is_Valid (Copy_A_Bytes, Test_Layout_Id, Test_Data_Length), True);
      Unsigned_32_Assert.Eq (Read_Save_Counter (Copy_A_Bytes), Unsigned_32'Last);
      Check_Restore (Copy_A_Bytes, Copy_B_Bytes, Restored, Copy_A, Unsigned_32'Last, Make_Data (1));

      -- The next save wraps the counter to zero and is still the newest:
      Save (Copy_A_Bytes, Copy_B_Bytes, Make_Data (2), Test_Layout_Id, Test_Time, Info);
      Copy_Type_Assert.Eq (Info.Copy, Copy_B);
      Unsigned_32_Assert.Eq (Info.Save_Counter, 0);
      Check_Restore (Copy_A_Bytes, Copy_B_Bytes, Restored, Copy_B, 0, Make_Data (2));

      -- And the one after that goes to A with counter one:
      Save (Copy_A_Bytes, Copy_B_Bytes, Make_Data (3), Test_Layout_Id, Test_Time, Info);
      Copy_Type_Assert.Eq (Info.Copy, Copy_A);
      Unsigned_32_Assert.Eq (Info.Save_Counter, 1);
      Check_Restore (Copy_A_Bytes, Copy_B_Bytes, Restored, Copy_A, 1, Make_Data (3));
   end Test_Save_Counter_Wraparound;

   overriding procedure Test_Layout_And_Length_Mismatch (Self : in out Instance) is
      Ignore : Instance renames Self;
      Copy_A_Bytes : Test_Copy_Type;
      Copy_B_Bytes : Test_Copy_Type;
      Info : Copy_Info;
      Ignore_Info : Copy_Info;
      Other_Layout_Id : constant Unsigned_32 := Test_Layout_Id + 1;
      Data : Test_Data_Type;
      Status : Restore_Status;
   begin
      Fill_Garbage (Copy_A_Bytes);
      Fill_Garbage (Copy_B_Bytes);
      Save (Copy_A_Bytes, Copy_B_Bytes, Make_Data (1), Test_Layout_Id, Test_Time, Info);
      Copy_Type_Assert.Eq (Info.Copy, Copy_A);
      Save (Copy_A_Bytes, Copy_B_Bytes, Make_Data (2), Test_Layout_Id, Test_Time, Info);
      Copy_Type_Assert.Eq (Info.Copy, Copy_B);

      -- Both copies are valid for the layout they were written with:
      Boolean_Assert.Eq (Is_Valid (Copy_A_Bytes, Test_Layout_Id, Test_Data_Length), True);
      Boolean_Assert.Eq (Is_Valid (Copy_B_Bytes, Test_Layout_Id, Test_Data_Length), True);

      -- Neither is valid for a different layout id, so a restore finds nothing:
      Boolean_Assert.Eq (Is_Valid (Copy_A_Bytes, Other_Layout_Id, Test_Data_Length), False);
      Boolean_Assert.Eq (Is_Valid (Copy_B_Bytes, Other_Layout_Id, Test_Data_Length), False);
      Restore (Copy_A_Bytes, Copy_B_Bytes, Other_Layout_Id, Data, Status, Ignore_Info);
      Restore_Status_Assert.Eq (Status, No_Valid_Copy);
      Byte_Array_Assert.Eq (Data, Test_Data_Type'[others => 0]);

      -- Neither is valid for a different data length either:
      Boolean_Assert.Eq (Is_Valid (Copy_A_Bytes, Test_Layout_Id, Test_Data_Length - 1), False);
      Boolean_Assert.Eq (Is_Valid (Copy_A_Bytes, Test_Layout_Id, Test_Data_Length - 8), False);
      declare
         subtype Short_Data_Type is Byte_Array (0 .. Test_Data_Length - 2);
         Short_Data : Short_Data_Type;
      begin
         Restore (Copy_A_Bytes, Copy_B_Bytes, Test_Layout_Id, Short_Data, Status, Ignore_Info);
         Restore_Status_Assert.Eq (Status, No_Valid_Copy);
         Byte_Array_Assert.Eq (Short_Data, Short_Data_Type'[others => 0]);
      end;

      -- A save under the new layout id starts over in copy A with counter one, since
      -- no copy is valid for it. The old copy B is untouched until the next save.
      Save (Copy_A_Bytes, Copy_B_Bytes, Make_Data (3), Other_Layout_Id, Test_Time, Info);
      Copy_Type_Assert.Eq (Info.Copy, Copy_A);
      Unsigned_32_Assert.Eq (Info.Save_Counter, 1);
      Boolean_Assert.Eq (Is_Valid (Copy_A_Bytes, Other_Layout_Id, Test_Data_Length), True);
      Boolean_Assert.Eq (Is_Valid (Copy_B_Bytes, Test_Layout_Id, Test_Data_Length), True);
      Boolean_Assert.Eq (Is_Valid (Copy_B_Bytes, Other_Layout_Id, Test_Data_Length), False);
   end Test_Layout_And_Length_Mismatch;

   overriding procedure Test_Oversized_Allocations (Self : in out Instance) is
      Ignore : Instance renames Self;
      -- Oversized allocations with nonzero first indices:
      Copy_A_Bytes : Byte_Array (5 .. 5 + Test_Store_Length + 9);
      Copy_B_Bytes : Byte_Array (3 .. 3 + Test_Store_Length + 21);
      Info : Copy_Info;
      Ignore_Info : Copy_Info;
      Data : Test_Data_Type;
      Status : Restore_Status;
   begin
      Copy_A_Bytes := [others => 16#AA#];
      Copy_B_Bytes := [others => 16#BB#];
      Boolean_Assert.Eq (Fits (Copy_A_Bytes, Test_Data_Length), True);
      Boolean_Assert.Eq (Fits (Copy_B_Bytes, Test_Data_Length), True);
      Boolean_Assert.Eq (Fits (Copy_A_Bytes (5 .. 5 + Test_Store_Length - 2), Test_Data_Length), False);

      Save (Copy_A_Bytes, Copy_B_Bytes, Make_Data (1), Test_Layout_Id, Test_Time, Info);
      Copy_Type_Assert.Eq (Info.Copy, Copy_A);
      Save (Copy_A_Bytes, Copy_B_Bytes, Make_Data (2), Test_Layout_Id, Test_Time, Info);
      Copy_Type_Assert.Eq (Info.Copy, Copy_B);

      -- Only the first Store_Length bytes of each allocation are written:
      for Idx in 5 + Test_Store_Length .. Copy_A_Bytes'Last loop
         Byte_Assert.Eq (Copy_A_Bytes (Idx), 16#AA#);
      end loop;
      for Idx in 3 + Test_Store_Length .. Copy_B_Bytes'Last loop
         Byte_Assert.Eq (Copy_B_Bytes (Idx), 16#BB#);
      end loop;

      -- The header sits at the first index of each allocation:
      Unsigned_32_Assert.Eq (Read_Save_Counter (Copy_A_Bytes), 1);
      Unsigned_32_Assert.Eq (Read_Save_Counter (Copy_B_Bytes), 2);
      Byte_Array_Assert.Eq (Copy_A_Bytes (5 + Header_Length .. 5 + Header_Length + 7), Make_Data (1));
      Byte_Array_Assert.Eq (Copy_B_Bytes (3 + Header_Length .. 3 + Header_Length + 7), Make_Data (2));

      -- Restores work from the oversized allocations:
      Restore (Copy_A_Bytes, Copy_B_Bytes, Test_Layout_Id, Data, Status, Info);
      Restore_Status_Assert.Eq (Status, Restored);
      Copy_Type_Assert.Eq (Info.Copy, Copy_B);
      Unsigned_32_Assert.Eq (Info.Save_Counter, 2);
      Byte_Array_Assert.Eq (Data, Make_Data (2));

      -- And a restore into a data array with a nonzero first index:
      declare
         Offset_Data : Byte_Array (100 .. 107) := [others => 16#EE#];
      begin
         Restore (Copy_A_Bytes, Copy_B_Bytes, Test_Layout_Id, Offset_Data, Status, Ignore_Info);
         Restore_Status_Assert.Eq (Status, Restored);
         Byte_Array_Assert.Eq (Offset_Data, Make_Data (2));
      end;

      -- Zero length data is permitted; the store is header only:
      declare
         Empty : constant Byte_Array (1 .. 0) := [];
         Restored_Empty : Byte_Array (1 .. 0);
         Small_A : Byte_Array (0 .. Header_Length - 1) := [others => 0];
         Small_B : Byte_Array (0 .. Header_Length - 1) := [others => 0];
      begin
         Save (Small_A, Small_B, Empty, Test_Layout_Id, Test_Time, Info);
         Copy_Type_Assert.Eq (Info.Copy, Copy_A);
         Boolean_Assert.Eq (Is_Valid (Small_A, Test_Layout_Id, 0), True);
         Restore (Small_A, Small_B, Test_Layout_Id, Restored_Empty, Status, Info);
         Restore_Status_Assert.Eq (Status, Restored);
         Unsigned_32_Assert.Eq (Info.Save_Counter, 1);
         Natural_Assert.Eq (Restored_Empty'Length, 0);
      end;
   end Test_Oversized_Allocations;

   overriding procedure Test_Typed_Wrapper (Self : in out Instance) is
      Ignore : Instance renames Self;

      -- Instantiate the typed wrapper on a packed 32-bit value with layout version 3:
      package U32_Store is new Double_Buffer_Store.Typed (
         T => Packed_U32.T,
         Serialized_Length => Packed_U32.Size_In_Bytes,
         To_Byte_Array => Packed_U32.Serialization.To_Byte_Array,
         From_Byte_Array => Packed_U32.Serialization.From_Byte_Array,
         Layout_Version => 3
      );

      Copy_A_Bytes : Byte_Array (0 .. U32_Store.Store_Length_In_Bytes - 1);
      Copy_B_Bytes : Byte_Array (0 .. U32_Store.Store_Length_In_Bytes - 1);
      Value : Packed_U32.T;
      Status : Restore_Status;
      Info : Copy_Info;
      Ignore_Info : Copy_Info;
   begin
      -- The layout id combines the version and the serialized length:
      Natural_Assert.Eq (U32_Store.Store_Length_In_Bytes, Header_Length + 4);
      Unsigned_32_Assert.Eq (U32_Store.Layout_Id, 16#0003_0004#);

      -- Nothing valid at first:
      Fill_Garbage (Copy_A_Bytes);
      Fill_Garbage (Copy_B_Bytes);
      Boolean_Assert.Eq (U32_Store.Fits (Copy_A_Bytes), True);
      Boolean_Assert.Eq (U32_Store.Is_Valid (Copy_A_Bytes), False);
      U32_Store.Restore (Copy_A_Bytes, Copy_B_Bytes, Value, Status, Ignore_Info);
      Restore_Status_Assert.Eq (Status, No_Valid_Copy);
      Packed_U32_Assert.Eq (Value, (Value => 0));

      -- Save and restore a value:
      U32_Store.Save (Copy_A_Bytes, Copy_B_Bytes, (Value => 16#1234_5678#), Test_Time, Info);
      Copy_Type_Assert.Eq (Info.Copy, Copy_A);
      Unsigned_32_Assert.Eq (Info.Save_Counter, 1);
      Boolean_Assert.Eq (U32_Store.Is_Valid (Copy_A_Bytes), True);
      Boolean_Assert.Eq (U32_Store.Is_Valid (Copy_B_Bytes), False);
      U32_Store.Restore (Copy_A_Bytes, Copy_B_Bytes, Value, Status, Info);
      Restore_Status_Assert.Eq (Status, Restored);
      Copy_Type_Assert.Eq (Info.Copy, Copy_A);
      Packed_U32_Assert.Eq (Value, (Value => 16#1234_5678#));

      -- The bytes in the store are the big endian serialization of the record:
      Byte_Array_Assert.Eq (Copy_A_Bytes (Header_Length .. Header_Length + 3), [16#12#, 16#34#, 16#56#, 16#78#]);
      Byte_Array_Assert.Eq (Copy_A_Bytes (Layout_Id_Offset .. Layout_Id_Offset + 3), [0, 3, 0, 4]);

      -- A second save alternates and the restore returns the newest:
      U32_Store.Save (Copy_A_Bytes, Copy_B_Bytes, (Value => 16#0000_0007#), Test_Time, Info);
      Copy_Type_Assert.Eq (Info.Copy, Copy_B);
      Unsigned_32_Assert.Eq (Info.Save_Counter, 2);
      U32_Store.Restore (Copy_A_Bytes, Copy_B_Bytes, Value, Status, Info);
      Restore_Status_Assert.Eq (Status, Restored);
      Copy_Type_Assert.Eq (Info.Copy, Copy_B);
      Packed_U32_Assert.Eq (Value, (Value => 7));

      -- A store written by a different layout version is not valid for this one:
      declare
         package Other_Version_Store is new Double_Buffer_Store.Typed (
            T => Packed_U32.T,
            Serialized_Length => Packed_U32.Size_In_Bytes,
            To_Byte_Array => Packed_U32.Serialization.To_Byte_Array,
            From_Byte_Array => Packed_U32.Serialization.From_Byte_Array,
            Layout_Version => 4
         );
      begin
         Boolean_Assert.Eq (Other_Version_Store.Is_Valid (Copy_A_Bytes), False);
         Boolean_Assert.Eq (Other_Version_Store.Is_Valid (Copy_B_Bytes), False);
         Other_Version_Store.Restore (Copy_A_Bytes, Copy_B_Bytes, Value, Status, Ignore_Info);
         Restore_Status_Assert.Eq (Status, No_Valid_Copy);
         Packed_U32_Assert.Eq (Value, (Value => 0));
      end;
   end Test_Typed_Wrapper;

end Double_Buffer_Store_Tests.Implementation;

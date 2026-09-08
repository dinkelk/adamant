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

   -- Save times, in increasing order:
   Time_1 : constant Sys_Time.T := (Seconds => 1_234, Subseconds => 5_678);
   Time_2 : constant Sys_Time.T := (Seconds => 1_234, Subseconds => 5_679);
   Time_3 : constant Sys_Time.T := (Seconds => 1_235, Subseconds => 0);
   Time_4 : constant Sys_Time.T := (Seconds => 2_000, Subseconds => 0);

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

   -- Check that a restore of the test store returns the expected status, copy, and
   -- data:
   procedure Check_Restore (
      Copy_A_Bytes : in Byte_Array;
      Copy_B_Bytes : in Byte_Array;
      Expected_Status : in Restore_Status;
      Expected_Source : in Copy_Type;
      Expected_Data : in Test_Data_Type
   ) is
      Data : Test_Data_Type := [others => 16#EE#];
      Status : Restore_Status;
      Source : Copy_Type;
   begin
      Restore (Copy_A_Bytes, Copy_B_Bytes, Data, Status, Source);
      Restore_Status_Assert.Eq (Status, Expected_Status);
      if Expected_Status = Restored then
         Copy_Type_Assert.Eq (Source, Expected_Source);
      end if;
      Byte_Array_Assert.Eq (Data, Expected_Data);
   end Check_Restore;

   -- Check the validity of both copies:
   procedure Check_Valid (Copy_A_Bytes : in Byte_Array; Copy_B_Bytes : in Byte_Array; A_Valid : in Boolean; B_Valid : in Boolean) is
   begin
      Boolean_Assert.Eq (Is_Valid (Copy_A_Bytes, Test_Data_Length), A_Valid);
      Boolean_Assert.Eq (Is_Valid (Copy_B_Bytes, Test_Data_Length), B_Valid);
   end Check_Valid;

   -- Build the bytes a save would write into a copy, for emulating interrupted saves:
   function Encode (Data : in Test_Data_Type; Save_Time : in Sys_Time.T) return Test_Copy_Type is
      Copy : Test_Copy_Type := [others => 0];
   begin
      Copy (Save_Time_Offset .. Save_Time_Offset + Sys_Time.Size_In_Bytes - 1) := Sys_Time.Serialization.To_Byte_Array (Save_Time);
      Copy (Header_Length .. Copy'Last) := Data;
      Copy (Crc_Offset .. Crc_Offset + 1) := Crc_16.Compute_Crc_16 (Copy (Save_Time_Offset .. Copy'Last));
      return Copy;
   end Encode;

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
   begin
      -- Garbage in both copies:
      Fill_Garbage (Copy_A_Bytes);
      Fill_Garbage (Copy_B_Bytes);
      Check_Valid (Copy_A_Bytes, Copy_B_Bytes, False, False);
      Check_Restore (Copy_A_Bytes, Copy_B_Bytes, No_Valid_Copy, Copy_A, [others => 0]);

      -- All zeros in both copies is also not a valid store, since the CRC of the
      -- zeroed contents is not zero:
      Copy_A_Bytes := [others => 0];
      Copy_B_Bytes := [others => 0];
      Check_Valid (Copy_A_Bytes, Copy_B_Bytes, False, False);
      Check_Restore (Copy_A_Bytes, Copy_B_Bytes, No_Valid_Copy, Copy_A, [others => 0]);

      -- All ones, the erased state of many nonvolatile memories, is not valid either:
      Copy_A_Bytes := [others => 16#FF#];
      Copy_B_Bytes := [others => 16#FF#];
      Check_Valid (Copy_A_Bytes, Copy_B_Bytes, False, False);
      Check_Restore (Copy_A_Bytes, Copy_B_Bytes, No_Valid_Copy, Copy_A, [others => 0]);
   end Test_No_Valid_Copy_On_First_Boot;

   overriding procedure Test_Save_Alternates_And_Invalidates (Self : in out Instance) is
      Ignore : Instance renames Self;
      Copy_A_Bytes : Test_Copy_Type;
      Copy_B_Bytes : Test_Copy_Type;
      Written : Copy_Type;
   begin
      Fill_Garbage (Copy_A_Bytes);
      Fill_Garbage (Copy_B_Bytes);

      -- First save goes to copy A:
      Save (Copy_A_Bytes, Copy_B_Bytes, Make_Data (1), Time_1, Written);
      Copy_Type_Assert.Eq (Written, Copy_A);
      Check_Valid (Copy_A_Bytes, Copy_B_Bytes, True, False);
      Sys_Time_Assert.Eq (Read_Save_Time (Copy_A_Bytes), Time_1);
      Check_Restore (Copy_A_Bytes, Copy_B_Bytes, Restored, Copy_A, Make_Data (1));

      -- Second save goes to copy B and invalidates copy A by zeroing its save time.
      -- The rest of copy A is left alone.
      Save (Copy_A_Bytes, Copy_B_Bytes, Make_Data (2), Time_2, Written);
      Copy_Type_Assert.Eq (Written, Copy_B);
      Check_Valid (Copy_A_Bytes, Copy_B_Bytes, False, True);
      Sys_Time_Assert.Eq (Read_Save_Time (Copy_A_Bytes), (Seconds => 0, Subseconds => 0));
      Sys_Time_Assert.Eq (Read_Save_Time (Copy_B_Bytes), Time_2);
      Byte_Array_Assert.Eq (Copy_A_Bytes (Header_Length .. Copy_A_Bytes'Last), Make_Data (1));
      Check_Restore (Copy_A_Bytes, Copy_B_Bytes, Restored, Copy_B, Make_Data (2));

      -- Third save goes back to copy A:
      Save (Copy_A_Bytes, Copy_B_Bytes, Make_Data (3), Time_3, Written);
      Copy_Type_Assert.Eq (Written, Copy_A);
      Check_Valid (Copy_A_Bytes, Copy_B_Bytes, True, False);
      Check_Restore (Copy_A_Bytes, Copy_B_Bytes, Restored, Copy_A, Make_Data (3));

      -- Fourth save goes to copy B:
      Save (Copy_A_Bytes, Copy_B_Bytes, Make_Data (4), Time_4, Written);
      Copy_Type_Assert.Eq (Written, Copy_B);
      Check_Valid (Copy_A_Bytes, Copy_B_Bytes, False, True);
      Check_Restore (Copy_A_Bytes, Copy_B_Bytes, Restored, Copy_B, Make_Data (4));

      -- Check the header layout directly on copy B: CRC, save time, data.
      Natural_Assert.Eq (Header_Length, 2 + Sys_Time.Size_In_Bytes);
      Byte_Array_Assert.Eq (Copy_B_Bytes (Crc_Offset .. Crc_Offset + 1), Crc_16.Compute_Crc_16 (Copy_B_Bytes (Save_Time_Offset .. Copy_B_Bytes'Last)));
      Byte_Array_Assert.Eq (Copy_B_Bytes (Save_Time_Offset .. Save_Time_Offset + Sys_Time.Size_In_Bytes - 1), Sys_Time.Serialization.To_Byte_Array (Time_4));
      Byte_Array_Assert.Eq (Copy_B_Bytes (Header_Length .. Header_Length + 7), Make_Data (4));
      Byte_Array_Assert.Eq (Copy_B_Bytes, Encode (Make_Data (4), Time_4));
   end Test_Save_Alternates_And_Invalidates;

   overriding procedure Test_Interrupted_Save (Self : in out Instance) is
      Ignore : Instance renames Self;
      Copy_A_Bytes : Test_Copy_Type;
      Copy_B_Bytes : Test_Copy_Type;
      Written : Copy_Type;
      Next : constant Test_Copy_Type := Encode (Make_Data (2), Time_2);
   begin
      -- Start from a store holding one save in copy A. The next save goes to copy B
      -- and the reboot can land at each point of that save.
      Fill_Garbage (Copy_A_Bytes);
      Fill_Garbage (Copy_B_Bytes);
      Save (Copy_A_Bytes, Copy_B_Bytes, Make_Data (1), Time_1, Written);
      Copy_Type_Assert.Eq (Written, Copy_A);

      -- Reboot after the save time and data reach copy B but before its CRC. Copy B is
      -- not valid and copy A still holds the data.
      Copy_B_Bytes (Save_Time_Offset .. Copy_B_Bytes'Last) := Next (Save_Time_Offset .. Next'Last);
      Check_Valid (Copy_A_Bytes, Copy_B_Bytes, True, False);
      Check_Restore (Copy_A_Bytes, Copy_B_Bytes, Restored, Copy_A, Make_Data (1));

      -- Reboot after the CRC reaches copy B but before copy A is invalidated. Both are
      -- valid and the later save time wins.
      Copy_B_Bytes := Next;
      Check_Valid (Copy_A_Bytes, Copy_B_Bytes, True, True);
      Check_Restore (Copy_A_Bytes, Copy_B_Bytes, Restored, Copy_B, Make_Data (2));

      -- The same with the copies swapped, so the later time is in copy A:
      Check_Restore (Copy_B_Bytes, Copy_A_Bytes, Restored, Copy_A, Make_Data (2));

      -- Equal save times fall back to copy A:
      Copy_B_Bytes := Encode (Make_Data (3), Time_1);
      Check_Valid (Copy_A_Bytes, Copy_B_Bytes, True, True);
      Check_Restore (Copy_A_Bytes, Copy_B_Bytes, Restored, Copy_A, Make_Data (1));

      -- After a reboot with both copies valid, the next save overwrites the older one
      -- and invalidates the newer, which is the normal alternation from the newest:
      Copy_B_Bytes := Next;
      Save (Copy_A_Bytes, Copy_B_Bytes, Make_Data (4), Time_3, Written);
      Copy_Type_Assert.Eq (Written, Copy_A);
      Check_Valid (Copy_A_Bytes, Copy_B_Bytes, True, False);
      Check_Restore (Copy_A_Bytes, Copy_B_Bytes, Restored, Copy_A, Make_Data (4));

      -- Reboot during the very first save, before its CRC. Nothing is valid.
      Fill_Garbage (Copy_A_Bytes);
      Fill_Garbage (Copy_B_Bytes);
      Copy_A_Bytes (Save_Time_Offset .. Copy_A_Bytes'Last) := Next (Save_Time_Offset .. Next'Last);
      Check_Valid (Copy_A_Bytes, Copy_B_Bytes, False, False);
      Check_Restore (Copy_A_Bytes, Copy_B_Bytes, No_Valid_Copy, Copy_A, [others => 0]);
   end Test_Interrupted_Save;

   overriding procedure Test_Corrupt_Copy (Self : in out Instance) is
      Ignore : Instance renames Self;
      Copy_A_Bytes : Test_Copy_Type;
      Copy_B_Bytes : Test_Copy_Type;
      Written : Copy_Type;
      Ignore_Written : Copy_Type;
   begin
      Fill_Garbage (Copy_A_Bytes);
      Fill_Garbage (Copy_B_Bytes);
      Save (Copy_A_Bytes, Copy_B_Bytes, Make_Data (1), Time_1, Ignore_Written);
      Save (Copy_A_Bytes, Copy_B_Bytes, Make_Data (2), Time_2, Written);
      Copy_Type_Assert.Eq (Written, Copy_B);

      -- Flip a data bit in the only valid copy. Nothing is valid, since the other copy
      -- was invalidated by the save.
      Copy_B_Bytes (Header_Length + 3) := Copy_B_Bytes (Header_Length + 3) xor 16#01#;
      Check_Valid (Copy_A_Bytes, Copy_B_Bytes, False, False);
      Check_Restore (Copy_A_Bytes, Copy_B_Bytes, No_Valid_Copy, Copy_A, [others => 0]);

      -- The next save starts over in copy A and invalidates copy B:
      Save (Copy_A_Bytes, Copy_B_Bytes, Make_Data (3), Time_3, Written);
      Copy_Type_Assert.Eq (Written, Copy_A);
      Check_Valid (Copy_A_Bytes, Copy_B_Bytes, True, False);
      Check_Restore (Copy_A_Bytes, Copy_B_Bytes, Restored, Copy_A, Make_Data (3));

      -- A flipped CRC bit invalidates a copy as well:
      Copy_A_Bytes (Crc_Offset) := Copy_A_Bytes (Crc_Offset) xor 16#10#;
      Check_Valid (Copy_A_Bytes, Copy_B_Bytes, False, False);

      -- And so does a flipped save time bit:
      Copy_A_Bytes (Crc_Offset) := Copy_A_Bytes (Crc_Offset) xor 16#10#;
      Check_Valid (Copy_A_Bytes, Copy_B_Bytes, True, False);
      Copy_A_Bytes (Save_Time_Offset + 1) := Copy_A_Bytes (Save_Time_Offset + 1) xor 16#80#;
      Check_Valid (Copy_A_Bytes, Copy_B_Bytes, False, False);
   end Test_Corrupt_Copy;

   overriding procedure Test_Oversized_Allocations (Self : in out Instance) is
      Ignore : Instance renames Self;
      -- Copies larger than the store with nonzero first indices:
      Copy_A_Bytes : Byte_Array (5 .. 5 + Test_Store_Length + 9) := [others => 16#AA#];
      Copy_B_Bytes : Byte_Array (3 .. 3 + Test_Store_Length + 21) := [others => 16#BB#];
      Written : Copy_Type;
      Data : Test_Data_Type;
      Status : Restore_Status;
      Source : Copy_Type;
      Ignore_Source : Copy_Type;
   begin
      Boolean_Assert.Eq (Fits (Copy_A_Bytes, Test_Data_Length), True);
      Boolean_Assert.Eq (Fits (Copy_A_Bytes (5 .. 5 + Test_Store_Length - 2), Test_Data_Length), False);

      Save (Copy_A_Bytes, Copy_B_Bytes, Make_Data (1), Time_1, Written);
      Copy_Type_Assert.Eq (Written, Copy_A);
      Save (Copy_A_Bytes, Copy_B_Bytes, Make_Data (2), Time_2, Written);
      Copy_Type_Assert.Eq (Written, Copy_B);

      -- Only the leading Store_Length bytes of each copy are written:
      Byte_Array_Assert.Eq (Copy_A_Bytes (5 + Test_Store_Length .. Copy_A_Bytes'Last), [for Idx in 5 + Test_Store_Length .. Copy_A_Bytes'Last => 16#AA#]);
      Byte_Array_Assert.Eq (Copy_B_Bytes (3 + Test_Store_Length .. Copy_B_Bytes'Last), [for Idx in 3 + Test_Store_Length .. Copy_B_Bytes'Last => 16#BB#]);

      -- The store sits at the first index of each copy:
      Byte_Array_Assert.Eq (Copy_B_Bytes (3 .. 3 + Test_Store_Length - 1), Encode (Make_Data (2), Time_2));
      Byte_Array_Assert.Eq (Copy_A_Bytes (5 + Header_Length .. 5 + Header_Length + 7), Make_Data (1));
      Sys_Time_Assert.Eq (Read_Save_Time (Copy_A_Bytes), (Seconds => 0, Subseconds => 0));

      -- Restores work from the oversized copies:
      Restore (Copy_A_Bytes, Copy_B_Bytes, Data, Status, Source);
      Restore_Status_Assert.Eq (Status, Restored);
      Copy_Type_Assert.Eq (Source, Copy_B);
      Byte_Array_Assert.Eq (Data, Make_Data (2));

      -- And into a data array with a nonzero first index:
      declare
         Offset_Data : Byte_Array (100 .. 107);
      begin
         Restore (Copy_A_Bytes, Copy_B_Bytes, Offset_Data, Status, Ignore_Source);
         Restore_Status_Assert.Eq (Status, Restored);
         Byte_Array_Assert.Eq (Offset_Data, Make_Data (2));
      end;

      -- Zero length data is permitted; the store is header only:
      declare
         Small_A : Byte_Array (0 .. Header_Length - 1) := [others => 0];
         Small_B : Byte_Array (0 .. Header_Length - 1) := [others => 0];
         Empty : constant Byte_Array (1 .. 0) := [];
         Restored_Empty : Byte_Array (1 .. 0);
      begin
         Natural_Assert.Eq (Store_Length (0), Header_Length);
         Save (Small_A, Small_B, Empty, Time_1, Written);
         Copy_Type_Assert.Eq (Written, Copy_A);
         Boolean_Assert.Eq (Is_Valid (Small_A, 0), True);
         Boolean_Assert.Eq (Is_Valid (Small_B, 0), False);
         Restore (Small_A, Small_B, Restored_Empty, Status, Source);
         Restore_Status_Assert.Eq (Status, Restored);
         Copy_Type_Assert.Eq (Source, Copy_A);
         Natural_Assert.Eq (Restored_Empty'Length, 0);
      end;
   end Test_Oversized_Allocations;

   overriding procedure Test_Typed_Wrapper (Self : in out Instance) is
      Ignore : Instance renames Self;

      package U32_Store is new Double_Buffer_Store.Typed (
         T => Packed_U32.T,
         Serialized_Length => Packed_U32.Size_In_Bytes,
         To_Byte_Array => Packed_U32.Serialization.To_Byte_Array,
         From_Byte_Array => Packed_U32.Serialization.From_Byte_Array
      );

      Copy_A_Bytes : Byte_Array (0 .. U32_Store.Store_Length_In_Bytes - 1);
      Copy_B_Bytes : Byte_Array (0 .. U32_Store.Store_Length_In_Bytes - 1);
      Value : Packed_U32.T;
      Status : Restore_Status;
      Written : Copy_Type;
      Source : Copy_Type;
   begin
      Natural_Assert.Eq (U32_Store.Store_Length_In_Bytes, Header_Length + 4);
      Fill_Garbage (Copy_A_Bytes);
      Fill_Garbage (Copy_B_Bytes);

      -- Nothing valid at first:
      Boolean_Assert.Eq (U32_Store.Is_Valid (Copy_A_Bytes), False);
      Boolean_Assert.Eq (U32_Store.Is_Valid (Copy_B_Bytes), False);
      U32_Store.Restore (Copy_A_Bytes, Copy_B_Bytes, Value, Status, Source);
      Restore_Status_Assert.Eq (Status, No_Valid_Copy);
      Packed_U32_Assert.Eq (Value, (Value => 0));

      -- Save and restore a value:
      U32_Store.Save (Copy_A_Bytes, Copy_B_Bytes, (Value => 16#1234_5678#), Time_1, Written);
      Copy_Type_Assert.Eq (Written, Copy_A);
      Boolean_Assert.Eq (U32_Store.Is_Valid (Copy_A_Bytes), True);
      Boolean_Assert.Eq (U32_Store.Is_Valid (Copy_B_Bytes), False);
      U32_Store.Restore (Copy_A_Bytes, Copy_B_Bytes, Value, Status, Source);
      Restore_Status_Assert.Eq (Status, Restored);
      Copy_Type_Assert.Eq (Source, Copy_A);
      Packed_U32_Assert.Eq (Value, (Value => 16#1234_5678#));

      -- The bytes in memory are the big endian serialization of the record:
      Byte_Array_Assert.Eq (Copy_A_Bytes (Header_Length .. Header_Length + 3), [16#12#, 16#34#, 16#56#, 16#78#]);

      -- A second save alternates and invalidates the first:
      U32_Store.Save (Copy_A_Bytes, Copy_B_Bytes, (Value => 7), Time_2, Written);
      Copy_Type_Assert.Eq (Written, Copy_B);
      Boolean_Assert.Eq (U32_Store.Is_Valid (Copy_A_Bytes), False);
      Boolean_Assert.Eq (U32_Store.Is_Valid (Copy_B_Bytes), True);
      U32_Store.Restore (Copy_A_Bytes, Copy_B_Bytes, Value, Status, Source);
      Restore_Status_Assert.Eq (Status, Restored);
      Copy_Type_Assert.Eq (Source, Copy_B);
      Packed_U32_Assert.Eq (Value, (Value => 7));
   end Test_Typed_Wrapper;

end Double_Buffer_Store_Tests.Implementation;

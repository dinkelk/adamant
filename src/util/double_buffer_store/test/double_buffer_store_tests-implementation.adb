--------------------------------------------------------------------------------
-- Double_Buffer_Store Tests Body
--------------------------------------------------------------------------------

with Basic_Types; use Basic_Types;
with Basic_Assertions; use Basic_Assertions;
with Crc_16;
with Double_Buffer_Store;
with Double_Buffer_Store_Layout;
with Double_Buffer_Store_Typed;
with Double_Buffer_Store_Types; use Double_Buffer_Store_Types;
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
   -- Stores under test. The copies stand in for persistent memory.
   -------------------------------------------------------------------------

   Test_Data_Length : constant Data_Length_Type := 8;
   subtype Test_Data_Type is Byte_Array (0 .. Test_Data_Length - 1);
   Test_Store_Length : constant Natural := Store_Length (Test_Data_Length);

   Test_Layout_Id : constant Unsigned_32 := 16#0102_0304#;
   Other_Layout_Id : constant Unsigned_32 := Test_Layout_Id + 1;
   Test_Time : constant Sys_Time.T := (Seconds => 1_234, Subseconds => 5_678);

   -- Copies exactly one store long, and stores over them with the nominal layout,
   -- another layout id, and a shorter data length:
   Region_A : Persistent_Bytes := [0 .. Test_Store_Length - 1 => 16#FF#];
   Region_B : Persistent_Bytes := [0 .. Test_Store_Length - 1 => 16#FF#];
   package Store is new Double_Buffer_Store (Region_A, Region_B, Test_Layout_Id, Test_Data_Length);
   package Other_Layout_Store is new Double_Buffer_Store (Region_A, Region_B, Other_Layout_Id, Test_Data_Length);
   package Short_Store is new Double_Buffer_Store (Region_A, Region_B, Test_Layout_Id, Test_Data_Length - 1);

   -- Oversized copies with nonzero first indices:
   Big_A : Persistent_Bytes (5 .. 5 + Test_Store_Length + 9) := [others => 16#AA#];
   Big_B : Persistent_Bytes (3 .. 3 + Test_Store_Length + 21) := [others => 16#BB#];
   package Big_Store is new Double_Buffer_Store (Big_A, Big_B, Test_Layout_Id, Test_Data_Length);

   -- Copies for a store of zero length data, which is header only:
   Small_A : Persistent_Bytes (0 .. Header_Length - 1) := [others => 0];
   Small_B : Persistent_Bytes (0 .. Header_Length - 1) := [others => 0];
   package Empty_Store is new Double_Buffer_Store (Small_A, Small_B, Test_Layout_Id, 0);

   -- Copies for typed stores over a packed 32-bit value, with two layout versions:
   Typed_A : Persistent_Bytes := [0 .. Store_Length (Packed_U32.Size_In_Bytes) - 1 => 16#FF#];
   Typed_B : Persistent_Bytes := [0 .. Store_Length (Packed_U32.Size_In_Bytes) - 1 => 16#FF#];
   package U32_Store is new Double_Buffer_Store_Typed (
      Region_A => Typed_A,
      Region_B => Typed_B,
      T => Packed_U32.T,
      Serialized_Length => Packed_U32.Size_In_Bytes,
      To_Byte_Array => Packed_U32.Serialization.To_Byte_Array,
      From_Byte_Array => Packed_U32.Serialization.From_Byte_Array,
      Layout_Version => 3
   );
   package Other_Version_Store is new Double_Buffer_Store_Typed (
      Region_A => Typed_A,
      Region_B => Typed_B,
      T => Packed_U32.T,
      Serialized_Length => Packed_U32.Size_In_Bytes,
      To_Byte_Array => Packed_U32.Serialization.To_Byte_Array,
      From_Byte_Array => Packed_U32.Serialization.From_Byte_Array,
      Layout_Version => 4
   );

   -------------------------------------------------------------------------
   -- Test helpers:
   -------------------------------------------------------------------------

   -- Produce a distinguishable data block from a seed:
   function Make_Data (Seed : in Byte) return Test_Data_Type is
      Data : Test_Data_Type;
   begin
      for Idx in Data'Range loop
         Data (Idx) := Seed + Byte (Idx);
      end loop;
      return Data;
   end Make_Data;

   -- Fill a copy with a garbage pattern that is not a valid store:
   procedure Fill_Garbage (Region : in out Persistent_Bytes) is
   begin
      for Idx in Region'Range loop
         Region (Idx) := Byte ((Idx * 37 + 11) mod 256);
      end loop;
   end Fill_Garbage;

   -- Read a copy out of memory for inspection:
   function Snapshot (Region : in Persistent_Bytes) return Byte_Array is
      (Byte_Array (Region));

   -- Check that a restore of the nominal store returns the expected status, copy,
   -- counter and data:
   procedure Check_Restore (
      Expected_Status : in Restore_Status;
      Expected_Copy : in Copy_Type;
      Expected_Counter : in Unsigned_32;
      Expected_Data : in Test_Data_Type
   ) is
      Data : Test_Data_Type;
      Status : Restore_Status;
      Info : Copy_Info;
   begin
      Store.Restore (Data, Status, Info);
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
      Ignore : Instance renames Self;
   begin
      -- Every test starts with copies holding no valid save:
      Fill_Garbage (Region_A);
      Fill_Garbage (Region_B);
      Big_A := [others => 16#AA#];
      Big_B := [others => 16#BB#];
      Small_A := [others => 0];
      Small_B := [others => 0];
      Fill_Garbage (Typed_A);
      Fill_Garbage (Typed_B);
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
   begin
      -- Garbage in both copies:
      Boolean_Assert.Eq (Store.Is_Valid (Copy_A), False);
      Boolean_Assert.Eq (Store.Is_Valid (Copy_B), False);
      Check_Restore (No_Valid_Copy, Copy_A, 0, [others => 0]);

      -- All zeros in both copies is also not a valid store, since the CRC of the
      -- zeroed contents is not zero:
      Region_A := [others => 0];
      Region_B := [others => 0];
      Boolean_Assert.Eq (Store.Is_Valid (Copy_A), False);
      Check_Restore (No_Valid_Copy, Copy_A, 0, [others => 0]);

      -- All ones, the erased state of many nonvolatile memories, is not valid either:
      Region_A := [others => 16#FF#];
      Region_B := [others => 16#FF#];
      Check_Restore (No_Valid_Copy, Copy_A, 0, [others => 0]);
   end Test_No_Valid_Copy_On_First_Boot;

   overriding procedure Test_Save_And_Restore_Alternate_Copies (Self : in out Instance) is
      Ignore : Instance renames Self;
      Info : Copy_Info;
   begin
      -- First save goes to copy A with counter one:
      Store.Save (Make_Data (1), Test_Time, Info);
      Copy_Type_Assert.Eq (Info.Copy, Copy_A);
      Unsigned_32_Assert.Eq (Info.Save_Counter, 1);
      Boolean_Assert.Eq (Store.Is_Valid (Copy_A), True);
      Boolean_Assert.Eq (Store.Is_Valid (Copy_B), False);
      Unsigned_32_Assert.Eq (Store.Save_Counter (Copy_A), 1);
      Sys_Time_Assert.Eq (Store.Save_Time (Copy_A), Test_Time);
      Check_Restore (Restored, Copy_A, 1, Make_Data (1));

      -- Second save goes to copy B with counter two, copy A untouched:
      Store.Save (Make_Data (2), (Seconds => 2, Subseconds => 0), Info);
      Copy_Type_Assert.Eq (Info.Copy, Copy_B);
      Unsigned_32_Assert.Eq (Info.Save_Counter, 2);
      Boolean_Assert.Eq (Store.Is_Valid (Copy_A), True);
      Boolean_Assert.Eq (Store.Is_Valid (Copy_B), True);
      Unsigned_32_Assert.Eq (Store.Save_Counter (Copy_A), 1);
      Unsigned_32_Assert.Eq (Store.Save_Counter (Copy_B), 2);
      Sys_Time_Assert.Eq (Store.Save_Time (Copy_B), (Seconds => 2, Subseconds => 0));
      Check_Restore (Restored, Copy_B, 2, Make_Data (2));

      -- Third save goes back to copy A with counter three:
      Store.Save (Make_Data (3), Test_Time, Info);
      Copy_Type_Assert.Eq (Info.Copy, Copy_A);
      Unsigned_32_Assert.Eq (Info.Save_Counter, 3);
      Unsigned_32_Assert.Eq (Store.Save_Counter (Copy_B), 2);
      Check_Restore (Restored, Copy_A, 3, Make_Data (3));

      -- Fourth save goes to copy B with counter four:
      Store.Save (Make_Data (4), Test_Time, Info);
      Copy_Type_Assert.Eq (Info.Copy, Copy_B);
      Unsigned_32_Assert.Eq (Info.Save_Counter, 4);
      Check_Restore (Restored, Copy_B, 4, Make_Data (4));

      -- Check the header layout directly in memory on copy B: CRC, counter, save
      -- time, layout id, length, data.
      declare
         B : constant Byte_Array := Snapshot (Region_B);
      begin
         Natural_Assert.Eq (Header_Length, 12 + Sys_Time.Size_In_Bytes);
         Byte_Array_Assert.Eq (B (Crc_Offset .. Crc_Offset + 1), Crc_16.Compute_Crc_16 (B (Save_Counter_Offset .. B'Last)));
         Byte_Array_Assert.Eq (B (Save_Counter_Offset .. Save_Counter_Offset + 3), [0, 0, 0, 4]);
         Byte_Array_Assert.Eq (B (Save_Time_Offset .. Save_Time_Offset + Sys_Time.Size_In_Bytes - 1), Sys_Time.Serialization.To_Byte_Array (Test_Time));
         Byte_Array_Assert.Eq (B (Layout_Id_Offset .. Layout_Id_Offset + 3), [16#01#, 16#02#, 16#03#, 16#04#]);
         Byte_Array_Assert.Eq (B (Data_Length_Offset .. Data_Length_Offset + 1), [0, 8]);
         Byte_Array_Assert.Eq (B (Header_Length .. Header_Length + 7), Make_Data (4));
         -- The layout package agrees with the store about this copy:
         Boolean_Assert.Eq (Double_Buffer_Store_Layout.Is_Valid (B, Test_Layout_Id, Test_Data_Length), True);
         Unsigned_32_Assert.Eq (Double_Buffer_Store_Layout.Read_Save_Counter (B), 4);
      end;
   end Test_Save_And_Restore_Alternate_Copies;

   overriding procedure Test_Restore_From_Older_Copy_When_Newest_Corrupt (Self : in out Instance) is
      Ignore : Instance renames Self;
      Info : Copy_Info;
   begin
      Store.Save (Make_Data (1), Test_Time, Info);
      Copy_Type_Assert.Eq (Info.Copy, Copy_A);
      Store.Save (Make_Data (2), Test_Time, Info);
      Copy_Type_Assert.Eq (Info.Copy, Copy_B);
      Check_Restore (Restored, Copy_B, 2, Make_Data (2));

      -- Flip a data bit in the newest copy (B). The restore falls back to A.
      Region_B (Header_Length + 3) := Region_B (Header_Length + 3) xor 16#01#;
      Boolean_Assert.Eq (Store.Is_Valid (Copy_B), False);
      Check_Restore (Restored, Copy_A, 1, Make_Data (1));

      -- The next save rewrites the invalid copy B, not the only good copy A:
      Store.Save (Make_Data (3), Test_Time, Info);
      Copy_Type_Assert.Eq (Info.Copy, Copy_B);
      Unsigned_32_Assert.Eq (Info.Save_Counter, 2);
      Check_Restore (Restored, Copy_B, 2, Make_Data (3));

      -- Flip a header bit (the counter) in the newest copy. Falls back to A again.
      Region_B (Save_Counter_Offset + 3) := Region_B (Save_Counter_Offset + 3) xor 16#80#;
      Check_Restore (Restored, Copy_A, 1, Make_Data (1));

      -- Flip a CRC bit in copy A as well. Now nothing is valid.
      Region_A (Crc_Offset) := Region_A (Crc_Offset) xor 16#10#;
      Check_Restore (No_Valid_Copy, Copy_A, 0, [others => 0]);

      -- Emulate a reboot in the middle of a save. Start from a good store with the
      -- newest save in A, then write everything except the CRC into B, as an
      -- interrupted save would. The restore must still come from A.
      Fill_Garbage (Region_A);
      Fill_Garbage (Region_B);
      Store.Save (Make_Data (7), Test_Time, Info);
      Copy_Type_Assert.Eq (Info.Copy, Copy_A);
      declare
         Interrupted : Byte_Array (0 .. Test_Store_Length - 1);
      begin
         Double_Buffer_Store_Layout.Encode (Interrupted, Make_Data (8), Test_Layout_Id, Test_Time, 2);
         Region_B (Save_Counter_Offset .. Region_B'Last) := Persistent_Bytes (Interrupted (Save_Counter_Offset .. Interrupted'Last));
      end;
      Boolean_Assert.Eq (Store.Is_Valid (Copy_B), False);
      Check_Restore (Restored, Copy_A, 1, Make_Data (7));

      -- Completing the save (rewriting B in full) recovers normally:
      Store.Save (Make_Data (8), Test_Time, Info);
      Copy_Type_Assert.Eq (Info.Copy, Copy_B);
      Unsigned_32_Assert.Eq (Info.Save_Counter, 2);
      Check_Restore (Restored, Copy_B, 2, Make_Data (8));
   end Test_Restore_From_Older_Copy_When_Newest_Corrupt;

   overriding procedure Test_Save_Counter_Wraparound (Self : in out Instance) is
      Ignore : Instance renames Self;
      Info : Copy_Info;
   begin
      -- Is_Newer is wraparound-aware:
      Boolean_Assert.Eq (Double_Buffer_Store_Layout.Is_Newer (1, Than => 0), True);
      Boolean_Assert.Eq (Double_Buffer_Store_Layout.Is_Newer (0, Than => 1), False);
      Boolean_Assert.Eq (Double_Buffer_Store_Layout.Is_Newer (5, Than => 5), False);
      Boolean_Assert.Eq (Double_Buffer_Store_Layout.Is_Newer (0, Than => Unsigned_32'Last), True);
      Boolean_Assert.Eq (Double_Buffer_Store_Layout.Is_Newer (Unsigned_32'Last, Than => 0), False);
      Boolean_Assert.Eq (Double_Buffer_Store_Layout.Is_Newer (2 ** 31 - 1, Than => 0), True);
      Boolean_Assert.Eq (Double_Buffer_Store_Layout.Is_Newer (2 ** 31, Than => 0), False);

      -- Build a store whose newest copy holds the maximum counter. Save once so copy
      -- A is valid, then poke the counter bytes to the maximum and recompute the CRC
      -- by hand.
      Store.Save (Make_Data (1), Test_Time, Info);
      Copy_Type_Assert.Eq (Info.Copy, Copy_A);
      Region_A (Save_Counter_Offset .. Save_Counter_Offset + 3) := [16#FF#, 16#FF#, 16#FF#, 16#FF#];
      declare
         A : constant Byte_Array := Snapshot (Region_A);
      begin
         Region_A (Crc_Offset .. Crc_Offset + 1) := Persistent_Bytes (Crc_16.Compute_Crc_16 (A (Save_Counter_Offset .. A'Last)));
      end;
      Boolean_Assert.Eq (Store.Is_Valid (Copy_A), True);
      Unsigned_32_Assert.Eq (Store.Save_Counter (Copy_A), Unsigned_32'Last);
      Check_Restore (Restored, Copy_A, Unsigned_32'Last, Make_Data (1));

      -- The next save wraps the counter to zero and is still the newest:
      Store.Save (Make_Data (2), Test_Time, Info);
      Copy_Type_Assert.Eq (Info.Copy, Copy_B);
      Unsigned_32_Assert.Eq (Info.Save_Counter, 0);
      Check_Restore (Restored, Copy_B, 0, Make_Data (2));

      -- And the one after that goes to A with counter one:
      Store.Save (Make_Data (3), Test_Time, Info);
      Copy_Type_Assert.Eq (Info.Copy, Copy_A);
      Unsigned_32_Assert.Eq (Info.Save_Counter, 1);
      Check_Restore (Restored, Copy_A, 1, Make_Data (3));
   end Test_Save_Counter_Wraparound;

   overriding procedure Test_Layout_And_Length_Mismatch (Self : in out Instance) is
      Ignore : Instance renames Self;
      Info : Copy_Info;
      Ignore_Info : Copy_Info;
      Data : Test_Data_Type;
      Status : Restore_Status;
   begin
      Store.Save (Make_Data (1), Test_Time, Info);
      Copy_Type_Assert.Eq (Info.Copy, Copy_A);
      Store.Save (Make_Data (2), Test_Time, Info);
      Copy_Type_Assert.Eq (Info.Copy, Copy_B);

      -- Both copies are valid for the store that wrote them:
      Boolean_Assert.Eq (Store.Is_Valid (Copy_A), True);
      Boolean_Assert.Eq (Store.Is_Valid (Copy_B), True);

      -- Neither is valid for a store with a different layout id over the same copies,
      -- so its restore finds nothing:
      Boolean_Assert.Eq (Other_Layout_Store.Is_Valid (Copy_A), False);
      Boolean_Assert.Eq (Other_Layout_Store.Is_Valid (Copy_B), False);
      Other_Layout_Store.Restore (Data, Status, Ignore_Info);
      Restore_Status_Assert.Eq (Status, No_Valid_Copy);
      Byte_Array_Assert.Eq (Data, Test_Data_Type'[others => 0]);

      -- Nor for a store with a different data length:
      Boolean_Assert.Eq (Short_Store.Is_Valid (Copy_A), False);
      declare
         subtype Short_Data_Type is Byte_Array (0 .. Test_Data_Length - 2);
         Short_Data : Short_Data_Type;
      begin
         Short_Store.Restore (Short_Data, Status, Ignore_Info);
         Restore_Status_Assert.Eq (Status, No_Valid_Copy);
         Byte_Array_Assert.Eq (Short_Data, Short_Data_Type'[others => 0]);
      end;

      -- A save through the other layout starts over in copy A with counter one, since
      -- no copy is valid for it. Copy B still holds the nominal store's save.
      Other_Layout_Store.Save (Make_Data (3), Test_Time, Info);
      Copy_Type_Assert.Eq (Info.Copy, Copy_A);
      Unsigned_32_Assert.Eq (Info.Save_Counter, 1);
      Boolean_Assert.Eq (Other_Layout_Store.Is_Valid (Copy_A), True);
      Boolean_Assert.Eq (Store.Is_Valid (Copy_A), False);
      Boolean_Assert.Eq (Store.Is_Valid (Copy_B), True);
      Check_Restore (Restored, Copy_B, 2, Make_Data (2));
   end Test_Layout_And_Length_Mismatch;

   overriding procedure Test_Oversized_Allocations (Self : in out Instance) is
      Ignore : Instance renames Self;
      Info : Copy_Info;
      Ignore_Info : Copy_Info;
      Data : Test_Data_Type;
      Status : Restore_Status;
   begin
      Natural_Assert.Eq (Big_Store.Store_Length_In_Bytes, Test_Store_Length);
      Boolean_Assert.Eq (Big_Store.Fits, True);

      Big_Store.Save (Make_Data (1), Test_Time, Info);
      Copy_Type_Assert.Eq (Info.Copy, Copy_A);
      Big_Store.Save (Make_Data (2), Test_Time, Info);
      Copy_Type_Assert.Eq (Info.Copy, Copy_B);

      -- Only the leading Store_Length bytes of each copy are written:
      for Idx in 5 + Test_Store_Length .. Big_A'Last loop
         Byte_Assert.Eq (Big_A (Idx), 16#AA#);
      end loop;
      for Idx in 3 + Test_Store_Length .. Big_B'Last loop
         Byte_Assert.Eq (Big_B (Idx), 16#BB#);
      end loop;

      -- The header sits at the first index of each copy:
      Unsigned_32_Assert.Eq (Big_Store.Save_Counter (Copy_A), 1);
      Unsigned_32_Assert.Eq (Big_Store.Save_Counter (Copy_B), 2);
      Byte_Array_Assert.Eq (Byte_Array (Big_A (5 + Header_Length .. 5 + Header_Length + 7)), Make_Data (1));
      Byte_Array_Assert.Eq (Byte_Array (Big_B (3 + Header_Length .. 3 + Header_Length + 7)), Make_Data (2));

      -- Restores work from the oversized copies:
      Big_Store.Restore (Data, Status, Info);
      Restore_Status_Assert.Eq (Status, Restored);
      Copy_Type_Assert.Eq (Info.Copy, Copy_B);
      Unsigned_32_Assert.Eq (Info.Save_Counter, 2);
      Byte_Array_Assert.Eq (Data, Make_Data (2));

      -- And into a data array with a nonzero first index:
      declare
         Offset_Data : Byte_Array (100 .. 107);
      begin
         Big_Store.Restore (Offset_Data, Status, Ignore_Info);
         Restore_Status_Assert.Eq (Status, Restored);
         Byte_Array_Assert.Eq (Offset_Data, Make_Data (2));
      end;

      -- Zero length data is permitted; the store is header only:
      declare
         Empty : constant Byte_Array (1 .. 0) := [];
         Restored_Empty : Byte_Array (1 .. 0);
      begin
         Natural_Assert.Eq (Empty_Store.Store_Length_In_Bytes, Header_Length);
         Empty_Store.Save (Empty, Test_Time, Info);
         Copy_Type_Assert.Eq (Info.Copy, Copy_A);
         Boolean_Assert.Eq (Empty_Store.Is_Valid (Copy_A), True);
         Empty_Store.Restore (Restored_Empty, Status, Info);
         Restore_Status_Assert.Eq (Status, Restored);
         Unsigned_32_Assert.Eq (Info.Save_Counter, 1);
         Natural_Assert.Eq (Restored_Empty'Length, 0);
      end;
   end Test_Oversized_Allocations;

   overriding procedure Test_Typed_Wrapper (Self : in out Instance) is
      Ignore : Instance renames Self;
      Value : Packed_U32.T;
      Status : Restore_Status;
      Info : Copy_Info;
      Ignore_Info : Copy_Info;
   begin
      -- The layout id combines the version and the serialized length:
      Natural_Assert.Eq (U32_Store.Store_Length_In_Bytes, Header_Length + 4);
      Unsigned_32_Assert.Eq (U32_Store.Layout_Id, 16#0003_0004#);

      -- Nothing valid at first:
      Boolean_Assert.Eq (U32_Store.Is_Valid (Copy_A), False);
      U32_Store.Restore (Value, Status, Ignore_Info);
      Restore_Status_Assert.Eq (Status, No_Valid_Copy);
      Packed_U32_Assert.Eq (Value, (Value => 0));

      -- Save and restore a value:
      U32_Store.Save ((Value => 16#1234_5678#), Test_Time, Info);
      Copy_Type_Assert.Eq (Info.Copy, Copy_A);
      Unsigned_32_Assert.Eq (Info.Save_Counter, 1);
      Boolean_Assert.Eq (U32_Store.Is_Valid (Copy_A), True);
      Boolean_Assert.Eq (U32_Store.Is_Valid (Copy_B), False);
      U32_Store.Restore (Value, Status, Info);
      Restore_Status_Assert.Eq (Status, Restored);
      Copy_Type_Assert.Eq (Info.Copy, Copy_A);
      Packed_U32_Assert.Eq (Value, (Value => 16#1234_5678#));

      -- The bytes in memory are the big endian serialization of the record:
      Byte_Array_Assert.Eq (Byte_Array (Typed_A (Header_Length .. Header_Length + 3)), [16#12#, 16#34#, 16#56#, 16#78#]);
      Byte_Array_Assert.Eq (Byte_Array (Typed_A (Layout_Id_Offset .. Layout_Id_Offset + 3)), [0, 3, 0, 4]);

      -- A second save alternates and the restore returns the newest:
      U32_Store.Save ((Value => 16#0000_0007#), Test_Time, Info);
      Copy_Type_Assert.Eq (Info.Copy, Copy_B);
      Unsigned_32_Assert.Eq (Info.Save_Counter, 2);
      U32_Store.Restore (Value, Status, Info);
      Restore_Status_Assert.Eq (Status, Restored);
      Copy_Type_Assert.Eq (Info.Copy, Copy_B);
      Packed_U32_Assert.Eq (Value, (Value => 7));

      -- A store with a different layout version over the same copies sees no valid
      -- copy:
      Boolean_Assert.Eq (Other_Version_Store.Is_Valid (Copy_A), False);
      Boolean_Assert.Eq (Other_Version_Store.Is_Valid (Copy_B), False);
      Other_Version_Store.Restore (Value, Status, Ignore_Info);
      Restore_Status_Assert.Eq (Status, No_Valid_Copy);
      Packed_U32_Assert.Eq (Value, (Value => 0));
   end Test_Typed_Wrapper;

end Double_Buffer_Store_Tests.Implementation;

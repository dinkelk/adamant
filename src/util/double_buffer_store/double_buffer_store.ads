with Basic_Types;
with Interfaces; use Interfaces;
with Sys_Time;

-- A double buffered, CRC protected store for a block of bytes that must survive a
-- reboot, typically held in nonvolatile memory such as MRAM.
--
-- The caller provides two byte arrays, Bytes_A and Bytes_B, holding copy A and copy B
-- of the store. Exactly one copy is valid at rest. A save writes the invalid copy,
-- stamps it with the save time, writes its CRC last, and then invalidates the other
-- copy by zeroing its save time. A reboot at any instant during a save leaves at
-- least one valid copy. If a reboot lands between writing the new CRC and zeroing the
-- old stamp, both copies are valid and the restore takes the one with the later save
-- time.
--
-- Each copy holds a header followed by the caller's data. With S the serialized size
-- of Sys_Time.T in bytes:
--
--    Offset  Size  Field
--    0       2     CRC-16 over every byte after itself
--    2       S     Save time, a serialized Sys_Time.T
--    2+S     n     Data
--
-- Zeroing the save time of the old copy changes the bytes under its CRC, so the copy
-- no longer validates except in the one in 65536 case that the CRC happens to match
-- anyway. In that case both copies validate and the restore still picks the newer
-- copy by save time, so no data is lost.
--
-- CRC last only protects a mid-save reboot if the stores reach memory in program
-- order. The memory behind the copies must be uncached, or the caller must fence
-- between writing the data and writing the CRC. This package does not fence.
--
-- This package holds no state and no access types. The caller owns the byte arrays
-- and passes them to every operation.
package Double_Buffer_Store with SPARK_Mode => On is

   -- Offsets of the header fields from the first byte of a copy, and the size of the
   -- header that precedes the data, in bytes:
   Crc_Offset : constant := 0;
   Save_Time_Offset : constant := 2;
   Header_Length : constant Natural := Save_Time_Offset + Sys_Time.Size_In_Bytes;

   -- The largest data block that can be stored. This bound keeps every length
   -- computation in this package within Natural.
   Max_Data_Length : constant := 65535;
   subtype Data_Length_Type is Natural range 0 .. Max_Data_Length;
   subtype Positive_Data_Length_Type is Data_Length_Type range 1 .. Max_Data_Length;

   -- The size of one copy of the store, in bytes, for a given data length:
   subtype Store_Length_Type is Natural range Header_Length .. Header_Length + Max_Data_Length;
   function Store_Length (Data_Length : in Data_Length_Type) return Store_Length_Type is
      (Header_Length + Data_Length);

   -- Identifies one of the two copies:
   type Copy_Type is (Copy_A, Copy_B);
   function Other_Copy (Copy : in Copy_Type) return Copy_Type is
      (if Copy = Copy_A then Copy_B else Copy_A);

   -- Result of a restore:
   type Restore_Status is (Restored, No_Valid_Copy);

   -- True if a byte array is large enough to hold one copy of the store for the
   -- given data length. Only the first Store_Length bytes of a larger array are used.
   function Fits (Copy : in Basic_Types.Byte_Array; Data_Length : in Data_Length_Type) return Boolean is
      (Copy'Length >= Store_Length (Data_Length));

   -- A copy is valid if its CRC matches the CRC computed over its contents.
   function Is_Valid (Copy : in Basic_Types.Byte_Array; Data_Length : in Data_Length_Type) return Boolean
      with Global => null,
           Pre => Fits (Copy, Data_Length);

   -- The save time stamped on a copy. This does not check validity.
   function Read_Save_Time (Copy : in Basic_Types.Byte_Array) return Sys_Time.T
      with Global => null,
           Pre => Copy'Length >= Header_Length;

   -- True if Time is later than Than:
   function Is_Later (Time : in Sys_Time.T; Than : in Sys_Time.T) return Boolean is
      (Time.Seconds > Than.Seconds or else (Time.Seconds = Than.Seconds and then Time.Subseconds > Than.Subseconds));

   -- Save Data into the store. The copy that is not valid is written (copy A if
   -- neither or both are valid, the older if both), stamped with Save_Time, and its
   -- CRC is written last. The other copy is then invalidated. Written reports the copy
   -- that now holds the data.
   procedure Save (
      Bytes_A : in out Basic_Types.Byte_Array;
      Bytes_B : in out Basic_Types.Byte_Array;
      Data : in Basic_Types.Byte_Array;
      Save_Time : in Sys_Time.T;
      Written : out Copy_Type
   )
      with Global => null,
           Pre => Data'Length <= Max_Data_Length
              and then Fits (Bytes_A, Data'Length)
              and then Fits (Bytes_B, Data'Length);

   -- Restore Data from the valid copy, or from the one with the later save time if
   -- both are valid. If neither copy is valid, Status is No_Valid_Copy, Data is
   -- zeroed, and Source is meaningless.
   procedure Restore (
      Bytes_A : in Basic_Types.Byte_Array;
      Bytes_B : in Basic_Types.Byte_Array;
      Data : out Basic_Types.Byte_Array;
      Status : out Restore_Status;
      Source : out Copy_Type
   )
      with Global => null,
           Pre => Data'Length <= Max_Data_Length
              and then Fits (Bytes_A, Data'Length)
              and then Fits (Bytes_B, Data'Length),
           Post => (if Status = No_Valid_Copy then (for all B of Data => B = 0));

end Double_Buffer_Store;

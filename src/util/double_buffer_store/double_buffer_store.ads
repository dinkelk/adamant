with Basic_Types;
with Interfaces; use Interfaces;
with Sys_Time;

-- A double buffered, CRC protected store for a block of bytes that must survive a
-- reboot, typically held in nonvolatile memory such as MRAM.
--
-- The caller provides two byte array allocations, Bytes_A and Bytes_B, holding copy A
-- and copy B of the store. Each save writes the copy that does NOT hold the most
-- recent valid save, stamps it with a save counter one newer than the newest valid
-- copy's, and writes its CRC last. A restore reads the valid copy holding the newest
-- save counter. A reboot at any instant during a save therefore leaves at least one
-- valid copy, and costs at most one save interval of freshness.
--
-- Each copy holds a header followed by the caller's data. With S the serialized size
-- of Sys_Time.T in bytes:
--
--    Offset  Size  Field
--    0       2     CRC-16 over every byte after itself
--    2       4     Save counter, monotonic, compared wraparound-aware
--    6       S     Save time, a serialized Sys_Time.T
--    6+S     4     Layout id, supplied by the caller
--    10+S    2     Data length in bytes
--    12+S    n     Data
--
-- The counter, layout id and data length are stored most significant byte first,
-- independent of the host byte order. The save time uses the Sys_Time serialization. A copy is valid only if its CRC matches, its layout id matches the
-- caller's, and its data length matches the caller's. A layout or length mismatch
-- therefore reads as no valid copy: there is nothing to resume from, so the caller
-- reports, starts fresh, and relies on the ground to reseed. The layout id exists so
-- that a software update which changes the meaning or order of the stored bytes can
-- never restore old contents into a new layout.
--
-- CRC last only protects a mid-save reboot if the stores reach memory in program
-- order. The memory behind the copies must be uncached, or the caller must fence
-- between writing the data and writing the CRC. This package does not fence.
--
-- This package holds no state and no access types. The caller owns the byte arrays
-- and passes them to every operation, so a component may keep access values to
-- memory mapped regions in its own (non SPARK) code and dereference them at the call.
package Double_Buffer_Store with SPARK_Mode => On is

   -- Offsets of the header fields from the first byte of a copy, and the size of the
   -- header that precedes the data, in bytes:
   Crc_Offset : constant := 0;
   Save_Counter_Offset : constant := 2;
   Save_Time_Offset : constant := 6;
   Layout_Id_Offset : constant Natural := Save_Time_Offset + Sys_Time.Size_In_Bytes;
   Data_Length_Offset : constant Natural := Layout_Id_Offset + 4;
   Header_Length : constant Natural := Data_Length_Offset + 2;

   -- The largest data block that can be stored. The data length is held in a 16-bit
   -- header field.
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

   -- The copy written by a save or read by a restore, and the save counter it holds:
   type Copy_Info is record
      Copy : Copy_Type := Copy_A;
      Save_Counter : Unsigned_32 := 0;
   end record;

   -- True if a byte array is large enough to hold one copy of the store for the
   -- given data length. Only the first Store_Length bytes of a larger array are used.
   function Fits (Copy : in Basic_Types.Byte_Array; Data_Length : in Data_Length_Type) return Boolean is
      (Copy'Length >= Store_Length (Data_Length));

   -- True if Counter is newer than Than. The comparison is wraparound-aware, so it
   -- remains correct after the 32-bit counter rolls over. Equal counters are not newer.
   function Is_Newer (Counter : in Unsigned_32; Than : in Unsigned_32) return Boolean is
      (Counter /= Than and then Counter - Than < 2 ** 31);

   -- A copy is valid if its CRC matches the CRC computed over its contents, its
   -- layout id matches, and its data length matches.
   function Is_Valid (Copy : in Basic_Types.Byte_Array; Layout_Id : in Unsigned_32; Data_Length : in Data_Length_Type) return Boolean
      with Global => null,
           Pre => Fits (Copy, Data_Length);

   -- Read header fields from a copy. These do not check validity.
   function Read_Save_Counter (Copy : in Basic_Types.Byte_Array) return Unsigned_32
      with Global => null,
           Pre => Copy'Length >= Header_Length;
   function Read_Save_Time (Copy : in Basic_Types.Byte_Array) return Sys_Time.T
      with Global => null,
           Pre => Copy'Length >= Header_Length;

   -- Find the valid copy holding the newest save counter. If neither copy is valid,
   -- Valid_Found is False and Newest is meaningless. When both copies are valid and
   -- hold equal counters, which cannot happen through this package's own saves, copy A
   -- is chosen.
   procedure Find_Newest_Valid (
      Bytes_A : in Basic_Types.Byte_Array;
      Bytes_B : in Basic_Types.Byte_Array;
      Layout_Id : in Unsigned_32;
      Data_Length : in Data_Length_Type;
      Valid_Found : out Boolean;
      Newest : out Copy_Type
   )
      with Global => null,
           Pre => Fits (Bytes_A, Data_Length) and then Fits (Bytes_B, Data_Length);

   -- Save Data into the store. The copy not holding the newest valid save is written
   -- (copy A if neither is valid), stamped with a save counter one newer than the
   -- newest valid copy's (one if neither is valid), and its CRC is written last. Info
   -- reports the copy written and its new counter.
   procedure Save (
      Bytes_A : in out Basic_Types.Byte_Array;
      Bytes_B : in out Basic_Types.Byte_Array;
      Data : in Basic_Types.Byte_Array;
      Layout_Id : in Unsigned_32;
      Save_Time : in Sys_Time.T;
      Info : out Copy_Info
   )
      with Global => null,
           Pre => Data'Length <= Max_Data_Length
              and then Fits (Bytes_A, Data'Length)
              and then Fits (Bytes_B, Data'Length);

   -- Restore Data from the valid copy holding the newest save counter. If neither copy
   -- is valid, Status is No_Valid_Copy, Data is zeroed, and Info is meaningless.
   procedure Restore (
      Bytes_A : in Basic_Types.Byte_Array;
      Bytes_B : in Basic_Types.Byte_Array;
      Layout_Id : in Unsigned_32;
      Data : out Basic_Types.Byte_Array;
      Status : out Restore_Status;
      Info : out Copy_Info
   )
      with Global => null,
           Pre => Data'Length <= Max_Data_Length
              and then Fits (Bytes_A, Data'Length)
              and then Fits (Bytes_B, Data'Length),
           Post => (if Status = No_Valid_Copy then (for all B of Data => B = 0));

end Double_Buffer_Store;

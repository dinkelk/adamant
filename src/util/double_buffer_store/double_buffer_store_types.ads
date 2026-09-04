with Basic_Types;
with Interfaces; use Interfaces;
with Sys_Time;

-- Types shared by the double buffer store packages.
--
-- A double buffer store keeps two copies of a block of bytes in memory that survives
-- a reboot, such as MRAM. Each copy holds a header followed by the caller's data. With
-- S the serialized size of Sys_Time.T in bytes:
--
--    Offset  Size  Field
--    0       2     CRC-16 over every byte after itself
--    2       4     Save counter, monotonic, compared wraparound-aware
--    6       S     Save time, a serialized Sys_Time.T
--    6+S     4     Layout id, supplied by the instantiator
--    10+S    2     Data length in bytes
--    12+S    n     Data
--
-- The counter, layout id and data length are stored most significant byte first,
-- independent of the host byte order. The save time uses the Sys_Time serialization.
package Double_Buffer_Store_Types with SPARK_Mode => On is

   -- The memory holding one copy of a store. It is volatile so that every write the
   -- store makes reaches memory in program order and reads come from memory. Nothing
   -- writes a copy asynchronously while the program runs, so reads are ordinary values
   -- in expressions. Declare the copies with this type where the persistent memory is
   -- mapped and bind them to a store at instantiation.
   type Persistent_Bytes is new Basic_Types.Byte_Array
      with Volatile, Async_Readers => True, Async_Writers => False, Effective_Reads => False, Effective_Writes => True;

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

end Double_Buffer_Store_Types;

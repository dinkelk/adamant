with Basic_Types;
with Double_Buffer_Store_Types; use Double_Buffer_Store_Types;
with Interfaces; use Interfaces;
with Sys_Time;

-- A double buffered, CRC protected store for a block of bytes that must survive a
-- reboot, held in memory such as MRAM that persists across the reboot.
--
-- An instance is bound at instantiation to the memory holding its two copies, Region_A
-- and Region_B, declared as Persistent_Bytes where the persistent memory is mapped. The
-- instance does every read and write of the copies; callers save and restore
-- ordinary byte arrays of Data_Length bytes. Each save writes the copy that does NOT
-- hold the most recent valid save, stamps it with a save counter one newer than the
-- newest valid copy's, and writes its CRC last. A restore reads the valid copy holding
-- the newest save counter. A reboot at any instant during a save therefore leaves at
-- least one valid copy, and costs at most one save interval of freshness.
--
-- A copy is valid only if its CRC matches, its layout id matches Layout_Id, and its
-- data length matches Data_Length. A layout or length mismatch therefore reads as no
-- valid copy: there is nothing to resume from, so the caller reports, starts fresh,
-- and relies on the ground to reseed. The layout id exists so that a software update
-- which changes the meaning or order of the stored bytes can never restore old
-- contents into a new layout.
--
-- Writing the CRC last protects a reboot during a save only if the memory commits
-- stores in program order, which holds for uncached memory. This package does not
-- fence. The encoding, validity and copy selection logic lives in
-- Double_Buffer_Store_Layout, over ordinary byte arrays.
generic
   -- The memory holding the two copies. Each must be at least Store_Length (Data_Length)
   -- bytes long; only the leading bytes of a longer region are used. They must not
   -- overlap.
   Region_A : in out Persistent_Bytes;
   Region_B : in out Persistent_Bytes;
   -- Identifies the layout of the stored data:
   Layout_Id : Unsigned_32;
   -- The size of the data saved and restored, in bytes:
   Data_Length : Data_Length_Type;
package Double_Buffer_Store with SPARK_Mode => On is

   -- The size of one copy of this store, in bytes:
   Store_Length_In_Bytes : constant Store_Length_Type := Store_Length (Data_Length);

   -- True if both copies are large enough for this store. Checked at elaboration and
   -- required by every operation.
   function Fits return Boolean is
      (Region_A'Length >= Store_Length_In_Bytes and then Region_B'Length >= Store_Length_In_Bytes);

   -- Save Data into the store. The copy not holding the newest valid save is written
   -- (copy A if neither is valid), stamped with a save counter one newer than the
   -- newest valid copy's (one if neither is valid), and its CRC is written last. Info
   -- reports the copy written and its new counter.
   procedure Save (Data : in Basic_Types.Byte_Array; Save_Time : in Sys_Time.T; Info : out Copy_Info)
      with Global => (In_Out => (Region_A, Region_B)),
           Pre => Fits and then Data'Length = Data_Length;

   -- Restore Data from the valid copy holding the newest save counter. If neither copy
   -- is valid, Status is No_Valid_Copy, Data is zeroed, and Info is meaningless.
   procedure Restore (Data : out Basic_Types.Byte_Array; Status : out Restore_Status; Info : out Copy_Info)
      with Global => (Input => (Region_A, Region_B)),
           Pre => Fits and then Data'Length = Data_Length,
           Post => (if Status = No_Valid_Copy then (for all B of Data => B = 0));

   -- Status of one copy, for reporting. These read the copy from memory.
   function Is_Valid (Copy : in Copy_Type) return Boolean
      with Global => (Input => (Region_A, Region_B)),
           Pre => Fits;
   function Save_Counter (Copy : in Copy_Type) return Unsigned_32
      with Global => (Input => (Region_A, Region_B)),
           Pre => Fits;
   function Save_Time (Copy : in Copy_Type) return Sys_Time.T
      with Global => (Input => (Region_A, Region_B)),
           Pre => Fits;

end Double_Buffer_Store;

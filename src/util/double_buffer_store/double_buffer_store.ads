with Crc_16;
with Sys_Time;

-- A double buffered, CRC protected store for a record that must survive a reboot,
-- held in nonvolatile memory such as MRAM.
--
-- The outer generic takes the record type and declares Persistent_Copy, the type of
-- the memory holding one copy of the store. The consumer declares two objects of that
-- type over its persistent memory and binds them with the inner generic, Bound, which
-- performs every read and write of that memory. Callers save and restore the record
-- and never touch bytes.
--
-- At boot the consumer calls Init once. It returns the contents of the valid copy, or
-- of the one with the later save time if both are valid, invalidates the other copy
-- by complementing its CRC, and selects that other copy as the target of the next
-- save. Restore returns the same contents without touching memory. Each Save writes
-- the target copy, save time and data first and CRC last, and moves the target to the
-- other copy. A reboot at any instant during a save leaves the previous copy intact,
-- and the next Init finds it. A Save before Init writes copy A.
--
-- T must be a type in which every bit pattern is a valid value, such as a packed
-- record of unsigned integers. The store converts T to bytes for the CRC with an
-- unchecked conversion, and GNATprove rejects the instantiation if T has invalid bit
-- patterns, so a proved instantiation satisfies this rule. Records with enumeration or
-- range constrained fields do not qualify.
--
-- The layout of a copy in memory is the compiler's layout of Persistent_Copy. It is
-- the same for every build of the same source, and a build that changes T reads the
-- old copies as invalid and starts over.
--
-- CRC last only protects a mid-save reboot if the stores reach memory in program
-- order. Persistent_Copy is volatile, so the compiler emits its component writes in
-- order, but the memory behind it must be uncached or the caller must fence. This
-- package does not fence.
generic
   type T is private;
package Double_Buffer_Store with SPARK_Mode => On is

   -- Result of Restore and Init:
   type Restore_Status is (Restored, No_Valid_Copy);

   -- The part of a copy that the CRC covers:
   type Payload_Type is record
      -- The time of the save that wrote this copy:
      Save_Time : Sys_Time.T;
      -- The stored record:
      Data : T;
   end record;

   -- The memory holding one copy of the store. Objects of this type overlay the
   -- persistent memory. The aspects tell the compiler and GNATprove how that memory
   -- behaves:
   type Persistent_Copy is record
      -- CRC-16 over the payload, computed over the serialized save time followed by
      -- the bytes of the data. Complemented to invalidate the copy.
      Crc : Crc_16.Crc_16_Type;
      Payload : Payload_Type;
   end record
      with
         -- Every read and write of the object is a real memory access, emitted in
         -- program order, never held in a register or removed:
         Volatile,
         -- Something outside the program reads the memory, namely the next boot, so
         -- every write is observable and none may be dropped:
         Async_Readers => True,
         -- Nothing outside the program changes the memory while it runs, so a read
         -- returns what the program last wrote and reads may appear in expressions:
         Async_Writers => False,
         -- Reading the memory does not change it:
         Effective_Reads => False,
         -- Every write matters on its own, even when it repeats the previous value,
         -- so a sequence of writes is never folded into the last one:
         Effective_Writes => True;

   generic
      -- The memory holding the two copies:
      Region_A : in out Persistent_Copy;
      Region_B : in out Persistent_Copy;
   package Bound with SPARK_Mode => On, Abstract_State => State, Initializes => State is

      -- Call once at boot. Return the data of the valid copy, or of the one with the
      -- later save time if both are valid, with Status Restored, then invalidate the
      -- other copy and make it the target of the next save. If neither copy is valid,
      -- Status is No_Valid_Copy, Value is all zero bits, nothing is invalidated, and
      -- copy A becomes the target.
      procedure Init (Value : out T; Status : out Restore_Status)
         with Global => (In_Out => (Region_A, Region_B), Output => State);

      -- Return the same Value and Status as Init would, without changing memory or
      -- the target:
      procedure Restore (Value : out T; Status : out Restore_Status)
         with Global => (Input => (Region_A, Region_B));

      -- Write Value and Save_Time to the target copy, CRC last, and make the other
      -- copy the target of the next save.
      procedure Save (Value : in T; Save_Time : in Sys_Time.T)
         with Global => (In_Out => (Region_A, Region_B, State));

   end Bound;

end Double_Buffer_Store;

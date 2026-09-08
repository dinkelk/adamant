--------------------------------------------------------------------------------
-- Double_Buffer_Store Tests Spec
--------------------------------------------------------------------------------

-- This is a unit test suite for the double buffer store.
package Double_Buffer_Store_Tests.Implementation is
   -- Test data and state:
   type Instance is new Double_Buffer_Store_Tests.Base_Instance with private;
private
   -- Fixture procedures:
   overriding procedure Set_Up_Test (Self : in out Instance);
   overriding procedure Tear_Down_Test (Self : in out Instance);

   -- This test fills both copies with garbage, zeros, and ones and checks that no
   -- copy is valid, that a restore reports No_Valid_Copy, and that the restored data
   -- is zeroed.
   overriding procedure Test_No_Valid_Copy_On_First_Boot (Self : in out Instance);
   -- This test performs a sequence of saves and checks that the writes alternate
   -- between copy A and copy B, that the previous copy is invalidated by each save,
   -- that the save time is stored, and that each restore returns the newest data. It
   -- also checks the header layout in memory.
   overriding procedure Test_Save_Alternates_And_Invalidates (Self : in out Instance);
   -- This test emulates a reboot at each point during a save and checks that the
   -- restore returns the newest data that was completely written, taking the later
   -- save time when both copies are valid.
   overriding procedure Test_Interrupted_Save (Self : in out Instance);
   -- This test corrupts the only valid copy and checks that no valid copy is found,
   -- and that the next save recovers the store.
   overriding procedure Test_Corrupt_Copy (Self : in out Instance);
   -- This test uses byte arrays larger than the store with nonzero first indices and
   -- checks that only the first store length bytes are written and that saves and
   -- restores are correct, including for zero length data.
   overriding procedure Test_Oversized_Allocations (Self : in out Instance);
   -- This test instantiates the typed wrapper on a packed record and checks save,
   -- restore, and the No_Valid_Copy behavior.
   overriding procedure Test_Typed_Wrapper (Self : in out Instance);

   -- Test data and state:
   type Instance is new Double_Buffer_Store_Tests.Base_Instance with record
      null;
   end record;
end Double_Buffer_Store_Tests.Implementation;

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

   -- This test fills both copies with garbage, zeros, and ones, and checks that no
   -- copy is valid, that a restore reports No_Valid_Copy, and that the restored data
   -- is zeroed.
   overriding procedure Test_No_Valid_Copy_On_First_Boot (Self : in out Instance);
   -- This test performs a sequence of saves and checks that the writes alternate
   -- between copy A and copy B, that the save counter increments, that the save time
   -- is stored, that the header layout in memory is as documented, and that each
   -- restore returns the newest data.
   overriding procedure Test_Save_And_Restore_Alternate_Copies (Self : in out Instance);
   -- This test corrupts the newest copy after two saves and checks that the restore
   -- falls back to the older copy. It then corrupts both copies and checks that no
   -- valid copy is found. It also emulates a reboot in the middle of a save.
   overriding procedure Test_Restore_From_Older_Copy_When_Newest_Corrupt (Self : in out Instance);
   -- This test saves with a counter at the maximum 32-bit value and checks that the
   -- next save wraps to zero and is still recognized as newest.
   overriding procedure Test_Save_Counter_Wraparound (Self : in out Instance);
   -- This test checks that stores instantiated over the same copies with a different
   -- layout id or a different data length treat the copies as invalid.
   overriding procedure Test_Layout_And_Length_Mismatch (Self : in out Instance);
   -- This test binds stores to copies larger than the store with nonzero first
   -- indices and checks that only the leading store length bytes are written and that
   -- saves and restores are correct, including a store of zero length data.
   overriding procedure Test_Oversized_Allocations (Self : in out Instance);
   -- This test instantiates the typed store on a packed record and checks save,
   -- restore, the layout id, and the No_Valid_Copy behavior, including a store with a
   -- different layout version over the same copies.
   overriding procedure Test_Typed_Wrapper (Self : in out Instance);

   -- Test data and state:
   type Instance is new Double_Buffer_Store_Tests.Base_Instance with record
      null;
   end record;
end Double_Buffer_Store_Tests.Implementation;

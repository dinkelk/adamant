--------------------------------------------------------------------------------
-- Parameter_Table_Buffer Tests Spec
--------------------------------------------------------------------------------

with Parameter_Table_Buffer;

-- Unit tests for the Parameter_Table_Buffer standalone package.
package Parameter_Table_Buffer_Tests.Implementation is

   -- Test data and state:
   type Instance is new Parameter_Table_Buffer_Tests.Base_Instance with private;
   type Class_Access is access all Instance'Class;

private
   -- Fixture procedures:
   overriding procedure Set_Up_Test (Self : in out Instance);
   overriding procedure Tear_Down_Test (Self : in out Instance);

   -- Test buffer creation, allocation, and destruction.
   overriding procedure Test_Create_Destroy (Self : in out Instance);
   -- Unsegmented packets are always ignored regardless of state.
   overriding procedure Test_Unsegmented_Ignored (Self : in out Instance);
   -- Test the nominal FirstSegment -> ContinuationSegment -> LastSegment flow.
   overriding procedure Test_Nominal_Segmented_Flow (Self : in out Instance);
   -- Verify Table ID is correctly deserialized from the first 2 bytes of a
   -- FirstSegment.
   overriding procedure Test_First_Segment_Extracts_Table_Id (Self : in out Instance);
   -- A FirstSegment with less than 2 bytes of data returns Too_Small_Table.
   overriding procedure Test_First_Segment_Too_Small (Self : in out Instance);
   -- ContinuationSegment and LastSegment without a prior FirstSegment return
   -- Packet_Ignored.
   overriding procedure Test_Continuation_Without_First (Self : in out Instance);
   -- A new FirstSegment while receiving discards the previous table and starts
   -- fresh.
   overriding procedure Test_First_Segment_Resets_Buffer (Self : in out Instance);
   -- A FirstSegment whose data (minus Table ID) exceeds the buffer capacity returns
   -- Buffer_Overflow.
   overriding procedure Test_Buffer_Overflow_First_Segment (Self : in out Instance);
   -- A ContinuationSegment that would exceed the buffer capacity returns
   -- Buffer_Overflow.
   overriding procedure Test_Buffer_Overflow_Continuation (Self : in out Instance);
   -- A LastSegment that would exceed the buffer capacity returns Buffer_Overflow.
   overriding procedure Test_Buffer_Overflow_Last_Segment (Self : in out Instance);
   -- Verify Get_Table_Region returns a region pointing to the correct buffer data
   -- with correct length.
   overriding procedure Test_Get_Table_Region (Self : in out Instance);
   -- Test receiving multiple complete tables in sequence to verify state is properly
   -- reset.
   overriding procedure Test_Multiple_Tables (Self : in out Instance);
   -- A FirstSegment with exactly 2 bytes (only Table ID, no payload) is valid.
   overriding procedure Test_First_Segment_Only_Table_Id (Self : in out Instance);

   -- Test data and state:
   type Instance is new Parameter_Table_Buffer_Tests.Base_Instance with record
      Buf : Parameter_Table_Buffer.Instance;
   end record;
end Parameter_Table_Buffer_Tests.Implementation;

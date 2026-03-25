--------------------------------------------------------------------------------
-- Parameter_Table_Buffer Tests Body
--------------------------------------------------------------------------------

with Basic_Assertions; use Basic_Assertions;
with Smart_Assert;
with Parameter_Table_Buffer; use Parameter_Table_Buffer;
with Ccsds_Enums; use Ccsds_Enums.Ccsds_Sequence_Flag;
with Basic_Types;
with Memory_Region;
with Parameter_Types;

package body Parameter_Table_Buffer_Tests.Implementation is

   -------------------------------------------------------------------------
   -- Assertion packages:
   -------------------------------------------------------------------------
   package Append_Status_Assert is new Smart_Assert.Basic (Append_Status, Append_Status'Image);
   package Table_Id_Assert is new Smart_Assert.Basic (Parameter_Types.Parameter_Table_Id, Parameter_Types.Parameter_Table_Id'Image);

   -- Default buffer size used by most tests:
   Default_Buffer_Size : constant Positive := 64;

   -------------------------------------------------------------------------
   -- Fixtures:
   -------------------------------------------------------------------------
   overriding procedure Set_Up_Test (Self : in out Instance) is
   begin
      Self.Buf.Create (Buffer_Size => Default_Buffer_Size);
   end Set_Up_Test;

   overriding procedure Tear_Down_Test (Self : in out Instance) is
   begin
      Self.Buf.Destroy;
   end Tear_Down_Test;

   -------------------------------------------------------------------------
   -- Tests:
   -------------------------------------------------------------------------

   overriding procedure Test_Create_Destroy (Self : in out Instance) is
   begin
      -- Buffer was created in fixture. Verify initial state:
      Natural_Assert.Eq (Self.Buf.Get_Table_Length, 0);
      Table_Id_Assert.Eq (Self.Buf.Get_Table_Id, 0);

      -- Destroy and recreate to test lifecycle:
      Self.Buf.Destroy;
      Natural_Assert.Eq (Self.Buf.Get_Table_Length, 0);
      Self.Buf.Create (Buffer_Size => 32);
      Natural_Assert.Eq (Self.Buf.Get_Table_Length, 0);
   end Test_Create_Destroy;

   overriding procedure Test_Unsegmented_Ignored (Self : in out Instance) is
      Status : Append_Status;
      Data : constant Basic_Types.Byte_Array := [16#00#, 16#01#, 16#AA#, 16#BB#];
   begin
      -- Unsegmented from Idle:
      Status := Self.Buf.Append (Data => Data, Sequence_Flag => Unsegmented);
      Append_Status_Assert.Eq (Status, Packet_Ignored);

      -- Start receiving a table, then try Unsegmented:
      Status := Self.Buf.Append (Data => Data, Sequence_Flag => Firstsegment);
      Append_Status_Assert.Eq (Status, New_Table);
      Status := Self.Buf.Append (Data => Data, Sequence_Flag => Unsegmented);
      Append_Status_Assert.Eq (Status, Packet_Ignored);
   end Test_Unsegmented_Ignored;

   overriding procedure Test_Nominal_Segmented_Flow (Self : in out Instance) is
      Status : Append_Status;
      -- Table ID = 0x0005 followed by 4 bytes of payload:
      First_Data : constant Basic_Types.Byte_Array := [16#00#, 16#05#, 16#11#, 16#22#, 16#33#, 16#44#];
      Cont_Data : constant Basic_Types.Byte_Array := [16#55#, 16#66#];
      Last_Data : constant Basic_Types.Byte_Array := [16#77#, 16#88#];
   begin
      -- FirstSegment:
      Status := Self.Buf.Append (Data => First_Data, Sequence_Flag => Firstsegment);
      Append_Status_Assert.Eq (Status, New_Table);
      Table_Id_Assert.Eq (Self.Buf.Get_Table_Id, 5);
      -- Buffer should contain data after Table ID (4 bytes):
      Natural_Assert.Eq (Self.Buf.Get_Table_Length, 4);

      -- ContinuationSegment:
      Status := Self.Buf.Append (Data => Cont_Data, Sequence_Flag => Continuationsegment);
      Append_Status_Assert.Eq (Status, Buffering_Table);
      Natural_Assert.Eq (Self.Buf.Get_Table_Length, 6);

      -- LastSegment:
      Status := Self.Buf.Append (Data => Last_Data, Sequence_Flag => Lastsegment);
      Append_Status_Assert.Eq (Status, Complete_Table);
      Natural_Assert.Eq (Self.Buf.Get_Table_Length, 8);

      -- Verify table region length:
      declare
         Region : constant Memory_Region.T := Self.Buf.Get_Table_Region;
      begin
         Natural_Assert.Eq (Region.Length, 8);
      end;
   end Test_Nominal_Segmented_Flow;

   overriding procedure Test_First_Segment_Extracts_Table_Id (Self : in out Instance) is
      Status : Append_Status;
   begin
      -- Table ID = 0x1234 (big-endian: 0x12, 0x34):
      Status := Self.Buf.Append (Data => [16#12#, 16#34#, 16#AA#], Sequence_Flag => Firstsegment);
      Append_Status_Assert.Eq (Status, New_Table);
      Table_Id_Assert.Eq (Self.Buf.Get_Table_Id, 16#1234#);

      -- Table ID = 0x0001:
      Status := Self.Buf.Append (Data => [16#00#, 16#01#, 16#BB#], Sequence_Flag => Firstsegment);
      Append_Status_Assert.Eq (Status, New_Table);
      Table_Id_Assert.Eq (Self.Buf.Get_Table_Id, 1);

      -- Table ID = 0xFF00:
      Status := Self.Buf.Append (Data => [16#FF#, 16#00#, 16#CC#], Sequence_Flag => Firstsegment);
      Append_Status_Assert.Eq (Status, New_Table);
      Table_Id_Assert.Eq (Self.Buf.Get_Table_Id, 16#FF00#);
   end Test_First_Segment_Extracts_Table_Id;

   overriding procedure Test_First_Segment_Too_Small (Self : in out Instance) is
      Status : Append_Status;
   begin
      -- Empty data:
      Status := Self.Buf.Append (Data => [1 .. 0 => 0], Sequence_Flag => Firstsegment);
      Append_Status_Assert.Eq (Status, Too_Small_Table);

      -- 1 byte (still too small for 2-byte Table ID):
      Status := Self.Buf.Append (Data => [16#01#], Sequence_Flag => Firstsegment);
      Append_Status_Assert.Eq (Status, Too_Small_Table);

      -- Verify we're back to Idle (continuation should be ignored):
      Status := Self.Buf.Append (Data => [16#AA#, 16#BB#], Sequence_Flag => Continuationsegment);
      Append_Status_Assert.Eq (Status, Packet_Ignored);
   end Test_First_Segment_Too_Small;

   overriding procedure Test_Continuation_Without_First (Self : in out Instance) is
      Status : Append_Status;
      Data : constant Basic_Types.Byte_Array := [16#AA#, 16#BB#, 16#CC#];
   begin
      -- ContinuationSegment from Idle:
      Status := Self.Buf.Append (Data => Data, Sequence_Flag => Continuationsegment);
      Append_Status_Assert.Eq (Status, Packet_Ignored);

      -- LastSegment from Idle:
      Status := Self.Buf.Append (Data => Data, Sequence_Flag => Lastsegment);
      Append_Status_Assert.Eq (Status, Packet_Ignored);
   end Test_Continuation_Without_First;

   overriding procedure Test_First_Segment_Resets_Buffer (Self : in out Instance) is
      Status : Append_Status;
   begin
      -- Start first table (ID = 1):
      Status := Self.Buf.Append (Data => [16#00#, 16#01#, 16#AA#, 16#BB#], Sequence_Flag => Firstsegment);
      Append_Status_Assert.Eq (Status, New_Table);
      Table_Id_Assert.Eq (Self.Buf.Get_Table_Id, 1);
      Natural_Assert.Eq (Self.Buf.Get_Table_Length, 2);

      -- Add continuation:
      Status := Self.Buf.Append (Data => [16#CC#, 16#DD#], Sequence_Flag => Continuationsegment);
      Append_Status_Assert.Eq (Status, Buffering_Table);
      Natural_Assert.Eq (Self.Buf.Get_Table_Length, 4);

      -- New FirstSegment interrupts (ID = 2):
      Status := Self.Buf.Append (Data => [16#00#, 16#02#, 16#EE#], Sequence_Flag => Firstsegment);
      Append_Status_Assert.Eq (Status, New_Table);
      Table_Id_Assert.Eq (Self.Buf.Get_Table_Id, 2);
      -- Buffer should only contain data from the new table:
      Natural_Assert.Eq (Self.Buf.Get_Table_Length, 1);
   end Test_First_Segment_Resets_Buffer;

   overriding procedure Test_Buffer_Overflow_First_Segment (Self : in out Instance) is
      Ignore_Self : Instance renames Self;
      Status : Append_Status;
      -- Use a small buffer for overflow testing:
      Small_Buf : Parameter_Table_Buffer.Instance;
      -- Buffer is 4 bytes, FirstSegment has 2-byte ID + 5 bytes payload = 7 total.
      -- Payload (5 bytes) exceeds buffer capacity (4 bytes):
      Big_Data : constant Basic_Types.Byte_Array := [16#00#, 16#01#, 16#AA#, 16#BB#, 16#CC#, 16#DD#, 16#EE#];
   begin
      Small_Buf.Create (Buffer_Size => 4);

      Status := Small_Buf.Append (Data => Big_Data, Sequence_Flag => Firstsegment);
      Append_Status_Assert.Eq (Status, Buffer_Overflow);

      -- Should be back to Idle:
      Status := Small_Buf.Append (Data => [16#AA#], Sequence_Flag => Continuationsegment);
      Append_Status_Assert.Eq (Status, Packet_Ignored);

      Small_Buf.Destroy;
      pragma Unreferenced (Small_Buf);
   end Test_Buffer_Overflow_First_Segment;

   overriding procedure Test_Buffer_Overflow_Continuation (Self : in out Instance) is
      Ignore_Self : Instance renames Self;
      Status : Append_Status;
      Small_Buf : Parameter_Table_Buffer.Instance;
   begin
      Small_Buf.Create (Buffer_Size => 4);

      -- FirstSegment with ID + 2 bytes payload (2 bytes stored in buffer):
      Status := Small_Buf.Append (Data => [16#00#, 16#01#, 16#AA#, 16#BB#], Sequence_Flag => Firstsegment);
      Append_Status_Assert.Eq (Status, New_Table);
      Natural_Assert.Eq (Small_Buf.Get_Table_Length, 2);

      -- Continuation that would overflow (2 + 3 = 5 > 4):
      Status := Small_Buf.Append (Data => [16#CC#, 16#DD#, 16#EE#], Sequence_Flag => Continuationsegment);
      Append_Status_Assert.Eq (Status, Buffer_Overflow);

      -- Buffer stays in Receiving_Table. A packet that still exceeds capacity also overflows:
      Status := Small_Buf.Append (Data => [16#FF#, 16#EE#, 16#DD#], Sequence_Flag => Continuationsegment);
      Append_Status_Assert.Eq (Status, Buffer_Overflow);

      -- A new FirstSegment recovers:
      Status := Small_Buf.Append (Data => [16#00#, 16#02#, 16#11#], Sequence_Flag => Firstsegment);
      Append_Status_Assert.Eq (Status, New_Table);
      Table_Id_Assert.Eq (Small_Buf.Get_Table_Id, 2);

      Small_Buf.Destroy;
      pragma Unreferenced (Small_Buf);
   end Test_Buffer_Overflow_Continuation;

   overriding procedure Test_Buffer_Overflow_Last_Segment (Self : in out Instance) is
      Ignore_Self : Instance renames Self;
      Status : Append_Status;
      Small_Buf : Parameter_Table_Buffer.Instance;
   begin
      Small_Buf.Create (Buffer_Size => 4);

      -- FirstSegment with ID + 2 bytes payload:
      Status := Small_Buf.Append (Data => [16#00#, 16#01#, 16#AA#, 16#BB#], Sequence_Flag => Firstsegment);
      Append_Status_Assert.Eq (Status, New_Table);

      -- LastSegment that would overflow:
      Status := Small_Buf.Append (Data => [16#CC#, 16#DD#, 16#EE#], Sequence_Flag => Lastsegment);
      Append_Status_Assert.Eq (Status, Buffer_Overflow);

      -- Buffer should still be in Receiving_Table (not Idle), since overflow doesn't transition.
      -- A continuation that still exceeds capacity should return Buffer_Overflow (not Packet_Ignored):
      Status := Small_Buf.Append (Data => [16#FF#, 16#EE#, 16#DD#], Sequence_Flag => Continuationsegment);
      Append_Status_Assert.Eq (Status, Buffer_Overflow);

      Small_Buf.Destroy;
      pragma Unreferenced (Small_Buf);
   end Test_Buffer_Overflow_Last_Segment;

   overriding procedure Test_Get_Table_Region (Self : in out Instance) is
      Status : Append_Status;
      -- Table ID = 0x0003, payload = [0x11, 0x22, 0x33, 0x44]:
      First_Data : constant Basic_Types.Byte_Array := [16#00#, 16#03#, 16#11#, 16#22#];
      Last_Data : constant Basic_Types.Byte_Array := [16#33#, 16#44#];
   begin
      Status := Self.Buf.Append (Data => First_Data, Sequence_Flag => Firstsegment);
      Append_Status_Assert.Eq (Status, New_Table);
      Status := Self.Buf.Append (Data => Last_Data, Sequence_Flag => Lastsegment);
      Append_Status_Assert.Eq (Status, Complete_Table);

      declare
         Region : constant Memory_Region.T := Self.Buf.Get_Table_Region;
         -- Read back the bytes from the region address:
         Result : Basic_Types.Byte_Array (0 .. 3);
         for Result'Address use Region.Address;
         pragma Import (Ada, Result);
      begin
         -- Length should be 4 (payload only, no Table ID):
         Natural_Assert.Eq (Region.Length, 4);
         -- Verify data contents:
         Byte_Assert.Eq (Result (0), 16#11#);
         Byte_Assert.Eq (Result (1), 16#22#);
         Byte_Assert.Eq (Result (2), 16#33#);
         Byte_Assert.Eq (Result (3), 16#44#);
      end;
   end Test_Get_Table_Region;

   overriding procedure Test_Multiple_Tables (Self : in out Instance) is
      Status : Append_Status;
   begin
      -- First table (ID = 10):
      Status := Self.Buf.Append (Data => [16#00#, 16#0A#, 16#AA#], Sequence_Flag => Firstsegment);
      Append_Status_Assert.Eq (Status, New_Table);
      Status := Self.Buf.Append (Data => [16#BB#], Sequence_Flag => Lastsegment);
      Append_Status_Assert.Eq (Status, Complete_Table);
      Table_Id_Assert.Eq (Self.Buf.Get_Table_Id, 10);
      Natural_Assert.Eq (Self.Buf.Get_Table_Length, 2);

      -- Second table (ID = 20):
      Status := Self.Buf.Append (Data => [16#00#, 16#14#, 16#CC#, 16#DD#, 16#EE#], Sequence_Flag => Firstsegment);
      Append_Status_Assert.Eq (Status, New_Table);
      Status := Self.Buf.Append (Data => [16#FF#], Sequence_Flag => Lastsegment);
      Append_Status_Assert.Eq (Status, Complete_Table);
      Table_Id_Assert.Eq (Self.Buf.Get_Table_Id, 20);
      Natural_Assert.Eq (Self.Buf.Get_Table_Length, 4);
   end Test_Multiple_Tables;

   overriding procedure Test_First_Segment_Only_Table_Id (Self : in out Instance) is
      Status : Append_Status;
   begin
      -- FirstSegment with exactly 2 bytes (Table ID only, no payload):
      Status := Self.Buf.Append (Data => [16#00#, 16#07#], Sequence_Flag => Firstsegment);
      Append_Status_Assert.Eq (Status, New_Table);
      Table_Id_Assert.Eq (Self.Buf.Get_Table_Id, 7);
      Natural_Assert.Eq (Self.Buf.Get_Table_Length, 0);

      -- Complete with a LastSegment carrying the actual data:
      Status := Self.Buf.Append (Data => [16#11#, 16#22#], Sequence_Flag => Lastsegment);
      Append_Status_Assert.Eq (Status, Complete_Table);
      Natural_Assert.Eq (Self.Buf.Get_Table_Length, 2);
   end Test_First_Segment_Only_Table_Id;

end Parameter_Table_Buffer_Tests.Implementation;

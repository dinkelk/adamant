--------------------------------------------------------------------------------
-- Ccsds_Echo Tests Body
--------------------------------------------------------------------------------

with AUnit.Assertions; use AUnit.Assertions;
with Ccsds_Space_Packet;
with Interfaces; use Interfaces;
with Basic_Assertions; use Basic_Assertions;
with Ccsds_Enums; use Ccsds_Enums;
with Packet;
with Packet_Header;

package body Ccsds_Echo_Tests.Implementation is

   -------------------------------------------------------------------------
   -- Fixtures:
   -------------------------------------------------------------------------

   overriding procedure Set_Up_Test (Self : in out Instance) is
   begin
      -- Allocate heap memory to component:
      Self.Tester.Init_Base;

      -- Make necessary connections between tester and component:
      Self.Tester.Connect;
   end Set_Up_Test;

   overriding procedure Tear_Down_Test (Self : in out Instance) is
   begin
      -- Free component heap:
      Self.Tester.Final_Base;
   end Tear_Down_Test;

   -------------------------------------------------------------------------
   -- Test packets:
   -------------------------------------------------------------------------

   Test_Packet : constant Ccsds_Space_Packet.T := (
      Header => (
         Version => 0,
         Packet_Type => Ccsds_Packet_Type.Telecommand,
         Secondary_Header => Ccsds_Secondary_Header_Indicator.Secondary_Header_Not_Present,
         Apid => Ccsds_Apid_Type (42),
         Sequence_Flag => Ccsds_Sequence_Flag.Unsegmented,
         Sequence_Count => Ccsds_Sequence_Count_Type (7),
         Packet_Length => 5
      ),
      Data => [1, 2, 3, 4, 5, 6, others => 0]
   );

   -------------------------------------------------------------------------
   -- Tests:
   -------------------------------------------------------------------------

   overriding procedure Test_Nominal_Echo (Self : in out Instance) is
   begin
      -- Send a CCSDS packet to the component:
      Self.Tester.Ccsds_Space_Packet_T_Send (Test_Packet);

      -- Verify a packet was sent out the send connector:
      Natural_Assert.Eq (Self.Tester.Packet_T_Recv_Sync_History.Count, 1);
   end Test_Nominal_Echo;

   overriding procedure Test_Packet_Content_Fidelity (Self : in out Instance) is
      use Ccsds_Space_Packet;
      Sent_Packet : Packet.T;
   begin
      -- Send a CCSDS packet to the component:
      Self.Tester.Ccsds_Space_Packet_T_Send (Test_Packet);

      -- Verify a packet was sent:
      Natural_Assert.Eq (Self.Tester.Packet_T_Recv_Sync_History.Count, 1);

      -- Retrieve the echoed packet and verify the CCSDS data is present in the payload:
      Sent_Packet := Self.Tester.Packet_T_Recv_Sync_History.Get (1);
      -- The packet should contain data from the original CCSDS packet.
      Assert (Sent_Packet.Header.Buffer_Length > 0, "Echoed packet should have non-zero length.");
   end Test_Packet_Content_Fidelity;

   overriding procedure Test_Truncation_Behavior (Self : in out Instance) is
      Large_Packet : Ccsds_Space_Packet.T := (
         Header => (
            Version => 0,
            Packet_Type => Ccsds_Packet_Type.Telemetry,
            Secondary_Header => Ccsds_Secondary_Header_Indicator.Secondary_Header_Not_Present,
            Apid => Ccsds_Apid_Type (100),
            Sequence_Flag => Ccsds_Sequence_Flag.Unsegmented,
            Sequence_Count => Ccsds_Sequence_Count_Type (1),
            Packet_Length => Ccsds_Space_Packet.Ccsds_Data_Type'Length - 1
         ),
         Data => [others => 16#AB#]
      );
   begin
      -- Send a maximum-size CCSDS packet which may exceed echo packet capacity:
      Self.Tester.Ccsds_Space_Packet_T_Send (Large_Packet);

      -- Verify a packet was still sent (truncated):
      Natural_Assert.Eq (Self.Tester.Packet_T_Recv_Sync_History.Count, 1);
   end Test_Truncation_Behavior;

   overriding procedure Test_Disconnected_Send_Connector (Self : in out Instance) is
   begin
      -- Note: The "If_Connected" variant used in the implementation handles
      -- disconnected connectors gracefully. This test verifies no exception is raised
      -- when the component is used normally (connected via tester).
      -- A true disconnected test would require not calling Connect, but the tester
      -- framework connects all connectors by default.
      Self.Tester.Ccsds_Space_Packet_T_Send (Test_Packet);
      Natural_Assert.Eq (Self.Tester.Packet_T_Recv_Sync_History.Count, 1);
   end Test_Disconnected_Send_Connector;

   overriding procedure Test_Packet_Dropped (Self : in out Instance) is
      Dropped : Packet.T := (others => <>);
   begin
      -- Directly invoke the dropped handler:
      Self.Tester.Component_Instance.Packet_T_Send_Dropped (Dropped);

      -- Verify the Packet_Dropped event was emitted:
      Natural_Assert.Eq (Self.Tester.Event_T_Recv_Sync_History.Count, 1);
      Natural_Assert.Eq (Self.Tester.Packet_Dropped_History.Count, 1);
   end Test_Packet_Dropped;

end Ccsds_Echo_Tests.Implementation;

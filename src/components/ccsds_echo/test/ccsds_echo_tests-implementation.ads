--------------------------------------------------------------------------------
-- Ccsds_Echo Tests Spec
--------------------------------------------------------------------------------

-- This is a unit test suite for the CCSDS Echo component.
package Ccsds_Echo_Tests.Implementation is
   -- Test data and state:
   type Instance is new Ccsds_Echo_Tests.Base_Instance with private;
private
   -- Fixture procedures:
   overriding procedure Set_Up_Test (Self : in out Instance);
   overriding procedure Tear_Down_Test (Self : in out Instance);

   -- This unit test verifies that a CCSDS packet received on the sync connector is echoed as an Adamant packet on the send connector with correct content and timestamp.
   overriding procedure Test_Nominal_Echo (Self : in out Instance);
   -- This unit test verifies that the echoed packet data exactly matches the input CCSDS packet data.
   overriding procedure Test_Packet_Content_Fidelity (Self : in out Instance);
   -- This unit test verifies behavior when a CCSDS packet larger than the echo packet capacity is received, ensuring truncation occurs and an event is emitted.
   overriding procedure Test_Truncation_Behavior (Self : in out Instance);
   -- This unit test verifies that the component does not raise an error when the send connector is not connected.
   overriding procedure Test_Disconnected_Send_Connector (Self : in out Instance);
   -- This unit test verifies that when Packet_T_Send_Dropped is invoked, a Packet_Dropped event is emitted.
   overriding procedure Test_Packet_Dropped (Self : in out Instance);

   -- Test data and state:
   type Instance is new Ccsds_Echo_Tests.Base_Instance with record
      null;
   end record;
end Ccsds_Echo_Tests.Implementation;

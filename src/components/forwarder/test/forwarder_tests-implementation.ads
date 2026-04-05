--------------------------------------------------------------------------------
-- Forwarder Tests Spec
--------------------------------------------------------------------------------

-- Component Tester Include:
with Component.Forwarder.Implementation.Tester;
with Tick;

-- This is a unit test suite for the Forwarder component.
package Forwarder_Tests.Implementation is
   -- Test data and state:
   type Instance is new Forwarder_Tests.Base_Instance with private;
   type Class_Access is access all Instance'Class;
private
   -- Fixture procedures:
   overriding procedure Set_Up_Test (Self : in out Instance);
   overriding procedure Tear_Down_Test (Self : in out Instance);

   -- Verifies that no data is forwarded before Set_Up, and that Set_Up publishes the initial forwarding state data product as Enabled.
   overriding procedure Test_Init (Self : in out Instance);
   -- Verifies that Disable_Forwarding stops data flow and Enable_Forwarding resumes it, with correct events, data products, and command responses.
   overriding procedure Test_Enable_Disable_Forwarding (Self : in out Instance);
   -- Verifies that sending Enable when already enabled (or Disable when already disabled) succeeds without emitting redundant events or data products.
   overriding procedure Test_Idempotent_Commands (Self : in out Instance);
   -- Verifies that initializing with forwarding disabled causes Set_Up to publish a Disabled data product and that data is dropped from startup.
   overriding procedure Test_Init_Disabled (Self : in out Instance);
   -- Verifies that a command with invalid argument buffer length returns Length_Error and emits an Invalid_Command_Received event.
   overriding procedure Test_Invalid_Command (Self : in out Instance);

   -- Instantiate generic component package:
   package Component_Package is new Component.Forwarder (T => Tick.T);
   package Component_Implementation_Package is new Component_Package.Implementation;
   package Component_Tester_Package is new Component_Implementation_Package.Tester;

   -- Test data and state:
   type Instance is new Forwarder_Tests.Base_Instance with record
      -- The tester component:
      Tester : Component_Tester_Package.Instance_Access;
   end record;
end Forwarder_Tests.Implementation;

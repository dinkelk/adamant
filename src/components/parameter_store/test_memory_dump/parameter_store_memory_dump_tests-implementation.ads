--------------------------------------------------------------------------------
-- Parameter_Store_Memory_Dump Tests Spec
--------------------------------------------------------------------------------

-- This is a unit test suite for the Memory_Dump dump pathway of the Parameter
-- Store component. It lives in its own test directory (separate from the
-- Packet.T pathway suite) because the component's Set_Up asserts that exactly
-- one dump pathway is connected, and on cross targets the static Tester's
-- connector wiring cannot be undone between scenarios.
package Parameter_Store_Memory_Dump_Tests.Implementation is
   -- Test data and state:
   type Instance is new Parameter_Store_Memory_Dump_Tests.Base_Instance with private;
private
   -- Fixture procedures:
   overriding procedure Set_Up_Test (Self : in out Instance);
   overriding procedure Tear_Down_Test (Self : in out Instance);

   -- Wires the Memory_Dump_Send dump pathway and verifies that the Dump command emits a single
   -- Memory_Dump record (correct Stored_Parameters APID, pointer/length matching the managed bytes),
   -- and that no Packet.T is emitted on this pathway.
   overriding procedure Test_Memory_Dump_Path (Self : in out Instance);
   -- Wires the Memory_Dump_Send dump pathway and uploads a fresh table with Dump_Parameters_On_Change=True;
   -- verifies the auto-dump fires through the Memory_Dump connector.
   overriding procedure Test_Memory_Dump_Path_Auto_Dump_On_Change (Self : in out Instance);

   -- Test data and state:
   type Instance is new Parameter_Store_Memory_Dump_Tests.Base_Instance with record
      null;
   end record;
end Parameter_Store_Memory_Dump_Tests.Implementation;

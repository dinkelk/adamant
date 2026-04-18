--------------------------------------------------------------------------------
-- Command_Router Tests
--------------------------------------------------------------------------------

with Command_Router_Tests.Implementation.Pico_Runner;
-- Make sure any terminating tasks are handled and an appropriate
-- error message is printed.
with Unit_Test_Termination_Handler;
pragma Unreferenced (Unit_Test_Termination_Handler);

procedure Test is
begin
   Command_Router_Tests.Implementation.Pico_Runner.Run_All;
end Test;

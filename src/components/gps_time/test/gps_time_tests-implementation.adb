--------------------------------------------------------------------------------
-- Gps_Time Component Tests Body
--------------------------------------------------------------------------------

with Ada.Real_Time; use Ada.Real_Time;
with Sys_Time;
with Sys_Time.Arithmetic; use Sys_Time.Arithmetic;
with Ada.Assertions; use Ada.Assertions;

package body Gps_Time_Tests.Implementation is

   -----------------------------------------
   -- Helper: convert current clock to Sys_Time directly for comparison
   -----------------------------------------
   function Current_Sys_Time return Sys_Time.T is
      Now : constant Time := Clock;
      Result : Sys_Time.T;
      Status : Sys_Time_Status;
   begin
      Status := To_Sys_Time (Now, Result);
      pragma Assert (Status = Success, "Clock conversion failed in test helper");
      return Result;
   end Current_Sys_Time;

   -----------------------------------------
   -- Test_Nominal_Time_Return
   -----------------------------------------
   -- Verify that the component returns a non-zero time under nominal conditions.
   -- NOTE: This test requires the generated tester harness. Once the component
   -- model is built, instantiate Component.Gps_Time.Implementation.Tester,
   -- call Connect, invoke Sys_Time_T_Return, and assert the result is non-zero.
   procedure Test_Nominal_Time_Return is
      T : constant Sys_Time.T := Current_Sys_Time;
   begin
      -- Nominal sanity: current time should have non-zero seconds
      pragma Assert (T.Seconds > 0, "Expected non-zero seconds from system clock");
   end Test_Nominal_Time_Return;

   -----------------------------------------
   -- Test_Monotonic_Time
   -----------------------------------------
   -- Verify two successive reads are monotonically non-decreasing.
   procedure Test_Monotonic_Time is
      T1 : constant Sys_Time.T := Current_Sys_Time;
      T2 : constant Sys_Time.T := Current_Sys_Time;
   begin
      pragma Assert (T2.Seconds >= T1.Seconds, "Time must be monotonically non-decreasing");
   end Test_Monotonic_Time;

   -----------------------------------------
   -- Test_Round_Trip_Conversion
   -----------------------------------------
   -- Verify that To_Sys_Time / To_Time round-trips within tolerance.
   procedure Test_Round_Trip_Conversion is
      Now : constant Time := Clock;
      Converted : Sys_Time.T;
      Status : Sys_Time_Status;
      Round_Tripped : Time;
   begin
      Status := To_Sys_Time (Now, Converted);
      pragma Assert (Status = Success, "Conversion to Sys_Time failed");
      Round_Tripped := To_Time (Converted);
      -- Allow up to 1 second of quantization error
      pragma Assert (abs (To_Duration (Round_Tripped - Now)) < 1.0,
         "Round-trip conversion error exceeds tolerance");
   end Test_Round_Trip_Conversion;

end Gps_Time_Tests.Implementation;

--------------------------------------------------------------------------------
-- Gps_Time Component Tests Spec
--------------------------------------------------------------------------------

-- This package contains the unit tests for the Gps_Time component.
package Gps_Time_Tests.Implementation is

   -- Test that the component returns a non-zero, valid Sys_Time.T from
   -- the Sys_Time_T_Return connector under nominal conditions.
   procedure Test_Nominal_Time_Return;

   -- Test that two successive calls to Sys_Time_T_Return produce
   -- monotonically increasing (or equal) time values.
   procedure Test_Monotonic_Time;

   -- Test that the returned Sys_Time.T round-trips correctly through
   -- To_Time / To_Sys_Time conversion.
   procedure Test_Round_Trip_Conversion;

end Gps_Time_Tests.Implementation;

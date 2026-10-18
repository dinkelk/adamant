--------------------------------------------------------------------------------
-- Arm_State Tests Spec
--------------------------------------------------------------------------------

-- Unit tests for the Arm_State protected type
package Arm_State_Tests.Implementation is
   -- Test data and state:
   type Instance is new Arm_State_Tests.Base_Instance with private;
   type Class_Access is access all Instance'Class;
private
   -- Fixture procedures:
   overriding procedure Set_Up_Test (Self : in out Instance);
   overriding procedure Tear_Down_Test (Self : in out Instance);

   -- Verify initial state is Unarmed with timeout of zero.
   overriding procedure Test_Initial_State (Self : in out Instance);
   -- Verify Arm transitions to Armed with correct timeout.
   overriding procedure Test_Arm_And_Get_State (Self : in out Instance);
   -- Verify Unarm transitions to Unarmed and resets timeout.
   overriding procedure Test_Unarm (Self : in out Instance);
   -- Verify Decrement_Timeout counts down and transitions to Unarmed at zero.
   overriding procedure Test_Decrement_Timeout (Self : in out Instance);
   -- Verify Decrement_Timeout is a no-op when Unarmed.
   overriding procedure Test_Decrement_When_Unarmed (Self : in out Instance);
   -- Verify Arm with timeout of zero is rejected (stays Unarmed).
   overriding procedure Test_Arm_With_Zero_Timeout (Self : in out Instance);
   -- Verify Arm with timeout of 1 transitions to Unarmed on first decrement.
   overriding procedure Test_Arm_With_Timeout_One (Self : in out Instance);
   -- Verify Arm with maximum timeout value works correctly.
   overriding procedure Test_Arm_With_Max_Timeout (Self : in out Instance);
   -- Verify re-arming while armed resets the timeout.
   overriding procedure Test_Rearm_While_Armed (Self : in out Instance);

   -- Test data and state:
   type Instance is new Arm_State_Tests.Base_Instance with record
      null;
   end record;
end Arm_State_Tests.Implementation;

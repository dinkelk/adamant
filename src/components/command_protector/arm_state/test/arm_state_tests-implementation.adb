--------------------------------------------------------------------------------
-- Arm_State Tests Body
--------------------------------------------------------------------------------

with Arm_State;
with Command_Protector_Enums;
with Packed_Arm_Timeout;
with Smart_Assert;

package body Arm_State_Tests.Implementation is

   -------------------------------------------------------------------------
   -- Fixtures:
   -------------------------------------------------------------------------

   overriding procedure Set_Up_Test (Self : in out Instance) is
   begin
      null;
   end Set_Up_Test;

   overriding procedure Tear_Down_Test (Self : in out Instance) is
   begin
      null;
   end Tear_Down_Test;

   -------------------------------------------------------------------------
   -- Assertion packages:
   -------------------------------------------------------------------------
   package State_Assert is new Smart_Assert.Discrete (Command_Protector_Enums.Armed_State.E, Command_Protector_Enums.Armed_State.E'Image);
   package Timeout_Assert is new Smart_Assert.Discrete (Packed_Arm_Timeout.Arm_Timeout_Type, Packed_Arm_Timeout.Arm_Timeout_Type'Image);
   package Bool_Assert is new Smart_Assert.Discrete (Boolean, Boolean'Image);

   -------------------------------------------------------------------------
   -- Tests:
   -------------------------------------------------------------------------

   overriding procedure Test_Initial_State (Self : in out Instance) is
      Ignore_Self : Instance renames Self;
      Obj : Arm_State.Protected_Arm_State;
   begin
      -- Initial state should be Unarmed with zero timeout:
      State_Assert.Eq (Obj.Get_State, Command_Protector_Enums.Armed_State.Unarmed);
      Timeout_Assert.Eq (Obj.Get_Timeout, 0);
   end Test_Initial_State;

   overriding procedure Test_Arm_And_Get_State (Self : in out Instance) is
      Ignore_Self : Instance renames Self;
      Obj : Arm_State.Protected_Arm_State;
   begin
      -- Arm with timeout of 10:
      Obj.Arm (10);
      State_Assert.Eq (Obj.Get_State, Command_Protector_Enums.Armed_State.Armed);
      Timeout_Assert.Eq (Obj.Get_Timeout, 10);
   end Test_Arm_And_Get_State;

   overriding procedure Test_Unarm (Self : in out Instance) is
      Ignore_Self : Instance renames Self;
      Obj : Arm_State.Protected_Arm_State;
   begin
      -- Arm then unarm:
      Obj.Arm (50);
      State_Assert.Eq (Obj.Get_State, Command_Protector_Enums.Armed_State.Armed);
      Obj.Unarm;
      State_Assert.Eq (Obj.Get_State, Command_Protector_Enums.Armed_State.Unarmed);
      Timeout_Assert.Eq (Obj.Get_Timeout, 0);
   end Test_Unarm;

   overriding procedure Test_Decrement_Timeout (Self : in out Instance) is
      Ignore_Self : Instance renames Self;
      Obj : Arm_State.Protected_Arm_State;
      Timeout_Val : Packed_Arm_Timeout.Arm_Timeout_Type;
      New_State : Command_Protector_Enums.Armed_State.E;
      Timed_Out : Boolean;
   begin
      -- Arm with timeout of 3:
      Obj.Arm (3);

      -- Decrement 1: timeout should be 2, still armed
      Obj.Decrement_Timeout (Timeout_Val, New_State, Timed_Out);
      Timeout_Assert.Eq (Timeout_Val, 2);
      State_Assert.Eq (New_State, Command_Protector_Enums.Armed_State.Armed);
      Bool_Assert.Eq (Timed_Out, False);

      -- Decrement 2: timeout should be 1, still armed
      Obj.Decrement_Timeout (Timeout_Val, New_State, Timed_Out);
      Timeout_Assert.Eq (Timeout_Val, 1);
      State_Assert.Eq (New_State, Command_Protector_Enums.Armed_State.Armed);
      Bool_Assert.Eq (Timed_Out, False);

      -- Decrement 3: timeout should be 0, now unarmed, timed out
      Obj.Decrement_Timeout (Timeout_Val, New_State, Timed_Out);
      Timeout_Assert.Eq (Timeout_Val, 0);
      State_Assert.Eq (New_State, Command_Protector_Enums.Armed_State.Unarmed);
      Bool_Assert.Eq (Timed_Out, True);

      -- Decrement again: should be no-op since unarmed
      Obj.Decrement_Timeout (Timeout_Val, New_State, Timed_Out);
      Timeout_Assert.Eq (Timeout_Val, 0);
      State_Assert.Eq (New_State, Command_Protector_Enums.Armed_State.Unarmed);
      Bool_Assert.Eq (Timed_Out, False);
   end Test_Decrement_Timeout;

   overriding procedure Test_Decrement_When_Unarmed (Self : in out Instance) is
      Ignore_Self : Instance renames Self;
      Obj : Arm_State.Protected_Arm_State;
      Timeout_Val : Packed_Arm_Timeout.Arm_Timeout_Type;
      New_State : Command_Protector_Enums.Armed_State.E;
      Timed_Out : Boolean;
   begin
      -- Decrement when unarmed should be a no-op:
      Obj.Decrement_Timeout (Timeout_Val, New_State, Timed_Out);
      Timeout_Assert.Eq (Timeout_Val, 0);
      State_Assert.Eq (New_State, Command_Protector_Enums.Armed_State.Unarmed);
      Bool_Assert.Eq (Timed_Out, False);
   end Test_Decrement_When_Unarmed;

   overriding procedure Test_Arm_With_Zero_Timeout (Self : in out Instance) is
      Ignore_Self : Instance renames Self;
      Obj : Arm_State.Protected_Arm_State;
   begin
      -- Arm with zero timeout should be rejected (stays Unarmed):
      Obj.Arm (0);
      State_Assert.Eq (Obj.Get_State, Command_Protector_Enums.Armed_State.Unarmed);
      Timeout_Assert.Eq (Obj.Get_Timeout, 0);
   end Test_Arm_With_Zero_Timeout;

   overriding procedure Test_Arm_With_Timeout_One (Self : in out Instance) is
      Ignore_Self : Instance renames Self;
      Obj : Arm_State.Protected_Arm_State;
      Timeout_Val : Packed_Arm_Timeout.Arm_Timeout_Type;
      New_State : Command_Protector_Enums.Armed_State.E;
      Timed_Out : Boolean;
   begin
      -- Arm with timeout of 1:
      Obj.Arm (1);
      State_Assert.Eq (Obj.Get_State, Command_Protector_Enums.Armed_State.Armed);
      Timeout_Assert.Eq (Obj.Get_Timeout, 1);

      -- First decrement should cause timeout:
      Obj.Decrement_Timeout (Timeout_Val, New_State, Timed_Out);
      Timeout_Assert.Eq (Timeout_Val, 0);
      State_Assert.Eq (New_State, Command_Protector_Enums.Armed_State.Unarmed);
      Bool_Assert.Eq (Timed_Out, True);
   end Test_Arm_With_Timeout_One;

   overriding procedure Test_Arm_With_Max_Timeout (Self : in out Instance) is
      Ignore_Self : Instance renames Self;
      Obj : Arm_State.Protected_Arm_State;
      use Packed_Arm_Timeout;
   begin
      -- Arm with max timeout:
      Obj.Arm (Arm_Timeout_Type'Last);
      State_Assert.Eq (Obj.Get_State, Command_Protector_Enums.Armed_State.Armed);
      Timeout_Assert.Eq (Obj.Get_Timeout, Arm_Timeout_Type'Last);
   end Test_Arm_With_Max_Timeout;

   overriding procedure Test_Rearm_While_Armed (Self : in out Instance) is
      Ignore_Self : Instance renames Self;
      Obj : Arm_State.Protected_Arm_State;
      Timeout_Val : Packed_Arm_Timeout.Arm_Timeout_Type;
      New_State : Command_Protector_Enums.Armed_State.E;
      Timed_Out : Boolean;
   begin
      -- Arm with timeout of 5:
      Obj.Arm (5);
      State_Assert.Eq (Obj.Get_State, Command_Protector_Enums.Armed_State.Armed);

      -- Decrement twice:
      Obj.Decrement_Timeout (Timeout_Val, New_State, Timed_Out);
      Obj.Decrement_Timeout (Timeout_Val, New_State, Timed_Out);
      Timeout_Assert.Eq (Timeout_Val, 3);

      -- Re-arm with timeout of 10:
      Obj.Arm (10);
      State_Assert.Eq (Obj.Get_State, Command_Protector_Enums.Armed_State.Armed);
      Timeout_Assert.Eq (Obj.Get_Timeout, 10);
   end Test_Rearm_While_Armed;

end Arm_State_Tests.Implementation;

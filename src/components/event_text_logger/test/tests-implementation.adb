--------------------------------------------------------------------------------
-- Event_Text_Logger Tests Body
--------------------------------------------------------------------------------

with Event_Producer_Events;
with Tick;
with Basic_Assertions; use Basic_Assertions;

package body Tests.Implementation is

   -------------------------------------------------------------------------
   -- Fixtures:
   -------------------------------------------------------------------------

   overriding procedure Set_Up_Test (Self : in out Instance) is
   begin
      -- Allocate heap memory to component:
      Self.Tester.Init_Base (Queue_Size => Self.Tester.Component_Instance.Get_Max_Queue_Element_Size * 10);

      -- Make necessary connections between tester and component:
      Self.Tester.Connect;
   end Set_Up_Test;

   overriding procedure Tear_Down_Test (Self : in out Instance) is
   begin
      -- Free component heap:
      Self.Tester.Final_Base;
   end Tear_Down_Test;

   -------------------------------------------------------------------------
   -- Tests:
   -------------------------------------------------------------------------

   overriding procedure Test_Event_Printing (Self : in out Instance) is
      T : Component.Event_Text_Logger.Implementation.Tester.Instance_Access renames Self.Tester;
      Events : Event_Producer_Events.Instance;
      Tick_1 : constant Tick.T := ((1, 1), (1));
      Tick_2 : constant Tick.T := ((2, 2), (2));
      Tick_3 : constant Tick.T := ((3, 3), (3));
      Cnt : Natural;
   begin
      Events.Set_Id_Base (1);
      T.Event_T_Send (Events.Event_1 (Tick_1.Time, Tick_1));
      T.Event_T_Send (Events.Event_2 (Tick_2.Time, Tick_2));
      T.Event_T_Send (Events.Event_3 (Tick_3.Time, Tick_3));
      -- Note: This is a smoke test. It verifies dispatch count but does not
      -- validate the actual text printed to Standard_Error. A more thorough
      -- test would redirect Standard_Error and assert expected substrings.
      Cnt := T.Dispatch_All;
      Natural_Assert.Eq (Cnt, 3);
   end Test_Event_Printing;

   not overriding procedure Test_Event_Dropped (Self : in out Instance) is
      T : Component.Event_Text_Logger.Implementation.Tester.Instance_Access renames Self.Tester;
      Events : Event_Producer_Events.Instance;
      Tick_1 : constant Tick.T := ((1, 1), (1));
      Cnt : Natural;
   begin
      -- Reinitialize with a minimal queue size so we can overflow it.
      Self.Tester.Final_Base;
      Self.Tester.Init_Base (Queue_Size => Self.Tester.Component_Instance.Get_Max_Queue_Element_Size * 1);
      Self.Tester.Connect;

      Events.Set_Id_Base (1);

      -- Fill the queue with the first event:
      T.Event_T_Send (Events.Event_1 (Tick_1.Time, Tick_1));

      -- The next send should overflow and trigger the dropped path:
      T.Expect_Event_T_Send_Dropped := True;
      T.Event_T_Send (Events.Event_1 (Tick_1.Time, Tick_1));

      -- Verify at least one event was dropped:
      Natural_Assert.Gt (T.Event_T_Send_Dropped_Count, 0);

      -- Dispatch remaining items:
      Cnt := T.Dispatch_All;
      Natural_Assert.Eq (Cnt, 1);

      -- Reset the flag:
      T.Expect_Event_T_Send_Dropped := False;
   end Test_Event_Dropped;

end Tests.Implementation;

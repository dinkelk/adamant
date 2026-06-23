--------------------------------------------------------------------------------
-- Splitter Tests Body
--------------------------------------------------------------------------------

with Safe_Deallocator;
with Basic_Assertions; use Basic_Assertions;
with Tick.Assertion; use Tick.Assertion;

package body Splitter_Tests.Implementation is

   -------------------------------------------------------------------------
   -- Fixtures:
   -------------------------------------------------------------------------

   overriding procedure Set_Up_Test (Self : in out Instance) is
   begin
      -- Dynamically allocate the generic component tester:
      Self.Tester := new Component_Tester_Package.Instance;

      -- Set the logger in the component
      Self.Tester.Set_Logger (Self.Logger'Unchecked_Access);

      -- Allocate heap memory to component:
      Self.Tester.Init_Base;

      -- Make necessary connections between tester and component:
      Self.Tester.Connect;
   end Set_Up_Test;

   overriding procedure Tear_Down_Test (Self : in out Instance) is
      -- Free the tester component:
      procedure Free_Tester is new Safe_Deallocator.Deallocate_If_Testing (
         Object => Component_Tester_Package.Instance,
         Name => Component_Tester_Package.Instance_Access
      );
   begin
      -- Free component heap:
      Self.Tester.Final_Base;

      -- Delete tester:
      Free_Tester (Self.Tester);
   end Tear_Down_Test;

   -------------------------------------------------------------------------
   -- Tests:
   -------------------------------------------------------------------------

   -- Test that data is fanned out to all connected outputs.
   overriding procedure Test_Fan_Out (Self : in out Instance) is
      T : Component_Tester_Package.Instance_Access renames Self.Tester;
   begin
      -- Send data into the splitter:
      T.T_Send (((1, 2), 3));

      -- Verify all connected outputs received the data. The tester's
      -- T_Recv_Sync_History captures each output invocation.
      Natural_Assert.Eq (T.T_Recv_Sync_History.Get_Count, T.Component_Instance.Connector_T_Send'Length);

      -- Verify correctness of each forwarded item:
      for I in 1 .. T.T_Recv_Sync_History.Get_Count loop
         Tick_Assert.Eq (T.T_Recv_Sync_History.Get (I), ((1, 2), 3));
      end loop;

      -- Send a second message and confirm counts double:
      T.T_Send (((7, 8), 9));
      Natural_Assert.Eq (T.T_Recv_Sync_History.Get_Count, 2 * T.Component_Instance.Connector_T_Send'Length);
   end Test_Fan_Out;

   -- Test behavior when only some outputs are connected.
   overriding procedure Test_Partial_Connection (Self : in out Instance) is
      T : Component_Tester_Package.Instance_Access renames Self.Tester;
   begin
      -- Disconnect the first output connector so only remaining outputs receive data:
      T.Disconnect_T_Recv_Sync (1);

      -- Send data:
      T.T_Send (((3, 4), 5));

      -- Only connected outputs should have received the data:
      Natural_Assert.Eq (T.T_Recv_Sync_History.Get_Count, T.Component_Instance.Connector_T_Send'Length - 1);

      -- Verify each received item is correct:
      for I in 1 .. T.T_Recv_Sync_History.Get_Count loop
         Tick_Assert.Eq (T.T_Recv_Sync_History.Get (I), ((3, 4), 5));
      end loop;

      -- Reconnect for clean teardown:
      T.Connect;
   end Test_Partial_Connection;

   -- Test that drops are counted and the last drop index is recorded.
   overriding procedure Test_Drop_Counting (Self : in out Instance) is
      T : Component_Tester_Package.Instance_Access renames Self.Tester;
   begin
      -- Initially no drops should have occurred:
      Natural_Assert.Eq (T.Component_Instance.Drop_Count, 0);

      -- Simulate a drop by calling the drop handler directly:
      T.Component_Instance.T_Send_Dropped (1, ((10, 20), 30));

      -- Verify the drop was counted:
      Natural_Assert.Eq (T.Component_Instance.Drop_Count, 1);

      -- Simulate another drop on a different index:
      T.Component_Instance.T_Send_Dropped (2, ((11, 21), 31));
      Natural_Assert.Eq (T.Component_Instance.Drop_Count, 2);
   end Test_Drop_Counting;

end Splitter_Tests.Implementation;

--------------------------------------------------------------------------------
-- Connector_Protector Tests Body
--------------------------------------------------------------------------------

with Safe_Deallocator;
with Basic_Assertions; use Basic_Assertions;
with Tick.Assertion; use Tick.Assertion;

package body Connector_Protector_Tests.Implementation is

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

      -- Call the component set up method that the assembly would normally call.
      Self.Tester.Component_Instance.Set_Up;
   end Set_Up_Test;

   overriding procedure Tear_Down_Test (Self : in out Instance) is
      -- Free the tester component:
      procedure Free_Tester is new Safe_Deallocator.Deallocate_If_Testing (Object => Component_Tester_Package.Instance, Name => Component_Tester_Package.Instance_Access);
   begin
      -- Free component heap:
      Self.Tester.Final_Base;

      -- Delete tester:
      Free_Tester (Self.Tester);
   end Tear_Down_Test;

   -------------------------------------------------------------------------
   -- Tests:
   -------------------------------------------------------------------------

   overriding procedure Test_Protected_Call (Self : in out Instance) is
      T : Component_Tester_Package.Instance_Access renames Self.Tester;
   begin
      -- Call the connector:
      T.T_Send (((1, 2), 3));

      -- Expect tick to be passed through:
      Natural_Assert.Eq (T.T_Recv_Sync_History.Get_Count, 1);
      Tick_Assert.Eq (T.T_Recv_Sync_History.Get (1), ((1, 2), 3));

      -- Call the connector:
      T.T_Send (((4, 5), 6));

      -- Expect tick to be passed through:
      Natural_Assert.Eq (T.T_Recv_Sync_History.Get_Count, 2);
      Tick_Assert.Eq (T.T_Recv_Sync_History.Get (2), ((4, 5), 6));

      -- Call the connector:
      T.T_Send (((7, 8), 9));

      -- Expect tick to be passed through:
      Natural_Assert.Eq (T.T_Recv_Sync_History.Get_Count, 3);
      Tick_Assert.Eq (T.T_Recv_Sync_History.Get (3), ((7, 8), 9));
   end Test_Protected_Call;

   overriding procedure Test_Concurrent_Protection (Self : in out Instance) is
      T : Component_Tester_Package.Instance_Access renames Self.Tester;
      Task_Count : constant := 10;
      Calls_Per_Task : constant := 50;

      task type Caller_Task is
         entry Start (Id : in Natural);
      end Caller_Task;

      task body Caller_Task is
         My_Id : Natural;
      begin
         accept Start (Id : in Natural) do
            My_Id := Id;
         end Start;
         for I in 1 .. Calls_Per_Task loop
            T.T_Send (((My_Id, I), My_Id + I));
         end loop;
      end Caller_Task;

      Tasks : array (1 .. Task_Count) of Caller_Task;
   begin
      -- Start all tasks to create contention on the protected connector:
      for I in Tasks'Range loop
         Tasks (I).Start (I);
      end loop;
      -- Block exit waits for all tasks to complete.

      -- Verify all calls were received (none lost due to concurrency):
      Natural_Assert.Eq (T.T_Recv_Sync_History.Get_Count, Task_Count * Calls_Per_Task);
   end Test_Concurrent_Protection;

end Connector_Protector_Tests.Implementation;

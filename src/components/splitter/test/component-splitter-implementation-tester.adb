--------------------------------------------------------------------------------
-- Splitter Component Tester Body
--------------------------------------------------------------------------------

package body Component.Splitter.Implementation.Tester is

   ---------------------------------------
   -- Initialize component heap variables:
   ---------------------------------------
   procedure Init_Base (Self : in out Instance) is
   begin
      -- Initialize the component base class:
      Self.Component_Instance.Init_Base;
   end Init_Base;

   procedure Final_Base (Self : in out Instance) is
   begin
      -- Finalize the component base class:
      Self.Component_Instance.Final_Base;
   end Final_Base;

   ---------------------------------------
   -- Test initialization functions:
   ---------------------------------------
   procedure Connect (Self : in out Instance) is
   begin
      -- Connect the component under test to the tester:
      Self.Component_Instance.Attach_T_Send_T_Recv_Sync (Self'Unchecked_Access);
      Self.Attach_T_Send_T_Recv_Sync (Self.Component_Instance'Unchecked_Access);
   end Connect;

   procedure Disconnect_T_Recv_Sync (Self : in out Instance; Index : in Positive) is
   begin
      Self.Component_Instance.Disconnect_T_Send (Index);
   end Disconnect_T_Recv_Sync;

   ---------------------------------------
   -- Invokee connector primitives:
   ---------------------------------------
   overriding procedure T_Recv_Sync (Self : in out Instance; Arg : in T) is
   begin
      -- Push the argument onto the test history for verification:
      Self.T_Recv_Sync_History.Push (Arg);
   end T_Recv_Sync;

end Component.Splitter.Implementation.Tester;

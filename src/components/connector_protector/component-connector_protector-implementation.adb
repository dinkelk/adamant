--------------------------------------------------------------------------------
-- Connector_Protector Component Implementation Body
--------------------------------------------------------------------------------

package body Component.Connector_Protector.Implementation is

   protected body Protected_Connector is

      procedure Call (Inst : in out Instance; Arg : in T) is
      begin
         -- Guard against reentrant calls which would be a bounded error
         -- (ARM 9.5.1) resulting in deadlock or Program_Error:
         pragma Assert (not In_Call, "Reentrant call to Connector_Protector detected");
         In_Call := True;
         -- Simply call the connector from within the protected
         -- procedure.
         Inst.T_Send (Arg);
         In_Call := False;
      end Call;

   end Protected_Connector;

   ---------------------------------------
   -- Invokee connector primitives:
   ---------------------------------------
   -- The generic invokee connector.
   overriding procedure T_Recv_Sync (Self : in out Instance; Arg : in T) is
   begin
      -- Call protected connector procedure:
      Self.P_Connector.Call (Self, Arg);
   end T_Recv_Sync;

end Component.Connector_Protector.Implementation;

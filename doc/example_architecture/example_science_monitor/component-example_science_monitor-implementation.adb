--------------------------------------------------------------------------------
-- Example_Science_Monitor Component Implementation Body
--------------------------------------------------------------------------------

package body Component.Example_Science_Monitor.Implementation is

   ---------------------------------------
   -- Invokee connector primitives:
   ---------------------------------------
   -- This connector provides the schedule tick for the component.
   overriding procedure Tick_T_Recv_Sync (Self : in out Instance; Arg : in Tick.T) is
      ignore : Tick.T renames Arg;
   begin
      null;
   end Tick_T_Recv_Sync;

   -----------------------------------------------
   -- Data dependency handlers:
   -----------------------------------------------
   -- Invalid data dependency handler:
   overriding procedure Invalid_Data_Dependency (Self : in out Instance; Id : in Data_Product_Types.Data_Product_Id; Ret : in Data_Product_Return.T) is
   begin
      null;
   end Invalid_Data_Dependency;

end Component.Example_Science_Monitor.Implementation;

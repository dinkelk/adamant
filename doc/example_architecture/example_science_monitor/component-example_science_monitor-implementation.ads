--------------------------------------------------------------------------------
-- Example_Science_Monitor Component Implementation Spec
--------------------------------------------------------------------------------

-- Includes:
with Tick;

-- This component monitors sensor data, sharing a data dependency with the science
-- component to exercise the data dependency ID collision case.
package Component.Example_Science_Monitor.Implementation is

   -- The component class instance record:
   type Instance is new Example_Science_Monitor.Base_Instance with private;

private

   -- The component class instance record:
   type Instance is new Example_Science_Monitor.Base_Instance with record
      null;
   end record;

   ---------------------------------------
   -- Set Up Procedure
   ---------------------------------------
   overriding procedure Set_Up (Self : in out Instance) is null;

   ---------------------------------------
   -- Invokee connector primitives:
   ---------------------------------------
   -- This connector provides the schedule tick for the component.
   overriding procedure Tick_T_Recv_Sync (Self : in out Instance; Arg : in Tick.T);

   -----------------------------------------------
   -- Data dependency primitives:
   -----------------------------------------------
   -- Function which retrieves a data dependency.
   overriding function Get_Data_Dependency (Self : in out Instance; Id : in Data_Product_Types.Data_Product_Id) return Data_Product_Return.T is (Self.Data_Product_Fetch_T_Request ((Id => Id)));

   -- Invalid data dependency handler:
   overriding procedure Invalid_Data_Dependency (Self : in out Instance; Id : in Data_Product_Types.Data_Product_Id; Ret : in Data_Product_Return.T);

end Component.Example_Science_Monitor.Implementation;

--------------------------------------------------------------------------------
-- Parameter_Table_Router Component Implementation Spec
--------------------------------------------------------------------------------

-- Includes:
with Ccsds_Space_Packet;
with Ccsds_Primary_Header;
with Command;
with Tick;
with Parameters_Memory_Region_Release;
with Protected_Variables;
with Task_Synchronization;
with Binary_Tree;
with Parameter_Table_Buffer;
with Parameter_Table_Router_Types;

package Component.Parameter_Table_Router.Implementation is

   -- The component class instance record:
   type Instance is new Parameter_Table_Router.Base_Instance with private;

   overriding procedure Init (Self : in out Instance; Table : in Parameter_Table_Router_Types.Router_Table; Ticks_Until_Timeout : in Natural; Warn_Unexpected_Sequence_Counts : in Boolean := False; Buffer_Size : in Positive; Load_All_Parameter_Tables_On_Set_Up : in Boolean := False);
   not overriding procedure Final (Self : in out Instance);

private
   use Parameter_Table_Router_Types;

   -- Protected variable for downstream response:
   package Protected_Parameters_Memory_Region_Release is
      new Protected_Variables.Generic_Variable (Parameters_Memory_Region_Release.T);

   -- Internal router table entry for binary tree:
   type Internal_Router_Table_Entry is record
      Table_Entry : Router_Table_Entry;
   end record;

   function Less_Than (Left, Right : Internal_Router_Table_Entry) return Boolean with
      Inline => True;
   function Greater_Than (Left, Right : Internal_Router_Table_Entry) return Boolean with
      Inline => True;
   package Router_Table_B_Tree is new Binary_Tree (Internal_Router_Table_Entry, Less_Than, Greater_Than);

   -- The component class instance record:
   type Instance is new Parameter_Table_Router.Base_Instance with record
      -- Routing table:
      Table : Router_Table_B_Tree.Instance;
      -- Staging buffer:
      Staging_Buffer : Parameter_Table_Buffer.Instance;
      -- Synchronization for downstream responses:
      Response : Protected_Parameters_Memory_Region_Release.Variable;
      Sync_Object : Task_Synchronization.Wait_Release_Timeout_Counter_Object;
      -- Configuration:
      Warn_Unexpected_Sequence_Counts : Boolean := False;
      Load_All_On_Set_Up : Boolean := False;
      -- Sequence count tracking:
      Last_Sequence_Count : Ccsds_Primary_Header.Ccsds_Sequence_Count_Type := Ccsds_Primary_Header.Ccsds_Sequence_Count_Type'Last;
      -- Overflow tracking:
      Buffer_Overflowed : Boolean := False;
      -- Data product counters:
      Packet_Count : Natural := 0;
      Reject_Count : Natural := 0;
      Table_Count : Natural := 0;
      Invalid_Count : Natural := 0;
   end record;

   -- Set_Up override:
   overriding procedure Set_Up (Self : in out Instance);

   -- Invokee connector handlers:
   overriding procedure Ccsds_Space_Packet_T_Recv_Async (Self : in out Instance; Arg : in Ccsds_Space_Packet.T);
   overriding procedure Ccsds_Space_Packet_T_Recv_Async_Dropped (Self : in out Instance; Arg : in Ccsds_Space_Packet.T);
   overriding procedure Command_T_Recv_Async (Self : in out Instance; Arg : in Command.T);
   overriding procedure Command_T_Recv_Async_Dropped (Self : in out Instance; Arg : in Command.T);
   overriding procedure Timeout_Tick_Recv_Sync (Self : in out Instance; Arg : in Tick.T);
   overriding procedure Parameters_Memory_Region_Release_T_Recv_Sync (Self : in out Instance; Arg : in Parameters_Memory_Region_Release.T);

   -- Invoker connector dropped handlers:
   overriding procedure Parameters_Memory_Region_T_Send_Dropped (Self : in out Instance; Index : in Parameters_Memory_Region_T_Send_Index; Arg : in Parameters_Memory_Region.T) is null;
   overriding procedure Command_Response_T_Send_Dropped (Self : in out Instance; Arg : in Command_Response.T) is null;
   overriding procedure Event_T_Send_Dropped (Self : in out Instance; Arg : in Event.T) is null;
   overriding procedure Data_Product_T_Send_Dropped (Self : in out Instance; Arg : in Data_Product.T) is null;

   -- Command handlers:
   overriding function Load_Parameter_Table (Self : in out Instance; Arg : in Parameter_Table_Id.T) return Command_Execution_Status.E;
   overriding function Load_All_Parameter_Tables (Self : in out Instance) return Command_Execution_Status.E;
   overriding procedure Invalid_Command (Self : in out Instance; Cmd : in Command.T; Errant_Field_Number : in Unsigned_32; Errant_Field : in Basic_Types.Poly_Type);

end Component.Parameter_Table_Router.Implementation;

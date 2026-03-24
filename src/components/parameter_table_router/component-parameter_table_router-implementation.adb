--------------------------------------------------------------------------------
-- Parameter_Table_Router Component Implementation Body
--------------------------------------------------------------------------------

with Parameter_Enums;
with Parameter_Types; use Parameter_Types;
with Ccsds_Enums;
with Ccsds_Primary_Header; use Ccsds_Primary_Header;

package body Component.Parameter_Table_Router.Implementation is

   use Parameter_Enums.Parameter_Table_Update_Status;

   -- Comparison operators for binary tree:
   function Less_Than (Left, Right : Router_Table_Entry) return Boolean is
   begin
      return Left.Table_Id < Right.Table_Id;
   end Less_Than;

   function Greater_Than (Left, Right : Router_Table_Entry) return Boolean is
   begin
      return Left.Table_Id > Right.Table_Id;
   end Greater_Than;

   -- No standalone helper needed — counter increments are simple inline statements.

   ---------------------------------------
   -- Helper: Send region to a destination and wait for response.
   -- Returns True on success, False on timeout or failure.
   -- The response is available via Self.Response.Get_Var after this call.
   ---------------------------------------
   function Send_And_Wait (Self : in out Instance; Index : in Connector_Types.Connector_Index_Type; Region : in Parameters_Memory_Region.T) return Boolean is
      Wait_Timed_Out : Boolean;
   begin
      Self.Sync_Object.Reset;
      Self.Parameters_Memory_Region_T_Send_If_Connected (Index, Region);
      Self.Sync_Object.Wait (Wait_Timed_Out);

      if Wait_Timed_Out then
         return False;
      end if;

      return Self.Response.Get_Var.Status = Success;
   end Send_And_Wait;

   ---------------------------------------
   -- Helper: Send Set to all destinations for a table entry.
   -- Sends to non-Load_From destinations first (in order), then Load_From last.
   -- Returns True if all succeeded, emits events on failure.
   ---------------------------------------
   function Send_Table_To_Destinations (Self : in out Instance; Table_Ent : in Router_Table_Entry; Region : in Parameters_Memory_Region.T) return Boolean is
      The_Time : constant Sys_Time.T := Self.Sys_Time_T_Get;
      Id_Param : constant Parameter_Table_Id.T := (Id => Table_Ent.Table_Id);
      Load_From_Index : Connector_Types.Connector_Index_Type := Connector_Types.Connector_Index_Type'First;
      Has_Load_From : Boolean := False;
   begin
      -- First pass: send to non-Load_From destinations in order:
      for I in Table_Ent.Destinations'Range loop
         if Table_Ent.Destinations (I).Load_From then
            Load_From_Index := Table_Ent.Destinations (I).Connector_Index;
            Has_Load_From := True;
         else
            if not Self.Send_And_Wait (Table_Ent.Destinations (I).Connector_Index, Region) then
               -- Determine if this was a timeout or downstream failure:
               declare
                  Release : constant Parameters_Memory_Region_Release.T := Self.Response.Get_Var;
               begin
                  case Release.Status is
                     when Success =>
                        -- Must have been a timeout:
                        Self.Event_T_Send_If_Connected (Self.Events.Table_Update_Timeout (The_Time, Id_Param));
                     when others =>
                        Self.Event_T_Send_If_Connected (Self.Events.Table_Update_Failure (The_Time, Release));
                  end case;
               end;
               return False;
            end if;
         end if;
      end loop;

      -- Second pass: send to Load_From destination last so we don't persist an
      -- invalid table if validation fails at another destination:
      if Has_Load_From then
         if not Self.Send_And_Wait (Load_From_Index, Region) then
            declare
               Release : constant Parameters_Memory_Region_Release.T := Self.Response.Get_Var;
            begin
               case Release.Status is
                  when Success =>
                     Self.Event_T_Send_If_Connected (Self.Events.Table_Update_Timeout (The_Time, Id_Param));
                  when others =>
                     Self.Event_T_Send_If_Connected (Self.Events.Table_Update_Failure (The_Time, Release));
               end case;
            end;
            return False;
         end if;
      end if;

      return True;
   end Send_Table_To_Destinations;

   ---------------------------------------
   -- Helper: Load a single table by ID from its Load_From source.
   -- Returns True on success, False on failure or if no Load_From exists.
   ---------------------------------------
   function Load_Single_Table (Self : in out Instance; Table_Id : in Parameter_Types.Parameter_Table_Id) return Boolean is
      The_Time : constant Sys_Time.T := Self.Sys_Time_T_Get;
      Id_Param : constant Parameter_Table_Id.T := (Id => Table_Id);
      Search_Key : constant Router_Table_Entry := (Table_Id => Table_Id, Destinations => null);
      Found : Router_Table_Entry;
      Found_Index : Positive;
   begin
      -- Look up table ID:
      if not Self.Table.Search (Search_Key, Found, Found_Index) then
         Self.Event_T_Send_If_Connected (Self.Events.Unrecognized_Table_Id (The_Time, Id_Param));
         return False;
      end if;

      -- Find the Load_From destination:
      declare
         Load_From_Idx : Connector_Types.Connector_Index_Type := Connector_Types.Connector_Index_Type'First;
         Has_Load_From : Boolean := False;
      begin
         for I in Found.Destinations'Range loop
            if Found.Destinations (I).Load_From then
               Load_From_Idx := Found.Destinations (I).Connector_Index;
               Has_Load_From := True;
               exit;
            end if;
         end loop;

         -- Silently skip tables without a Load_From source:
         if not Has_Load_From then
            return True;
         end if;

         -- Send Get to Load_From destination to retrieve the table.
         -- We provide our staging buffer as the memory region to be filled:
         declare
            Get_Region : constant Parameters_Memory_Region.T := (
               Region => Self.Staging_Buffer.Get_Table_Region,
               Operation => Parameter_Enums.Parameter_Table_Operation_Type.Get
            );
         begin
            if not Self.Send_And_Wait (Load_From_Idx, Get_Region) then
               declare
                  Release : constant Parameters_Memory_Region_Release.T := Self.Response.Get_Var;
               begin
                  case Release.Status is
                     when Success =>
                        Self.Event_T_Send_If_Connected (Self.Events.Table_Update_Timeout (The_Time, Id_Param));
                     when others =>
                        Self.Event_T_Send_If_Connected (Self.Events.Table_Load_Failure (The_Time, Release));
                  end case;
               end;
               return False;
            end if;
         end;

         -- The Load_From destination populated the region. The response contains
         -- the actual data length. Forward this to non-Load_From destinations:
         declare
            Release : constant Parameters_Memory_Region_Release.T := Self.Response.Get_Var;
            Set_Region : constant Parameters_Memory_Region.T := (
               Region => Release.Region,
               Operation => Parameter_Enums.Parameter_Table_Operation_Type.Set
            );
         begin
            for I in Found.Destinations'Range loop
               if not Found.Destinations (I).Load_From then
                  if not Self.Send_And_Wait (Found.Destinations (I).Connector_Index, Set_Region) then
                     declare
                        Fail_Release : constant Parameters_Memory_Region_Release.T := Self.Response.Get_Var;
                     begin
                        case Fail_Release.Status is
                           when Success =>
                              Self.Event_T_Send_If_Connected (Self.Events.Table_Update_Timeout (The_Time, Id_Param));
                           when others =>
                              Self.Event_T_Send_If_Connected (Self.Events.Table_Update_Failure (The_Time, Fail_Release));
                        end case;
                     end;
                     return False;
                  end if;
               end if;
            end loop;
         end;

         Self.Event_T_Send_If_Connected (Self.Events.Table_Loaded (The_Time, Id_Param));
         return True;
      end;
   end Load_Single_Table;

   --------------------------------------------------
   -- Subprogram for implementation init method:
   --------------------------------------------------
   -- Initialization parameters for the Parameter Table Router.
   --
   -- Init Parameters:
   -- Table : Parameter_Table_Router_Types.Router_Table - The routing table mapping
   -- parameter table IDs to destination connector indexes. Typically produced by the
   -- generator.
   -- Buffer_Size : Positive - The size in bytes of the internal staging buffer for
   -- reassembling segmented CCSDS packets.
   -- Ticks_Until_Timeout : Natural - The number of timeout ticks to wait for a
   -- response from a downstream component before declaring a timeout.
   -- Warn_Unexpected_Sequence_Counts : Boolean - If True, an event is produced when
   -- a CCSDS packet is received with an unexpected (non-incrementing) sequence
   -- count.
   -- Load_All_Parameter_Tables_On_Set_Up : Boolean - If True, all parameter tables
   -- that have a load_from source will be loaded from persistent storage during
   -- Set_Up.
   --
   overriding procedure Init (Self : in out Instance; Table : in Parameter_Table_Router_Types.Router_Table; Buffer_Size : in Positive; Ticks_Until_Timeout : in Natural; Warn_Unexpected_Sequence_Counts : in Boolean := False; Load_All_Parameter_Tables_On_Set_Up : in Boolean := False) is
   begin
      -- Set timeout limit:
      Self.Sync_Object.Set_Timeout_Limit (Ticks_Until_Timeout);

      -- Store configuration:
      Self.Warn_Unexpected_Sequence_Counts := Warn_Unexpected_Sequence_Counts;
      Self.Load_All_On_Set_Up := Load_All_Parameter_Tables_On_Set_Up;

      -- Create staging buffer:
      Self.Staging_Buffer.Create (Buffer_Size);

      -- Initialize binary tree and populate from table:
      Self.Table.Init (Table'Length);
      for Table_Ent of Table loop
         -- Destinations must not be null:
         pragma Assert (Table_Ent.Destinations /= null);

         -- Validate: at most one Load_From per entry:
         declare
            Load_From_Count : Natural := 0;
         begin
            for Dest of Table_Ent.Destinations.all loop
               if Dest.Load_From then
                  Load_From_Count := @ + 1;
               end if;
               -- Make sure destination connector index is in range:
               pragma Assert (
                  Dest.Connector_Index >= Self.Connector_Parameters_Memory_Region_T_Send'First
                  and then Dest.Connector_Index <= Self.Connector_Parameters_Memory_Region_T_Send'Last
               );
            end loop;
            -- At most one Load_From per entry:
            pragma Assert (Load_From_Count <= 1);
         end;

         -- Make sure the table ID is not already in the tree:
         declare
            Ignore_1 : Router_Table_Entry;
            Ignore_2 : Natural;
            Ret : Boolean;
         begin
            Ret := Self.Table.Search (Table_Ent, Ignore_1, Ignore_2);
            -- Duplicate table IDs are not allowed:
            pragma Assert (not Ret);
            -- Add entry to the table:
            Ret := Self.Table.Add (Table_Ent);
            -- Tree should have enough capacity since we initialized with Table'Length:
            pragma Assert (Ret);
         end;
      end loop;
   end Init;

   not overriding procedure Final (Self : in out Instance) is
   begin
      Self.Table.Destroy;
      Self.Staging_Buffer.Destroy;
   end Final;

   ---------------------------------------
   -- Set Up Procedure
   ---------------------------------------
   overriding procedure Set_Up (Self : in out Instance) is
      The_Time : constant Sys_Time.T := Self.Sys_Time_T_Get;
   begin
      -- Publish initial data product values:
      Self.Data_Product_T_Send_If_Connected (Self.Data_Products.Num_Packets_Received (The_Time, (Value => Self.Packet_Count)));
      Self.Data_Product_T_Send_If_Connected (Self.Data_Products.Num_Packets_Rejected (The_Time, (Value => Self.Reject_Count)));
      Self.Data_Product_T_Send_If_Connected (Self.Data_Products.Num_Tables_Received (The_Time, (Value => Self.Table_Count)));
      Self.Data_Product_T_Send_If_Connected (Self.Data_Products.Num_Tables_Invalid (The_Time, (Value => Self.Invalid_Count)));

      -- Load all parameter tables if configured:
      if Self.Load_All_On_Set_Up then
         for I in Self.Table.Get_First_Index .. Self.Table.Get_Last_Index loop
            declare
               Tbl_Entry : constant Router_Table_Entry := Self.Table.Get (I);
               Has_Load_From : Boolean := False;
            begin
               -- Check if this entry has a Load_From destination:
               for Dest of Tbl_Entry.Destinations.all loop
                  if Dest.Load_From then
                     Has_Load_From := True;
                     exit;
                  end if;
               end loop;

               if Has_Load_From then
                  -- Load this table; failures are reported via events:
                  declare
                     Ignore_Result : constant Boolean := Self.Load_Single_Table (Tbl_Entry.Table_Id);
                  begin
                     null;
                  end;
               end if;
            end;
         end loop;
      end if;
   end Set_Up;

   ---------------------------------------
   -- Invokee connector primitives:
   ---------------------------------------
   -- Receives segmented CCSDS packets containing parameter table data.
   overriding procedure Ccsds_Space_Packet_T_Recv_Async (Self : in out Instance; Arg : in Ccsds_Space_Packet.T) is
      use Ccsds_Enums.Ccsds_Sequence_Flag;
      use Parameter_Table_Buffer;
      -- Note: CCSDS Packet_Length field value is one less than the actual data
      -- length per the CCSDS standard, hence the seemingly missing "-1" in the
      -- slice below.
      Data : Basic_Types.Byte_Array renames Arg.Data (Arg.Data'First .. Arg.Data'First + Natural (Arg.Header.Packet_Length));
      Seq_Flag : Ccsds_Enums.Ccsds_Sequence_Flag.E renames Arg.Header.Sequence_Flag;
      Status : Append_Status;
   begin
      -- Increment packet counter:
      Self.Packet_Count := @ + 1;

      -- Check sequence count if enabled:
      if Self.Warn_Unexpected_Sequence_Counts then
         declare
            Expected : constant Ccsds_Sequence_Count_Type := Self.Last_Sequence_Count + 1;
         begin
            if Self.Last_Sequence_Count /= Ccsds_Sequence_Count_Type'Last
               and then Arg.Header.Sequence_Count /= Expected
            then
               Self.Event_T_Send_If_Connected (Self.Events.Unexpected_Sequence_Count_Detected (Self.Sys_Time_T_Get, (
                  Ccsds_Header => Arg.Header,
                  Received_Sequence_Count => Interfaces.Unsigned_16 (Arg.Header.Sequence_Count),
                  Expected_Sequence_Count => Interfaces.Unsigned_16 (Expected)
               )));
            end if;
         end;
         Self.Last_Sequence_Count := Arg.Header.Sequence_Count;
      end if;

      -- Append to staging buffer:
      Status := Self.Staging_Buffer.Append (Data => Data, Sequence_Flag => Seq_Flag);

      case Status is
         when Packet_Ignored =>
            Self.Reject_Count := @ + 1;
            Self.Event_T_Send_If_Connected (Self.Events.Packet_Ignored (Self.Sys_Time_T_Get, Arg.Header));

         when Too_Small_Table =>
            Self.Reject_Count := @ + 1;
            Self.Event_T_Send_If_Connected (Self.Events.Too_Small_Table (Self.Sys_Time_T_Get, Arg.Header));

         when New_Table =>
            -- Emit event with table ID. The ID will be validated against the
            -- routing table when the complete table arrives:
            Self.Event_T_Send_If_Connected (Self.Events.Receiving_New_Table (
               Self.Sys_Time_T_Get, (Id => Self.Staging_Buffer.Get_Table_Id)
            ));

         when Buffering_Table =>
            null;

         when Complete_Table =>
            Self.Table_Count := @ + 1;
            declare
               The_Time : constant Sys_Time.T := Self.Sys_Time_T_Get;
               Tid : constant Parameter_Table_Id.T := (Id => Self.Staging_Buffer.Get_Table_Id);
               Search_Key : constant Router_Table_Entry := (Table_Id => Tid.Id, Destinations => null);
               Found : Router_Table_Entry;
               Found_Index : Positive;
            begin
               Self.Event_T_Send_If_Connected (Self.Events.Table_Received (The_Time, Tid));

               if not Self.Table.Search (Search_Key, Found, Found_Index) then
                  Self.Event_T_Send_If_Connected (Self.Events.Unrecognized_Table_Id (The_Time, Tid));
               else
                  -- Build set region and send to destinations:
                  declare
                     Set_Region : constant Parameters_Memory_Region.T := (
                        Region => Self.Staging_Buffer.Get_Table_Region,
                        Operation => Parameter_Enums.Parameter_Table_Operation_Type.Set
                     );
                  begin
                     if Send_Table_To_Destinations (Self, Found, Set_Region) then
                        Self.Event_T_Send_If_Connected (Self.Events.Table_Updated (The_Time, Tid));
                     else
                        Self.Invalid_Count := @ + 1;
                     end if;
                  end;

                  -- Update last table received data product:
                  Self.Data_Product_T_Send_If_Connected (Self.Data_Products.Last_Table_Received (The_Time, (
                     Table_Id => Tid.Id,
                     Table_Length => Interfaces.Unsigned_32 (Self.Staging_Buffer.Get_Table_Length),
                     Timestamp => The_Time
                  )));
               end if;
            end;

         when Buffer_Overflow =>
            Self.Reject_Count := @ + 1;
            Self.Event_T_Send_If_Connected (Self.Events.Staging_Buffer_Overflow (Self.Sys_Time_T_Get, Arg.Header));
      end case;

      -- Update data products at end of handler:
      declare
         The_Time : constant Sys_Time.T := Self.Sys_Time_T_Get;
      begin
         Self.Data_Product_T_Send_If_Connected (Self.Data_Products.Num_Packets_Received (The_Time, (Value => Self.Packet_Count)));
         Self.Data_Product_T_Send_If_Connected (Self.Data_Products.Num_Packets_Rejected (The_Time, (Value => Self.Reject_Count)));
         Self.Data_Product_T_Send_If_Connected (Self.Data_Products.Num_Tables_Received (The_Time, (Value => Self.Table_Count)));
         Self.Data_Product_T_Send_If_Connected (Self.Data_Products.Num_Tables_Invalid (The_Time, (Value => Self.Invalid_Count)));
      end;
   end Ccsds_Space_Packet_T_Recv_Async;

   -- This procedure is called when a Ccsds_Space_Packet_T_Recv_Async message is dropped due to a full queue.
   overriding procedure Ccsds_Space_Packet_T_Recv_Async_Dropped (Self : in out Instance; Arg : in Ccsds_Space_Packet.T) is
   begin
      Self.Event_T_Send_If_Connected (Self.Events.Packet_Dropped (Self.Sys_Time_T_Get, Arg.Header));
   end Ccsds_Space_Packet_T_Recv_Async_Dropped;

   -- The command receive connector.
   overriding procedure Command_T_Recv_Async (Self : in out Instance; Arg : in Command.T) is
      -- Execute the command:
      Stat : constant Command_Response_Status.E := Self.Execute_Command (Arg);
   begin
      -- Send the return status:
      Self.Command_Response_T_Send_If_Connected ((Source_Id => Arg.Header.Source_Id, Registration_Id => Self.Command_Reg_Id, Command_Id => Arg.Header.Id, Status => Stat));
   end Command_T_Recv_Async;

   -- This procedure is called when a Command_T_Recv_Async message is dropped due to a full queue.
   overriding procedure Command_T_Recv_Async_Dropped (Self : in out Instance; Arg : in Command.T) is
   begin
      Self.Event_T_Send_If_Connected (Self.Events.Command_Dropped (Self.Sys_Time_T_Get, Arg.Header));
   end Command_T_Recv_Async_Dropped;

   -- Periodic tick used for timeout counting when waiting for downstream responses.
   overriding procedure Timeout_Tick_Recv_Sync (Self : in out Instance; Arg : in Tick.T) is
      Ignore : Tick.T renames Arg;
   begin
      -- Increment the timeout counter. This will only cause a timeout if the
      -- sync object is currently waiting and the counter exceeds the limit:
      Self.Sync_Object.Increment_Timeout_If_Waiting;
   end Timeout_Tick_Recv_Sync;

   -- Synchronous response from downstream components after a Set or Get operation.
   overriding procedure Parameters_Memory_Region_Release_T_Recv_Sync (Self : in out Instance; Arg : in Parameters_Memory_Region_Release.T) is
   begin
      -- Store the response from the downstream component. Error handling based
      -- on the contents of this response is done by this component's task
      -- (executing the command or table update):
      Self.Response.Set_Var (Arg);

      -- Signal to the component that a response has been received:
      Self.Sync_Object.Release;

      -- Note: There is a possible race condition where we store the response
      -- and then release the sync object, but before the waiting task reads
      -- the data, another response could arrive and overwrite it. This should
      -- never occur in practice since downstream components should not send
      -- unprovoked responses. The protected buffer and sync object prevent
      -- data corruption; only ordering could be affected if the assembly is
      -- designed incorrectly.
   end Parameters_Memory_Region_Release_T_Recv_Sync;

   -----------------------------------------------
   -- Command handler primitives:
   -----------------------------------------------
   -- Description:
   --    Commands for the Parameter Table Router component.
   -- Load a single parameter table from its load_from source and distribute to other
   -- destinations.
   overriding function Load_Parameter_Table (Self : in out Instance; Arg : in Parameter_Table_Id.T) return Command_Execution_Status.E is
      use Command_Execution_Status;
   begin
      if Self.Load_Single_Table (Arg.Id) then
         return Success;
      else
         return Failure;
      end if;
   end Load_Parameter_Table;

   -- Load all parameter tables that have a load_from source configured and
   -- distribute to their destinations.
   overriding function Load_All_Parameter_Tables (Self : in out Instance) return Command_Execution_Status.E is
      use Command_Execution_Status;
   begin
      for I in Self.Table.Get_First_Index .. Self.Table.Get_Last_Index loop
         declare
            Tbl_Entry : constant Router_Table_Entry := Self.Table.Get (I);
            Has_Load_From : Boolean := False;
         begin
            for Dest of Tbl_Entry.Destinations.all loop
               if Dest.Load_From then
                  Has_Load_From := True;
                  exit;
               end if;
            end loop;

            if Has_Load_From then
               declare
                  Ignore_Result : constant Boolean := Self.Load_Single_Table (Tbl_Entry.Table_Id);
               begin
                  null;
               end;
            end if;
         end;
      end loop;
      return Success;
   end Load_All_Parameter_Tables;

   -- Invalid command handler. This procedure is called when a command's arguments are found to be invalid:
   overriding procedure Invalid_Command (Self : in out Instance; Cmd : in Command.T; Errant_Field_Number : in Unsigned_32; Errant_Field : in Basic_Types.Poly_Type) is
   begin
      Self.Event_T_Send_If_Connected (Self.Events.Invalid_Command_Received (
         Self.Sys_Time_T_Get,
         (Id => Cmd.Header.Id, Errant_Field_Number => Errant_Field_Number, Errant_Field => Errant_Field)
      ));
   end Invalid_Command;

end Component.Parameter_Table_Router.Implementation;

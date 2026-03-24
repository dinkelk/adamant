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
   function Less_Than (Left, Right : Internal_Router_Table_Entry) return Boolean is
   begin
      return Left.Table_Entry.Table_Id < Right.Table_Entry.Table_Id;
   end Less_Than;

   function Greater_Than (Left, Right : Internal_Router_Table_Entry) return Boolean is
   begin
      return Left.Table_Entry.Table_Id > Right.Table_Entry.Table_Id;
   end Greater_Than;

   ---------------------------------------
   -- Helper: Send region to a destination and wait for response.
   -- Returns True on success, False on timeout or failure.
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

      declare
         Release : constant Parameters_Memory_Region_Release.T := Self.Response.Get_Var;
      begin
         return Release.Status = Parameter_Enums.Parameter_Table_Update_Status.Success;
      end;
   end Send_And_Wait;

   ---------------------------------------
   -- Helper: Send Set to all destinations for a table entry.
   -- Sends to non-Load_From destinations first (in order), then Load_From last.
   -- Returns True if all succeeded.
   ---------------------------------------
   function Send_Table_To_Destinations (Self : in out Instance; Table_Entry : in Router_Table_Entry; Region : in Parameters_Memory_Region.T) return Boolean is
      The_Time : constant Sys_Time.T := Self.Sys_Time_T_Get;
      Table_Id_Param : constant Parameter_Table_Id.T := (Id => Table_Entry.Table_Id);
      Load_From_Index : Connector_Types.Connector_Index_Type := Connector_Types.Connector_Index_Type'First;
      Has_Load_From : Boolean := False;
   begin
      -- First pass: send to non-Load_From destinations in order:
      for I in Table_Entry.Destinations'Range loop
         if Table_Entry.Destinations (I).Load_From then
            Load_From_Index := Table_Entry.Destinations (I).Connector_Index;
            Has_Load_From := True;
         else
            if not Self.Send_And_Wait (Table_Entry.Destinations (I).Connector_Index, Region) then
               -- Check if it was a timeout or failure:
               declare
                  Release : constant Parameters_Memory_Region_Release.T := Self.Response.Get_Var;
               begin
                  if Release.Status = Parameter_Enums.Parameter_Table_Update_Status.Success then
                     -- Must have been a timeout:
                     Self.Event_T_Send_If_Connected (Self.Events.Table_Update_Timeout (The_Time, Table_Id_Param));
                  else
                     Self.Event_T_Send_If_Connected (Self.Events.Table_Update_Failure (The_Time, Release));
                  end if;
               end;
               return False;
            end if;
         end if;
      end loop;

      -- Second pass: send to Load_From destination last:
      if Has_Load_From then
         if not Self.Send_And_Wait (Load_From_Index, Region) then
            declare
               Release : constant Parameters_Memory_Region_Release.T := Self.Response.Get_Var;
            begin
               if Release.Status = Parameter_Enums.Parameter_Table_Update_Status.Success then
                  Self.Event_T_Send_If_Connected (Self.Events.Table_Update_Timeout (The_Time, Table_Id_Param));
               else
                  Self.Event_T_Send_If_Connected (Self.Events.Table_Update_Failure (The_Time, Release));
               end if;
            end;
            return False;
         end if;
      end if;

      return True;
   end Send_Table_To_Destinations;

   ---------------------------------------
   -- Helper: Load a single table by ID. Returns True on success.
   ---------------------------------------
   function Load_Single_Table (Self : in out Instance; Table_Id : in Parameter_Types.Parameter_Table_Id) return Boolean is
      The_Time : constant Sys_Time.T := Self.Sys_Time_T_Get;
      Table_Id_Param : constant Parameter_Table_Id.T := (Id => Table_Id);
      Search_Entry : constant Internal_Router_Table_Entry := (Table_Entry => (Table_Id => Table_Id, Destinations => null));
      Found_Entry : Internal_Router_Table_Entry;
      Found_Index : Positive;
   begin
      -- Look up table ID:
      if not Self.Table.Search (Search_Entry, Found_Entry, Found_Index) then
         Self.Event_T_Send_If_Connected (Self.Events.Unrecognized_Table_Id (The_Time, Table_Id_Param));
         return False;
      end if;

      -- Find the Load_From destination:
      declare
         Tbl_Entry : Router_Table_Entry renames Found_Entry.Table_Entry;
         Load_From_Index : Connector_Types.Connector_Index_Type := Connector_Types.Connector_Index_Type'First;
         Has_Load_From : Boolean := False;
      begin
         for I in Tbl_Entry.Destinations'Range loop
            if Tbl_Entry.Destinations (I).Load_From then
               Load_From_Index := Tbl_Entry.Destinations (I).Connector_Index;
               Has_Load_From := True;
               exit;
            end if;
         end loop;

         if not Has_Load_From then
            Self.Event_T_Send_If_Connected (Self.Events.No_Load_Source (The_Time, Table_Id_Param));
            return False;
         end if;

         -- Send Get to Load_From destination to retrieve the table:
         declare
            Get_Region : constant Parameters_Memory_Region.T := (
               Region => Parameter_Table_Buffer.Get_Full_Buffer_Region (Self.Staging_Buffer),
               Operation => Parameter_Enums.Parameter_Table_Operation_Type.Get
            );
         begin
            if not Self.Send_And_Wait (Load_From_Index, Get_Region) then
               declare
                  Release : constant Parameters_Memory_Region_Release.T := Self.Response.Get_Var;
               begin
                  if Release.Status = Parameter_Enums.Parameter_Table_Update_Status.Success then
                     Self.Event_T_Send_If_Connected (Self.Events.Table_Update_Timeout (The_Time, Table_Id_Param));
                  else
                     Self.Event_T_Send_If_Connected (Self.Events.Table_Load_Failure (The_Time, Release));
                  end if;
               end;
               return False;
            end if;
         end;

         -- Get the actual data length from the response:
         declare
            Release : constant Parameters_Memory_Region_Release.T := Self.Response.Get_Var;
            Set_Region : constant Parameters_Memory_Region.T := (
               Region => Release.Region,
               Operation => Parameter_Enums.Parameter_Table_Operation_Type.Set
            );
         begin
            -- Send Set to each non-Load_From destination in order:
            for I in Tbl_Entry.Destinations'Range loop
               if not Tbl_Entry.Destinations (I).Load_From then
                  if not Self.Send_And_Wait (Tbl_Entry.Destinations (I).Connector_Index, Set_Region) then
                     declare
                        Fail_Release : constant Parameters_Memory_Region_Release.T := Self.Response.Get_Var;
                     begin
                        if Fail_Release.Status = Parameter_Enums.Parameter_Table_Update_Status.Success then
                           Self.Event_T_Send_If_Connected (Self.Events.Table_Update_Timeout (The_Time, Table_Id_Param));
                        else
                           Self.Event_T_Send_If_Connected (Self.Events.Table_Update_Failure (The_Time, Fail_Release));
                        end if;
                     end;
                     return False;
                  end if;
               end if;
            end loop;
         end;

         Self.Event_T_Send_If_Connected (Self.Events.Table_Loaded (The_Time, Table_Id_Param));
         return True;
      end;
   end Load_Single_Table;

   --------------------------------------------------
   -- Init:
   --------------------------------------------------
   overriding procedure Init (Self : in out Instance; Table : in Parameter_Table_Router_Types.Router_Table; Ticks_Until_Timeout : in Natural; Warn_Unexpected_Sequence_Counts : in Boolean := False; Buffer_Size : in Positive; Load_All_Parameter_Tables_On_Set_Up : in Boolean := False) is
      Add_Success : Boolean;
   begin
      -- Set timeout limit:
      Self.Sync_Object.Set_Timeout_Limit (Ticks_Until_Timeout);

      -- Store configuration:
      Self.Warn_Unexpected_Sequence_Counts := Warn_Unexpected_Sequence_Counts;
      Self.Load_All_On_Set_Up := Load_All_Parameter_Tables_On_Set_Up;

      -- Create staging buffer:
      Parameter_Table_Buffer.Create (Self.Staging_Buffer, Buffer_Size);

      -- Initialize binary tree and populate from table:
      Self.Table.Init (Table'Length);
      for I in Table'Range loop
         -- Validate: at most one Load_From per entry:
         declare
            Load_From_Count : Natural := 0;
         begin
            if Table (I).Destinations /= null then
               for J in Table (I).Destinations'Range loop
                  if Table (I).Destinations (J).Load_From then
                     Load_From_Count := Load_From_Count + 1;
                  end if;
               end loop;
            end if;
            pragma Assert (Load_From_Count <= 1, "At most one destination per table entry may have Load_From = True.");
         end;

         -- Add to tree:
         Add_Success := Self.Table.Add ((Table_Entry => Table (I)));
         pragma Assert (Add_Success, "Failed to add table entry. Possible duplicate Table_Id or tree full.");
      end loop;
   end Init;

   not overriding procedure Final (Self : in out Instance) is
   begin
      Self.Table.Destroy;
      Parameter_Table_Buffer.Destroy (Self.Staging_Buffer);
   end Final;

   --------------------------------------------------
   -- Set_Up:
   --------------------------------------------------
   overriding procedure Set_Up (Self : in out Instance) is
      The_Time : constant Sys_Time.T := Self.Sys_Time_T_Get;
   begin
      -- Publish initial data product values:
      Self.Data_Product_T_Send_If_Connected (Self.Data_Products.Num_Packets_Received (The_Time, (Value => 0)));
      Self.Data_Product_T_Send_If_Connected (Self.Data_Products.Num_Packets_Rejected (The_Time, (Value => 0)));
      Self.Data_Product_T_Send_If_Connected (Self.Data_Products.Num_Tables_Received (The_Time, (Value => 0)));
      Self.Data_Product_T_Send_If_Connected (Self.Data_Products.Num_Tables_Invalid (The_Time, (Value => 0)));

      -- Load all parameter tables if configured:
      if Self.Load_All_On_Set_Up then
         -- Iterate all entries in the tree and load those with Load_From:
         for I in Self.Table.Get_First_Index .. Self.Table.Get_Last_Index loop
            declare
               Tbl_Entry : constant Internal_Router_Table_Entry := Self.Table.Get (I);
               Has_Load_From : Boolean := False;
            begin
               if Tbl_Entry.Table_Entry.Destinations /= null then
                  for J in Tbl_Entry.Table_Entry.Destinations'Range loop
                     if Tbl_Entry.Table_Entry.Destinations (J).Load_From then
                        Has_Load_From := True;
                        exit;
                     end if;
                  end loop;
               end if;

               if Has_Load_From then
                  -- Load this table; failures are reported via events:
                  declare
                     Ignore_Result : constant Boolean := Self.Load_Single_Table (Tbl_Entry.Table_Entry.Table_Id);
                  begin
                     null;
                  end;
               end if;
            end;
         end loop;
      end if;
   end Set_Up;

   --------------------------------------------------
   -- Packet reception:
   --------------------------------------------------
   overriding procedure Ccsds_Space_Packet_T_Recv_Async (Self : in out Instance; Arg : in Ccsds_Space_Packet.T) is
      use Ccsds_Enums.Ccsds_Sequence_Flag;
      use Parameter_Table_Buffer;
      The_Time : constant Sys_Time.T := Self.Sys_Time_T_Get;
      Seq_Flag : constant Ccsds_Enums.Ccsds_Sequence_Flag.E := Arg.Header.Sequence_Flag;
      Status : Append_Status;
   begin
      -- Increment packet counter:
      Self.Packet_Count := Self.Packet_Count + 1;
      Self.Data_Product_T_Send_If_Connected (Self.Data_Products.Num_Packets_Received (The_Time, (Value => Interfaces.Unsigned_32 (Self.Packet_Count))));

      -- Check sequence count if enabled:
      if Self.Warn_Unexpected_Sequence_Counts then
         declare
            Expected : constant Ccsds_Primary_Header.Ccsds_Sequence_Count_Type := Self.Last_Sequence_Count + 1;
         begin
            if Self.Last_Sequence_Count /= Ccsds_Primary_Header.Ccsds_Sequence_Count_Type'Last
               and then Arg.Header.Sequence_Count /= Expected
            then
               Self.Event_T_Send_If_Connected (Self.Events.Unexpected_Sequence_Count_Detected (The_Time, (
                  Ccsds_Header => Arg.Header,
                  Received_Sequence_Count => Interfaces.Unsigned_16 (Arg.Header.Sequence_Count),
                  Expected_Sequence_Count => Interfaces.Unsigned_16 (Expected)
               )));
            end if;
         end;
         Self.Last_Sequence_Count := Arg.Header.Sequence_Count;
      end if;

      -- Handle overflow state: drop packets until new FirstSegment:
      if Self.Buffer_Overflowed and then Seq_Flag /= Firstsegment then
         return;
      end if;

      -- Clear overflow on FirstSegment:
      if Seq_Flag = Firstsegment then
         Self.Buffer_Overflowed := False;
      end if;

      -- Append to staging buffer:
      Status := Parameter_Table_Buffer.Append (
         Self => Self.Staging_Buffer,
         Data => Arg.Data (Arg.Data'First .. Arg.Data'First + Natural (Arg.Header.Packet_Length)),
         Sequence_Flag => Seq_Flag
      );

      case Status is
         when Packet_Ignored =>
            Self.Reject_Count := Self.Reject_Count + 1;
            Self.Data_Product_T_Send_If_Connected (Self.Data_Products.Num_Packets_Rejected (The_Time, (Value => Interfaces.Unsigned_32 (Self.Reject_Count))));
            Self.Event_T_Send_If_Connected (Self.Events.Packet_Ignored (The_Time, Arg.Header));

         when Too_Small_Table =>
            Self.Reject_Count := Self.Reject_Count + 1;
            Self.Data_Product_T_Send_If_Connected (Self.Data_Products.Num_Packets_Rejected (The_Time, (Value => Interfaces.Unsigned_32 (Self.Reject_Count))));
            Self.Event_T_Send_If_Connected (Self.Events.Too_Small_Table (The_Time, Arg.Header));

         when New_Table =>
            -- Look up table ID:
            declare
               Tid : constant Parameter_Types.Parameter_Table_Id := Parameter_Table_Buffer.Get_Table_Id (Self.Staging_Buffer);
               Table_Id_Param : constant Parameter_Table_Id.T := (Id => Tid);
               Search_Entry : constant Internal_Router_Table_Entry := (Table_Entry => (Table_Id => Tid, Destinations => null));
               Found_Entry : Internal_Router_Table_Entry;
               Found_Index : Positive;
            begin
               Self.Event_T_Send_If_Connected (Self.Events.Receiving_New_Table (The_Time, Table_Id_Param));
               if not Self.Table.Search (Search_Entry, Found_Entry, Found_Index) then
                  Self.Event_T_Send_If_Connected (Self.Events.Unrecognized_Table_Id (The_Time, Table_Id_Param));
                  Parameter_Table_Buffer.Reset (Self.Staging_Buffer);
               end if;
            end;

         when Buffering_Table =>
            null;

         when Complete_Table =>
            Self.Table_Count := Self.Table_Count + 1;
            Self.Data_Product_T_Send_If_Connected (Self.Data_Products.Num_Tables_Received (The_Time, (Value => Interfaces.Unsigned_32 (Self.Table_Count))));
            declare
               Tid : constant Parameter_Types.Parameter_Table_Id := Parameter_Table_Buffer.Get_Table_Id (Self.Staging_Buffer);
               Table_Id_Param : constant Parameter_Table_Id.T := (Id => Tid);
               Search_Entry : constant Internal_Router_Table_Entry := (Table_Entry => (Table_Id => Tid, Destinations => null));
               Found_Entry : Internal_Router_Table_Entry;
               Found_Index : Positive;
            begin
               Self.Event_T_Send_If_Connected (Self.Events.Table_Received (The_Time, Table_Id_Param));

               if not Self.Table.Search (Search_Entry, Found_Entry, Found_Index) then
                  Self.Event_T_Send_If_Connected (Self.Events.Unrecognized_Table_Id (The_Time, Table_Id_Param));
               else
                  -- Build set region and send to destinations:
                  declare
                     Set_Region : constant Parameters_Memory_Region.T := (
                        Region => Parameter_Table_Buffer.Get_Table_Region (Self.Staging_Buffer),
                        Operation => Parameter_Enums.Parameter_Table_Operation_Type.Set
                     );
                  begin
                     if Send_Table_To_Destinations (Self, Found_Entry.Table_Entry, Set_Region) then
                        Self.Event_T_Send_If_Connected (Self.Events.Table_Updated (The_Time, Table_Id_Param));
                     else
                        Self.Invalid_Count := Self.Invalid_Count + 1;
                        Self.Data_Product_T_Send_If_Connected (Self.Data_Products.Num_Tables_Invalid (The_Time, (Value => Interfaces.Unsigned_32 (Self.Invalid_Count))));
                     end if;
                  end;

                  -- Update last table received data product:
                  Self.Data_Product_T_Send_If_Connected (Self.Data_Products.Last_Table_Received (The_Time, (
                     Table_Id => Tid,
                     Table_Length => Interfaces.Unsigned_32 (Parameter_Table_Buffer.Get_Table_Length (Self.Staging_Buffer)),
                     Timestamp => The_Time
                  )));
               end if;
            end;

         when Buffer_Overflow =>
            Self.Buffer_Overflowed := True;
            Self.Reject_Count := Self.Reject_Count + 1;
            Self.Data_Product_T_Send_If_Connected (Self.Data_Products.Num_Packets_Rejected (The_Time, (Value => Interfaces.Unsigned_32 (Self.Reject_Count))));
            Self.Event_T_Send_If_Connected (Self.Events.Staging_Buffer_Overflow (The_Time, Arg.Header));
      end case;
   end Ccsds_Space_Packet_T_Recv_Async;

   overriding procedure Ccsds_Space_Packet_T_Recv_Async_Dropped (Self : in out Instance; Arg : in Ccsds_Space_Packet.T) is
   begin
      Self.Event_T_Send_If_Connected (Self.Events.Packet_Dropped (Self.Sys_Time_T_Get, Arg.Header));
   end Ccsds_Space_Packet_T_Recv_Async_Dropped;

   --------------------------------------------------
   -- Command handling:
   --------------------------------------------------
   overriding procedure Command_T_Recv_Async (Self : in out Instance; Arg : in Command.T) is
      Stat : constant Command_Response_Status.E := Self.Execute_Command (Arg);
   begin
      Self.Command_Response_T_Send_If_Connected ((Source_Id => Arg.Header.Source_Id, Registration_Id => Self.Command_Reg_Id, Command_Id => Arg.Header.Id, Status => Stat));
   end Command_T_Recv_Async;

   overriding procedure Command_T_Recv_Async_Dropped (Self : in out Instance; Arg : in Command.T) is
   begin
      Self.Event_T_Send_If_Connected (Self.Events.Command_Dropped (Self.Sys_Time_T_Get, Arg.Header));
   end Command_T_Recv_Async_Dropped;

   overriding function Load_Parameter_Table (Self : in out Instance; Arg : in Parameter_Table_Id.T) return Command_Execution_Status.E is
      use Command_Execution_Status;
   begin
      if Self.Load_Single_Table (Arg.Id) then
         return Success;
      else
         return Failure;
      end if;
   end Load_Parameter_Table;

   overriding function Load_All_Parameter_Tables (Self : in out Instance) return Command_Execution_Status.E is
      use Command_Execution_Status;
   begin
      for I in Self.Table.Get_First_Index .. Self.Table.Get_Last_Index loop
         declare
            Iter_Entry : constant Internal_Router_Table_Entry := Self.Table.Get (I);
            Has_Load_From : Boolean := False;
         begin
            if Iter_Entry.Table_Entry.Destinations /= null then
               for J in Iter_Entry.Table_Entry.Destinations'Range loop
                  if Iter_Entry.Table_Entry.Destinations (J).Load_From then
                     Has_Load_From := True;
                     exit;
                  end if;
               end loop;
            end if;

            if Has_Load_From then
               declare
                  Ignore_Result : constant Boolean := Self.Load_Single_Table (Iter_Entry.Table_Entry.Table_Id);
               begin
                  null;
               end;
            end if;
         end;
      end loop;
      return Success;
   end Load_All_Parameter_Tables;

   --------------------------------------------------
   -- Timeout tick:
   --------------------------------------------------
   overriding procedure Timeout_Tick_Recv_Sync (Self : in out Instance; Arg : in Tick.T) is
      Ignore : Tick.T renames Arg;
   begin
      Self.Sync_Object.Increment_Timeout_If_Waiting;
   end Timeout_Tick_Recv_Sync;

   --------------------------------------------------
   -- Response handler:
   --------------------------------------------------
   overriding procedure Parameters_Memory_Region_Release_T_Recv_Sync (Self : in out Instance; Arg : in Parameters_Memory_Region_Release.T) is
   begin
      Self.Response.Set_Var (Arg);
      Self.Sync_Object.Release;
   end Parameters_Memory_Region_Release_T_Recv_Sync;

   --------------------------------------------------
   -- Invalid command:
   --------------------------------------------------
   overriding procedure Invalid_Command (Self : in out Instance; Cmd : in Command.T; Errant_Field_Number : in Unsigned_32; Errant_Field : in Basic_Types.Poly_Type) is
   begin
      Self.Event_T_Send_If_Connected (Self.Events.Invalid_Command_Received (
         Self.Sys_Time_T_Get,
         (Id => Cmd.Header.Id, Errant_Field_Number => Errant_Field_Number, Errant_Field => Errant_Field)
      ));
   end Invalid_Command;

end Component.Parameter_Table_Router.Implementation;

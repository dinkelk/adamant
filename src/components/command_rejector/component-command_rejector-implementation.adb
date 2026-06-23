--------------------------------------------------------------------------------
-- Command_Rejector Component Implementation Body
--------------------------------------------------------------------------------

with Packet_Types;
with Serializer_Types;

package body Component.Command_Rejector.Implementation is

   --------------------------------------------------
   -- Subprogram for implementation init method:
   --------------------------------------------------
   -- This component requires a list of command ID to reject at initialization.
   --
   -- Init Parameters:
   -- Command_Id_Reject_List : Command_Id_List - The list of command IDs to reject.
   --
   overriding procedure Init (Self : in out Instance; Command_Id_Reject_List : in Command_Id_List) is
   begin
      -- The binary tree package needs to be allocated with a positive. This component is completely
      -- useless without a list of at least one command to reject.
      if Command_Id_Reject_List'Length = 0 then
         raise Constraint_Error with "Empty protected command list is not allowed.";
      end if;

      -- Allocate space for protected command list:
      Self.Command_Reject_List.Init (Command_Id_Reject_List'Length);

      -- Store elements in the list:
      for Command_Identifier of Command_Id_Reject_List loop
         declare
            Ignore_1 : Command_Id;
            Ignore_2 : Natural;
            Ret : Boolean;
         begin
            -- Make sure the Command ID is not already stored in our list.
            Ret := Self.Command_Reject_List.Search (Command_Identifier, Ignore_1, Ignore_2);
            if Ret then
               raise Constraint_Error with "Duplicate command ID '" & Command_Id'Image (Command_Identifier) & "' not allowed command reject list!";
            end if;
            -- Add ID to the list:
            Ret := Self.Command_Reject_List.Add (Command_Identifier);
            if not Ret then
               raise Constraint_Error with "Binary tree too small to hold ID. This should never happen unless there is a bug.";
            end if;
         end;
      end loop;
   end Init;

   not overriding procedure Final (Self : in out Instance) is
   begin
      Self.Command_Reject_List.Destroy;
   end Final;

   -- Send out data products:
   overriding procedure Set_Up (Self : in out Instance) is
   begin
      if Self.Is_Packet_T_Send_Connected then
         -- We assume that a command fits within a packet in order for us to produce an error packet:
         pragma Assert (Command.Size_In_Bytes <= Packet_Types.Packet_Buffer_Type'Length, "Command does not fit within an error packet!");
      end if;

      Self.Data_Product_T_Send_If_Connected (Self.Data_Products.Rejected_Command_Count (Self.Sys_Time_T_Get, (Value => Self.Command_Reject_Counter)));
   end Set_Up;

   ---------------------------------------
   -- Invokee connector primitives:
   ---------------------------------------
   -- Commands received on this connector will be checked against the command reject list. Commands not found in the command reject list they will be forwarded.
   overriding procedure Command_T_To_Forward_Recv_Sync (Self : in out Instance; Arg : in Command.T) is
      -- Look up to see if this command is in the protected list:
      Id_To_Find : Command_Id renames Arg.Header.Id;
      Ignore_Found_Id : Command_Id;
      Ignore_Found_Index : Natural;
      Should_Reject_Command : constant Boolean := Self.Command_Reject_List.Search (Id_To_Find, Ignore_Found_Id, Ignore_Found_Index);
   begin
      -- If command is found in the reject list, then we need to drop it.
      case Should_Reject_Command is
         -- Command found in reject list, drop and report it.
         when True =>
            declare
               use Interfaces;
               -- Timestamp:
               The_Time : constant Sys_Time.T := Self.Sys_Time_T_Get;
            begin
               -- Increment the reject counter, saturating at max to avoid silent wrap:
               if Self.Command_Reject_Counter < Interfaces.Unsigned_16'Last then
                  Self.Command_Reject_Counter := @ + 1;
               end if;
               Self.Data_Product_T_Send_If_Connected (Self.Data_Products.Rejected_Command_Count (The_Time, (Value => Self.Command_Reject_Counter)));

               -- Send info event:
               Self.Event_T_Send_If_Connected (Self.Events.Rejected_Command (The_Time, Arg.Header));

               -- Send the error packet:
               if Self.Is_Packet_T_Send_Connected then
                  declare
                     use Serializer_Types;
                     -- Create the error packet:
                     Pkt : Packet.T;
                     Stat : constant Serialization_Status := Self.Packets.Error_Packet (The_Time, Arg, Pkt);
                  begin
                     pragma Assert (Stat = Success, "This should never fail if Init was called first.");
                     Self.Packet_T_Send (Pkt);
                  end;
               end if;
            end;

            -- This is command is not on the reject list, forward it on:
         when False =>
            Self.Command_T_Send_If_Connected (Arg);
      end case;
   end Command_T_To_Forward_Recv_Sync;

end Component.Command_Rejector.Implementation;

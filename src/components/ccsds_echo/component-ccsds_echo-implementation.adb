--------------------------------------------------------------------------------
-- Ccsds_Echo Component Implementation Body
--------------------------------------------------------------------------------

with Serializer_Types;
with Packet_Types;
with Packed_U16;
with Interfaces;

package body Component.Ccsds_Echo.Implementation is

   ---------------------------------------
   -- Invokee connector primitives:
   ---------------------------------------
   -- The CCSDS receive connector.
   overriding procedure Ccsds_Space_Packet_T_Recv_Sync (Self : in out Instance; Arg : in Ccsds_Space_Packet.T) is
      Num_Bytes : Natural;
      use Serializer_Types;
      Stat : constant Serialization_Status := Ccsds_Space_Packet.Serialized_Length (Arg, Num_Bytes);
   begin
      -- Check if the CCSDS packet will be truncated when placed into an Adamant packet.
      -- If serialization succeeds and the serialized length exceeds the packet buffer capacity,
      -- emit a warning event before sending the truncated echo.
      if Stat = Success and then Num_Bytes > Packet_Types.Packet_Buffer_Length_Type'Last then
         Self.Event_T_Send_If_Connected (Self.Events.Packet_Truncated (
            Self.Sys_Time_T_Get,
            (Value => Interfaces.Unsigned_16 (Num_Bytes))
         ));
      end if;
      Self.Packet_T_Send_If_Connected (Self.Packets.Echo_Packet_Truncate (Self.Sys_Time_T_Get, Arg));
   end Ccsds_Space_Packet_T_Recv_Sync;

   ---------------------------------------
   -- Invoker connector primitives:
   ---------------------------------------
   -- This procedure is called when a Packet_T_Send message is dropped due to a full queue.
   overriding procedure Packet_T_Send_Dropped (Self : in out Instance; Arg : in Packet.T) is
   begin
      -- Emit an event reporting the dropped packet:
      Self.Event_T_Send_If_Connected (Self.Events.Packet_Dropped (Self.Sys_Time_T_Get, Arg.Header));
   end Packet_T_Send_Dropped;

end Component.Ccsds_Echo.Implementation;

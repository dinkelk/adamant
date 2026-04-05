
package body Extract_Data_Product is

   -- General function to extract a data product from a ccsds space packet given the location in the packet of the extracted product
   function Extract_Data_Product (Pkt : in Ccsds_Space_Packet.T; Offset : in Natural; Length : in Natural; Id : in Data_Product_Types.Data_Product_Id; Timestamp : in Sys_Time.T; Dp : out Data_Product.T) return Extract_Status is
   begin
      -- Initialize out parameters. Buffer is zero-filled; only the first
      -- Buffer_Length bytes (set to Length) contain valid extracted data.
      -- Consumers must use Header.Buffer_Length to determine the valid region.
      Dp := (
         Header => (
            Time => Timestamp,
            Id => Id,
            Buffer_Length => Length
         ),
         Buffer => [others => 0]
      );

      -- Don't try to read if it's going to overflow out of the packet.
      -- Note: Per the CCSDS Space Packet Protocol (CCSDS 133.0-B-2), the Packet_Length
      -- field contains the number of octets in the packet data field minus 1. Therefore
      -- Packet_Length represents the index of the last valid byte when Pkt.Data is 0-based.
      -- Offset is a 0-based index into Pkt.Data, so the last byte accessed is at
      -- Offset + Length - 1, and we check that this does not exceed Packet_Length.
      -- Note: Offset + Length - 1 cannot overflow Natural in practice because both values
      -- are constrained by the maximum CCSDS packet data size (65535 bytes), which is well
      -- within Natural'Last. If this constraint ever changes, this arithmetic should be
      -- revisited for overflow safety.
      if Offset + Length - 1 <= Natural (Pkt.Header.Packet_Length) then
         Dp.Buffer (Dp.Buffer'First .. Dp.Buffer'First + Length - 1) := Pkt.Data (Offset .. Offset + Length - 1);
         return Success;
      else
         return Length_Overflow;
      end if;
   end Extract_Data_Product;

end Extract_Data_Product;

with Basic_Types;
with Parameter_Types;
with Ccsds_Enums;
with Memory_Region;

package Parameter_Table_Buffer is

   -- Return status from the Append operation:
   type Append_Status is (
      Packet_Ignored,   -- ContinuationSegment/LastSegment without prior FirstSegment, or Unsegmented
      Buffering_Table,  -- ContinuationSegment received after valid FirstSegment, data appended
      New_Table,        -- Valid FirstSegment received, buffer reset and data stored
      Complete_Table,   -- LastSegment received after valid FirstSegment, table is complete
      Too_Small_Table,  -- FirstSegment data is less than 2 bytes (cannot extract Table ID)
      Buffer_Overflow   -- Data would exceed buffer capacity, not written
   );

   -- Internal buffer state:
   type Buffer_State is (Idle, Receiving_Table);

   -- The staging buffer instance:
   type Instance is record
      Buffer : Basic_Types.Byte_Array_Access := null;
      Buffer_Length : Natural := 0;
      Buffer_Index : Natural := 0;
      Table_Id : Parameter_Types.Parameter_Table_Id := 0;
      State : Buffer_State := Idle;
   end record;

   -- Allocate the internal buffer.
   procedure Create (Self : in out Instance; Buffer_Size : in Positive);

   -- Deallocate the internal buffer.
   procedure Destroy (Self : in out Instance);

   -- Append CCSDS packet data to the buffer.
   function Append (
      Self : in out Instance;
      Data : in Basic_Types.Byte_Array;
      Sequence_Flag : in Ccsds_Enums.Ccsds_Sequence_Flag.E
   ) return Append_Status;

   -- Get a Memory_Region.T pointing to the table data in the buffer,
   -- starting AFTER the 2-byte Table ID.
   function Get_Table_Region (Self : in Instance) return Memory_Region.T;

   -- Get a Memory_Region.T pointing to the full buffer capacity.
   -- Used for Load (Get) operations where the buffer receives data.
   function Get_Full_Buffer_Region (Self : in Instance) return Memory_Region.T;

   -- Get the Table ID extracted from the most recent FirstSegment.
   function Get_Table_Id (Self : in Instance) return Parameter_Types.Parameter_Table_Id;

   -- Get the total number of table data bytes received (excluding the 2-byte Table ID).
   function Get_Table_Length (Self : in Instance) return Natural;

   -- Reset the buffer state to Idle and index to 0.
   procedure Reset (Self : in out Instance);

end Parameter_Table_Buffer;

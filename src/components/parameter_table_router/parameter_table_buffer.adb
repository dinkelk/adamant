with Interfaces; use Interfaces;

package body Parameter_Table_Buffer is

   use Basic_Types;

   procedure Create (Self : in out Instance; Buffer_Size : in Positive) is
   begin
      pragma Assert (Self.Buffer = null, "Buffer already allocated.");
      Self.Buffer := new Basic_Types.Byte_Array (0 .. Buffer_Size - 1);
      Self.Buffer_Length := Buffer_Size;
      Self.Buffer_Index := 0;
      Self.Table_Id := 0;
      Self.State := Idle;
   end Create;

   procedure Destroy (Self : in out Instance) is
   begin
      -- Note: Under Ravenscar, memory is never freed. The buffer persists
      -- for the lifetime of the application. This is acceptable for embedded
      -- systems where the component is never destroyed.
      Self.Buffer := null;
      Self.Buffer_Length := 0;
      Self.Buffer_Index := 0;
      Self.State := Idle;
   end Destroy;

   function Append (
      Self : in out Instance;
      Data : in Basic_Types.Byte_Array;
      Sequence_Flag : in Ccsds_Enums.Ccsds_Sequence_Flag.E
   ) return Append_Status is
      use Ccsds_Enums.Ccsds_Sequence_Flag;
   begin
      case Sequence_Flag is
         when Unsegmented =>
            return Packet_Ignored;

         when Firstsegment =>
            -- Reset buffer for new table:
            Self.Buffer_Index := 0;
            Self.State := Receiving_Table;

            -- Check minimum data length for Table ID:
            if Data'Length < 2 then
               Self.State := Idle;
               return Too_Small_Table;
            end if;

            -- Extract Table ID from first 2 bytes (big-endian):
            Self.Table_Id := Parameter_Types.Parameter_Table_Id (
               Shift_Left (Unsigned_16 (Data (Data'First)), 8)
               or Unsigned_16 (Data (Data'First + 1))
            );

            -- Check buffer capacity:
            if Data'Length > Self.Buffer_Length then
               Self.State := Idle;
               return Buffer_Overflow;
            end if;

            -- Copy all data (including Table ID bytes) to buffer:
            Self.Buffer (0 .. Data'Length - 1) := Data;
            Self.Buffer_Index := Data'Length;
            return New_Table;

         when Continuationsegment =>
            if Self.State = Idle then
               return Packet_Ignored;
            end if;

            -- Check buffer capacity:
            if Self.Buffer_Index + Data'Length > Self.Buffer_Length then
               return Buffer_Overflow;
            end if;

            -- Append data:
            Self.Buffer (Self.Buffer_Index .. Self.Buffer_Index + Data'Length - 1) := Data;
            Self.Buffer_Index := Self.Buffer_Index + Data'Length;
            return Buffering_Table;

         when Lastsegment =>
            if Self.State = Idle then
               return Packet_Ignored;
            end if;

            -- Check buffer capacity:
            if Self.Buffer_Index + Data'Length > Self.Buffer_Length then
               return Buffer_Overflow;
            end if;

            -- Append data and complete:
            Self.Buffer (Self.Buffer_Index .. Self.Buffer_Index + Data'Length - 1) := Data;
            Self.Buffer_Index := Self.Buffer_Index + Data'Length;
            Self.State := Idle;
            return Complete_Table;
      end case;
   end Append;

   function Get_Table_Region (Self : in Instance) return Memory_Region.T is
   begin
      pragma Assert (Self.Buffer /= null, "Buffer not allocated.");
      pragma Assert (Self.Buffer_Index >= 2, "Buffer does not contain a complete table header.");
      return (
         Address => Self.Buffer (2)'Address,
         Length => Self.Buffer_Index - 2
      );
   end Get_Table_Region;

   function Get_Full_Buffer_Region (Self : in Instance) return Memory_Region.T is
   begin
      pragma Assert (Self.Buffer /= null, "Buffer not allocated.");
      return (
         Address => Self.Buffer (0)'Address,
         Length => Self.Buffer_Length
      );
   end Get_Full_Buffer_Region;

   function Get_Table_Id (Self : in Instance) return Parameter_Types.Parameter_Table_Id is
   begin
      return Self.Table_Id;
   end Get_Table_Id;

   function Get_Table_Length (Self : in Instance) return Natural is
   begin
      if Self.Buffer_Index >= 2 then
         return Self.Buffer_Index - 2;
      else
         return 0;
      end if;
   end Get_Table_Length;

   procedure Reset (Self : in out Instance) is
   begin
      Self.State := Idle;
      Self.Buffer_Index := 0;
   end Reset;

end Parameter_Table_Buffer;

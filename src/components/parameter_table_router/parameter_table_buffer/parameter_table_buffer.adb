with Safe_Deallocator;
with Packed_U16;

package body Parameter_Table_Buffer is

   use Basic_Types;
   use Parameter_Table_Router_Enums.Table_Status;

   procedure Create (Self : in out Instance; Buffer_Size : in Positive) is
   begin
      pragma Assert (Self.Buffer = null);
      Self.Buffer := new Basic_Types.Byte_Array (0 .. Buffer_Size - 1);
      Self.Buffer_Index := 0;
      Self.Table_Id := 0;
      Self.State := Idle;
   end Create;

   procedure Destroy (Self : in out Instance) is
      procedure Free_If_Testing is new Safe_Deallocator.Deallocate_If_Testing (
         Object => Basic_Types.Byte_Array,
         Name => Basic_Types.Byte_Array_Access
      );
   begin
      if Self.Buffer /= null then
         Free_If_Testing (Self.Buffer);
      end if;
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
            Self.Buffer_Index := 0;
            Self.State := Receiving_Table;

            if Data'Length < 2 then
               Self.State := Idle;
               return Too_Small;
            end if;

            -- Extract Table ID from first 2 bytes using packed deserialization:
            declare
               Id_Packed : constant Packed_U16.T := Packed_U16.Serialization.From_Byte_Array (Data (Data'First .. Data'First + 1));
            begin
               Self.Table_Id := Parameter_Types.Parameter_Table_Id (Id_Packed.Value);
            end;

            -- Store only the data AFTER the 2-byte Table ID:
            declare
               Table_Data_Length : constant Natural := Data'Length - 2;
            begin
               if Table_Data_Length > Self.Buffer.all'Length then
                  Self.State := Idle;
                  return Buffer_Overflow;
               end if;

               if Table_Data_Length > 0 then
                  Self.Buffer (0 .. Table_Data_Length - 1) := Data (Data'First + 2 .. Data'Last);
               end if;
               Self.Buffer_Index := Table_Data_Length;
            end;
            return New_Table;

         when Continuationsegment =>
            if Self.State = Idle then
               return Packet_Ignored;
            end if;

            if Self.Buffer_Index + Data'Length > Self.Buffer.all'Length then
               return Buffer_Overflow;
            end if;

            Self.Buffer (Self.Buffer_Index .. Self.Buffer_Index + Data'Length - 1) := Data;
            Self.Buffer_Index := @ + Data'Length;
            return Receiving_Table;

         when Lastsegment =>
            if Self.State = Idle then
               return Packet_Ignored;
            end if;

            if Self.Buffer_Index + Data'Length > Self.Buffer.all'Length then
               return Buffer_Overflow;
            end if;

            Self.Buffer (Self.Buffer_Index .. Self.Buffer_Index + Data'Length - 1) := Data;
            Self.Buffer_Index := @ + Data'Length;
            Self.State := Idle;
            return Complete_Table;
      end case;
   end Append;

   function Get_Table_Region (Self : in Instance) return Memory_Region.T is
   begin
      pragma Assert (Self.Buffer /= null);
      return (
         Address => Self.Buffer (0)'Address,
         Length => Self.Buffer_Index
      );
   end Get_Table_Region;

   function Get_Full_Buffer_Region (Self : in Instance) return Memory_Region.T is
   begin
      pragma Assert (Self.Buffer /= null);
      return (
         Address => Self.Buffer (0)'Address,
         Length => Self.Buffer.all'Length
      );
   end Get_Full_Buffer_Region;

   function Get_Table_Id (Self : in Instance) return Parameter_Types.Parameter_Table_Id is
   begin
      return Self.Table_Id;
   end Get_Table_Id;

   function Get_Table_Length (Self : in Instance) return Natural is
   begin
      return Self.Buffer_Index;
   end Get_Table_Length;

end Parameter_Table_Buffer;

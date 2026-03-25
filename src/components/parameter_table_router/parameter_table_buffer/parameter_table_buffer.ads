with Basic_Types;
with Parameter_Types;
with Parameter_Table_Router_Enums;
with Ccsds_Enums;
with Memory_Region;

package Parameter_Table_Buffer is

   -- Use the component's shared status enum as the Append return type:
   subtype Append_Status is Parameter_Table_Router_Enums.Table_Status.E;

   -- The staging buffer instance:
   type Instance is tagged limited private;

   procedure Create (Self : in out Instance; Buffer_Size : in Positive);
   procedure Destroy (Self : in out Instance);

   function Append (
      Self : in out Instance;
      Data : in Basic_Types.Byte_Array;
      Sequence_Flag : in Ccsds_Enums.Ccsds_Sequence_Flag.E
   ) return Append_Status;

   function Get_Table_Region (Self : in Instance) return Memory_Region.T;
   function Get_Full_Buffer_Region (Self : in Instance) return Memory_Region.T;
   function Get_Table_Id (Self : in Instance) return Parameter_Types.Parameter_Table_Id;
   function Get_Table_Length (Self : in Instance) return Natural;

private

   type Buffer_State is (Idle, Receiving_Table);

   type Instance is tagged limited record
      Buffer : Basic_Types.Byte_Array_Access := null;
      Buffer_Index : Natural := 0;
      Table_Id : Parameter_Types.Parameter_Table_Id := 0;
      State : Buffer_State := Idle;
   end record;

end Parameter_Table_Buffer;

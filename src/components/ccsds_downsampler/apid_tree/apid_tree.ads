-- This is a somewhat generic, unprotected binary tree for holding apids and filter factors for the downsampler component.
with Binary_Tree;
with Ccsds_Primary_Header;
with Interfaces;
with Ccsds_Downsampler_Types;

package Apid_Tree is
   use Interfaces;
   use Ccsds_Primary_Header;
   use Ccsds_Downsampler_Types;
   type Instance is tagged limited private;

   -- Defined return type
   type Filter_Action_Status is (Pass, Filter, Invalid_Id);
   type Filter_Factor_Set_Status is (Success, Invalid_Id);
   --
   -- Initialization/destruction functions:
   --
   -- Init Parameters:
   -- Downsample_List : Ccsds_Downsampler_Types.Ccsds_Downsample_Packet_List_Access - The list of apids and their associated starting filter factor to be added to the tree at init
   --
   procedure Init (Self : in out Instance; Downsample_List : in Ccsds_Downsample_Packet_List_Access);

   -- Determine whether to pass or filter a packet with the given APID, incrementing internal counters.
   function Filter_Packet (Self : in out Instance; Apid : in Ccsds_Apid_Type; Count : out Unsigned_16) return Filter_Action_Status;
   -- Update the filter factor for a given APID in the tree, resetting its filter count.
   function Set_Filter_Factor (Self : in out Instance; Apid : in Ccsds_Apid_Type; New_Filter_Factor : in Unsigned_16; Tree_Index : out Positive) return Filter_Factor_Set_Status;
   -- Functions to get the first and last index of the tree
   function Get_Tree_First_Index (Self : in Instance) return Positive;
   function Get_Tree_Last_Index (Self : in Instance) return Natural;
   -- Functions to get the element when given an index.
   function Get_Tree_Entry (Self : in Instance; Index : in Positive) return Ccsds_Downsampler_Tree_Entry;

private

   -- Binary tree for searching for apids
   function Less_Than (Left, Right : Ccsds_Downsampler_Tree_Entry) return Boolean with
      Inline => True;
   function Greater_Than (Left, Right : Ccsds_Downsampler_Tree_Entry) return Boolean with
      Inline => True;
   package Ccsds_Downsample_B_Tree is new Binary_Tree (Ccsds_Downsampler_Tree_Entry, Less_Than, Greater_Than);

   type Instance is tagged limited record
      -- Note: These counters are modular Unsigned_16 and intentionally wrap around at 65535->0.
      -- They are used for telemetry display only; wrap-around is acceptable.
      Num_Filtered_Packets : Unsigned_16 := Unsigned_16'First;
      Num_Passed_Packets : Unsigned_16 := Unsigned_16'First;
      -- Binary tree instance for tracking downsampling
      Downsample_Entry : Ccsds_Downsample_B_Tree.Instance;
   end record;

end Apid_Tree;

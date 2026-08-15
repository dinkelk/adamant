--------------------------------------------------------------------------------
-- Parameter_Store_Memory_Dump Tests Body
--------------------------------------------------------------------------------

with Basic_Assertions; use Basic_Assertions;
with Command_Response.Assertion; use Command_Response.Assertion;
with Command_Enums; use Command_Enums.Command_Response_Status;
with Parameters_Memory_Region_Release.Assertion; use Parameters_Memory_Region_Release.Assertion;
with Parameter_Enums;
with Basic_Types;
with Memory_Region;
with Parameter_Table_Header;
with Crc_16;
with Byte_Array_Pointer;
with Memory_Packetizer_Types;

package body Parameter_Store_Memory_Dump_Tests.Implementation is

   -------------------------------------------------------------------------
   -- Globals:
   -------------------------------------------------------------------------
   -- Declare memory store data:
   Bytes : aliased Basic_Types.Byte_Array := [0 .. 99 => 0];

   -------------------------------------------------------------------------
   -- Fixtures:
   -------------------------------------------------------------------------

   overriding procedure Set_Up_Test (Self : in out Instance) is
   begin
      -- Allocate heap memory to component:
      Self.Tester.Init_Base (Queue_Size => Self.Tester.Component_Instance.Get_Max_Queue_Element_Size * 3);

      -- Call component init here.
      Bytes := [others => 0];
      Bytes (1) := 1;
      Bytes (2) := 2;
      Bytes (3) := 3;
      Bytes (4) := 4;
      Bytes (5) := 5;
      Self.Tester.Component_Instance.Init (Bytes => Bytes'Access, Dump_Parameters_On_Change => True);

      -- Wire the Memory_Dump dump pathway (no Packet_T_Send) and run Set_Up.
      -- Every scenario in this suite uses the Memory_Dump pathway; the
      -- Packet.T pathway scenarios live in the sibling test/ directory.
      Self.Tester.Connect_Memory_Dump_Path;
      Self.Tester.Component_Instance.Set_Up;
   end Set_Up_Test;

   overriding procedure Tear_Down_Test (Self : in out Instance) is
   begin
      -- Free component heap:
      Self.Tester.Final_Base;
      -- Reset per-scenario component state for cross-test reuse:
      -- the bareboard Tester is a static singleton, so without this
      -- the packet generator's Sequence_Count carries over from the
      -- prior scenario.
      Self.Tester.Component_Instance.Final;
   end Tear_Down_Test;

   -------------------------------------------------------------------------
   -- Tests:
   -------------------------------------------------------------------------

   overriding procedure Test_Memory_Dump_Path (Self : in out Instance) is
      T : Component.Parameter_Store.Implementation.Tester.Instance_Access renames Self.Tester;
      Dump : Memory_Packetizer_Types.Memory_Dump;
   begin
      -- No traffic on either pathway yet:
      Natural_Assert.Eq (T.Memory_Dump_Recv_Sync_History.Get_Count, 0);
      Natural_Assert.Eq (T.Packet_T_Recv_Sync_History.Get_Count, 0);

      -- Issue the dump command:
      T.Command_T_Send (T.Commands.Dump_Parameter_Store);
      Natural_Assert.Eq (T.Dispatch_All, 1);
      Natural_Assert.Eq (T.Command_Response_T_Recv_Sync_History.Get_Count, 1);
      Command_Response_Assert.Eq (
         T.Command_Response_T_Recv_Sync_History.Get (1),
         (Source_Id => 0, Registration_Id => 0, Command_Id => T.Commands.Get_Dump_Parameter_Store_Id, Status => Success));

      -- Exactly one Memory_Dump emitted; no Packet.T on this path:
      Natural_Assert.Eq (T.Memory_Dump_Recv_Sync_History.Get_Count, 1);
      Natural_Assert.Eq (T.Packet_T_Recv_Sync_History.Get_Count, 0);

      Dump := T.Memory_Dump_Recv_Sync_History.Get (1);

      -- Stored_Parameters APID == 0 (only packet defined for this component).
      Natural_Assert.Eq (Natural (Dump.Id), 0);
      -- The Memory_Dump points at the full parameter table buffer (zero-copy):
      Natural_Assert.Eq (Byte_Array_Pointer.Length (Dump.Memory_Pointer), Bytes'Length);
      Byte_Array_Assert.Eq (Byte_Array_Pointer.To_Byte_Array (Dump.Memory_Pointer), Bytes);

      -- Dumped_Parameters event fired once:
      Natural_Assert.Eq (T.Dumped_Parameters_History.Get_Count, 1);

      -- A second dump command bumps everything by one:
      T.Command_T_Send (T.Commands.Dump_Parameter_Store);
      Natural_Assert.Eq (T.Dispatch_All, 1);
      Natural_Assert.Eq (T.Memory_Dump_Recv_Sync_History.Get_Count, 2);
      Natural_Assert.Eq (T.Packet_T_Recv_Sync_History.Get_Count, 0);
      Natural_Assert.Eq (T.Dumped_Parameters_History.Get_Count, 2);
   end Test_Memory_Dump_Path;

   overriding procedure Test_Memory_Dump_Path_Auto_Dump_On_Change (Self : in out Instance) is
      use Parameter_Enums.Parameter_Table_Update_Status;
      use Parameter_Enums.Parameter_Table_Operation_Type;
      T : Component.Parameter_Store.Implementation.Tester.Instance_Access renames Self.Tester;
      -- Build a valid (CRC-correct) parameter table:
      Table : aliased Basic_Types.Byte_Array := [0 .. 99 => 17];
      Crc : Crc_16.Crc_16_Type;
      Region : constant Memory_Region.T := (Address => Table'Address, Length => Table'Length);
      Expected_Table_Bytes : Basic_Types.Byte_Array (0 .. 99) := Table;
      Dump : Memory_Packetizer_Types.Memory_Dump;
   begin
      -- Stamp version + CRC into both the staging table and the comparison
      -- copy so the component's bytes match Expected_Table_Bytes after the Set:
      Table (Table'First .. Table'First + Parameter_Table_Header.Size_In_Bytes - 1) :=
         Parameter_Table_Header.Serialization.To_Byte_Array ((Crc_Table => [0, 0], Version => 1.0));
      Crc := Crc_16.Compute_Crc_16 (Table (Table'First + Parameter_Table_Header.Crc_Section_Length .. Table'Last));
      Table (Table'First .. Table'First + Parameter_Table_Header.Size_In_Bytes - 1) :=
         Parameter_Table_Header.Serialization.To_Byte_Array ((Crc_Table => Crc, Version => 1.0));
      Expected_Table_Bytes (Table'First .. Table'First + Parameter_Table_Header.Size_In_Bytes - 1) :=
         Parameter_Table_Header.Serialization.To_Byte_Array ((Crc_Table => Crc, Version => 1.0));

      -- Send the memory region (Set) -- fixture has Dump_Parameters_On_Change => True,
      -- so this should auto-dump through the Memory_Dump pathway:
      T.Parameters_Memory_Region_T_Send ((Region => Region, Operation => Set));
      Natural_Assert.Eq (T.Dispatch_All, 1);

      -- Component's bytes were updated:
      Byte_Array_Assert.Eq (Bytes, Expected_Table_Bytes);

      -- Exactly one Memory_Dump fired automatically; nothing on the Packet path:
      Natural_Assert.Eq (T.Memory_Dump_Recv_Sync_History.Get_Count, 1);
      Natural_Assert.Eq (T.Packet_T_Recv_Sync_History.Get_Count, 0);

      Dump := T.Memory_Dump_Recv_Sync_History.Get (1);
      Natural_Assert.Eq (Natural (Dump.Id), 0);
      Natural_Assert.Eq (Byte_Array_Pointer.Length (Dump.Memory_Pointer), Bytes'Length);
      Byte_Array_Assert.Eq (Byte_Array_Pointer.To_Byte_Array (Dump.Memory_Pointer), Expected_Table_Bytes);

      -- Release/event bookkeeping:
      Natural_Assert.Eq (T.Parameter_Table_Updated_History.Get_Count, 1);
      Natural_Assert.Eq (T.Dumped_Parameters_History.Get_Count, 1);
      Natural_Assert.Eq (T.Parameters_Memory_Region_Release_T_Recv_Sync_History.Get_Count, 1);
      Parameters_Memory_Region_Release_Assert.Eq (
         T.Parameters_Memory_Region_Release_T_Recv_Sync_History.Get (1),
         (Region, Success));
   end Test_Memory_Dump_Path_Auto_Dump_On_Change;

end Parameter_Store_Memory_Dump_Tests.Implementation;

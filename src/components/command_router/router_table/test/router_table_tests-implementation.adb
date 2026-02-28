--------------------------------------------------------------------------------
-- Router_Table Tests Body
--------------------------------------------------------------------------------

with Safe_Deallocator;
with Smart_Assert;
with Command_Types;
with Basic_Assertions; use Basic_Assertions;

package body Router_Table_Tests.Implementation is

   -------------------------------------------------------------------------
   -- Fixtures:
   -------------------------------------------------------------------------

   overriding procedure Set_Up_Test (Self : in out Instance) is
   begin
      Self.Table := new Router_Table.Instance;
      Self.Table.Init (3);
   end Set_Up_Test;

   overriding procedure Tear_Down_Test (Self : in out Instance) is
      procedure Free_If_Testing is new Safe_Deallocator.Deallocate_If_Testing (Object => Router_Table.Instance, Name => Router_Table.Instance_Access);
   begin
      Self.Table.Destroy;
      Free_If_Testing (Self.Table);
   end Tear_Down_Test;

   -------------------------------------------------------------------------
   -- Tests:
   -------------------------------------------------------------------------

   package Status_Assert is new Smart_Assert.Basic (Router_Table.Add_Status, Router_Table.Add_Status'Image);
   package Lookup_Assert is new Smart_Assert.Basic (Router_Table.Lookup_Status, Router_Table.Lookup_Status'Image);
   package Registration_Assert is new Smart_Assert.Basic (Command_Types.Command_Registration_Id, Command_Types.Command_Registration_Id'Image);

   overriding procedure Add_To_Table (Self : in out Instance) is
      Registration_Id : Command_Types.Command_Registration_Id;
      Ignore : Command_Types.Command_Registration_Id;
   begin
      -- Add to table, make sure duplicates are rejected:
      Natural_Assert.Eq (Self.Table.Get_Size, 0);
      Natural_Assert.Eq (Self.Table.Get_Capacity, 3);
      Status_Assert.Eq (Self.Table.Add ((Registration_Id => 19, Command_Id => 0)), Router_Table.Success);
      Natural_Assert.Eq (Self.Table.Get_Size, 1);
      Status_Assert.Eq (Self.Table.Add ((Registration_Id => 15, Command_Id => 0)), Router_Table.Id_Conflict);
      Natural_Assert.Eq (Self.Table.Get_Size, 1);
      Status_Assert.Eq (Self.Table.Add ((Registration_Id => 36, Command_Id => 1)), Router_Table.Success);
      Natural_Assert.Eq (Self.Table.Get_Size, 2);
      Status_Assert.Eq (Self.Table.Add ((Registration_Id => 17, Command_Id => 1)), Router_Table.Id_Conflict);
      Natural_Assert.Eq (Self.Table.Get_Size, 2);
      Status_Assert.Eq (Self.Table.Add ((Registration_Id => 17, Command_Id => 19)), Router_Table.Success);
      Natural_Assert.Eq (Self.Table.Get_Size, 3);
      Status_Assert.Eq (Self.Table.Add ((Registration_Id => 12, Command_Id => 19)), Router_Table.Id_Conflict);
      Natural_Assert.Eq (Self.Table.Get_Size, 3);
      Status_Assert.Eq (Self.Table.Add ((Registration_Id => 7, Command_Id => 4)), Router_Table.Table_Full);
      Natural_Assert.Eq (Self.Table.Get_Size, 3);

      -- Search table for existing registrations:
      Lookup_Assert.Eq (Self.Table.Lookup_Registration_Id (0, Registration_Id), Router_Table.Success);
      Registration_Assert.Eq (Registration_Id, 19);
      Natural_Assert.Eq (Self.Table.Get_Size, 3);

      Lookup_Assert.Eq (Self.Table.Lookup_Registration_Id (19, Registration_Id), Router_Table.Success);
      Registration_Assert.Eq (Registration_Id, 17);
      Natural_Assert.Eq (Self.Table.Get_Size, 3);

      Lookup_Assert.Eq (Self.Table.Lookup_Registration_Id (1, Registration_Id), Router_Table.Success);
      Registration_Assert.Eq (Registration_Id, 36);
      Natural_Assert.Eq (Self.Table.Get_Size, 3);

      -- Search table for nonexistent registrations, verify sentinel value:
      Lookup_Assert.Eq (Self.Table.Lookup_Registration_Id (96, Registration_Id), Router_Table.Id_Not_Found);
      Registration_Assert.Eq (Registration_Id, Command_Types.Command_Registration_Id'Last);
      Natural_Assert.Eq (Self.Table.Get_Size, 3);

      Lookup_Assert.Eq (Self.Table.Lookup_Registration_Id (17, Registration_Id), Router_Table.Id_Not_Found);
      Registration_Assert.Eq (Registration_Id, Command_Types.Command_Registration_Id'Last);
      Natural_Assert.Eq (Self.Table.Get_Size, 3);

      Lookup_Assert.Eq (Self.Table.Lookup_Registration_Id (7, Registration_Id), Router_Table.Id_Not_Found);
      Registration_Assert.Eq (Registration_Id, Command_Types.Command_Registration_Id'Last);
      Natural_Assert.Eq (Self.Table.Get_Size, 3);

      -- Clear table:
      Self.Table.Clear;
      Natural_Assert.Eq (Self.Table.Get_Size, 0);
      Natural_Assert.Eq (Self.Table.Get_Capacity, 3);

      -- Verify lookup fails after clear for previously-added entries:
      Lookup_Assert.Eq (Self.Table.Lookup_Registration_Id (0, Ignore), Router_Table.Id_Not_Found);
      Lookup_Assert.Eq (Self.Table.Lookup_Registration_Id (1, Ignore), Router_Table.Id_Not_Found);
      Lookup_Assert.Eq (Self.Table.Lookup_Registration_Id (19, Ignore), Router_Table.Id_Not_Found);

      -- Verify re-add works after clear:
      Status_Assert.Eq (Self.Table.Add ((Registration_Id => 5, Command_Id => 42)), Router_Table.Success);
      Natural_Assert.Eq (Self.Table.Get_Size, 1);
      Lookup_Assert.Eq (Self.Table.Lookup_Registration_Id (42, Registration_Id), Router_Table.Success);
      Registration_Assert.Eq (Registration_Id, 5);
   end Add_To_Table;

   overriding procedure Single_Entry_Table (Self : in out Instance) is
      Tbl : Router_Table.Instance;
      Registration_Id : Command_Types.Command_Registration_Id;
   begin
      -- Initialize table with minimum capacity of 1:
      Tbl.Init (1);
      Natural_Assert.Eq (Tbl.Get_Size, 0);
      Natural_Assert.Eq (Tbl.Get_Capacity, 1);

      -- Add single entry:
      Status_Assert.Eq (Tbl.Add ((Registration_Id => 7, Command_Id => 99)), Router_Table.Success);
      Natural_Assert.Eq (Tbl.Get_Size, 1);

      -- Table should be full:
      Status_Assert.Eq (Tbl.Add ((Registration_Id => 8, Command_Id => 100)), Router_Table.Table_Full);
      Natural_Assert.Eq (Tbl.Get_Size, 1);

      -- Duplicate should still be rejected:
      Status_Assert.Eq (Tbl.Add ((Registration_Id => 9, Command_Id => 99)), Router_Table.Id_Conflict);

      -- Lookup the single entry:
      Lookup_Assert.Eq (Tbl.Lookup_Registration_Id (99, Registration_Id), Router_Table.Success);
      Registration_Assert.Eq (Registration_Id, 7);

      -- Lookup nonexistent entry:
      Lookup_Assert.Eq (Tbl.Lookup_Registration_Id (100, Registration_Id), Router_Table.Id_Not_Found);
      Registration_Assert.Eq (Registration_Id, Command_Types.Command_Registration_Id'Last);

      Tbl.Destroy;
   end Single_Entry_Table;

end Router_Table_Tests.Implementation;

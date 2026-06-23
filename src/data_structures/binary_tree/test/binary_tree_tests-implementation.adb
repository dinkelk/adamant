--------------------------------------------------------------------------------
-- Binary_Tree Tests Body
--------------------------------------------------------------------------------

with Ada.Unchecked_Deallocation;
with Basic_Assertions; use Basic_Assertions;
with Ada.Text_IO; use Ada.Text_IO;

package body Binary_Tree_Tests.Implementation is

   -------------------------------------------------------------------------
   -- Fixtures:
   -------------------------------------------------------------------------

   overriding procedure Set_Up_Test (Self : in out Instance) is
   begin
      Self.Tree := new Positive_B_Tree.Instance;
      Self.Tree.Init (10);
   end Set_Up_Test;

   overriding procedure Tear_Down_Test (Self : in out Instance) is
      procedure Free_Tree is new Ada.Unchecked_Deallocation (Object => Positive_B_Tree.Instance, Name => Positive_B_Tree.Instance_Access);
   begin
      Self.Tree.Destroy;
      Free_Tree (Self.Tree);
   end Tear_Down_Test;

   -------------------------------------------------------------------------
   -- Tests:
   -------------------------------------------------------------------------

   overriding procedure Test_Tree (Self : in out Instance) is
      Tree_Element : Positive;
      Ignore : Positive;
      Tree_Index : Positive;
      Ignore_Index : Positive;
   begin
      Put_Line ("Start Test_Tree...");
      -- Make sure tree looks good empty
      Natural_Assert.Eq (Self.Tree.Get_Capacity, 10);
      Natural_Assert.Eq (Self.Tree.Get_Size, 0);
      Natural_Assert.Eq (Self.Tree.Get_First_Index, 1);
      Natural_Assert.Eq (Self.Tree.Get_Last_Index, 0);
      Boolean_Assert.Eq (Positive_B_Tree_Tester.Issorted (Self.Tree.all), True);

      -- Search on pristine empty tree should return False:
      Boolean_Assert.Eq (Self.Tree.Search (42, Ignore, Ignore_Index), False);

      -- Fill up tree making sure the internals are sorted after each insertion:
      Boolean_Assert.Eq (Self.Tree.Add (16), True);
      Natural_Assert.Eq (Self.Tree.Get_Size, 1);
      Boolean_Assert.Eq (Positive_B_Tree_Tester.Issorted (Self.Tree.all), True);

      Boolean_Assert.Eq (Self.Tree.Add (7), True);
      Natural_Assert.Eq (Self.Tree.Get_Size, 2);
      Boolean_Assert.Eq (Positive_B_Tree_Tester.Issorted (Self.Tree.all), True);

      Boolean_Assert.Eq (Self.Tree.Add (1), True);
      Natural_Assert.Eq (Self.Tree.Get_Size, 3);
      Boolean_Assert.Eq (Positive_B_Tree_Tester.Issorted (Self.Tree.all), True);

      Boolean_Assert.Eq (Self.Tree.Add (12), True);
      Natural_Assert.Eq (Self.Tree.Get_Size, 4);
      Boolean_Assert.Eq (Positive_B_Tree_Tester.Issorted (Self.Tree.all), True);

      Boolean_Assert.Eq (Self.Tree.Add (100), True);
      Natural_Assert.Eq (Self.Tree.Get_Size, 5);
      Boolean_Assert.Eq (Positive_B_Tree_Tester.Issorted (Self.Tree.all), True);

      Boolean_Assert.Eq (Self.Tree.Add (50), True);
      Natural_Assert.Eq (Self.Tree.Get_Size, 6);
      Boolean_Assert.Eq (Positive_B_Tree_Tester.Issorted (Self.Tree.all), True);

      Boolean_Assert.Eq (Self.Tree.Add (35), True);
      Natural_Assert.Eq (Self.Tree.Get_Size, 7);
      Boolean_Assert.Eq (Positive_B_Tree_Tester.Issorted (Self.Tree.all), True);

      Boolean_Assert.Eq (Self.Tree.Add (17), True);
      Natural_Assert.Eq (Self.Tree.Get_Size, 8);
      Boolean_Assert.Eq (Positive_B_Tree_Tester.Issorted (Self.Tree.all), True);

      Boolean_Assert.Eq (Self.Tree.Add (110), True);
      Natural_Assert.Eq (Self.Tree.Get_Size, 9);
      Boolean_Assert.Eq (Positive_B_Tree_Tester.Issorted (Self.Tree.all), True);

      -- Duplicate element should be rejected:
      Boolean_Assert.Eq (Self.Tree.Add (17), False);
      Natural_Assert.Eq (Self.Tree.Get_Size, 9);
      Boolean_Assert.Eq (Positive_B_Tree_Tester.Issorted (Self.Tree.all), True);

      -- Fill to capacity:
      Boolean_Assert.Eq (Self.Tree.Add (200), True);
      Natural_Assert.Eq (Self.Tree.Get_Size, 10);
      Boolean_Assert.Eq (Positive_B_Tree_Tester.Issorted (Self.Tree.all), True);

      -- Tree is full, add should fail:
      Boolean_Assert.Eq (Self.Tree.Add (999), False);
      Natural_Assert.Eq (Self.Tree.Get_Size, 10);
      Boolean_Assert.Eq (Positive_B_Tree_Tester.Issorted (Self.Tree.all), True);

      -- Search the tree:
      -- Smallest Tree_Element:
      Boolean_Assert.Eq (Self.Tree.Search (1, Tree_Element, Tree_Index), True);
      Natural_Assert.Eq (Tree_Element, 1);
      Natural_Assert.Eq (Tree_Index, 1);

      -- Largest:
      Boolean_Assert.Eq (Self.Tree.Search (200, Tree_Element, Tree_Index), True);
      Natural_Assert.Eq (Tree_Element, 200);
      Natural_Assert.Eq (Tree_Index, 10);

      -- Medium:
      Boolean_Assert.Eq (Self.Tree.Search (16, Tree_Element, Ignore), True);
      Natural_Assert.Eq (Tree_Element, 16);
      Boolean_Assert.Eq (Self.Tree.Search (35, Tree_Element, Ignore), True);
      Natural_Assert.Eq (Tree_Element, 35);

      -- Unique element that was previously a duplicate test:
      Boolean_Assert.Eq (Self.Tree.Search (17, Tree_Element, Ignore), True);
      Natural_Assert.Eq (Tree_Element, 17);

      -- Non existent Tree_Elements:
      Boolean_Assert.Eq (Self.Tree.Search (2, Ignore, Ignore_Index), False);
      Boolean_Assert.Eq (Self.Tree.Search (11, Ignore, Ignore_Index), False);
      Boolean_Assert.Eq (Self.Tree.Search (27, Ignore, Ignore_Index), False);
      Boolean_Assert.Eq (Self.Tree.Search (56, Ignore, Ignore_Index), False);
      Boolean_Assert.Eq (Self.Tree.Search (8, Ignore, Ignore_Index), False);
      Boolean_Assert.Eq (Self.Tree.Search (10_001, Ignore, Ignore_Index), False);

      -- Test Get: retrieve elements by index after search
      Boolean_Assert.Eq (Self.Tree.Search (35, Tree_Element, Tree_Index), True);
      Natural_Assert.Eq (Self.Tree.Get (Tree_Index), 35);
      -- Get first and last elements:
      Natural_Assert.Eq (Self.Tree.Get (1), 1);
      Natural_Assert.Eq (Self.Tree.Get (10), 200);

      -- Test Set: replace element maintaining sorted order (Set now returns Boolean)
      -- Replace 35 with 36 (valid: neighbors are 17 and 50)
      Boolean_Assert.Eq (Self.Tree.Search (35, Tree_Element, Tree_Index), True);
      Boolean_Assert.Eq (Self.Tree.Set (Tree_Index, 36), True);
      Natural_Assert.Eq (Self.Tree.Get (Tree_Index), 36);
      Boolean_Assert.Eq (Positive_B_Tree_Tester.Issorted (Self.Tree.all), True);
      -- Try to set a value that would break sorted order (should fail):
      Boolean_Assert.Eq (Self.Tree.Set (Tree_Index, 999), False);
      -- Element should be unchanged:
      Natural_Assert.Eq (Self.Tree.Get (Tree_Index), 36);
      Boolean_Assert.Eq (Positive_B_Tree_Tester.Issorted (Self.Tree.all), True);
      -- Restore original value for remaining tests:
      Boolean_Assert.Eq (Self.Tree.Set (Tree_Index, 35), True);

      -- Test Set with out-of-bounds index (should fail):
      Boolean_Assert.Eq (Self.Tree.Set (11, 42), False);

      -- Clear the tree:
      Natural_Assert.Eq (Self.Tree.Get_Capacity, 10);
      Natural_Assert.Eq (Self.Tree.Get_Size, 10);
      Natural_Assert.Eq (Self.Tree.Get_First_Index, 1);
      Natural_Assert.Eq (Self.Tree.Get_Last_Index, 10);
      Self.Tree.Clear;
      Natural_Assert.Eq (Self.Tree.Get_Capacity, 10);
      Natural_Assert.Eq (Self.Tree.Get_Size, 0);
      Natural_Assert.Eq (Self.Tree.Get_First_Index, 1);
      Natural_Assert.Eq (Self.Tree.Get_Last_Index, 0);
      Put_Line ("Done.");
      Put_Line ("");
   end Test_Tree;

   overriding procedure Test_Tree_Removal (Self : in out Instance) is
      Ignore : Positive;
      Tree_Index : Positive;
      Ignore_Index : Positive;
   begin
      Put_Line ("Start Test_Tree_Removal...");
      -- Make sure tree looks good empty
      Natural_Assert.Eq (Self.Tree.Get_Capacity, 10);
      Natural_Assert.Eq (Self.Tree.Get_Size, 0);
      Boolean_Assert.Eq (Positive_B_Tree_Tester.Issorted (Self.Tree.all), True);

      -- Add Tree_Element
      Boolean_Assert.Eq (Self.Tree.Add (16), True);
      Natural_Assert.Eq (Self.Tree.Get_Size, 1);
      Boolean_Assert.Eq (Positive_B_Tree_Tester.Issorted (Self.Tree.all), True);

      -- Remove Tree_Element
      Boolean_Assert.Eq (Self.Tree.Search (16, Ignore, Tree_Index), True);
      Boolean_Assert.Eq (Self.Tree.Remove (Tree_Index), True);
      Natural_Assert.Eq (Self.Tree.Get_Size, 0);
      Boolean_Assert.Eq (Positive_B_Tree_Tester.Issorted (Self.Tree.all), True);
      -- Check index boundaries after removal to empty:
      Natural_Assert.Eq (Self.Tree.Get_First_Index, 1);
      Natural_Assert.Eq (Self.Tree.Get_Last_Index, 0);

      -- Add two Tree_Elements
      Boolean_Assert.Eq (Self.Tree.Add (16), True);
      Natural_Assert.Eq (Self.Tree.Get_Size, 1);
      Boolean_Assert.Eq (Self.Tree.Add (5), True);
      Natural_Assert.Eq (Self.Tree.Get_Size, 2);
      Boolean_Assert.Eq (Positive_B_Tree_Tester.Issorted (Self.Tree.all), True);

      -- Remove Tree_Element
      Boolean_Assert.Eq (Self.Tree.Search (16, Ignore, Tree_Index), True);
      Boolean_Assert.Eq (Self.Tree.Remove (Tree_Index), True);
      Natural_Assert.Eq (Self.Tree.Get_Size, 1);
      Boolean_Assert.Eq (Positive_B_Tree_Tester.Issorted (Self.Tree.all), True);
      -- Check index boundaries after partial removal:
      Natural_Assert.Eq (Self.Tree.Get_First_Index, 1);
      Natural_Assert.Eq (Self.Tree.Get_Last_Index, 1);

      -- Add two Tree_Elements
      Boolean_Assert.Eq (Self.Tree.Add (4), True);
      Natural_Assert.Eq (Self.Tree.Get_Size, 2);
      Boolean_Assert.Eq (Self.Tree.Add (6), True);
      Natural_Assert.Eq (Self.Tree.Get_Size, 3);
      Boolean_Assert.Eq (Positive_B_Tree_Tester.Issorted (Self.Tree.all), True);

      -- Remove Tree_Element
      Boolean_Assert.Eq (Self.Tree.Search (5, Ignore, Tree_Index), True);
      Boolean_Assert.Eq (Self.Tree.Remove (Tree_Index), True);
      Natural_Assert.Eq (Self.Tree.Get_Size, 2);
      Boolean_Assert.Eq (Positive_B_Tree_Tester.Issorted (Self.Tree.all), True);

      -- Add two Tree_Elements
      Boolean_Assert.Eq (Self.Tree.Add (99), True);
      Natural_Assert.Eq (Self.Tree.Get_Size, 3);
      Boolean_Assert.Eq (Self.Tree.Add (105), True);
      Natural_Assert.Eq (Self.Tree.Get_Size, 4);
      Boolean_Assert.Eq (Positive_B_Tree_Tester.Issorted (Self.Tree.all), True);

      -- Remove Tree_Element
      Boolean_Assert.Eq (Self.Tree.Search (4, Ignore, Tree_Index), True);
      Boolean_Assert.Eq (Self.Tree.Remove (Tree_Index), True);
      Natural_Assert.Eq (Self.Tree.Get_Size, 3);
      Boolean_Assert.Eq (Positive_B_Tree_Tester.Issorted (Self.Tree.all), True);

      -- Add two Tree_Elements
      Boolean_Assert.Eq (Self.Tree.Add (88), True);
      Natural_Assert.Eq (Self.Tree.Get_Size, 4);
      Boolean_Assert.Eq (Self.Tree.Add (3), True);
      Natural_Assert.Eq (Self.Tree.Get_Size, 5);
      Boolean_Assert.Eq (Positive_B_Tree_Tester.Issorted (Self.Tree.all), True);

      -- Remove Tree_Element
      Boolean_Assert.Eq (Self.Tree.Search (6, Ignore, Tree_Index), True);
      Boolean_Assert.Eq (Self.Tree.Remove (Tree_Index), True);
      Natural_Assert.Eq (Self.Tree.Get_Size, 4);
      Boolean_Assert.Eq (Positive_B_Tree_Tester.Issorted (Self.Tree.all), True);

      -- Remove Tree_Element that does not exist:
      Boolean_Assert.Eq (Self.Tree.Remove (5), False);
      Boolean_Assert.Eq (Self.Tree.Remove (6), False);
      Boolean_Assert.Eq (Self.Tree.Remove (100), False);

      -- Empty tree:
      Boolean_Assert.Eq (Self.Tree.Search (99, Ignore, Tree_Index), True);
      Boolean_Assert.Eq (Self.Tree.Remove (Tree_Index), True);
      Natural_Assert.Eq (Self.Tree.Get_Size, 3);
      Boolean_Assert.Eq (Positive_B_Tree_Tester.Issorted (Self.Tree.all), True);
      Boolean_Assert.Eq (Self.Tree.Search (3, Ignore, Tree_Index), True);
      Boolean_Assert.Eq (Self.Tree.Remove (Tree_Index), True);
      Natural_Assert.Eq (Self.Tree.Get_Size, 2);
      Boolean_Assert.Eq (Positive_B_Tree_Tester.Issorted (Self.Tree.all), True);
      Boolean_Assert.Eq (Self.Tree.Search (105, Ignore, Tree_Index), True);
      Boolean_Assert.Eq (Self.Tree.Remove (Tree_Index), True);
      Natural_Assert.Eq (Self.Tree.Get_Size, 1);
      Boolean_Assert.Eq (Positive_B_Tree_Tester.Issorted (Self.Tree.all), True);
      Boolean_Assert.Eq (Self.Tree.Search (88, Ignore, Tree_Index), True);
      Boolean_Assert.Eq (Self.Tree.Remove (Tree_Index), True);
      Natural_Assert.Eq (Self.Tree.Get_Size, 0);
      Boolean_Assert.Eq (Positive_B_Tree_Tester.Issorted (Self.Tree.all), True);

      -- Nothing in tree:
      Boolean_Assert.Eq (Self.Tree.Search (88, Ignore, Ignore_Index), False);
      Boolean_Assert.Eq (Self.Tree.Remove (1), False);
      Natural_Assert.Eq (Self.Tree.Get_Size, 0);
      Boolean_Assert.Eq (Positive_B_Tree_Tester.Issorted (Self.Tree.all), True);

      Put_Line ("Done.");
      Put_Line ("");
   end Test_Tree_Removal;
end Binary_Tree_Tests.Implementation;

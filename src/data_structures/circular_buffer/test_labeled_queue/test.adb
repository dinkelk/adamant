with Ada.Text_IO; use Ada.Text_IO;
with Circular_Buffer.Labeled_Queue;
with Basic_Types.Representation; use Basic_Types;
with Basic_Assertions; use Basic_Assertions;
with Smart_Assert;
with Static.Assertion; use Static.Assertion;
with Static.Representation;

procedure Test is
   package Labeled_Queue_Package is new Circular_Buffer.Labeled_Queue (Static.T);
   Heap_Queue : Labeled_Queue_Package.Instance;
   Data_Queue : Labeled_Queue_Package.Instance;
   Data : aliased Byte_Array := (0 .. 29 => 0);

   procedure Go (Q : in out Labeled_Queue_Package.Instance) is
      use Circular_Buffer;
      package Push_Assert is new Smart_Assert.Basic (Circular_Buffer.Push_Return_Status, Circular_Buffer.Push_Return_Status'Image);
      package Pop_Assert is new Smart_Assert.Basic (Circular_Buffer.Pop_Return_Status, Circular_Buffer.Pop_Return_Status'Image);
      Bytes : Byte_Array (0 .. 29) := (others => 0);
      Len : Natural;
      Max_Count : Natural := 0;

      procedure Check_Meta (Cnt : in Natural; Filename : in String := Smart_Assert.Sinfo.File; Line : in Natural := Smart_Assert.Sinfo.Line) is
      begin
         if Cnt > Max_Count then
            Max_Count := Cnt;
         end if;
         Natural_Assert.Eq (Q.Get_Count, Cnt, "Get_Count failed.", Filename, Line);
         Natural_Assert.Eq (Q.Get_Max_Count, Max_Count, "Get_Count failed.", Filename, Line);
      end Check_Meta;

      Label : Static.T := (1, 2, 3);
   begin
      Put_Line ("Check initial sizes.");
      Check_Meta (0);
      Pop_Assert.Eq (Q.Peek_Length (Len), Empty);
      Pop_Assert.Eq (Q.Peek_Label (Label), Empty);
      Pop_Assert.Eq (Q.Peek (Label, Bytes, Length => Len), Empty);
      Pop_Assert.Eq (Q.Pop (Label, Bytes, Length => Len), Empty);
      Pop_Assert.Eq (Q.Pop, Empty);
      Put_Line ("Passed.");
      Put_Line ("");

      Put_Line ("Small push, peek, and pop.");
      Push_Assert.Eq (Q.Push ((4, 5, 6), (1, 2, 3)), Success);
      Put_Line (Static.Representation.Image (Label));
      Put_Line (Basic_Types.Representation.Image (Data));
      Check_Meta (1);
      Pop_Assert.Eq (Q.Peek_Length (Len), Success);
      Pop_Assert.Eq (Q.Peek_Label (Label), Success);
      Static_Assert.Eq (Label, (4, 5, 6));
      Natural_Assert.Eq (Len, 3);
      Check_Meta (1);
      Len := 0;
      Label := (0, 0, 0);
      Pop_Assert.Eq (Q.Peek (Label, Bytes, Length => Len), Success);
      Static_Assert.Eq (Label, (4, 5, 6));
      Natural_Assert.Eq (Len, 3);
      Byte_Array_Assert.Eq (Bytes (0 .. Len - 1), (1, 2, 3));
      Check_Meta (1);
      Put_Line ("Passed.");
      Put_Line ("");

      Put_Line ("Peek and pop empty.");
      Q.Clear;
      Bytes := (others => 0);
      Pop_Assert.Eq (Q.Peek (Label, Bytes (1 .. 0), Length => Len), Empty);
      Natural_Assert.Eq (Len, 0);
      Pop_Assert.Eq (Q.Peek (Label, Bytes (0 .. 0), Length => Len), Empty);
      Natural_Assert.Eq (Len, 0);
      Byte_Array_Assert.Eq (Bytes, (0 .. 29 => 0));
      Check_Meta (0);
      Pop_Assert.Eq (Q.Pop (Label, Bytes (3 .. 3)), Empty);
      Byte_Array_Assert.Eq (Bytes, (0 .. 29 => 0));
      Check_Meta (0);
      Pop_Assert.Eq (Q.Pop, Empty);
      Put_Line ("Passed.");
      Put_Line ("");

      Put_Line ("Push, peek, and pop zero length arrays.");
      Q.Clear;
      Data := (others => 0);
      Push_Assert.Eq (Q.Push ((7, 9, 8), Bytes (1 .. 0)), Success);
      Check_Meta (1);
      Pop_Assert.Eq (Q.Peek_Label (Label), Success);
      Static_Assert.Eq (Label, (7, 9, 8));
      Pop_Assert.Eq (Q.Peek_Length (Len), Success);
      Natural_Assert.Eq (Len, 0);
      Check_Meta (1);
      Label := (0, 0, 0);
      Pop_Assert.Eq (Q.Peek (Label, Bytes (1 .. 0), Length => Len), Success);
      Static_Assert.Eq (Label, (7, 9, 8));
      Natural_Assert.Eq (Len, 0);
      Byte_Array_Assert.Eq (Bytes, (0 .. 29 => 0));
      Check_Meta (1);
      Label := (0, 0, 0);
      Pop_Assert.Eq (Q.Pop (Label, Bytes (3 .. 1), Length => Len), Success);
      Static_Assert.Eq (Label, (7, 9, 8));
      Natural_Assert.Eq (Len, 0);
      Byte_Array_Assert.Eq (Bytes, (0 .. 29 => 0));
      Check_Meta (0);
      Put_Line ("Passed.");
      Put_Line ("");

      Put_Line ("Push full.");
      Q.Clear;
      Push_Assert.Eq (Q.Push ((10, 10, 9), (1, 2, 3, 4, 5, 6, 7, 8, 9, 10)), Success);
      Check_Meta (1);
      Pop_Assert.Eq (Q.Peek (Label, Bytes (0 .. 9)), Success);
      Byte_Array_Assert.Eq (Bytes (0 .. 9), (1, 2, 3, 4, 5, 6, 7, 8, 9, 10));
      Put_Line ("Num_Bytes_Used: " & Natural'Image (Q.Num_Bytes_Used));
      Natural_Assert.Eq (Q.Num_Bytes_Used, 18);
      Push_Assert.Eq (Q.Push ((10, 10, 8), (3 .. 6 => 11)), Success);
      Check_Meta (2);
      Put_Line ("Num_Bytes_Used: " & Natural'Image (Q.Num_Bytes_Used));
      Natural_Assert.Eq (Q.Num_Bytes_Used, 30);
      Push_Assert.Eq (Q.Push ((10, 10, 7), (0 .. 0 => 5)), Too_Full);
      Put_Line ("Passed.");
      Put_Line ("");

      Put_Line ("Peek and pop too much.");
      Bytes := (others => 0);
      Label := (0, 0, 0);
      Pop_Assert.Eq (Q.Peek (Label, Bytes (0 .. 4), Length => Len), Success);
      Static_Assert.Eq (Label, (10, 10, 9));
      Natural_Assert.Eq (Len, 5);
      Byte_Array_Assert.Eq (Bytes (0 .. Len - 1), (1, 2, 3, 4, 5));
      Check_Meta (2);
      Label := (0, 0, 0);
      Pop_Assert.Eq (Q.Peek (Label, Bytes, Length => Len), Success);
      Static_Assert.Eq (Label, (10, 10, 9));
      Static_Assert.Eq (Label, (10, 10, 9));
      Natural_Assert.Eq (Len, 10);
      Byte_Array_Assert.Eq (Bytes (0 .. Len - 1), (1, 2, 3, 4, 5, 6, 7, 8, 9, 10));
      Check_Meta (2);
      Label := (0, 0, 0);
      Pop_Assert.Eq (Q.Peek (Label, Bytes, Length => Len, Offset => 2), Success);
      Static_Assert.Eq (Label, (10, 10, 9));
      Natural_Assert.Eq (Len, 8);
      Byte_Array_Assert.Eq (Bytes (0 .. Len - 1), (3, 4, 5, 6, 7, 8, 9, 10));
      Check_Meta (2);
      Label := (0, 0, 0);
      Pop_Assert.Eq (Q.Peek (Label, Bytes (0 .. 1), Length => Len, Offset => 2), Success);
      Static_Assert.Eq (Label, (10, 10, 9));
      Natural_Assert.Eq (Len, 2);
      Byte_Array_Assert.Eq (Bytes (0 .. Len - 1), (3, 4));
      Check_Meta (2);
      Label := (0, 0, 0);
      Pop_Assert.Eq (Q.Peek (Label, Bytes (0 .. 1), Length => Len, Offset => 9), Success);
      Static_Assert.Eq (Label, (10, 10, 9));
      Natural_Assert.Eq (Len, 1);
      Byte_Array_Assert.Eq (Bytes (0 .. Len - 1), (1 => 10));
      Check_Meta (2);
      Label := (0, 0, 0);
      Pop_Assert.Eq (Q.Peek (Label, Bytes (0 .. 1), Length => Len, Offset => 10), Success);
      Static_Assert.Eq (Label, (10, 10, 9));
      Natural_Assert.Eq (Len, 0);
      Check_Meta (2);
      Label := (0, 0, 0);
      Pop_Assert.Eq (Q.Peek (Label, Bytes (0 .. 1), Length => Len, Offset => 11), Success);
      Static_Assert.Eq (Label, (10, 10, 9));
      Natural_Assert.Eq (Len, 0);
      Check_Meta (2);
      Label := (0, 0, 0);
      Pop_Assert.Eq (Q.Peek (Label, Bytes (0 .. 1), Length => Len, Offset => 2_000), Success);
      Static_Assert.Eq (Label, (10, 10, 9));
      Natural_Assert.Eq (Len, 0);
      Check_Meta (2);
      Label := (0, 0, 0);
      Pop_Assert.Eq (Q.Peek (Label, Bytes (1 .. 0), Length => Len, Offset => 1), Success);
      Static_Assert.Eq (Label, (10, 10, 9));
      Natural_Assert.Eq (Len, 0);
      Check_Meta (2);
      Label := (0, 0, 0);
      Pop_Assert.Eq (Q.Pop (Label, Bytes (0 .. 6), Length => Len), Success);
      Static_Assert.Eq (Label, (10, 10, 9));
      Natural_Assert.Eq (Len, 7);
      Byte_Array_Assert.Eq (Bytes (0 .. Len - 1), (1, 2, 3, 4, 5, 6, 7));
      Check_Meta (1);
      Put_Line ("Num_Bytes_Used: " & Natural'Image (Q.Num_Bytes_Used));
      Natural_Assert.Eq (Q.Num_Bytes_Used, 12);
      Label := (0, 0, 0);
      Pop_Assert.Eq (Q.Pop (Label, Bytes (0 .. 3), Length => Len, Offset => 5), Success);
      Static_Assert.Eq (Label, (10, 10, 8));
      Natural_Assert.Eq (Len, 0);
      Check_Meta (0);
      Label := (0, 0, 0);
      Put_Line ("Num_Bytes_Used: " & Natural'Image (Q.Num_Bytes_Used));
      Natural_Assert.Eq (Q.Num_Bytes_Used, 0);
      Pop_Assert.Eq (Q.Peek (Label, Bytes), Empty);
      Check_Meta (0);
      Pop_Assert.Eq (Q.Pop (Label, Bytes), Empty);
      Check_Meta (0);
      Push_Assert.Eq (Q.Push ((10, 10, 2), (1, 2, 3, 4, 5, 6, 7, 8, 9, 10)), Success);
      Check_Meta (1);
      Label := (0, 0, 0);
      Pop_Assert.Eq (Q.Pop (Label, Bytes, Length => Len, Offset => 4), Success);
      Static_Assert.Eq (Label, (10, 10, 2));
      Natural_Assert.Eq (Len, 6);
      Byte_Array_Assert.Eq (Bytes (0 .. Len - 1), (5, 6, 7, 8, 9, 10));
      Check_Meta (0);
      Put_Line ("Passed.");
      Put_Line ("");

      Put_Line ("Push too much.");
      Push_Assert.Eq (Q.Push ((10, 10, 10), (0 .. 30 => 5)), Too_Full);
      Check_Meta (0);
      Put_Line ("Passed.");
      Put_Line ("");

      Put_Line ("Test rollover.");
      Q.Clear;
      Check_Meta (0);
      Push_Assert.Eq (Q.Push ((8, 8, 7), (0 .. 9 => 255, 10 .. 21 => 254)), Success);
      Put_Line ("Num_Bytes_Used: " & Natural'Image (Q.Num_Bytes_Used));
      Natural_Assert.Eq (Q.Num_Bytes_Used, 30);
      Put_Line (Basic_Types.Representation.Image (Data));
      Check_Meta (1);
      Label := (0, 0, 0);
      Pop_Assert.Eq (Q.Pop (Label, Bytes (0 .. 8)), Success);
      Static_Assert.Eq (Label, (8, 8, 7));
      Put_Line ("Num_Bytes_Used: " & Natural'Image (Q.Num_Bytes_Used));
      Natural_Assert.Eq (Q.Num_Bytes_Used, 0);
      Byte_Array_Assert.Eq (Bytes (0 .. 8), (0 .. 8 => 255));
      Check_Meta (0);
      Push_Assert.Eq (Q.Push ((7, 7, 6), (0 .. 9 => 10)), Success);
      Put_Line ("Num_Bytes_Used: " & Natural'Image (Q.Num_Bytes_Used));
      Natural_Assert.Eq (Q.Num_Bytes_Used, 18);
      Put_Line (Basic_Types.Representation.Image (Data));
      Check_Meta (1);
      Push_Assert.Eq (Q.Push ((6, 6, 5), (0 .. 2 => 11)), Success);
      Put_Line ("Num_Bytes_Used: " & Natural'Image (Q.Num_Bytes_Used));
      Natural_Assert.Eq (Q.Num_Bytes_Used, 29);
      Put_Line (Basic_Types.Representation.Image (Data));
      Check_Meta (2);
      Push_Assert.Eq (Q.Push ((5, 5, 4), (0 .. 9 => 12)), Too_Full);
      Natural_Assert.Eq (Q.Num_Bytes_Used, 29);
      Check_Meta (2);
      Label := (0, 0, 0);
      Pop_Assert.Eq (Q.Pop (Label, Bytes, Length => Len), Success);
      Static_Assert.Eq (Label, (7, 7, 6));
      Put_Line ("Num_Bytes_Used: " & Natural'Image (Q.Num_Bytes_Used));
      Natural_Assert.Eq (Q.Num_Bytes_Used, 11);
      Byte_Array_Assert.Eq (Bytes (0 .. Len - 1), (0 .. Len - 1 => 10));
      Check_Meta (1);
      -- Push, and cause rollover:
      Push_Assert.Eq (Q.Push ((4, 4, 3), (0 .. 7 => 12)), Success);
      Put_Line ("Num_Bytes_Used: " & Natural'Image (Q.Num_Bytes_Used));
      Natural_Assert.Eq (Q.Num_Bytes_Used, 27);
      Put_Line (Basic_Types.Representation.Image (Data));
      Check_Meta (2);
      Push_Assert.Eq (Q.Push ((3, 3, 3), (0 .. 0 => 12)), Too_Full);
      Check_Meta (2);
      -- Pop and check:
      Pop_Assert.Eq (Q.Peek_Label (Label), Success);
      Static_Assert.Eq (Label, (6, 6, 5));
      Pop_Assert.Eq (Q.Pop, Success);
      -- Pop_Assert.eq(Q.Pop(bytes, Length => len), Success);
      Put_Line ("Num_Bytes_Used: " & Natural'Image (Q.Num_Bytes_Used));
      Natural_Assert.Eq (Q.Num_Bytes_Used, 16);
      -- Byte_Array_Assert.eq(bytes(0 .. len - 1), (0 .. len - 1 => 11));
      Check_Meta (1);
      Pop_Assert.Eq (Q.Peek_Label (Label), Success);
      Static_Assert.Eq (Label, (4, 4, 3));
      Pop_Assert.Eq (Q.Pop (Label, Bytes, Length => Len), Success);
      Static_Assert.Eq (Label, (4, 4, 3));
      Put_Line ("Num_Bytes_Used: " & Natural'Image (Q.Num_Bytes_Used));
      Natural_Assert.Eq (Q.Num_Bytes_Used, 0);
      Byte_Array_Assert.Eq (Bytes (0 .. Len - 1), (0 .. Len - 1 => 12));
      Check_Meta (0);
      Put_Line ("Passed.");
      Put_Line ("");

   end Go;
begin
   Put_Line ("Create heap queue.");
   Heap_Queue.Init (30);
   Put_Line ("Passed.");
   Put_Line ("");

   Put_Line ("----------------------------------");
   Put_Line ("Testing heap queue.");
   Put_Line ("----------------------------------");
   Go (Heap_Queue);
   Put_Line ("----------------------------------");
   Put_Line ("");

   Put_Line ("Destroy heap queue.");
   Heap_Queue.Destroy;
   Put_Line ("Passed.");
   Put_Line ("");

   Put_Line ("Create data queue.");
   Data_Queue.Init (Data'Unchecked_Access);
   Put_Line ("Passed.");
   Put_Line ("");

   Put_Line ("----------------------------------");
   Put_Line ("Testing data queue.");
   Put_Line ("----------------------------------");
   Go (Data_Queue);
   Put_Line ("----------------------------------");
   Put_Line ("");

   Put_Line ("Destroy data queue.");
   Data_Queue.Destroy;
   Put_Line ("Passed.");
end Test;

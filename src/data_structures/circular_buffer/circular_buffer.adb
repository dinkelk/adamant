with Safe_Deallocator;
with Circular_Buffer.Core;

package body Circular_Buffer with SPARK_Mode => On is

   -- See the note in the package specification. All contracts and ghost code
   -- are for proof only and are disabled at runtime:
   pragma Assertion_Policy
      (Pre => Ignore,
       Pre'Class => Ignore,
       Post => Ignore,
       Post'Class => Ignore,
       Contract_Cases => Ignore,
       Ghost => Ignore,
       Loop_Invariant => Ignore,
       Loop_Variant => Ignore,
       Assert_And_Cut => Ignore,
       Subprogram_Variant => Ignore);

   --
   -- Subprograms for Base
   --

   -- The body is not analyzed by SPARK since assigning a new allocation over
   -- a potentially reused access value is outside the SPARK ownership model.
   -- The postcondition holds because the callers obeying the precondition
   -- provide a reset buffer, and the allocation below is zero indexed with
   -- the requested positive size.
   procedure Init (Self : in out Base; Size : in Natural) with SPARK_Mode => Off is
   begin
      Self.Bytes := new Basic_Types.Byte_Array (0 .. Size - 1);
      Self.Allocated := True;
   end Init;

   -- The body is not analyzed by SPARK since it adopts caller provided,
   -- possibly aliased memory, which is outside the SPARK ownership model.
   -- The assertions below check the properties of the provided memory that
   -- the postcondition promises to the proof, except for the maximum size
   -- bound, which is also asserted. This project always builds with
   -- assertions enabled, so these checks are live at runtime.
   procedure Init (Self : in out Base; Bytes : in not null Basic_Types.Byte_Array_Access) with SPARK_Mode => Off is
   begin
      Self.Bytes := Bytes;
      pragma Assert (Self.Bytes.all'First = Natural'First, "Must be zero indexed.");
      pragma Assert (Self.Bytes.all'Last >= Natural'First, "Must be zero indexed.");
      pragma Assert (Self.Bytes.all'Length <= Max_Buffer_Size, "Buffer size is outside the verified domain.");
      Self.Allocated := False;
   end Init;

   -- The body is not analyzed by SPARK since conditional deallocation of
   -- possibly adopted memory is outside the SPARK ownership model. The
   -- postcondition holds because Clear resets the head and count below.
   procedure Destroy (Self : in out Base) with SPARK_Mode => Off is
      procedure Free_If_Testing is new Safe_Deallocator.Deallocate_If_Testing (Object => Basic_Types.Byte_Array, Name => Basic_Types.Byte_Array_Access);
   begin
      if Self.Allocated then
         Free_If_Testing (Self.Bytes);
         Self.Allocated := False;
      end if;
      Self.Clear;
      -- Reset state:
      Self.Max_Count := 0;
   end Destroy;

   procedure Clear (Self : in out Base) is
   begin
      Self.Head := 0;
      Self.Count := 0;
   end Clear;

   function Is_Full (Self : in Base) return Boolean is
   begin
      return Self.Count = Self.Bytes'Length;
   end Is_Full;

   function Is_Empty (Self : in Base) return Boolean is
   begin
      return Self.Count = 0;
   end Is_Empty;

   function Num_Bytes_Free (Self : in Base) return Natural is
   begin
      return Self.Bytes'Length - Self.Count;
   end Num_Bytes_Free;

   function Num_Bytes_Used (Self : in Base) return Natural is
   begin
      return Self.Count;
   end Num_Bytes_Used;

   function Max_Num_Bytes_Used (Self : in Base) return Natural is
   begin
      return Self.Max_Count;
   end Max_Num_Bytes_Used;

   function Num_Bytes_Total (Self : in Base) return Natural is
   begin
      return Self.Bytes'Length;
   end Num_Bytes_Total;

   function Current_Percent_Used (Self : in Base) return Basic_Types.Byte is
   begin
      if Self.Bytes /= null and then Self.Bytes'Length > 0 then
         -- A count so large that the multiplication below would overflow
         -- means the buffer is essentially full. Before the SPARK conversion
         -- this case raised Constraint_Error and was mapped to 100 by an
         -- exception handler, which SPARK does not allow. The explicit check
         -- returns the same result on the same inputs:
         if Self.Count > Integer'Last / 100 then
            return 100;
         end if;
         declare
            Usage : constant Integer := (Self.Count * 100) / Self.Bytes'Length;
         begin
            if Usage < 100 then
               return Basic_Types.Byte (Usage);
            else
               return 100;
            end if;
         end;
      else
         return 0;
      end if;
   end Current_Percent_Used;

   function Max_Percent_Used (Self : in Base) return Basic_Types.Byte is
   begin
      if Self.Bytes /= null and then Self.Bytes'Length > 0 then
         -- See the comment in Current_Percent_Used above. This check
         -- replicates the behavior of the removed exception handler:
         if Self.Max_Count > Integer'Last / 100 then
            return 100;
         end if;
         declare
            Usage : constant Integer := (Self.Max_Count * 100) / Self.Bytes'Length;
         begin
            if Usage < 100 then
               return Basic_Types.Byte (Usage);
            else
               return 100;
            end if;
         end;
      else
         return 0;
      end if;
   end Max_Percent_Used;

   function Get_Meta_Data (Self : in Base) return Circular_Buffer_Meta.T is
   begin
      return (Head => Interfaces.Unsigned_32 (Self.Head), Count => Interfaces.Unsigned_32 (Self.Count), Size => Interfaces.Unsigned_32 (Self.Bytes'Length));
   end Get_Meta_Data;

   -- Declaration provides the contract that the callers below are proved
   -- against:
   function Do_Dump (Self : in Base; Head : in Natural; Tail : in Natural) return Pointer_Dump
      with Pre => Valid (Self) and then (if Self.Count > 0 then Head < Self.Bytes'Length and then Tail < Self.Bytes'Length);

   -- The body is not analyzed by SPARK since it hands out addresses of the
   -- internal buffer through the Byte_Array_Pointer abstraction:
   function Do_Dump (Self : in Base; Head : in Natural; Tail : in Natural) return Pointer_Dump with SPARK_Mode => Off is
      To_Return : Pointer_Dump;
   begin
      if Self.Count > 0 then
         -- This function assumes head and tail are in range at this point.
         pragma Assert (Head in Self.Bytes'Range, "Caller must ensure head is in range.");
         pragma Assert (Tail in Self.Bytes'Range, "Caller must ensure tail is in range.");
         -- Dump between head and tail, no wrap around:
         if Tail > Head then
            -- Fill the first pointer with the entire memory:
            To_Return (0) := Byte_Array_Pointer.From_Address (Self.Bytes (Head)'Address, Size => Tail - Head);
            To_Return (1) := Byte_Array_Pointer.Null_Pointer;
         else
            -- Fill the first pointer with the memory to the end:
            To_Return (0) := Byte_Array_Pointer.From_Address (Self.Bytes (Head)'Address, Size => Self.Bytes'Last - Head + 1);
            -- Fill the second pointer with the memory at the beginning:
            To_Return (1) := Byte_Array_Pointer.From_Address (Self.Bytes (Self.Bytes'First)'Address, Size => Tail - Self.Bytes'First);
         end if;
      end if;
      return To_Return;
   end Do_Dump;

   function Dump (Self : in Base) return Pointer_Dump is
      Tail : constant Natural := (Self.Head + Self.Count) mod Self.Bytes'Length;
   begin
      return Do_Dump (Self, Self.Head, Tail);
   end Dump;

   function Dump_Newest (Self : in Base; Num_Bytes_To_Dump : in Natural) return Pointer_Dump is
      Bytes_To_Dump : Natural := Num_Bytes_To_Dump;
   begin
      -- Cap the maximum number of bytes to dump at the count:
      if Bytes_To_Dump > Self.Count then
         Bytes_To_Dump := Self.Count;
      end if;

      if Bytes_To_Dump > 0 then
         declare
            -- Calculate new head that starts Num_Bytes_To_Dump in front of the tail:
            New_Head : constant Natural := (Self.Head + (Self.Count - Bytes_To_Dump)) mod Self.Bytes'Length;
            Tail : constant Natural := (Self.Head + Self.Count) mod Self.Bytes'Length;
         begin
            return Do_Dump (Self, New_Head, Tail);
         end;
      end if;

      return [Byte_Array_Pointer.Null_Pointer, Byte_Array_Pointer.Null_Pointer];
   end Dump_Newest;

   function Dump_Oldest (Self : in Base; Num_Bytes_To_Dump : in Natural) return Pointer_Dump is
      Bytes_To_Dump : Natural := Num_Bytes_To_Dump;
   begin
      -- Cap the maximum number of bytes to dump at the count:
      if Bytes_To_Dump > Self.Count then
         Bytes_To_Dump := Self.Count;
      end if;

      if Bytes_To_Dump > 0 then
         declare
            -- Calculate new tail that starts Num_Bytes_To_Dump behind the head:
            Tail : constant Natural := (Self.Head + Self.Count) mod Self.Bytes'Length;
            New_Tail : constant Natural := (Tail - (Self.Count - Bytes_To_Dump)) mod Self.Bytes'Length;
         begin
            return Do_Dump (Self, Self.Head, New_Tail);
         end;
      end if;

      return [Byte_Array_Pointer.Null_Pointer, Byte_Array_Pointer.Null_Pointer];
   end Dump_Oldest;

   -- The body is not analyzed by SPARK since it hands out addresses of the
   -- internal buffer through the Byte_Array_Pointer abstraction:
   function Dump_Memory (Self : in Base) return Pointer_Dump with SPARK_Mode => Off is
      To_Return : Pointer_Dump;
   begin
      -- Fill the first pointer with the entire memory:
      To_Return (0) := Byte_Array_Pointer.From_Address (Self.Bytes (Self.Bytes'First)'Address, Size => Self.Bytes'Length);
      To_Return (1) := Byte_Array_Pointer.Null_Pointer;
      return To_Return;
   end Dump_Memory;

   --
   -- Subprograms for Circular
   --

   function Push (Self : in out Circular; Bytes : in Basic_Types.Byte_Array; Overwrite : in Boolean := False) return Push_Status is
      Stat : Push_Status;
   begin
      Stat := Core.Push (Base (Self), Bytes, Overwrite);
      return Stat;
   end Push;

   function Pop (Self : in out Circular; Bytes : in out Basic_Types.Byte_Array; Num_Bytes_Returned : out Natural) return Pop_Status is
      Stat : Pop_Status;
   begin
      Stat := Core.Pop (Base (Self), Bytes, Num_Bytes_Returned);
      return Stat;
   end Pop;

   function Peek (Self : in Circular; Bytes : in out Basic_Types.Byte_Array; Num_Bytes_Returned : out Natural; Offset : in Natural := 0) return Pop_Status is
      Stat : Pop_Status;
   begin
      Stat := Core.Peek (Base (Self), Bytes, Num_Bytes_Returned, Offset);
      return Stat;
   end Peek;

   procedure Make_Full (Self : in out Circular; Head_Index : Natural := 0) is
   begin
      Self.Head := Head_Index mod Self.Bytes'Length;
      Self.Count := Self.Bytes'Length;
   end Make_Full;

   --
   -- Subprograms for Queue Base
   --
   --

   --
   -- Ghost lemma bodies. These perform the inductions over the record walk
   -- that the queue subprogram proofs below rely on. None of this code is
   -- ever compiled or executed:
   --

   procedure Lemma_Wrap_Offsets (Head : in Natural; Base_Offset : in Natural; Span : in Natural; Size : in Natural) is
   begin
      -- Follows from the definition of Wrap_Index by linear case analysis:
      null;
   end Lemma_Wrap_Offsets;

   procedure Lemma_CP_Tail (B_Old : in Basic_Types.Byte_Array; B_New : in Basic_Types.Byte_Array; Head : in Natural; Offset : in Natural; Span : in Natural) is
   begin
      if Span > 0 then
         Lemma_CP_Tail (B_Old, B_New, Head, Offset, Span - 1);
         declare
            Size : constant Natural := B_Old'Length;
            Sub_Head : constant Natural := Wrap_Index (Head, Offset, Size);
            K : constant Natural := Span - 1;
         begin
            pragma Assert (B_New'Length = Size);
            pragma Assert (Wrap_Index (Sub_Head, K, Size) = Wrap_Index (Head, Offset + K, Size));
            pragma Assert (Element_At (B_New, Head, Offset + K) = Element_At (B_Old, Head, Offset + K));
            pragma Assert (Element_At (B_New, Sub_Head, K) = Element_At (B_Old, Sub_Head, K));
         end;
      end if;
   end Lemma_CP_Tail;

   procedure Lemma_Records_Frame (B_Old : in Basic_Types.Byte_Array; B_New : in Basic_Types.Byte_Array; Head : in Natural; Count : in Natural; Items : in Natural; Min : in Natural) is
   begin
      if Items > 0 then
         declare
            Element_Length : constant Natural := Header_Length (B_Old, Head);
            Offset : constant Natural := Queue_Element_Storage_Overhead + Element_Length;
            New_Head : constant Natural := Wrap_Index (Head, Offset, B_Old'Length);
            New_Count : constant Natural := Count - Offset;
         begin
            -- The header bytes lie within the preserved region, so the head
            -- record reads back identically:
            pragma Assert (Header_U32 (B_New, Head) = Header_U32 (B_Old, Head));
            -- The tail of the record walk lies within the preserved region
            -- as well:
            Lemma_CP_Tail (B_Old, B_New, Head, Offset, New_Count);
            Lemma_Records_Frame (B_Old, B_New, New_Head, New_Count, Items - 1, Min);
         end;
      end if;
   end Lemma_Records_Frame;

   procedure Lemma_Records_Append (Bytes : in Basic_Types.Byte_Array; Head : in Natural; Count : in Natural; Items : in Natural; Min : in Natural; New_Length : in Natural) is
   begin
      if Items = 0 then
         -- The walk is empty, so the appended record starts at the head
         -- index and is followed by an empty walk:
         pragma Assert (Count = 0);
         pragma Assert (Wrap_Index (Head, 0, Bytes'Length) = Head);
         pragma Assert (Header_Length (Bytes, Head) = New_Length);
         pragma Assert (Records_Ok (Bytes, Wrap_Index (Head, Queue_Element_Storage_Overhead + New_Length, Bytes'Length), 0, 0));
      else
         declare
            Element_Length : constant Natural := Header_Length (Bytes, Head);
            New_Head : constant Natural := Wrap_Index (Head, Queue_Element_Storage_Overhead + Element_Length, Bytes'Length);
            New_Count : constant Natural := Count - Queue_Element_Storage_Overhead - Element_Length;
         begin
            -- The tail position of the shorter walk is the same buffer
            -- index, so the appended record sits at its end too:
            pragma Assert (Wrap_Index (New_Head, New_Count, Bytes'Length) = Wrap_Index (Head, Count, Bytes'Length));
            Lemma_Records_Append (Bytes, New_Head, New_Count, Items - 1, Min, New_Length);
         end;
      end if;
   end Lemma_Records_Append;

   procedure Lemma_Records_Pop (Bytes : in Basic_Types.Byte_Array; Head : in Natural; Count : in Natural; Items : in Natural; New_Head : in Natural; New_Count : in Natural) is
      Element_Length : constant Natural := Header_Length (Bytes, Head);
      Walk_Head : constant Natural := Wrap_Index (Head, Queue_Element_Storage_Overhead + Element_Length, Bytes'Length);
   begin
      pragma Assert (New_Count = Count - Queue_Element_Storage_Overhead - Element_Length);
      if New_Count = 0 then
         -- The remaining walk is empty, so it must hold zero records, and
         -- the model holds at any head index:
         pragma Assert (Records_Ok (Bytes, Walk_Head, 0, Items - 1));
         pragma Assert (Items - 1 = 0);
      end if;
      pragma Assert (Records_Ok (Bytes, New_Head, New_Count, Items - 1));
   end Lemma_Records_Pop;

   procedure Lemma_Records_Head (Bytes : in Basic_Types.Byte_Array; Head : in Natural; Count : in Natural; Items : in Natural) is
   begin
      -- Follows from one unfolding of Records_Ok:
      null;
   end Lemma_Records_Head;

   procedure Lemma_Header_Read (Bytes : in Basic_Types.Byte_Array; Head : in Natural; Header_Bytes : in Length_Byte_Array) is
   begin
      -- Follows from the definitions of Header_U32 and Compose:
      null;
   end Lemma_Header_Read;

   procedure Lemma_Header_Written (Bytes : in Basic_Types.Byte_Array; Head : in Natural; Count : in Natural; Header_Bytes : in Length_Byte_Array) is
      Tail : constant Natural := Wrap_Index (Head, Count, Bytes'Length);
   begin
      -- The wrapped positions of the header bytes coincide with the
      -- positions behind the head index where they were written:
      Lemma_Wrap_Offsets (Head, Count, Queue_Element_Storage_Overhead, Bytes'Length);
      pragma Assert
         (for all J in 0 .. Queue_Element_Storage_Overhead - 1 =>
            Wrap_Index (Tail, J, Bytes'Length) = Wrap_Index (Head, Count + J, Bytes'Length));
      pragma Assert
         (for all J in 0 .. Queue_Element_Storage_Overhead - 1 =>
            Element_At (Bytes, Tail, J) = Header_Bytes (J));
   end Lemma_Header_Written;

   procedure Lemma_Content_Chain (B_First : in Basic_Types.Byte_Array; B_Second : in Basic_Types.Byte_Array; B_Third : in Basic_Types.Byte_Array; Head : in Natural; Count_First : in Natural; Count_Second : in Natural) is
   begin
      -- Pointwise chaining of the two preservation facts:
      pragma Assert (Count_First <= Count_Second);
      pragma Assert
         (for all K in 0 .. Count_First - 1 =>
            Element_At (B_Third, Head, K) = Element_At (B_Second, Head, K));
      pragma Assert
         (for all K in 0 .. Count_First - 1 =>
            Element_At (B_Second, Head, K) = Element_At (B_First, Head, K));
   end Lemma_Content_Chain;

   procedure Lemma_Header_Preserved (B_Old : in Basic_Types.Byte_Array; B_New : in Basic_Types.Byte_Array; Head : in Natural; Count : in Natural) is
      Size : constant Natural := B_Old'Length;
      Tail : constant Natural := Wrap_Index (Head, Count, Size);
   begin
      pragma Assert (B_New'Length = Size);
      -- Each header byte position behind the tail index coincides with a
      -- position within the preserved window behind the head index:
      pragma Assert (Wrap_Index (Tail, 0, Size) = Wrap_Index (Head, Count + 0, Size));
      pragma Assert (Wrap_Index (Tail, 1, Size) = Wrap_Index (Head, Count + 1, Size));
      pragma Assert (Wrap_Index (Tail, 2, Size) = Wrap_Index (Head, Count + 2, Size));
      pragma Assert (Wrap_Index (Tail, 3, Size) = Wrap_Index (Head, Count + 3, Size));
      pragma Assert (Element_At (B_New, Head, Count + 0) = Element_At (B_Old, Head, Count + 0));
      pragma Assert (Element_At (B_New, Head, Count + 1) = Element_At (B_Old, Head, Count + 1));
      pragma Assert (Element_At (B_New, Head, Count + 2) = Element_At (B_Old, Head, Count + 2));
      pragma Assert (Element_At (B_New, Head, Count + 3) = Element_At (B_Old, Head, Count + 3));
      pragma Assert (Element_At (B_New, Tail, 0) = Element_At (B_Old, Tail, 0));
      pragma Assert (Element_At (B_New, Tail, 1) = Element_At (B_Old, Tail, 1));
      pragma Assert (Element_At (B_New, Tail, 2) = Element_At (B_Old, Tail, 2));
      pragma Assert (Element_At (B_New, Tail, 3) = Element_At (B_Old, Tail, 3));
   end Lemma_Header_Preserved;

   procedure Lemma_Records_Count_Bound (Bytes : in Basic_Types.Byte_Array; Head : in Natural; Count : in Natural; Items : in Natural) is
   begin
      if Items > 0 then
         Lemma_Records_Count_Bound
            (Bytes,
             Wrap_Index (Head, Queue_Element_Storage_Overhead + Header_Length (Bytes, Head), Bytes'Length),
             Count - Queue_Element_Storage_Overhead - Header_Length (Bytes, Head),
             Items - 1);
      end if;
   end Lemma_Records_Count_Bound;

   function Peek_Length (Self : in Queue_Base; Length : out Natural) return Pop_Status is
      Stat : Pop_Status;
   begin
      Stat := Core.Do_Peek_Length (Self, Length);
      return Stat;
   end Peek_Length;

   function Pop (Self : in out Queue_Base) return Pop_Status is
      Element_Length : Natural;
      Stat : Pop_Status;
   begin
      Stat := Core.Do_Peek_Length (Self, Element_Length);

      -- Check return status:
      if Stat /= Success then
         return Stat;
      end if;

      Core.Do_Pop (Self, Element_Length);

      return Success;
   end Pop;

   function Get_Count (Self : in Queue_Base) return Natural is
   begin
      return Self.Item_Count;
   end Get_Count;

   function Get_Max_Count (Self : in Queue_Base) return Natural is
   begin
      return Self.Item_Max_Count;
   end Get_Max_Count;

   overriding procedure Clear (Self : in out Queue_Base) is
   begin
      -- Call the base class implementation:
      Clear (Base (Self));
      -- Clear the item count:
      Self.Item_Count := 0;
   end Clear;

   overriding procedure Destroy (Self : in out Queue_Base) is
   begin
      Base (Self).Destroy;
      -- Reset state:
      Self.Item_Count := 0;
      Self.Item_Max_Count := 0;
   end Destroy;

   --
   -- Subprograms for Queue
   --
   --

   function Push (Self : in out Queue; Bytes : in Basic_Types.Byte_Array) return Push_Status is
      Old_Bytes : constant Basic_Types.Byte_Array := Self.Bytes.all with Ghost;
      Old_Count : constant Natural := Self.Count with Ghost;
      Old_Items : constant Natural := Self.Item_Count with Ghost;
      Stat : Push_Status;
   begin
      Stat := Core.Push_Length (Queue_Base (Self), Bytes'Length);

      -- Check return status:
      if Stat /= Success then
         -- Ghost: nothing changed, so the record model is preserved:
         Lemma_Records_Frame (Old_Bytes, Self.Bytes.all, Self.Head, Old_Count, Old_Items, 0);
         return Stat;
      end if;

      declare
         Mid_Bytes : constant Basic_Types.Byte_Array := Self.Bytes.all with Ghost;
      begin
         -- Push the data bytes on to buffer:
         Stat := Core.Push (Base (Self), Bytes);
         pragma Assert (Stat = Success, "Pushing bytes failed. This can only be false if there is a software bug.");

         -- Ghost: the old records survived both pushes untouched, and the
         -- header and payload just pushed form one more record at the tail:
         Lemma_Content_Chain (Old_Bytes, Mid_Bytes, Self.Bytes.all, Self.Head, Old_Count, Old_Count + Queue_Element_Storage_Overhead);
         Lemma_Header_Preserved (Mid_Bytes, Self.Bytes.all, Self.Head, Old_Count);
         Lemma_Records_Frame (Old_Bytes, Self.Bytes.all, Self.Head, Old_Count, Old_Items, 0);
         Lemma_Records_Append (Self.Bytes.all, Self.Head, Old_Count, Old_Items, 0, Bytes'Length);
      end;

      return Success;
   end Push;

   function Do_Peek (Self : in Queue; Bytes : in out Basic_Types.Byte_Array; Length : out Natural; Element_Length : out Natural; Offset : in Natural := 0) return Pop_Status
      with Side_Effects,
           Pre => Queue_Valid (Self),
           Post => (if Self.Item_Count = 0 then Do_Peek'Result = Empty
                    else Do_Peek'Result = Success
                       and then Element_Length = Header_Length (Self.Bytes.all, Self.Head))
   is
      Stat : Pop_Status;
   begin
      -- Initialize the element length to zero:
      Element_Length := 0;

      Stat := Core.Do_Peek_Length (Queue_Base (Self), Length);

      -- Check return status:
      if Stat /= Success then
         return Stat;
      end if;

      -- Save element length, since we are going to modify "length" to
      -- correspond to the length of the returned data, not the length
      -- of the actual item on the queue:
      Element_Length := Length;

      -- Read the bytes from the queue:
      if Element_Length > 0 then
         Core.Peek_Bytes (Queue_Base (Self), Bytes, Element_Length, Length, Offset);
      end if;

      return Success;
   end Do_Peek;

   function Peek (Self : in Queue; Bytes : in out Basic_Types.Byte_Array; Length : out Natural; Offset : in Natural := 0) return Pop_Status is
      Ignore : Natural;
      Stat : Pop_Status;
   begin
      Stat := Self.Do_Peek (Bytes, Length, Ignore, Offset);
      return Stat;
   end Peek;

   function Pop (Self : in out Queue; Bytes : in out Basic_Types.Byte_Array; Length : out Natural; Offset : in Natural := 0) return Pop_Status is
      -- Peek some bytes:
      Element_Length : Natural;
      Stat : Pop_Status;
   begin
      Stat := Self.Do_Peek (Bytes, Length, Element_Length, Offset);

      -- Check return status:
      if Stat /= Success then
         return Stat;
      end if;

      -- Pop the bytes from the base:
      Core.Do_Pop (Queue_Base (Self), Element_Length);

      return Success;
   end Pop;

end Circular_Buffer;

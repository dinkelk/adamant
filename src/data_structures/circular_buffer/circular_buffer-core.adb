package body Circular_Buffer.Core with SPARK_Mode => On is

   -- See the note in the parent specification. All contracts and ghost code
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

   function Push (Self : in out Base; Bytes : in Basic_Types.Byte_Array; Overwrite : in Boolean := False) return Push_Status is
      Tail : constant Natural := (Self.Head + Self.Count) mod Self.Bytes'Length;
      -- The length attribute handles empty arrays gracefully, returning zero:
      Bytes_Length : constant Natural := Bytes'Length;
   begin
      pragma Assert (Self.Bytes.all'First = Natural'First, "Must be zero indexed.");
      pragma Assert (Self.Bytes.all'Last >= Natural'First, "Must be zero indexed.");
      pragma Assert (Tail <= Self.Bytes'Last, "This must be True by design.");

      -- There is nothing to copy:
      if Bytes_Length = 0 then
         return Success;
      end if;

      -- Make there is enough free bytes left:
      if Bytes_Length > Self.Bytes'Length or else (not Overwrite and then Self.Bytes'Length - Self.Count < Bytes_Length) then
         return Too_Full;
      end if;

      -- Relate the modular tail computation to the conditional form used by
      -- the ghost wrap index model. This assertion is proved and is trivial
      -- at runtime:
      pragma Assert (Tail = (if Self.Head + Self.Count < Self.Bytes'Length then Self.Head + Self.Count else Self.Head + Self.Count - Self.Bytes'Length));

      declare
         -- The inclusive end index of a single copy. This is computed after
         -- the size checks above so that the sum cannot overflow for very
         -- long input arrays. Before the SPARK conversion it was computed
         -- unconditionally, where an enormous input array could overflow the
         -- sum and raise Constraint_Error instead of returning Too_Full:
         End_Index : constant Integer := Tail + Bytes_Length - 1;
      begin
         -- Set the correct end index if a roll over is going to happen:
         if End_Index > Self.Bytes'Last then
            declare
               -- Calculate lengths of first and second copies:
               First_Copy_Length : constant Positive := Self.Bytes'Last - Tail + 1;
               Second_Copy_Length : constant Positive := Bytes_Length - First_Copy_Length;
            begin
               -- The addition of the two copies should make sense:
               pragma Assert (First_Copy_Length + Second_Copy_Length = Bytes_Length);
               -- Perform first copy to end of internal array:
               Self.Bytes (Tail .. Self.Bytes'Last) := Bytes (Bytes'First .. Bytes'First + First_Copy_Length - 1);
               -- Wrap around and copy bytes at beginning of internal array:
               Self.Bytes (Self.Bytes'First .. Self.Bytes'First + Second_Copy_Length - 1) := Bytes (Bytes'First + First_Copy_Length .. Bytes'Last);
            end;
         else
            -- Perform single copy onto internal array:
            Self.Bytes (Tail .. End_Index) := Bytes;
         end if;
      end;

      -- Set the and count:
      Self.Count := @ + Bytes_Length;
      if Overwrite and then Self.Count > Self.Bytes'Length then
         -- We need to move head if an overwrite actually occurs, since we are
         -- basically "popping" old data by doing the overwrite.
         Self.Head := (@ + (Self.Count - Self.Bytes'Length)) mod Self.Bytes'Length;
         -- The count should never be greater than the length of the buffer.
         Self.Count := Self.Bytes'Length;
      end if;

      -- Set the max count:
      if Self.Count > Self.Max_Count then
         Self.Max_Count := Self.Count;
      end if;

      return Success;
   end Push;

   function Peek (Self : in Base; Bytes : in out Basic_Types.Byte_Array; Num_Bytes_Returned : out Natural; Offset : in Natural := 0) return Pop_Status is
      -- The length attribute handles empty arrays gracefully, returning zero:
      Bytes_Length : constant Natural := Bytes'Length;
      Current_Head : Natural;
      Num_Bytes_To_Copy : Integer;
      End_Index : Integer;
   begin
      -- Initialized the number of bytes returned to zero:
      Num_Bytes_Returned := 0;

      -- There is nothing to copy:
      if Bytes_Length = 0 then
         return Success;
      end if;

      -- Return an error if there is no memory to peek on:
      if Self.Count <= Offset then
         return Empty;
      end if;

      -- The absolute head index for this peek. This is computed after the
      -- emptiness check above so that the sum cannot overflow for very large
      -- offsets. Before the SPARK conversion it was computed unconditionally,
      -- where an enormous offset could overflow the sum and raise
      -- Constraint_Error instead of returning Empty:
      Current_Head := Self.Head + Offset;

      -- Calculate the number of bytes we are going to return. The bound
      -- check is phrased as a subtraction so that it cannot overflow for
      -- very long input arrays:
      Num_Bytes_Returned := Bytes_Length;
      if Num_Bytes_Returned > Self.Count - Offset then
         Num_Bytes_Returned := Self.Count - Offset;
      end if;

      -- Calculate the end index:
      End_Index := Current_Head + Num_Bytes_Returned - 1;

      -- Correct the end index if a roll over is going to happen:
      if End_Index > Self.Bytes'Last then
         End_Index := Self.Bytes'Last;
      end if;

      -- Calculate the number of bytes to copy:
      Num_Bytes_To_Copy := End_Index - Current_Head + 1;

      -- Copy bytes over:
      if Num_Bytes_To_Copy > 0 then
         Bytes (Bytes'First .. Bytes'First + Num_Bytes_To_Copy - 1) := Self.Bytes (Current_Head .. End_Index);
      end if;

      -- If the number of bytes copied was not the full amount then
      -- we need to wrap around.
      if Num_Bytes_To_Copy < Num_Bytes_Returned then
         declare
            Num_Bytes_Copied : Integer := Num_Bytes_To_Copy;
            Bytes_Index : Natural;
            Start_Offset : Natural := 0;
         begin
            -- If num bytes copied is negative, then make correction for
            -- wrap around:
            if Num_Bytes_Copied < 0 then
               Num_Bytes_Copied := 0;
               Start_Offset := -1 * Num_Bytes_To_Copy;
            end if;
            -- Do second copy:
            Bytes_Index := Bytes'First + Num_Bytes_Copied;
            Num_Bytes_To_Copy := Num_Bytes_Returned - Num_Bytes_Copied;
            Bytes (Bytes_Index .. Bytes_Index + Num_Bytes_To_Copy - 1) := Self.Bytes (Start_Offset .. Start_Offset + Num_Bytes_To_Copy - 1);
         end;
      end if;

      return Success;
   end Peek;

   function Pop (Self : in out Base; Bytes : in out Basic_Types.Byte_Array; Num_Bytes_Returned : out Natural) return Pop_Status is
      Old_Head : constant Natural := Self.Head;
      Stat : Pop_Status;
   begin
      Stat := Peek (Self, Bytes, Num_Bytes_Returned);
      if Stat /= Success then
         return Stat;
      end if;

      -- Set the new head and count if we removed any bytes.
      if Self.Bytes'Length > 0 and then Num_Bytes_Returned > 0 then
         Self.Head := (@ + Num_Bytes_Returned) mod Self.Bytes'Length;
         -- Relate the modular head computation to the conditional form used
         -- by the ghost wrap index model. This assertion is proved and is
         -- trivial at runtime:
         pragma Assert (Self.Head = (if Old_Head + Num_Bytes_Returned < Self.Bytes'Length then Old_Head + Num_Bytes_Returned else Old_Head + Num_Bytes_Returned - Self.Bytes'Length));
         Self.Count := @ - Num_Bytes_Returned;
      end if;

      -- Optimization: set head to zero if count is zero, this
      -- prevents rollover of the buffer as much as possible.
      if Self.Count = 0 then
         Self.Head := 0;
      end if;

      return Success;
   end Pop;

   -- Serialize a length into big endian bytes for storage on the buffer. The
   -- explicit byte composition avoids an address overlay, which keeps this
   -- code compatible with SPARK.
   function Length_To_Bytes (Value : in Natural) return Length_Byte_Array
      with Post => Compose (Length_To_Bytes'Result (0), Length_To_Bytes'Result (1), Length_To_Bytes'Result (2), Length_To_Bytes'Result (3)) = Interfaces.Unsigned_32 (Value)
   is
      use Interfaces;
      Value_U32 : constant Unsigned_32 := Unsigned_32 (Value);
      To_Return : constant Length_Byte_Array := [
         Basic_Types.Byte (Shift_Right (Value_U32, 24) and 16#FF#),
         Basic_Types.Byte (Shift_Right (Value_U32, 16) and 16#FF#),
         Basic_Types.Byte (Shift_Right (Value_U32, 8) and 16#FF#),
         Basic_Types.Byte (Value_U32 and 16#FF#)
      ];
   begin
      return To_Return;
   end Length_To_Bytes;

   -- Deserialize a length from the big endian bytes stored on the buffer,
   -- range checking the value into a Natural via a modular intermediate.
   function Bytes_To_Length (Bytes : in Length_Byte_Array) return Natural
      with Pre => Compose (Bytes (0), Bytes (1), Bytes (2), Bytes (3)) <= Interfaces.Unsigned_32 (Natural'Last),
           Post => Interfaces.Unsigned_32 (Bytes_To_Length'Result) = Compose (Bytes (0), Bytes (1), Bytes (2), Bytes (3))
   is
      use Interfaces;
      Value_U32 : constant Unsigned_32 :=
         Shift_Left (Unsigned_32 (Bytes (0)), 24) or
         Shift_Left (Unsigned_32 (Bytes (1)), 16) or
         Shift_Left (Unsigned_32 (Bytes (2)), 8) or
         Unsigned_32 (Bytes (3));
   begin
      pragma Assert (Value_U32 <= Unsigned_32 (Natural'Last), "Length found on buffer is out of range. This can only be false if there is a software bug.");
      return Natural (Value_U32);
   end Bytes_To_Length;

   function Do_Peek_Length (Self : in Queue_Base; Length : out Natural) return Pop_Status is
   begin
      -- Initialize length to zero:
      Length := 0;

      -- Make sure there is data on the queue:
      if Self.Item_Count = 0 then
         return Empty;
      end if;

      -- Ghost: expose the facts of the head record for the proof:
      Lemma_Records_Head (Self.Bytes.all, Self.Head, Self.Count, Self.Item_Count);

      declare
         Stat : Pop_Status;
         Num_Bytes_Returned : Natural;
         Length_Bytes : Length_Byte_Array := [others => 0];
      begin
         -- Deserialize the length from the buffer:
         Stat := Peek (Base (Self), Length_Bytes, Num_Bytes_Returned);
         pragma Assert (Stat = Success, "Peeking length failed. This can only be false if there is a software bug.");
         pragma Assert (Num_Bytes_Returned = Queue_Element_Storage_Overhead, "Peeking length returned too few bytes. This can only be false if there is a software bug.");
         -- Ghost: the bytes just read compose to the stored header value:
         Lemma_Header_Read (Self.Bytes.all, Self.Head, Length_Bytes);
         Length := Bytes_To_Length (Length_Bytes);
      end;

      return Success;
   end Do_Peek_Length;

   function Push_Length (Self : in out Queue_Base; Element_Length : in Natural) return Push_Status is
      Len : constant Natural := Element_Length + Queue_Element_Storage_Overhead;
      Old_Count : constant Natural := Self.Count with Ghost;
      Header_Bytes : constant Length_Byte_Array := Length_To_Bytes (Element_Length);
      Stat : Push_Status;
   begin
      -- Make sure we can fit the data and the length. The free byte count
      -- is written out directly here instead of calling Num_Bytes_Free,
      -- whose precondition is not meaningful for a partially constructed
      -- record:
      if Len > Self.Bytes'Length - Self.Count then
         return Too_Full;
      end if;

      -- Ghost: every record holds a header, which bounds the item count
      -- and shows the increment below cannot overflow:
      Lemma_Records_Count_Bound (Self.Bytes.all, Self.Head, Self.Count, Self.Item_Count);

      -- Serialize the length onto the buffer:
      Stat := Push (Base (Self), Header_Bytes);
      pragma Assert (Stat = Success, "Pushing length failed. This can only be false if there is a software bug.");

      -- Increment the counters:
      Self.Item_Count := @ + 1;
      if Self.Item_Count > Self.Item_Max_Count then
         Self.Item_Max_Count := Self.Item_Count;
      end if;

      -- Ghost: the header bytes just pushed read back as the element
      -- length at the old tail position:
      Lemma_Header_Written (Self.Bytes.all, Self.Head, Old_Count, Header_Bytes);

      return Success;
   end Push_Length;

   procedure Peek_Bytes (Self : in Queue_Base; Bytes : in out Basic_Types.Byte_Array; Num_Bytes_To_Read : in Natural; Num_Bytes_Read : out Natural; Offset : in Natural := 0) is
   begin
      -- Initialize bytes read to zero:
      Num_Bytes_Read := 0;

      -- If there are bytes to peek then do that:
      if Num_Bytes_To_Read > Offset then
         declare
            Num_Bytes_Returned : Natural;
            Stat : Pop_Status;
            Bytes_To_Peek : Natural := Num_Bytes_To_Read - Offset;
         begin
            -- Modify bytes to peek if it is longer than caller's byte array:
            if Bytes_To_Peek > Bytes'Length then
               Bytes_To_Peek := Bytes'Length;
            end if;

            -- Deserialize the data from the buffer:
            Stat := Peek (Base (Self), Bytes (Bytes'First .. Bytes'First + Bytes_To_Peek - 1), Num_Bytes_Returned, Offset => Queue_Element_Storage_Overhead + Offset);
            pragma Assert (Stat = Success, "Peeking bytes failed. This can only be false if there is a software bug.");
            pragma Assert (Num_Bytes_Returned = Bytes_To_Peek, "Peeking bytes returned too few bytes. This can only be false if there is a software bug.");

            -- Return the actual number of bytes read to caller:
            Num_Bytes_Read := Bytes_To_Peek;
         end;
      end if;
   end Peek_Bytes;

   procedure Do_Pop (Self : in out Queue_Base; Element_Length : in Natural) is
      Old_Head : constant Natural := Self.Head;
      Old_Count : constant Natural := Self.Count with Ghost;
      Old_Items : constant Natural := Self.Item_Count with Ghost;
      Bytes_To_Pop : constant Natural := Element_Length + Queue_Element_Storage_Overhead;
   begin
      -- This subprogram used to pop the head record by reading it through
      -- Pop into a stack allocated scratch array that was then discarded.
      -- It now advances the head and count directly, exactly as Pop would,
      -- which removes a useless copy and an element sized stack allocation
      -- from every queue pop. The state transition is identical. The assert
      -- below subsumes the two asserts that guarded the old implementation,
      -- since it is exactly the condition under which the old Pop returned
      -- Success with the full number of bytes:
      -- Ghost: expose the facts of the head record for the proof:
      Lemma_Records_Head (Self.Bytes.all, Self.Head, Self.Count, Self.Item_Count);

      pragma Assert (Bytes_To_Pop <= Self.Count, "Popping more bytes than exist on the queue. This can only be false if there is a software bug.");

      -- Remove the record from the buffer:
      pragma Assert (Old_Head + Bytes_To_Pop < 2 * Self.Bytes'Length);
      Self.Head := (@ + Bytes_To_Pop) mod Self.Bytes'Length;
      -- Relate the modular head computation to the conditional form used by
      -- the ghost wrap index model. These assertions are proved and are
      -- trivial at runtime:
      pragma Assert (Self.Head = (if Old_Head + Bytes_To_Pop < Self.Bytes'Length then Old_Head + Bytes_To_Pop else Old_Head + Bytes_To_Pop - Self.Bytes'Length));
      Self.Count := @ - Bytes_To_Pop;

      -- Optimization: set head to zero if count is zero, this
      -- prevents rollover of the buffer as much as possible.
      if Self.Count = 0 then
         Self.Head := 0;
      end if;

      -- Decrement the counter:
      Self.Item_Count := @ - 1;

      -- Ghost: the remaining bytes form exactly the remaining records:
      Lemma_Records_Pop (Self.Bytes.all, Old_Head, Old_Count, Old_Items, Self.Head, Self.Count);
   end Do_Pop;

end Circular_Buffer.Core;

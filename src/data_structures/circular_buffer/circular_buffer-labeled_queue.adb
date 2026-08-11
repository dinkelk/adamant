with Serializer;
with Circular_Buffer.Core;

package body Circular_Buffer.Labeled_Queue with SPARK_Mode => On is

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

   -- The Serializer generic performs its conversions with address overlays,
   -- so its instantiation and use live in a package that is not analyzed:
   package Serial with SPARK_Mode => Off is
      package Label_Serializer is new Serializer (Label_Type);
   end Serial;

   -- The byte array holding one serialized label:
   subtype Label_Byte_Array is Basic_Types.Byte_Array (0 .. Label_Length - 1);

   -- Serialize a label into a byte array with an explicit copy. This avoids
   -- an address overlay in the queue implementation, which keeps this code
   -- compatible with SPARK. The body is not analyzed since the Serializer
   -- generic it calls uses overlays internally. The label bytes carry no
   -- proof significance, only their count does:
   procedure Serialize_Label (Dest : out Label_Byte_Array; Src : in Label_Type)
      with Inline => True;
   procedure Serialize_Label (Dest : out Label_Byte_Array; Src : in Label_Type) with SPARK_Mode => Off is
   begin
      Serial.Label_Serializer.To_Byte_Array (Dest => Dest, Src => Src);
   end Serialize_Label;

   -- Deserialize a label from a byte array with an explicit copy. See the
   -- note on Serialize_Label above:
   procedure Deserialize_Label (Dest : out Label_Type; Src : in Label_Byte_Array)
      with Inline => True;
   procedure Deserialize_Label (Dest : out Label_Type; Src : in Label_Byte_Array) with SPARK_Mode => Off is
   begin
      Serial.Label_Serializer.From_Byte_Array (Dest => Dest, Src => Src);
   end Deserialize_Label;

   -- Ghost lemma: the head record of a labeled queue is at least a label
   -- long:
   procedure Lemma_Min_Length_Head (Bytes : in Basic_Types.Byte_Array; Head : in Natural; Count : in Natural; Items : in Natural; Min : in Natural)
      with Ghost,
           Global => null,
           Pre => Bytes'First = 0
              and then Bytes'Length in 1 .. Max_Buffer_Size
              and then Head < Bytes'Length
              and then Count <= Bytes'Length
              and then Items > 0
              and then Records_Ok (Bytes, Head, Count, Items)
              and then Min_Lengths_Ok (Bytes, Head, Count, Items, Min),
           Post => Header_Ok (Bytes, Head) and then Header_Length (Bytes, Head) >= Min;
   procedure Lemma_Min_Length_Head (Bytes : in Basic_Types.Byte_Array; Head : in Natural; Count : in Natural; Items : in Natural; Min : in Natural) is
   begin
      Lemma_Records_Head (Bytes, Head, Count, Items);
      pragma Assert (if Min > 0 then Header_Length (Bytes, Head) >= Min);
   end Lemma_Min_Length_Head;

   --
   -- Subprograms for Labeled Queue:
   --

   function Push (Self : in out Instance; Label : in Label_Type; Bytes : in Basic_Types.Byte_Array) return Push_Status is
      Old_Bytes : constant Basic_Types.Byte_Array := Self.Bytes.all with Ghost;
      Old_Count : constant Natural := Self.Count with Ghost;
      Old_Items : constant Natural := Self.Item_Count with Ghost;
      Element_Length : constant Natural := Label_Length + Bytes'Length;
      Stat : Push_Status;
   begin
      Stat := Core.Push_Length (Queue_Base (Self), Element_Length);

      -- Check return status:
      if Stat /= Success then
         -- Ghost: nothing changed, so the record model is preserved:
         Lemma_Records_Frame (Old_Bytes, Self.Bytes.all, Self.Head, Old_Count, Old_Items, Label_Length);
         return Stat;
      end if;

      declare
         Mid_Bytes : constant Basic_Types.Byte_Array := Self.Bytes.all with Ghost;
         Label_Bytes : Label_Byte_Array;
      begin
         Serialize_Label (Label_Bytes, Label);
         -- Push the label onto the buffer:
         Stat := Core.Push (Base (Self), Label_Bytes);
         pragma Assert (Stat = Success, "Pushing label failed. This can only be false if there is a software bug.");

         declare
            Mid_Bytes_2 : constant Basic_Types.Byte_Array := Self.Bytes.all with Ghost;
         begin
            -- Push the data bytes onto buffer:
            Stat := Core.Push (Base (Self), Bytes);
            pragma Assert (Stat = Success, "Pushing bytes failed. This can only be false if there is a software bug.");

            -- Ghost: the old records survived all three pushes untouched,
            -- the header just pushed survived the label and payload pushes,
            -- and together the pushed bytes form one more record at the
            -- tail, at least a label long:
            Lemma_Content_Chain (Old_Bytes, Mid_Bytes, Mid_Bytes_2, Self.Head, Old_Count, Old_Count + Queue_Element_Storage_Overhead);
            Lemma_Content_Chain (Old_Bytes, Mid_Bytes_2, Self.Bytes.all, Self.Head, Old_Count, Old_Count + Queue_Element_Storage_Overhead + Label_Length);
            Lemma_Header_Preserved (Mid_Bytes, Mid_Bytes_2, Self.Head, Old_Count);
            Lemma_Header_Preserved (Mid_Bytes_2, Self.Bytes.all, Self.Head, Old_Count);
            Lemma_Records_Frame (Old_Bytes, Self.Bytes.all, Self.Head, Old_Count, Old_Items, Label_Length);
            Lemma_Records_Append (Self.Bytes.all, Self.Head, Old_Count, Old_Items, Label_Length, Element_Length);
         end;
      end;

      return Success;
   end Push;

   function Do_Peek_Label (Self : in Instance; Label : out Label_Type; Length : out Natural; Element_Length : out Natural) return Pop_Status
      with Side_Effects,
           Pre => Labeled_Model_Valid (Self),
           Post => (if Self.Item_Count = 0 then Do_Peek_Label'Result = Empty
                    else Do_Peek_Label'Result = Success
                       and then Length = Header_Length (Self.Bytes.all, Self.Head)
                       and then Element_Length = Length
                       and then Length >= Label_Length
                       and then Length <= Self.Count - Queue_Element_Storage_Overhead)
   is
      Stat : Pop_Status;
   begin
      -- Initialize element length to zero:
      Element_Length := 0;

      -- Peek the length:
      Stat := Core.Do_Peek_Length (Queue_Base (Self), Length);

      -- Check return status:
      if Stat /= Success then
         -- The queue is empty. Set the label to a deterministic value so
         -- that it is set on every path, as SPARK flow analysis requires.
         -- The label is only meaningful when Success is returned. Before
         -- the SPARK conversion the label was simply left unwritten here,
         -- which for by copy label types clobbered the caller's actual
         -- with an uninitialized value on this path:
         Deserialize_Label (Label, [others => 0]);
         return Stat;
      end if;

      -- Save element length, since we are going to modify "length" to
      -- correspond to the length of the returned data, not the length
      -- of the actual item on the queue:
      Element_Length := Length;

      -- Ghost: every record in a labeled queue is at least a label long:
      Lemma_Min_Length_Head (Self.Bytes.all, Self.Head, Self.Count, Self.Item_Count, Label_Length);

      -- The returned length must be at least as big as the label otherwise there is a bug:
      pragma Assert (Length >= Label_Length, "Peeking length too small for label. This can only be false is there is a software bug.");

      declare
         Num_Bytes_Returned : Natural;
         Label_Bytes : Label_Byte_Array := [others => 0];
      begin
         -- Deserialize the label from the buffer:
         Stat := Core.Peek (Base (Self), Label_Bytes, Num_Bytes_Returned, Offset => Queue_Element_Storage_Overhead);
         pragma Assert (Stat = Success, "Peeking label failed. This can only be false if there is a software bug.");
         pragma Assert (Num_Bytes_Returned = Label_Length, "Peeking label returned too few bytes. This can only be false if there is a software bug.");
         -- Deserialize the label from the byte array with an explicit copy.
         -- This avoids an address overlay, which keeps this code compatible
         -- with SPARK.
         Deserialize_Label (Label, Label_Bytes);
      end;

      return Success;
   end Do_Peek_Label;

   function Do_Peek (Self : in Instance; Label : out Label_Type; Bytes : in out Basic_Types.Byte_Array; Length : out Natural; Element_Length : out Natural; Offset : in Natural := 0) return Pop_Status
      with Side_Effects,
           Pre => Labeled_Model_Valid (Self) and then Offset <= Natural'Last - Labeled_Queue_Element_Storage_Overhead,
           Post => (if Self.Item_Count = 0 then Do_Peek'Result = Empty
                    else Do_Peek'Result = Success
                       and then Element_Length = Header_Length (Self.Bytes.all, Self.Head))
   is
      Stat : Pop_Status;
   begin
      -- Peek the label:
      Stat := Do_Peek_Label (Self, Label, Length, Element_Length);

      -- Check return status:
      if Stat /= Success then
         return Stat;
      end if;

      -- Read the bytes from the queue:
      if Element_Length > 0 then
         Core.Peek_Bytes (Queue_Base (Self), Bytes, Element_Length, Length, Label_Length + Offset);
      end if;

      return Success;
   end Do_Peek;

   function Peek (Self : in Instance; Label : out Label_Type; Bytes : in out Basic_Types.Byte_Array; Length : out Natural; Offset : in Natural := 0) return Pop_Status is
      Ignore : Natural;
      Stat : Pop_Status;
   begin
      Stat := Do_Peek (Self, Label, Bytes, Length, Ignore, Offset);
      return Stat;
   end Peek;

   function Peek (Self : in Instance; Label : out Label_Type; Bytes : in out Basic_Types.Byte_Array; Offset : in Natural := 0) return Pop_Status is
      Ignore : Natural;
      Stat : Pop_Status;
   begin
      Stat := Self.Peek (Label, Bytes, Ignore, Offset);
      return Stat;
   end Peek;

   function Pop (Self : in out Instance; Label : out Label_Type; Bytes : in out Basic_Types.Byte_Array; Length : out Natural; Offset : in Natural := 0) return Pop_Status is
      -- Peek some bytes:
      Element_Length : Natural;
      Stat : Pop_Status;
   begin
      Stat := Do_Peek (Self, Label, Bytes, Length, Element_Length, Offset);

      -- Check return status:
      if Stat /= Success then
         return Stat;
      end if;

      -- Pop the bytes from the base:
      Core.Do_Pop (Queue_Base (Self), Element_Length);

      return Success;
   end Pop;

   function Pop (Self : in out Instance; Label : out Label_Type; Bytes : in out Basic_Types.Byte_Array; Offset : in Natural := 0) return Pop_Status is
      Ignore : Natural;
      Stat : Pop_Status;
   begin
      Stat := Self.Pop (Label, Bytes, Ignore, Offset);
      return Stat;
   end Pop;

   function Peek_Label (Self : in Instance; Label : out Label_Type) return Pop_Status is
      Ignore1, Ignore2 : Natural;
      Stat : Pop_Status;
   begin
      Stat := Do_Peek_Label (Self, Label, Ignore1, Ignore2);
      return Stat;
   end Peek_Label;

   -- The body is not analyzed by SPARK. This overriding inherits the
   -- class-wide precondition of the parent operation, which carries the
   -- plain queue model, and an overriding cannot strengthen its inherited
   -- precondition to the labeled queue model that the subtraction below
   -- relies on. The subtraction is safe for the same reason the assert in
   -- Do_Peek_Label holds and is proved: every record in a labeled queue is
   -- at least a label long, which is exactly what Labeled_Model_Valid
   -- states. The labeled queue unit tests exercise this subprogram:
   overriding function Peek_Length (Self : in Instance; Length : out Natural) return Pop_Status with SPARK_Mode => Off is
      Stat : Pop_Status;
      Total_Length : Natural;
   begin
      -- Initialize to zero:
      Length := 0;

      -- Call the base class length:
      Stat := Core.Do_Peek_Length (Queue_Base (Self), Total_Length);
      if Stat /= Success then
         return Stat;
      end if;

      -- Correct the length for the length of the label:
      Length := Total_Length - Label_Length;

      return Success;
   end Peek_Length;

end Circular_Buffer.Labeled_Queue;

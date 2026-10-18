-- The internal operations of the circular buffer package family. This is a
-- private child package so that these subprograms are not primitive
-- operations of the tagged buffer types, which exempts them from the
-- dispatching contract rules (SPARK RM 6.1.1) and lets them carry the
-- precise proof contracts that the implementations of the parent package
-- and the labeled queue child package rely on. Every call to these
-- subprograms is statically bound.
private package Circular_Buffer.Core with SPARK_Mode => On is

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
   pragma Unevaluated_Use_Of_Old (Allow);

   --
   -- Add/remove/look at data on the base buffer:
   --
   -- Push data from a byte array onto the buffer. If not enough space remains on the internal buffer to read
   -- store the entire byte array then Failure is returned.
   function Push (Self : in out Base; Bytes : in Basic_Types.Byte_Array; Overwrite : in Boolean := False) return Push_Status
      with Side_Effects,
           Pre => Valid (Self),
           Post => Valid (Self)
              and then Self.Bytes'Length = Self.Bytes.all'Old'Length
              and then (if Bytes'Length = 0 then
                           Push'Result = Success
                              and then Self.Head = Self.Head'Old
                              and then Self.Count = Self.Count'Old
                              and then Self.Max_Count = Self.Max_Count'Old
                              and then Self.Bytes.all = Self.Bytes.all'Old
                        elsif Bytes'Length > Self.Bytes'Length or else (not Overwrite and then Bytes'Length > Self.Bytes'Length - Self.Count'Old) then
                           Push'Result = Too_Full
                              and then Self.Head = Self.Head'Old
                              and then Self.Count = Self.Count'Old
                              and then Self.Max_Count = Self.Max_Count'Old
                              and then Self.Bytes.all = Self.Bytes.all'Old
                        elsif Bytes'Length <= Self.Bytes'Length - Self.Count'Old then
                           Push'Result = Success
                              and then Self.Head = Self.Head'Old
                              and then Self.Count = Self.Count'Old + Bytes'Length
                              and then Self.Max_Count = Natural'Max (Self.Max_Count'Old, Self.Count)
                              and then Content_Preserved (Self.Bytes.all'Old, Self.Bytes.all, Self.Head, Self.Count'Old)
                              and then (for all J in 0 .. Bytes'Length - 1 =>
                                           Element_At (Self.Bytes.all, Self.Head, Self.Count'Old + J) = Bytes (Bytes'First + J))
                        else
                           -- Overwrite of old data. The queue layers never use this
                           -- mode, so the model is intentionally weak here:
                           Push'Result = Success and then Self.Count = Self.Bytes'Length);
   -- Pop data from buffer onto a byte array. The function attempts to return a number of bytes equal to
   -- the size of the provided "bytes" array. The actual number of bytes returned is returned in the
   -- Num_Bytes_Returned variable.
   function Pop (Self : in out Base; Bytes : in out Basic_Types.Byte_Array; Num_Bytes_Returned : out Natural) return Pop_Status
      with Side_Effects,
           Pre => Valid (Self),
           Post => Valid (Self)
              and then Self.Bytes'Length = Self.Bytes.all'Old'Length
              and then Self.Bytes.all = Self.Bytes.all'Old
              and then Self.Max_Count = Self.Max_Count'Old
              and then (if Bytes'Length = 0 or else Self.Count'Old > 0 then Pop'Result = Success else Pop'Result = Empty)
              and then (if Pop'Result = Empty then
                           Num_Bytes_Returned = 0
                              and then Self.Head = Self.Head'Old
                              and then Self.Count = Self.Count'Old
                        else
                           Num_Bytes_Returned = Natural'Min (Bytes'Length, Self.Count'Old)
                              and then Self.Count = Self.Count'Old - Num_Bytes_Returned
                              and then (if Self.Count = 0 then Self.Head = 0
                                        else Self.Head = Wrap_Index (Self.Head'Old, Num_Bytes_Returned, Self.Bytes'Length))
                              and then (for all I in 0 .. Num_Bytes_Returned - 1 =>
                                           Bytes (Bytes'First + I) = Element_At (Self.Bytes.all'Old, Self.Head'Old, I)));
   -- Peek data from buffer onto a byte array. This function is like pop, except the bytes are not actually
   -- removed from the internal buffer. The function attempts to return a number of bytes equal to
   -- the size of the provided "bytes" array. The actual number of bytes returned is returned in the
   -- Num_Bytes_Returned variable. An offset can be provided to peek ahead a certain number of bytes
   -- from the head of the internal circular buffer.
   function Peek (Self : in Base; Bytes : in out Basic_Types.Byte_Array; Num_Bytes_Returned : out Natural; Offset : in Natural := 0) return Pop_Status
      with Side_Effects,
           Pre => Valid (Self),
           Post => (if Bytes'Length = 0 or else Self.Count > Offset then Peek'Result = Success else Peek'Result = Empty)
              and then Num_Bytes_Returned = (if Bytes'Length = 0 or else Self.Count <= Offset then 0 else Natural'Min (Bytes'Length, Self.Count - Offset))
              and then (for all I in 0 .. Num_Bytes_Returned - 1 =>
                           Bytes (Bytes'First + I) = Element_At (Self.Bytes.all, Self.Head, Offset + I));

   --
   -- Queue operations:
   --
   -- Get the length of the oldest item on the queue, including storage
   -- overhead, without removing it. This is the implementation behind the
   -- public Peek_Length, carrying the precise contract that the internal
   -- callers and the labeled queue child need:
   function Do_Peek_Length (Self : in Queue_Base; Length : out Natural) return Pop_Status
      with Side_Effects,
           Inline => True,
           Pre => Queue_Valid (Self),
           Post => (if Self.Item_Count = 0 then
                       Do_Peek_Length'Result = Empty and then Length = 0
                    else
                       Do_Peek_Length'Result = Success
                          and then Length = Header_Length (Self.Bytes.all, Self.Head)
                          and then Length <= Self.Count - Queue_Element_Storage_Overhead);
   -- Push a length header onto the buffer and account for the new item.
   -- The record is not complete until the caller pushes the payload, so
   -- this contract exposes the raw effects rather than the queue model:
   function Push_Length (Self : in out Queue_Base; Element_Length : in Natural) return Push_Status
      with Side_Effects,
           Pre => Queue_Valid (Self) and then Element_Length <= Natural'Last - Queue_Element_Storage_Overhead,
           Post => Valid (Self)
              and then Self.Bytes'Length = Self.Bytes.all'Old'Length
              and then Self.Head = Self.Head'Old
              and then (if Queue_Element_Storage_Overhead + Element_Length > Self.Bytes'Length - Self.Count'Old then
                           Push_Length'Result = Too_Full
                              and then Self.Count = Self.Count'Old
                              and then Self.Item_Count = Self.Item_Count'Old
                              and then Self.Bytes.all = Self.Bytes.all'Old
                        else
                           Push_Length'Result = Success
                              and then Self.Count = Self.Count'Old + Queue_Element_Storage_Overhead
                              and then Self.Item_Count = Self.Item_Count'Old + 1
                              and then Content_Preserved (Self.Bytes.all'Old, Self.Bytes.all, Self.Head, Self.Count'Old)
                              and then Header_Ok (Self.Bytes.all, Wrap_Index (Self.Head, Self.Count'Old, Self.Bytes'Length))
                              and then Header_Length (Self.Bytes.all, Wrap_Index (Self.Head, Self.Count'Old, Self.Bytes'Length)) = Element_Length);
   -- Peek payload bytes of the head record, past the header:
   procedure Peek_Bytes (Self : in Queue_Base; Bytes : in out Basic_Types.Byte_Array; Num_Bytes_To_Read : in Natural; Num_Bytes_Read : out Natural; Offset : in Natural := 0)
      with Pre => Queue_Valid (Self)
              and then Self.Count >= Queue_Element_Storage_Overhead
              and then Num_Bytes_To_Read <= Self.Count - Queue_Element_Storage_Overhead,
           Post => Num_Bytes_Read = (if Num_Bytes_To_Read <= Offset then 0 else Natural'Min (Num_Bytes_To_Read - Offset, Bytes'Length));
   -- Remove the head record from the queue:
   procedure Do_Pop (Self : in out Queue_Base; Element_Length : in Natural)
      with Pre => Queue_Valid (Self)
              and then Self.Item_Count > 0
              and then Element_Length = Header_Length (Self.Bytes.all, Self.Head),
           Post => Queue_Valid (Self)
              and then Self.Bytes'Length = Self.Bytes.all'Old'Length
              and then Self.Bytes.all = Self.Bytes.all'Old
              and then Self.Item_Count = Self.Item_Count'Old - 1
              and then Self.Count = Self.Count'Old - Queue_Element_Storage_Overhead - Element_Length
              and then (for all M in Natural =>
                          (if Min_Lengths_Ok (Self.Bytes.all'Old, Self.Head'Old, Self.Count'Old, Self.Item_Count'Old, M) then
                              Min_Lengths_Ok (Self.Bytes.all, Self.Head, Self.Count, Self.Item_Count, M)));

end Circular_Buffer.Core;

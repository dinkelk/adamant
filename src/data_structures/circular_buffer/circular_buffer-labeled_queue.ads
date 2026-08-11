with Basic_Types;

generic
   type Label_Type is private;
package Circular_Buffer.Labeled_Queue with SPARK_Mode => On is

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

   -- The labeled queue type:
   -- This queue is identical to the Queue type above
   -- except that each element is stored with a generic label. The most obvious
   -- use for this label is to store information regarding the type of the element
   -- stored in the queue, such that the correct deserialization method can be called
   -- to decode the data. However, the label can really be any statically sized
   -- type. If you use a variable length type as the label, the maximum size of that
   -- variable length type will be stored, so this is not recommended.
   type Instance is new Queue_Base with private;

   -- Ghost predicate stating that the labeled queue is in a valid state: the
   -- queue record model holds, and additionally every stored element begins
   -- with a serialized label, so every record is at least a label long:
   function Labeled_Model_Valid (Self : in Instance'Class) return Boolean
      with Ghost;

   -- Add/remove/look at data on the queue:
   --
   -- Push data from a byte array onto the queue. If not enough space remains on the internal queue to read
   -- store the entire byte array then Failure is returned.
   function Push (Self : in out Instance; Label : in Label_Type; Bytes : in Basic_Types.Byte_Array) return Push_Status
      with Side_Effects,
           Pre'Class => Labeled_Model_Valid (Self) and then Bytes'Length <= Natural'Last - Labeled_Queue_Element_Storage_Overhead,
           Post => Labeled_Model_Valid (Self);
   -- Pop data from queue onto a byte array. The number of bytes returned will match the length
   -- of "bytes". If "bytes" cannot be completely filled then Failure is returned.
   function Pop (Self : in out Instance; Label : out Label_Type; Bytes : in out Basic_Types.Byte_Array; Length : out Natural; Offset : in Natural := 0) return Pop_Status
      with Side_Effects,
           Pre'Class => Labeled_Model_Valid (Self) and then Offset <= Natural'Last - Labeled_Queue_Element_Storage_Overhead,
           Post => Labeled_Model_Valid (Self);
   function Pop (Self : in out Instance; Label : out Label_Type; Bytes : in out Basic_Types.Byte_Array; Offset : in Natural := 0) return Pop_Status
      with Side_Effects,
           Pre'Class => Labeled_Model_Valid (Self) and then Offset <= Natural'Last - Labeled_Queue_Element_Storage_Overhead,
           Post => Labeled_Model_Valid (Self);
   -- Peek data from queue onto a byte array. This function is like pop, except the bytes are not actually
   -- removed from the internal queue.
   function Peek (Self : in Instance; Label : out Label_Type; Bytes : in out Basic_Types.Byte_Array; Length : out Natural; Offset : in Natural := 0) return Pop_Status
      with Side_Effects,
           Pre'Class => Labeled_Model_Valid (Self) and then Offset <= Natural'Last - Labeled_Queue_Element_Storage_Overhead;
   function Peek (Self : in Instance; Label : out Label_Type; Bytes : in out Basic_Types.Byte_Array; Offset : in Natural := 0) return Pop_Status
      with Side_Effects,
           Pre'Class => Labeled_Model_Valid (Self) and then Offset <= Natural'Last - Labeled_Queue_Element_Storage_Overhead;

   -- Get the label of the oldest item on the queue without removing it.
   function Peek_Label (Self : in Instance; Label : out Label_Type) return Pop_Status
      with Side_Effects,
           Pre'Class => Labeled_Model_Valid (Self);
   -- Get the length of the oldest item on the queue without removing it. We need to override because we need to subtract the length of the label.
   overriding function Peek_Length (Self : in Instance; Length : out Natural) return Pop_Status
      with Side_Effects;

   -- Declare constant for size of overhead for storing length on the buffer
   -- and the label itself (in bytes):
   Labeled_Queue_Element_Storage_Overhead : constant Natural;

private

   -- The number of bytes a label occupies when serialized onto the buffer.
   -- This mirrors the Serialized_Length constant of the Serializer generic,
   -- which performs the actual conversion in the package body:
   Label_Length : constant Natural := Label_Type'Object_Size / Basic_Types.Byte'Object_Size;

   -- Resolve the element storage constant:
   Labeled_Queue_Element_Storage_Overhead : constant Natural := Circular_Buffer.Queue_Element_Storage_Overhead + Label_Length;

   -- Internal type for labeled queue:
   type Instance is new Queue_Base with record
      null; -- Nothing more needed, just adding methods.
   end record;

   -- Ghost model completion. Every element stored through Push above begins
   -- with a serialized label, so every record length is at least the label
   -- length:
   function Labeled_Model_Valid (Self : in Instance'Class) return Boolean is
      (Queue_Valid (Self)
         and then Min_Lengths_Ok (Self.Bytes.all, Self.Head, Self.Count, Self.Item_Count, Label_Length));

end Circular_Buffer.Labeled_Queue;

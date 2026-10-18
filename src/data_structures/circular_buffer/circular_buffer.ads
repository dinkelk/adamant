with Basic_Types;
with Circular_Buffer_Meta;
with Byte_Array_Pointer;
with Interfaces;

package Circular_Buffer with SPARK_Mode => On is

   -- The contracts and ghost code in this package exist for proof with
   -- GNATprove only. The assertion policy below disables them at runtime, so
   -- the generated code and the runtime behavior of this package family is
   -- identical to what it was before the SPARK conversion. The defensive
   -- pragma Assert statements in the package bodies are not affected by this
   -- policy. They remain compiled in and enabled under the project wide
   -- assertion policy, and they are also proved.
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

   -- Status type:
   type Push_Status is (Success, Too_Full);
   type Pop_Status is (Success, Empty);

   -- Maximum buffer size supported by the proof. The internal arithmetic
   -- sums a head index and byte counts, and in overwrite mode the count can
   -- temporarily reach twice the buffer size, so this bound keeps every such
   -- sum within Integer. All realistic buffers are far below this bound.
   -- Buffers larger than this are outside the verified domain and behave as
   -- they did before the SPARK conversion.
   Max_Buffer_Size : constant := 2 ** 30 - 1;

   -- Basic Buffer definition:
   -- This is a base type for many other data structures which use
   -- a byte array buffer as their central functioning. This type is pretty
   -- useless on its own. It can be instantiated, deleted, and queried for
   -- meta data, but no access to the internal buffer is granted the user.
   -- Look at inheriting packages for better data structures to use. The
   -- purpose of this package is solely to consolidate shared code and thus
   -- ease of implementation and testing of the inheriting data structures.
   type Base is tagged private;

   -- Ghost predicate stating that the buffer is in a valid, initialized
   -- state. This function is the class-wide precondition of most operations
   -- below. It takes a class-wide parameter so that it is not a dispatching
   -- operation, which would force every derived type to override each
   -- operation mentioning it (SPARK RM 6.1.1). The queue types below state
   -- their stronger model with a separate predicate for the same reason.
   function Model_Valid (Self : in Base'Class) return Boolean
      with Ghost;

   -- Ghost predicate stating that the buffer meta data is in its freshly
   -- reset state, as left by Clear or Destroy or as found in a default
   -- initialized object.
   function Is_Reset (Self : in Base'Class) return Boolean
      with Ghost;

   --
   -- Initialization/destruction functions:
   --
   -- Provide a size, and allocate the memory on the heap using malloc:
   procedure Init (Self : in out Base; Size : in Natural)
      with Pre'Class => Is_Reset (Self) and then Size in 1 .. Max_Buffer_Size,
           Post => Model_Valid (Self);
   -- Provide a pointer to an already allocated set of bytes:
   procedure Init (Self : in out Base; Bytes : in not null Basic_Types.Byte_Array_Access)
      with Pre'Class => Is_Reset (Self),
           Post => Model_Valid (Self);
   -- Destroy all bytes on the buffer:
   procedure Destroy (Self : in out Base)
      with Post => Is_Reset (Self);
   -- Clear the buffer:
   procedure Clear (Self : in out Base)
      with Pre'Class => Model_Valid (Self),
           Post => Model_Valid (Self) and then Is_Reset (Self);

   --
   -- Meta data functions:
   --
   -- Is the circular buffer completely full of data?
   function Is_Full (Self : in Base) return Boolean
      with Inline => True, Pre'Class => Model_Valid (Self);
   -- Is the circular buffer completely empty?
   function Is_Empty (Self : in Base) return Boolean
      with Inline => True;
   -- How many bytes are not currently being used on the buffer?
   function Num_Bytes_Free (Self : in Base) return Natural
      with Inline => True, Pre'Class => Model_Valid (Self);
   -- How many bytes are being used currently on the buffer?
   function Num_Bytes_Used (Self : in Base) return Natural
      with Inline => True;
   -- This is the "high water mark" or the maximum number of bytes
   -- ever seen on the buffer since instantiation.
   function Max_Num_Bytes_Used (Self : in Base) return Natural
      with Inline => True;
   -- How many bytes have been allocated to the buffer?
   function Num_Bytes_Total (Self : in Base) return Natural
      with Inline => True, Pre'Class => Model_Valid (Self);
   -- Returns a byte with value 0 - 100 of the percentage of the queue
   -- that is currently being used. Num_Bytes_Used/Num_Bytes_Total
   function Current_Percent_Used (Self : in Base) return Basic_Types.Byte;
   -- Returns a byte with value 0 - 100 of the maximum percentage of the queue
   -- that was used since the queue was instantiated. Max_Num_Bytes_Used/Num_Bytes_Total
   -- "high water mark"
   function Max_Percent_Used (Self : in Base) return Basic_Types.Byte;
   -- Get the meta data for the circular buffer in a convenient packed
   -- type.
   function Get_Meta_Data (Self : in Base) return Circular_Buffer_Meta.T
      with Inline => True, Pre'Class => Model_Valid (Self);

   --
   -- Dump functions:
   --
   -- These functions dump the internal circular buffer via an array of pointers.
   -- This array of pointers is of length 2, the second pointer accounting for
   -- wrap arounds in the dump request. Sometimes the dump request can be accommodated
   -- using a single pointer, in which case the second pointer will be set to null
   -- with zero length:
   type Pointer_Dump is array (0 .. 1) of Byte_Array_Pointer.Instance;
   -- Dump all data from oldest to newest:
   function Dump (Self : in Base) return Pointer_Dump
      with Pre'Class => Model_Valid (Self);
   -- Return the newest n number of bytes.
   function Dump_Newest (Self : in Base; Num_Bytes_To_Dump : in Natural) return Pointer_Dump
      with Pre'Class => Model_Valid (Self);
   -- Return the oldest n number of bytes.
   function Dump_Oldest (Self : in Base; Num_Bytes_To_Dump : in Natural) return Pointer_Dump
      with Pre'Class => Model_Valid (Self);
   -- Dump all data in memory order.
   function Dump_Memory (Self : in Base) return Pointer_Dump
      with Pre'Class => Model_Valid (Self);

   -- Circular buffer type:
   -- This is an unprotected circular buffer data structure which allows the
   -- user to push and pop byte arrays from an internal buffer. The usage of
   -- this data structure by itself is error prone since it provides little
   -- in the way of type protection, sizing of internal elements, etc. However,
   -- more useful data structures can be built on top of this simple base.
   type Circular is new Base with private;

   --
   -- Add/remove/look at data on the buffer:
   --
   -- Push data from a byte array onto the buffer. If not enough space remains on the internal buffer to read
   -- store the entire byte array then Failure is returned.
   function Push (Self : in out Circular; Bytes : in Basic_Types.Byte_Array; Overwrite : in Boolean := False) return Push_Status
      with Side_Effects,
           Pre'Class => Model_Valid (Self),
           Post => Model_Valid (Self);
   -- Pop data from buffer onto a byte array. The number of bytes returned will match the length
   -- of "bytes". If "bytes" cannot be completely filled then Failure is returned.
   function Pop (Self : in out Circular; Bytes : in out Basic_Types.Byte_Array; Num_Bytes_Returned : out Natural) return Pop_Status
      with Side_Effects,
           Pre'Class => Model_Valid (Self),
           Post => Model_Valid (Self) and then Num_Bytes_Returned <= Bytes'Length;
   -- Peek data from buffer onto a byte array. This function is like pop, except the bytes are not actually
   -- removed from the internal buffer.
   function Peek (Self : in Circular; Bytes : in out Basic_Types.Byte_Array; Num_Bytes_Returned : out Natural; Offset : in Natural := 0) return Pop_Status
      with Side_Effects,
           Pre'Class => Model_Valid (Self),
           Post => Num_Bytes_Returned <= Bytes'Length;

   -- Force the buffer to be completely full, with the head at the specified index. This
   -- subprogram is useful if you want to read out the entire buffer from start to finish
   -- of the allocation in memory.
   procedure Make_Full (Self : in out Circular; Head_Index : Natural := 0)
      with Inline => True,
           Pre'Class => Model_Valid (Self),
           Post => Model_Valid (Self);

   -- The queue base type:
   -- This type provides a base type that encapsulates functionality for the inheriting
   -- queue classes below:
   type Queue_Base is new Base with private;

   -- Ghost predicate stating that the queue is in a valid state: the buffer
   -- is valid and its content is a whole number of records, each a length
   -- header followed by that many payload bytes:
   function Queue_Model_Valid (Self : in Queue_Base'Class) return Boolean
      with Ghost;

   -- Get the length of the oldest item on the queue without removing it.
   function Peek_Length (Self : in Queue_Base; Length : out Natural) return Pop_Status
      with Side_Effects,
           Pre'Class => Queue_Model_Valid (Self),
           Post => (if Peek_Length'Result = Empty then Length = 0);
   -- Remove an item off the queue, without returning it:
   function Pop (Self : in out Queue_Base) return Pop_Status
      with Side_Effects,
           Pre'Class => Queue_Model_Valid (Self),
           Post => Queue_Model_Valid (Self);

   --
   -- Meta data functions:
   --
   -- how many items are on the queue currently?
   function Get_Count (Self : in Queue_Base) return Natural
      with Inline => True;
   -- what is the maximum number of items ever seen on the queue since instantiation?
   function Get_Max_Count (Self : in Queue_Base) return Natural
      with Inline => True;
   -- Clear the buffer:
   overriding procedure Clear (Self : in out Queue_Base)
      with Post => Queue_Model_Valid (Self) and then Is_Reset (Self);
   -- Destroy the buffer (also resets Item_Count and Item_Max_Count):
   overriding procedure Destroy (Self : in out Queue_Base)
      with Post => Is_Reset (Self);

   -- The queue type:
   -- This is an unprotected byte array queue data structure which allows the
   -- user to push and pop byte arrays from an internal buffer. This package
   -- extends the Circular Buffer class, storing the length of each byte
   -- buffer along with the byte buffer itself. Adding this feature, the queue
   -- does not treat its internal store as an array of bytes, but as an array
   -- of elements (stored as bytes). The user can then add and remove these
   -- elements safely, without knowing apriori what the size of each element is
   -- on the queue.
   type Queue is new Queue_Base with private;

   -- Add/remove/look at data on the queue:
   --
   -- Push data from a byte array onto the queue. If not enough space remains on the internal queue to read
   -- store the entire byte array then Failure is returned.
   function Push (Self : in out Queue; Bytes : in Basic_Types.Byte_Array) return Push_Status
      with Side_Effects,
           Pre'Class => Queue_Model_Valid (Self) and then Bytes'Length <= Natural'Last - Queue_Element_Storage_Overhead,
           Post => Queue_Model_Valid (Self);
   -- Pop data from queue onto a byte array. The number of bytes returned will match the length
   -- of "bytes". If "bytes" cannot be completely filled then Failure is returned.
   function Pop (Self : in out Queue; Bytes : in out Basic_Types.Byte_Array; Length : out Natural; Offset : in Natural := 0) return Pop_Status
      with Side_Effects,
           Pre'Class => Queue_Model_Valid (Self),
           Post => Queue_Model_Valid (Self);
   -- Peek data from queue onto a byte array. This function is like pop, except the bytes are not actually
   -- removed from the internal queue.
   function Peek (Self : in Queue; Bytes : in out Basic_Types.Byte_Array; Length : out Natural; Offset : in Natural := 0) return Pop_Status
      with Side_Effects,
           Pre'Class => Queue_Model_Valid (Self);

   -- Declare constant for size of overhead for storing length on the buffer
   -- itself (in bytes):
   Queue_Element_Storage_Overhead : constant Natural;

private

   use type Interfaces.Unsigned_32;
   use type Basic_Types.Byte;
   use type Basic_Types.Byte_Array;
   use type Basic_Types.Byte_Array_Access;

   -- Internal types for managing the memory pool:
   type Base is tagged record
      Bytes : Basic_Types.Byte_Array_Access := null;
      Head : Natural := 0;
      Count : Natural := 0;
      Max_Count : Natural := 0;
      Allocated : Boolean := False;
   end record;

   -- Resolve the element storage constant. The length of each queue element
   -- is stored on the buffer as the byte representation of a Natural:
   Queue_Element_Storage_Overhead : constant Natural := Natural'Object_Size / Basic_Types.Byte'Object_Size;

   -- The byte array subtype used to serialize an element length onto the
   -- buffer. The explicit byte composition functions in the package body
   -- assume this is exactly four bytes, which is checked at compile time:
   subtype Length_Byte_Array is Basic_Types.Byte_Array (0 .. Queue_Element_Storage_Overhead - 1);
   pragma Compile_Time_Error (Queue_Element_Storage_Overhead /= 4, "The queue element length header is assumed to be exactly four bytes.");

   --
   -- Ghost model of the buffer. Everything below exists for proof only and
   -- is never executed at runtime.
   --

   -- Structural validity of the base circular buffer, established by Init
   -- and preserved by every operation until Destroy:
   function Valid (Self : in Base'Class) return Boolean is
      (Self.Bytes /= null
         and then Self.Bytes.all'First = 0
         and then Self.Bytes'Length >= 1
         and then Self.Bytes'Length <= Max_Buffer_Size
         and then Self.Head < Self.Bytes'Length
         and then Self.Count <= Self.Bytes'Length)
      with Ghost;

   -- Map an offset relative to a head index onto an absolute buffer index,
   -- wrapping around the end of the buffer. This is equivalent to
   -- (Head + Offset) mod Size for the argument ranges allowed by the
   -- precondition, but stays within linear arithmetic which the provers
   -- handle much better than modular division:
   function Wrap_Index (Head : in Natural; Offset : in Natural; Size : in Natural) return Natural is
      (if Offset < Size - Head then Head + Offset else Offset - (Size - Head))
      with Ghost,
           Pre => Size in 1 .. Max_Buffer_Size and then Head < Size and then Offset <= Size,
           Post => Wrap_Index'Result < Size;

   -- The byte stored at the provided offset behind the head index:
   function Element_At (Bytes : in Basic_Types.Byte_Array; Head : in Natural; Offset : in Natural) return Basic_Types.Byte is
      (Bytes (Wrap_Index (Head, Offset, Bytes'Length)))
      with Ghost,
           Pre => Bytes'First = 0
              and then Bytes'Length in 1 .. Max_Buffer_Size
              and then Head < Bytes'Length
              and then Offset < Bytes'Length;

   -- True if the first Count bytes behind the head index hold the same
   -- values in both byte arrays:
   function Content_Preserved (B_Old : in Basic_Types.Byte_Array; B_New : in Basic_Types.Byte_Array; Head : in Natural; Count : in Natural) return Boolean is
      (for all K in 0 .. Count - 1 => Element_At (B_New, Head, K) = Element_At (B_Old, Head, K))
      with Ghost,
           Pre => B_Old'First = 0
              and then B_New'First = 0
              and then B_New'Length = B_Old'Length
              and then B_Old'Length in 1 .. Max_Buffer_Size
              and then Head < B_Old'Length
              and then Count <= B_Old'Length;

   -- Compose four bytes into an unsigned 32-bit value in big endian byte
   -- order. This is the ghost model of the length header serialization
   -- performed by the package body:
   function Compose (B0 : in Basic_Types.Byte; B1 : in Basic_Types.Byte; B2 : in Basic_Types.Byte; B3 : in Basic_Types.Byte) return Interfaces.Unsigned_32 is
      (Interfaces.Shift_Left (Interfaces.Unsigned_32 (B0), 24) or
          Interfaces.Shift_Left (Interfaces.Unsigned_32 (B1), 16) or
          Interfaces.Shift_Left (Interfaces.Unsigned_32 (B2), 8) or
          Interfaces.Unsigned_32 (B3))
      with Ghost;

   -- Ghost model completions for Base:
   function Model_Valid (Self : in Base'Class) return Boolean is (Valid (Self));
   function Is_Reset (Self : in Base'Class) return Boolean is (Self.Head = 0 and then Self.Count = 0);

   -- Internal type for circular buffer:
   type Circular is new Base with record
      null; -- Nothing more needed, just adding methods.
   end record;

   -- Internal type for queue buffer:
   type Queue_Base is new Base with record
      Item_Count : Natural := 0;
      Item_Max_Count : Natural := 0;
   end record;

   --
   -- Ghost model of the queue record structure. The buffer content of a
   -- valid queue is a whole number of records, each a big endian length
   -- header of Queue_Element_Storage_Overhead bytes followed by that many
   -- payload bytes. Everything below exists for proof only.
   --

   -- The header value stored at the provided head index, wrapping around
   -- the buffer end:
   function Header_U32 (Bytes : in Basic_Types.Byte_Array; Head : in Natural) return Interfaces.Unsigned_32 is
      (Compose (Element_At (Bytes, Head, 0), Element_At (Bytes, Head, 1), Element_At (Bytes, Head, 2), Element_At (Bytes, Head, 3)))
      with Ghost,
           Pre => Bytes'First = 0
              and then Bytes'Length in Queue_Element_Storage_Overhead .. Max_Buffer_Size
              and then Head < Bytes'Length;

   -- True if the header value fits in a Natural, which holds for every
   -- header written by Push_Length:
   function Header_Ok (Bytes : in Basic_Types.Byte_Array; Head : in Natural) return Boolean is
      (Header_U32 (Bytes, Head) <= Interfaces.Unsigned_32 (Natural'Last))
      with Ghost,
           Pre => Bytes'First = 0
              and then Bytes'Length in Queue_Element_Storage_Overhead .. Max_Buffer_Size
              and then Head < Bytes'Length;

   -- The element length stored in the header at the provided head index:
   function Header_Length (Bytes : in Basic_Types.Byte_Array; Head : in Natural) return Natural is
      (Natural (Header_U32 (Bytes, Head)))
      with Ghost,
           Pre => Bytes'First = 0
              and then Bytes'Length in Queue_Element_Storage_Overhead .. Max_Buffer_Size
              and then Head < Bytes'Length
              and then Header_Ok (Bytes, Head);

   -- The heart of the queue model: the Count bytes behind the head index
   -- form exactly Items records, each a valid length header followed by
   -- that many payload bytes:
   function Records_Ok (Bytes : in Basic_Types.Byte_Array; Head : in Natural; Count : in Natural; Items : in Natural) return Boolean is
      (if Items = 0 then Count = 0
       elsif Count < Queue_Element_Storage_Overhead or else not Header_Ok (Bytes, Head) then False
       elsif Header_Length (Bytes, Head) > Count - Queue_Element_Storage_Overhead then False
       else Records_Ok
          (Bytes,
           Wrap_Index (Head, Queue_Element_Storage_Overhead + Header_Length (Bytes, Head), Bytes'Length),
           Count - Queue_Element_Storage_Overhead - Header_Length (Bytes, Head),
           Items - 1))
      with Ghost,
           Pre => Bytes'First = 0
              and then Bytes'Length in 1 .. Max_Buffer_Size
              and then Head < Bytes'Length
              and then Count <= Bytes'Length,
           Subprogram_Variant => (Decreases => Items);

   -- True if every record length is at least Min. The labeled queue child
   -- package uses this with the serialized label length as the minimum,
   -- since every element it stores begins with a label:
   function Min_Lengths_Ok (Bytes : in Basic_Types.Byte_Array; Head : in Natural; Count : in Natural; Items : in Natural; Min : in Natural) return Boolean is
      (if Min = 0 or else Items = 0 then True
       else Header_Length (Bytes, Head) >= Min
          and then Min_Lengths_Ok
             (Bytes,
              Wrap_Index (Head, Queue_Element_Storage_Overhead + Header_Length (Bytes, Head), Bytes'Length),
              Count - Queue_Element_Storage_Overhead - Header_Length (Bytes, Head),
              Items - 1,
              Min))
      with Ghost,
           Pre => Bytes'First = 0
              and then Bytes'Length in 1 .. Max_Buffer_Size
              and then Head < Bytes'Length
              and then Count <= Bytes'Length
              and then Records_Ok (Bytes, Head, Count, Items),
           Subprogram_Variant => (Decreases => Items);

   -- Structural validity plus the record structure model for the queue:
   function Queue_Valid (Self : in Queue_Base'Class) return Boolean is
      (Valid (Self) and then Records_Ok (Self.Bytes.all, Self.Head, Self.Count, Self.Item_Count))
      with Ghost;

   -- Ghost model completion for Queue_Base:
   function Queue_Model_Valid (Self : in Queue_Base'Class) return Boolean is (Queue_Valid (Self));

   --
   -- Ghost lemmas for the queue record model. The bodies perform induction
   -- over the record walk. All are proof only:
   --

   -- Composing wrapped offsets: stepping K behind offset Base_Offset lands
   -- at offset Base_Offset + K:
   procedure Lemma_Wrap_Offsets (Head : in Natural; Base_Offset : in Natural; Span : in Natural; Size : in Natural)
      with Ghost,
           Global => null,
           Pre => Size in 1 .. Max_Buffer_Size
              and then Head < Size
              and then Base_Offset <= Size
              and then Span <= Size - Base_Offset,
           Post =>
              (for all K in 0 .. Span - 1 =>
                 Wrap_Index (Wrap_Index (Head, Base_Offset, Size), K, Size) = Wrap_Index (Head, Base_Offset + K, Size));

   -- Content preservation over a window implies content preservation over
   -- a trailing sub window rebased at its own wrapped head index:
   procedure Lemma_CP_Tail (B_Old : in Basic_Types.Byte_Array; B_New : in Basic_Types.Byte_Array; Head : in Natural; Offset : in Natural; Span : in Natural)
      with Ghost,
           Global => null,
           Subprogram_Variant => (Decreases => Span),
           Pre => B_Old'First = 0
              and then B_New'First = 0
              and then B_New'Length = B_Old'Length
              and then B_Old'Length in 1 .. Max_Buffer_Size
              and then Head < B_Old'Length
              and then Offset <= B_Old'Length
              and then Span <= B_Old'Length - Offset
              and then Content_Preserved (B_Old, B_New, Head, Offset + Span),
           Post => Content_Preserved (B_Old, B_New, Wrap_Index (Head, Offset, B_Old'Length), Span);

   -- The record model only depends on the occupied bytes, so it survives
   -- any modification of the free region:
   procedure Lemma_Records_Frame (B_Old : in Basic_Types.Byte_Array; B_New : in Basic_Types.Byte_Array; Head : in Natural; Count : in Natural; Items : in Natural; Min : in Natural)
      with Ghost,
           Global => null,
           Subprogram_Variant => (Decreases => Items),
           Pre => B_Old'First = 0
              and then B_New'First = 0
              and then B_New'Length = B_Old'Length
              and then B_Old'Length in 1 .. Max_Buffer_Size
              and then Head < B_Old'Length
              and then Count <= B_Old'Length
              and then Records_Ok (B_Old, Head, Count, Items)
              and then Min_Lengths_Ok (B_Old, Head, Count, Items, Min)
              and then Content_Preserved (B_Old, B_New, Head, Count),
           Post => Records_Ok (B_New, Head, Count, Items)
              and then Min_Lengths_Ok (B_New, Head, Count, Items, Min);

   -- Appending a well formed record at the tail extends the model by one
   -- record:
   procedure Lemma_Records_Append (Bytes : in Basic_Types.Byte_Array; Head : in Natural; Count : in Natural; Items : in Natural; Min : in Natural; New_Length : in Natural)
      with Ghost,
           Global => null,
           Subprogram_Variant => (Decreases => Items),
           Pre => Bytes'First = 0
              and then Bytes'Length in 1 .. Max_Buffer_Size
              and then Head < Bytes'Length
              and then Items < Natural'Last
              and then Count <= Bytes'Length - Queue_Element_Storage_Overhead
              and then New_Length <= Bytes'Length - Count - Queue_Element_Storage_Overhead
              and then Records_Ok (Bytes, Head, Count, Items)
              and then Min_Lengths_Ok (Bytes, Head, Count, Items, Min)
              and then Header_Ok (Bytes, Wrap_Index (Head, Count, Bytes'Length))
              and then Header_Length (Bytes, Wrap_Index (Head, Count, Bytes'Length)) = New_Length
              and then New_Length >= Min,
           Post => Records_Ok (Bytes, Head, Count + Queue_Element_Storage_Overhead + New_Length, Items + 1)
              and then Min_Lengths_Ok (Bytes, Head, Count + Queue_Element_Storage_Overhead + New_Length, Items + 1, Min);

   -- Popping the head record leaves the model of the remaining records,
   -- for any minimum length bound:
   procedure Lemma_Records_Pop (Bytes : in Basic_Types.Byte_Array; Head : in Natural; Count : in Natural; Items : in Natural; New_Head : in Natural; New_Count : in Natural)
      with Ghost,
           Global => null,
           Pre => Bytes'First = 0
              and then Bytes'Length in 1 .. Max_Buffer_Size
              and then Head < Bytes'Length
              and then Count <= Bytes'Length
              and then Items > 0
              and then Records_Ok (Bytes, Head, Count, Items)
              and then New_Count = Count - Queue_Element_Storage_Overhead - Header_Length (Bytes, Head)
              and then (if New_Count = 0 then New_Head = 0
                        else New_Head = Wrap_Index (Head, Queue_Element_Storage_Overhead + Header_Length (Bytes, Head), Bytes'Length)),
           Post => Records_Ok (Bytes, New_Head, New_Count, Items - 1)
              and then (for all M in Natural =>
                          (if Min_Lengths_Ok (Bytes, Head, Count, Items, M) then
                              Min_Lengths_Ok (Bytes, New_Head, New_Count, Items - 1, M)));

   -- Unfold the model of a non empty queue at its head record:
   procedure Lemma_Records_Head (Bytes : in Basic_Types.Byte_Array; Head : in Natural; Count : in Natural; Items : in Natural)
      with Ghost,
           Global => null,
           Pre => Bytes'First = 0
              and then Bytes'Length in 1 .. Max_Buffer_Size
              and then Head < Bytes'Length
              and then Count <= Bytes'Length
              and then Items > 0
              and then Records_Ok (Bytes, Head, Count, Items),
           Post => Count >= Queue_Element_Storage_Overhead
              and then Header_Ok (Bytes, Head)
              and then Header_Length (Bytes, Head) <= Count - Queue_Element_Storage_Overhead;

   -- Bytes read back from the head of the buffer compose to the stored
   -- header value:
   procedure Lemma_Header_Read (Bytes : in Basic_Types.Byte_Array; Head : in Natural; Header_Bytes : in Length_Byte_Array)
      with Ghost,
           Global => null,
           Pre => Bytes'First = 0
              and then Bytes'Length in Queue_Element_Storage_Overhead .. Max_Buffer_Size
              and then Head < Bytes'Length
              and then (for all I in 0 .. Queue_Element_Storage_Overhead - 1 => Header_Bytes (I) = Element_At (Bytes, Head, I)),
           Post => Compose (Header_Bytes (0), Header_Bytes (1), Header_Bytes (2), Header_Bytes (3)) = Header_U32 (Bytes, Head);

   -- Header bytes written at the tail of the buffer read back as the
   -- stored header value at the tail position:
   procedure Lemma_Header_Written (Bytes : in Basic_Types.Byte_Array; Head : in Natural; Count : in Natural; Header_Bytes : in Length_Byte_Array)
      with Ghost,
           Global => null,
           Pre => Bytes'First = 0
              and then Bytes'Length in 1 .. Max_Buffer_Size
              and then Head < Bytes'Length
              and then Count <= Bytes'Length - Queue_Element_Storage_Overhead
              and then (for all J in 0 .. Queue_Element_Storage_Overhead - 1 => Element_At (Bytes, Head, Count + J) = Header_Bytes (J)),
           Post => Header_U32 (Bytes, Wrap_Index (Head, Count, Bytes'Length)) = Compose (Header_Bytes (0), Header_Bytes (1), Header_Bytes (2), Header_Bytes (3));

   -- Content preservation composes across two successive buffer updates:
   procedure Lemma_Content_Chain (B_First : in Basic_Types.Byte_Array; B_Second : in Basic_Types.Byte_Array; B_Third : in Basic_Types.Byte_Array; Head : in Natural; Count_First : in Natural; Count_Second : in Natural)
      with Ghost,
           Global => null,
           Pre => B_First'First = 0
              and then B_Second'First = 0
              and then B_Third'First = 0
              and then B_Second'Length = B_First'Length
              and then B_Third'Length = B_First'Length
              and then B_First'Length in 1 .. Max_Buffer_Size
              and then Head < B_First'Length
              and then Count_First <= Count_Second
              and then Count_Second <= B_First'Length
              and then Content_Preserved (B_First, B_Second, Head, Count_First)
              and then Content_Preserved (B_Second, B_Third, Head, Count_Second),
           Post => Content_Preserved (B_First, B_Third, Head, Count_First);

   -- A header at the tail position survives an update that preserves the
   -- content up to and including the header:
   procedure Lemma_Header_Preserved (B_Old : in Basic_Types.Byte_Array; B_New : in Basic_Types.Byte_Array; Head : in Natural; Count : in Natural)
      with Ghost,
           Global => null,
           Pre => B_Old'First = 0
              and then B_New'First = 0
              and then B_New'Length = B_Old'Length
              and then B_Old'Length in 1 .. Max_Buffer_Size
              and then Head < B_Old'Length
              and then Count <= B_Old'Length - Queue_Element_Storage_Overhead
              and then Content_Preserved (B_Old, B_New, Head, Count + Queue_Element_Storage_Overhead),
           Post => Header_U32 (B_New, Wrap_Index (Head, Count, B_Old'Length)) = Header_U32 (B_Old, Wrap_Index (Head, Count, B_Old'Length));

   -- Every record takes at least a header of bytes, which bounds the item
   -- count from the byte count:
   procedure Lemma_Records_Count_Bound (Bytes : in Basic_Types.Byte_Array; Head : in Natural; Count : in Natural; Items : in Natural)
      with Ghost,
           Global => null,
           Subprogram_Variant => (Decreases => Items),
           Pre => Bytes'First = 0
              and then Bytes'Length in 1 .. Max_Buffer_Size
              and then Head < Bytes'Length
              and then Count <= Bytes'Length
              and then Records_Ok (Bytes, Head, Count, Items),
           Post => Items <= Count / Queue_Element_Storage_Overhead;

   -- Internal type for queue:
   type Queue is new Queue_Base with record
      null; -- Nothing more needed, just adding methods.
   end record;

end Circular_Buffer;

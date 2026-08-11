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
   -- state. Each derived type overrides this function to state its own,
   -- stronger notion of validity, and every overriding must contain the
   -- conjuncts of the overridden version so that a derived model always
   -- implies the ancestor model. This function is the class-wide
   -- precondition of most operations below.
   function Model_Valid (Self : in Base) return Boolean
      with Ghost;

   -- Ghost predicate stating that the buffer meta data is in its freshly
   -- reset state, as left by Clear or Destroy or as found in a default
   -- initialized object.
   function Is_Reset (Self : in Base) return Boolean
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

   -- Get the length of the oldest item on the queue without removing it.
   function Peek_Length (Self : in Queue_Base; Length : out Natural) return Pop_Status
      with Side_Effects;
   -- Remove an item off the queue, without returning it:
   function Pop (Self : in out Queue_Base) return Pop_Status
      with Side_Effects;

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
   overriding procedure Clear (Self : in out Queue_Base);
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
      with Side_Effects;
   -- Pop data from queue onto a byte array. The number of bytes returned will match the length
   -- of "bytes". If "bytes" cannot be completely filled then Failure is returned.
   function Pop (Self : in out Queue; Bytes : in out Basic_Types.Byte_Array; Length : out Natural; Offset : in Natural := 0) return Pop_Status
      with Side_Effects;
   -- Peek data from queue onto a byte array. This function is like pop, except the bytes are not actually
   -- removed from the internal queue.
   function Peek (Self : in Queue; Bytes : in out Basic_Types.Byte_Array; Length : out Natural; Offset : in Natural := 0) return Pop_Status
      with Side_Effects;

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
   function Model_Valid (Self : in Base) return Boolean is (Valid (Self));
   function Is_Reset (Self : in Base) return Boolean is (Self.Head = 0 and then Self.Count = 0);

   --
   -- Add/remove/look at data on the base buffer:
   --
   -- These take a class-wide parameter so that they are not primitive
   -- operations of the type, which keeps them out of the dispatching
   -- contract rules and lets them carry the precise contracts that the
   -- derived types need internally. They are never dispatched to.
   --
   -- Push data from a byte array onto the buffer. If not enough space remains on the internal buffer to read
   -- store the entire byte array then Failure is returned.
   function Push (Self : in out Base'Class; Bytes : in Basic_Types.Byte_Array; Overwrite : in Boolean := False) return Push_Status
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
   function Pop (Self : in out Base'Class; Bytes : in out Basic_Types.Byte_Array; Num_Bytes_Returned : out Natural) return Pop_Status
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
   function Peek (Self : in Base'Class; Bytes : in out Basic_Types.Byte_Array; Num_Bytes_Returned : out Natural; Offset : in Natural := 0) return Pop_Status
      with Side_Effects,
           Pre => Valid (Self),
           Post => (if Bytes'Length = 0 or else Self.Count > Offset then Peek'Result = Success else Peek'Result = Empty)
              and then Num_Bytes_Returned = (if Bytes'Length = 0 or else Self.Count <= Offset then 0 else Natural'Min (Bytes'Length, Self.Count - Offset))
              and then (for all I in 0 .. Num_Bytes_Returned - 1 =>
                           Bytes (Bytes'First + I) = Element_At (Self.Bytes.all, Self.Head, Offset + I));

   -- Internal type for circular buffer:
   type Circular is new Base with record
      null; -- Nothing more needed, just adding methods.
   end record;

   -- Internal type for queue buffer:
   type Queue_Base is new Base with record
      Item_Count : Natural := 0;
      Item_Max_Count : Natural := 0;
   end record;

   -- Queue Base private subprograms:
   function Push_Length (Self : in out Queue_Base; Element_Length : in Natural) return Push_Status
      with Side_Effects;
   procedure Peek_Bytes (Self : in Queue_Base; Bytes : in out Basic_Types.Byte_Array; Num_Bytes_To_Read : in Natural; Num_Bytes_Read : out Natural; Offset : in Natural := 0);
   procedure Do_Pop (Self : in out Queue_Base; Element_Length : in Natural);

   -- Internal type for queue:
   type Queue is new Queue_Base with record
      null; -- Nothing more needed, just adding methods.
   end record;

end Circular_Buffer;

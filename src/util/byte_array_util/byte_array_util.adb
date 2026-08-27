with Interfaces; use Interfaces;

package body Byte_Array_Util with SPARK_Mode => On is

   -- See the note in the package specification. All contracts are for proof
   -- only and are disabled at runtime:
   pragma Assertion_Policy
      (Pre => Ignore,
       Post => Ignore,
       Contract_Cases => Ignore,
       Ghost => Ignore,
       Loop_Invariant => Ignore,
       Loop_Variant => Ignore,
       Assert_And_Cut => Ignore,
       Assume => Ignore);

   function Safe_Right_Copy (Dest : in out Byte_Array; Src : in Byte_Array) return Natural is
   begin
      -- If the length of both arrays is positive we can do a copy. Otherwise
      -- there is no need to continue.
      if Is_Not_Empty (Src) and then Is_Not_Empty (Dest) then
         declare
            Num_Bytes_To_Copy : constant Natural :=
               Natural'Min (Src'Last - Src'First, Dest'Last - Dest'First) + 1;
         begin
            -- Help static analysis understand that the number of bytes to copy
            -- must be less than or equal to both the destination and src array
            -- lengths at this point. We know that both dest and src cannot be
            -- a null array.
            pragma Assert (Num_Bytes_To_Copy <= Dest'Length);
            pragma Assert (Num_Bytes_To_Copy <= Src'Length);

            -- Perform the copy:
            Dest (Dest'Last - Num_Bytes_To_Copy + 1 .. Dest'Last) := Src (Src'Last - Num_Bytes_To_Copy + 1 .. Src'Last);
            return Num_Bytes_To_Copy;
         end;
      else
         return Natural'First;
      end if;
   end Safe_Right_Copy;

   procedure Safe_Right_Copy (Dest : in out Byte_Array; Src : in Byte_Array) is
      Ignore : Natural;
   begin
      Ignore := Safe_Right_Copy (Dest, Src);
   end Safe_Right_Copy;

   function Safe_Left_Copy (Dest : in out Byte_Array; Src : in Byte_Array) return Natural is
   begin
      -- If the length of both arrays is positive we can do a copy. Otherwise
      -- there is no need to continue.
      if Is_Not_Empty (Src) and then Is_Not_Empty (Dest) then
         declare
            Num_Bytes_To_Copy : constant Natural :=
               Natural'Min (Src'Last - Src'First, Dest'Last - Dest'First) + 1;
         begin
            -- Help static analysis understand that the number of bytes to copy
            -- must be less than or equal to both the destination and src array
            -- lengths at this point. We know that both dest and src cannot be
            -- a null array.
            pragma Assert (Num_Bytes_To_Copy <= Dest'Length);
            pragma Assert (Num_Bytes_To_Copy <= Src'Length);

            -- Perform the copy:
            Dest (Dest'First .. Dest'First + Num_Bytes_To_Copy - 1) := Src (Src'First .. Src'First + Num_Bytes_To_Copy - 1);
            return Num_Bytes_To_Copy;
         end;
      else
         return Natural'First;
      end if;
   end Safe_Left_Copy;

   procedure Safe_Left_Copy (Dest : in out Byte_Array; Src : in Byte_Array) is
      Ignore : Natural;
   begin
      Ignore := Safe_Left_Copy (Dest, Src);
   end Safe_Left_Copy;

   -- A field of at most 32 bits at any bit offset spans at most five bytes. The
   -- extract and set operations below gather those bytes into a 64-bit
   -- accumulator, most significant byte first, operate on the field with one
   -- shift and one mask, and scatter the bytes back. Within the accumulator the
   -- field occupies bits Field_Shift .. Field_Shift + Size - 1, counted from the
   -- least significant bit.

   -- The bytes covering a field and the field's position within them:
   type Field_Span is record
      -- Index of the first and last covering byte, relative to the array's first index:
      First_Byte : Natural;
      Last_Byte : Natural;
      -- Shift from the accumulator's least significant bit to the field's least significant bit:
      Field_Shift : Natural;
   end record;

   -- Most bytes a field can span: 32 bits starting at bit 7 of a byte covers five bytes.
   Max_Span_Bytes : constant Natural := 5;

   -- Locate the bytes covering Size bits at bit Offset:
   function Span_Of (Offset : in Natural; Size : in Positive) return Field_Span
      with
         -- The field fits in a 32-bit value.
         Pre => Size <= Poly_32_Type'Object_Size,
         -- The span holds at most five bytes, the field lies within it, and the last byte starts
         -- before the field ends, so a field that fits the array has a span that fits the array.
         Post => Span_Of'Result.Last_Byte >= Span_Of'Result.First_Byte
            and then Span_Of'Result.Last_Byte - Span_Of'Result.First_Byte < Max_Span_Bytes
            and then Span_Of'Result.Field_Shift < Byte'Object_Size
            and then Long_Long_Integer (Span_Of'Result.Last_Byte) * Long_Long_Integer (Byte'Object_Size) < Long_Long_Integer (Offset) + Long_Long_Integer (Size);

   function Span_Of (Offset : in Natural; Size : in Positive) return Field_Span is
      -- Split the offset into whole bytes and remaining bits, so the arithmetic below stays
      -- small and cannot overflow for any offset:
      Offset_Bytes : constant Natural := Offset / Byte'Object_Size;
      Offset_Bits : constant Natural := Offset mod Byte'Object_Size;
      -- The number of bytes the field covers:
      Num_Bytes : constant Positive := (Offset_Bits + Size - 1) / Byte'Object_Size + 1;
   begin
      return (
         First_Byte => Offset_Bytes,
         Last_Byte => Offset_Bytes + Num_Bytes - 1,
         -- The field starts Offset_Bits from the top of the span and is Size bits long, the
         -- rest of the span below it is the shift:
         Field_Shift => Num_Bytes * Byte'Object_Size - Offset_Bits - Size
      );
   end Span_Of;

   -- A mask of Size ones in the low bits:
   function Field_Mask (Size : in Positive) return Unsigned_32 is
      (Shift_Right (Unsigned_32'Last, Unsigned_32'Object_Size - Size))
      with
         -- The field fits in a 32-bit value.
         Pre => Size <= Poly_32_Type'Object_Size;

   -- The poly type holds its value big endian, most significant byte first:
   function To_Unsigned_32 (Value : in Poly_32_Type) return Unsigned_32 is
      (Shift_Left (Unsigned_32 (Value (Poly_32_Type'First)), 24) or
       Shift_Left (Unsigned_32 (Value (Poly_32_Type'First + 1)), 16) or
       Shift_Left (Unsigned_32 (Value (Poly_32_Type'First + 2)), 8) or
       Unsigned_32 (Value (Poly_32_Type'First + 3)));

   function To_Poly_32 (Value : in Unsigned_32) return Poly_32_Type is
      [Unsigned_8 (Shift_Right (Value, 24) and 16#FF#),
       Unsigned_8 (Shift_Right (Value, 16) and 16#FF#),
       Unsigned_8 (Shift_Right (Value, 8) and 16#FF#),
       Unsigned_8 (Value and 16#FF#)];

   -- Gather the bytes of a span, most significant first, into an accumulator:
   function Gather (Bytes : in Byte_Array; Span : in Field_Span) return Unsigned_64
      with
         -- The span lies within the array.
         Pre => Span.Last_Byte >= Span.First_Byte
            and then Span.Last_Byte - Span.First_Byte < Max_Span_Bytes
            and then Span.Last_Byte < Bytes'Length;

   function Gather (Bytes : in Byte_Array; Span : in Field_Span) return Unsigned_64 is
      Acc : Unsigned_64 := 0;
   begin
      for Idx in Span.First_Byte .. Span.Last_Byte loop
         Acc := Shift_Left (Acc, Byte'Object_Size) or Unsigned_64 (Bytes (Bytes'First + Idx));
      end loop;
      return Acc;
   end Gather;

   -- Scatter an accumulator back over the bytes of a span, most significant first:
   procedure Scatter (Bytes : in out Byte_Array; Span : in Field_Span; Acc : in Unsigned_64)
      with
         -- The span lies within the array.
         Pre => Span.Last_Byte >= Span.First_Byte
            and then Span.Last_Byte - Span.First_Byte < Max_Span_Bytes
            and then Span.Last_Byte < Bytes'Length;

   procedure Scatter (Bytes : in out Byte_Array; Span : in Field_Span; Acc : in Unsigned_64) is
   begin
      for Idx in Span.First_Byte .. Span.Last_Byte loop
         Bytes (Bytes'First + Idx) := Unsigned_8 (Shift_Right (Acc, (Span.Last_Byte - Idx) * Byte'Object_Size) and 16#FF#);
      end loop;
   end Scatter;

   function Extract_Poly_Type (Src : in Byte_Array; Offset : in Natural; Size : in Positive; Is_Signed : in Boolean; Value : out Poly_32_Type) return Extract_Poly_Type_Status is
   begin
      -- Initialize out parameter:
      Value := [0, 0, 0, 0];

      -- Validate offset and size. Size must be <= 32 bits. The size + offset must not overflow
      -- the size of the byte array. Size must be greater than zero. The comparison is done in
      -- 64 bits so that it cannot itself overflow for any offset or array length.
      if Size > Poly_32_Type'Object_Size or else
          Long_Long_Integer (Offset) + Long_Long_Integer (Size) > Long_Long_Integer (Src'Length) * Long_Long_Integer (Byte'Object_Size)
      then
         return Error;
      end if;

      -- OK the we can safely extract the data from the byte array.
      declare
         Span : constant Field_Span := Span_Of (Offset, Size);
         -- Gather the covering bytes and pull out the field:
         Field : Unsigned_32 := Unsigned_32 (Shift_Right (Gather (Src, Span), Span.Field_Shift) and Unsigned_64 (Field_Mask (Size)));
      begin
         -- If the value we extracted is signed and its left-most bit is set, then it is negative
         -- and the bits above the field must be set to 1 to represent it as a 32-bit signed integer.
         if Is_Signed and then Size < Unsigned_32'Object_Size and then (Field and Shift_Left (1, Size - 1)) /= 0 then
            Field := Field or Shift_Left (Unsigned_32'Last, Size);
         end if;
         Value := To_Poly_32 (Field);
      end;

      return Success;
   end Extract_Poly_Type;

   function Set_Poly_Type (Dest : in out Byte_Array; Offset : in Natural; Size : in Positive; Value : in Poly_32_Type; Truncation_Allowed : Boolean := False) return Set_Poly_Type_Status is
   begin
      -- Validate offset and size. Size must be <= 32 bits. The size + offset must not overflow
      -- the size of the byte array. Size must be greater than zero. The comparison is done in
      -- 64 bits so that it cannot itself overflow for any offset or array length.
      if Size > Poly_32_Type'Object_Size or else
          Long_Long_Integer (Offset) + Long_Long_Integer (Size) > Long_Long_Integer (Dest'Length) * Long_Long_Integer (Byte'Object_Size)
      then
         return Error;
      end if;
      pragma Annotate (GNATSAS, Intentional, "condition predetermined", "Defensive check - no current callers use Size > 32, but kept for safety");

      declare
         -- The largest value that fits in the field. Anything above it would be truncated.
         Limit : constant Unsigned_32 := Field_Mask (Size);
         Value_Int : constant Unsigned_32 := To_Unsigned_32 (Value);
      begin
         -- See if truncation would occur:
         if Value_Int > Limit and then not Truncation_Allowed then
            return Truncation_Error;
         end if;

         -- OK, we can safely set the data from the poly type into the byte array: gather the
         -- covering bytes, replace the field bits with the (possibly truncated) value, and
         -- scatter them back. The bits outside the field are untouched.
         declare
            Span : constant Field_Span := Span_Of (Offset, Size);
            Field_Bits : constant Unsigned_64 := Shift_Left (Unsigned_64 (Limit), Span.Field_Shift);
            Acc : constant Unsigned_64 := Gather (Dest, Span);
         begin
            Scatter (Dest, Span, (Acc and not Field_Bits) or Shift_Left (Unsigned_64 (Value_Int and Limit), Span.Field_Shift));
         end;
      end;

      return Success;
   end Set_Poly_Type;

end Byte_Array_Util;

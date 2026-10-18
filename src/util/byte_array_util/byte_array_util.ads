with Basic_Types; use Basic_Types;
with Interfaces; use Interfaces;

-- A collection of utility functions for managing byte arrays:
package Byte_Array_Util with SPARK_Mode => On is

   -- The contracts in this package exist for proof with GNATprove only. The
   -- assertion policy below disables them at runtime, so the generated code
   -- and the runtime behavior of this package is identical to what it was
   -- before the SPARK conversion. The defensive pragma Assert statements in
   -- the package body are not affected by this policy. They remain compiled
   -- in and enabled under the project wide assertion policy, and they are
   -- also proved.
   pragma Assertion_Policy
      (Pre => Ignore,
       Post => Ignore,
       Contract_Cases => Ignore,
       Ghost => Ignore,
       Loop_Invariant => Ignore,
       Loop_Variant => Ignore,
       Assert_And_Cut => Ignore,
       Assume => Ignore);
   pragma Unevaluated_Use_Of_Old (Allow);

   -- Helper functions to determine if array is empty or not.
   function Is_Empty (A : in Byte_Array) return Boolean is (A'First > A'Last)
      with Inline => True;
   function Is_Not_Empty (A : in Byte_Array) return Boolean is (A'Last >= A'First)
      with Inline => True;

   -- Given a source array of bytes copy the right-most bytes in that array to the destination
   -- aligned to the right in the destination array. If src is bigger than dest, only
   -- the amount of bytes available in the destination are copied. If dest is bigger than source
   -- then only the amount of bytes available in the source is copied.
   procedure Safe_Right_Copy (Dest : in out Byte_Array; Src : in Byte_Array)
      with
         Inline => True,
         -- The last N bytes of the destination now equal the last N bytes of the source, where N is the
         -- smaller of the two lengths, and every other destination byte is unchanged.
         Post => (for all I in Dest'Range =>
                    (if I > Dest'Last - Natural'Min (Dest'Length, Src'Length)
                     then Dest (I) = Src (Src'Last - (Dest'Last - I))
                     else Dest (I) = Dest'Old (I)));
   -- Same as above, but the number of bytes copied is returned:
   function Safe_Right_Copy (Dest : in out Byte_Array; Src : in Byte_Array) return Natural
      with
         Side_Effects,
         -- The number of bytes copied is the smaller of the two lengths, the last N bytes of the
         -- destination now equal the last N bytes of the source, and every other destination byte is
         -- unchanged.
         Post => Safe_Right_Copy'Result = Natural'Min (Dest'Length, Src'Length)
            and then (for all I in Dest'Range =>
                        (if I > Dest'Last - Safe_Right_Copy'Result
                         then Dest (I) = Src (Src'Last - (Dest'Last - I))
                         else Dest (I) = Dest'Old (I)));

   -- Given a source array of bytes copy the left-most bytes in that array to the destination
   -- aligned to the left in the destination array. If src is bigger than dest, only
   -- the amount of bytes available in the destination are copied. If dest is bigger than source
   -- then only the amount of bytes available in the source is copied.
   procedure Safe_Left_Copy (Dest : in out Byte_Array; Src : in Byte_Array)
      with
         Inline => True,
         -- The first N bytes of the destination now equal the first N bytes of the source, where N is
         -- the smaller of the two lengths, and every other destination byte is unchanged.
         Post => (for all I in Dest'Range =>
                    (if I < Dest'First + Natural'Min (Dest'Length, Src'Length)
                     then Dest (I) = Src (Src'First + (I - Dest'First))
                     else Dest (I) = Dest'Old (I)));
   -- Same as above, but the number of bytes copied is returned:
   function Safe_Left_Copy (Dest : in out Byte_Array; Src : in Byte_Array) return Natural
      with
         Side_Effects,
         -- The number of bytes copied is the smaller of the two lengths, the first N bytes of the
         -- destination now equal the first N bytes of the source, and every other destination byte is
         -- unchanged.
         Post => Safe_Left_Copy'Result = Natural'Min (Dest'Length, Src'Length)
            and then (for all I in Dest'Range =>
                        (if I < Dest'First + Safe_Left_Copy'Result
                         then Dest (I) = Src (Src'First + (I - Dest'First))
                         else Dest (I) = Dest'Old (I)));

   -- Given a source byte array, extract data into a poly type (32-bits) starting at offset (in bits)
   -- and of size (in bits). If the offset and size are too large to extract from the given byte array,
   -- an error is returned, otherwise Success is returned and the extracted value is supplied in Value,
   -- right shifted as much as possible.
   --
   -- Note: This function assumes Value represents the type in big endian, i.e. MSB first, LSB last (right)
   type Extract_Poly_Type_Status is (Success, Error);

   -- True when a field of Size bits starting Offset bits into an array of Num_Bytes bytes fits both the
   -- poly type and the array. This is the condition under which Extract_Poly_Type and Set_Poly_Type
   -- succeed. The comparison is done in 64 bits so that it cannot overflow for any offset or length.
   function Field_Fits (Offset : in Natural; Size : in Positive; Num_Bytes : in Natural) return Boolean is
      (Size <= Poly_32_Type'Object_Size
         and then Long_Long_Integer (Offset) + Long_Long_Integer (Size) <= Long_Long_Integer (Num_Bytes) * Long_Long_Integer (Byte'Object_Size));

   -- The unsigned integer value of a poly type, which stores its value in big endian:
   function To_Unsigned_32 (Value : in Poly_32_Type) return Unsigned_32 is
      (Unsigned_32 (Value (Poly_32_Type'First + 3)) +
         Shift_Left (Unsigned_32 (Value (Poly_32_Type'First + 2)), 8) +
         Shift_Left (Unsigned_32 (Value (Poly_32_Type'First + 1)), 16) +
         Shift_Left (Unsigned_32 (Value (Poly_32_Type'First + 0)), 24));

   function Extract_Poly_Type (Src : in Byte_Array; Offset : in Natural; Size : in Positive; Is_Signed : in Boolean; Value : out Poly_32_Type) return Extract_Poly_Type_Status
      with
         Side_Effects,
         -- The extraction succeeds exactly when the field fits, and on failure the value is zero.
         Post => (Extract_Poly_Type'Result = Success) = Field_Fits (Offset, Size, Src'Length)
            and then (if Extract_Poly_Type'Result = Error then Value = [0, 0, 0, 0]);

   -- Given a source poly type (32-bits) set bits in the destination byte array starting at offset
   -- (in bits) and size (in bits). The right-most (least significant) bytes in the poly type (Value)
   -- are set in the byte array if size is less than 32-bits. If offset and size are too large to set
   -- in the given byte array, an error is returned, otherwise Success is returned.
   --
   -- The Set_Poly_Type_Status is returned from the function
   --    Success - The polytype was successfully stored in the destination byte array
   --    Truncation_Error - If truncation is not allowed (i.e. Truncation_Allowed = False) then this can occur. This means
   --                                 that the provided polytype value exceeds the value representable in a type with Size size in
   --                                 bytes. This means that some information will be lost during the "set" operation. If this is
   --                                 intended, then Truncation_Allowed must be set to True. In this case, Truncation_Error will
   --                                 never be returned from the function.
   --   Error - The Offset and Size do not fit in the provided destination byte array and thus the "set" operation cannot
   --               be performed.
   --
   -- Note: This function assumes Value represents the type in big endian, i.e. MSB first, LSB last (right)
   type Set_Poly_Type_Status is (Success, Error, Truncation_Error);

   -- True when the value does not fit in Size bits, so that setting it would truncate it:
   function Would_Truncate (Value : in Poly_32_Type; Size : in Positive) return Boolean is
      (To_Unsigned_32 (Value) > Shift_Right (16#FFFFFFFF#, Unsigned_32'Object_Size - Size))
      with Pre => Size <= Poly_32_Type'Object_Size;

   function Set_Poly_Type (Dest : in out Byte_Array; Offset : in Natural; Size : in Positive; Value : in Poly_32_Type; Truncation_Allowed : Boolean := False) return Set_Poly_Type_Status
      with
         Side_Effects,
         -- The status is Error when the field does not fit, Truncation_Error when the value does not
         -- fit in the field and truncation is not allowed, and Success otherwise. Only the bytes that
         -- hold the field change, and nothing changes unless the status is Success.
         Post => Set_Poly_Type'Result =
                    (if not Field_Fits (Offset, Size, Dest'Length) then Error
                     elsif not Truncation_Allowed and then Would_Truncate (Value, Size) then Truncation_Error
                     else Success)
            and then (for all I in Dest'Range =>
                        (if Set_Poly_Type'Result /= Success
                            or else I < Dest'First + Offset / Byte'Object_Size
                            or else I > Dest'First + Offset / Byte'Object_Size + (Offset mod Byte'Object_Size + Size - 1) / Byte'Object_Size
                         then Dest (I) = Dest'Old (I)));

end Byte_Array_Util;

with System;
with Ada.Unchecked_Conversion;

package body Example_Record.Checked_Deserialization with SPARK_Mode => On is

   -- See the note in the package specification. The contracts of the
   -- subprograms declared in this body are for proof only too:
   pragma Assertion_Policy (Pre => Ignore, Post => Ignore);

   use type Basic_Types.Byte;

   -------------------------------------------------------------------------
   -- The raw twin of T
   -------------------------------------------------------------------------
   -- The same layout as T, field for field, with each field typed so that every
   -- bit pattern is a valid value: a modular type of the field's width for the
   -- integer and enumeration fields, and an unsigned word for the float. SPARK
   -- accepts an unchecked conversion into it, since it has no invalid values.
   type Raw_Value_1 is mod 2 ** Value_1_Size;
   type Raw_Value_2 is mod 2 ** Value_2_Size;
   type Raw_Value_3 is mod 2 ** Value_3_Size;
   -- A field of whole bytes is kept as bytes, most significant first: reading it
   -- as a word would need a byte swap on a little endian processor, and the
   -- checks only need particular bytes.
   type Raw_Bytes_4 is array (0 .. 3) of Basic_Types.Byte;
   subtype Raw_Value_4 is Raw_Bytes_4;

   -- The byte array field has no scalar storage order of its own:
   pragma Warnings (Off, "scalar storage order specified for ""Raw_T"" does not apply to component");
   type Raw_T is record
      Value_1 : Raw_Value_1;
      Value_2 : Raw_Value_2;
      Value_3 : Raw_Value_3;
      Value_4 : Raw_Value_4;
   end record
      with Bit_Order => System.High_Order_First,
           Scalar_Storage_Order => System.High_Order_First,
           Size => Size,
           Object_Size => Size,
           Alignment => 1;
   for Raw_T use record
      Value_1 at 0 range 0 .. 4;
      Value_2 at 0 range 5 .. 7;
      Value_3 at 0 range 8 .. 15;
      Value_4 at 0 range 16 .. 47;
   end record;
   pragma Warnings (On, "scalar storage order specified for ""Raw_T"" does not apply to component");

   function To_Raw is new Ada.Unchecked_Conversion (Source => Serialization.Byte_Array, Target => Raw_T);

   -------------------------------------------------------------------------
   -- Field conversions
   -------------------------------------------------------------------------

   -- A signed field is stored in two's complement in its bits. Its raw value is
   -- the unsigned reading of those bits, so values with the top bit set are
   -- negative.
   function To_Signed (Raw : in Raw_Value_2) return Integer is
      (if Raw >= 2 ** (Value_2_Size - 1) then Integer (Raw) - 2 ** Value_2_Size else Integer (Raw))
      with Inline => True;

   -- The bits of a float that mean NaN or infinity, which are not values of the
   -- type: an exponent field of all ones, which spans the low seven bits of the
   -- first byte and the top bit of the second.
   function Is_Finite (Bytes : in Raw_Value_4) return Boolean is
      (not ((Bytes (0) and 16#7F#) = 16#7F# and then (Bytes (1) and 16#80#) = 16#80#))
      with Inline => True;

   -- The bits of a float as a word, most significant byte first:
   function To_Word (Bytes : in Raw_Value_4) return Interfaces.Unsigned_32 is
      (Interfaces.Shift_Left (Interfaces.Unsigned_32 (Bytes (0)), 24) or
       Interfaces.Shift_Left (Interfaces.Unsigned_32 (Bytes (1)), 16) or
       Interfaces.Shift_Left (Interfaces.Unsigned_32 (Bytes (2)), 8) or
       Interfaces.Unsigned_32 (Bytes (3)))
      with Inline => True;

   -- Reinterpret the bits of a finite float. SPARK cannot reinterpret bits as a
   -- float, since NaN and infinity are not values of the type, so this one line
   -- is outside the proof. Its precondition, proved at every call, excludes
   -- exactly those patterns, so the result is always a valid value.
   function Bits_To_Float (Bytes : in Raw_Value_4) return Short_Float
      with
         Inline => True,
         -- The bits hold a finite value.
         Pre => Is_Finite (Bytes);

   function Bits_To_Float (Bytes : in Raw_Value_4) return Short_Float with SPARK_Mode => Off is
      function Convert is new Ada.Unchecked_Conversion (Source => Interfaces.Unsigned_32, Target => Short_Float);
   begin
      return Convert (To_Word (Bytes));
   end Bits_To_Float;

   -------------------------------------------------------------------------
   -- Validation of the raw twin
   -------------------------------------------------------------------------

   -- All fields hold values of their types:
   function Is_Valid (Raw : in Raw_T) return Boolean is
      (To_Signed (Raw.Value_2) in Three_Bit_Signed_Integer
         and then Raw.Value_3 <= My_Color'Pos (My_Color'Last)
         and then Is_Finite (Raw.Value_4));

   -- Check every raw field against its field type. Returns the number of the
   -- first field that is not a value of its type, or zero if all are.
   function First_Invalid_Field (Raw : in Raw_T) return Interfaces.Unsigned_32
      with
         Inline => True,
         -- The result names a field or none, and none means every field is valid.
         Post => First_Invalid_Field'Result <= Interfaces.Unsigned_32 (Num_Fields)
            and then (if First_Invalid_Field'Result = 0 then Is_Valid (Raw));

   function First_Invalid_Field (Raw : in Raw_T) return Interfaces.Unsigned_32 is
   begin
      -- Value_1, a 5 bit modular integer: every 5 bit pattern is a value, so there
      -- is nothing to check.

      -- Value_2, a 3 bit signed integer with range -3 .. 2: the bits can also hold -4.
      if To_Signed (Raw.Value_2) not in Three_Bit_Signed_Integer then
         return 2;
      end if;

      -- Value_3, an 8 bit enumeration with six literals, so 6 .. 255 are not values:
      if Raw.Value_3 > My_Color'Pos (My_Color'Last) then
         return 3;
      end if;

      -- Value_4, a 32 bit float: NaN and infinity are not values.
      if not Is_Finite (Raw.Value_4) then
         return 4;
      end if;

      return 0;
   end First_Invalid_Field;

   -------------------------------------------------------------------------
   -- The operations
   -------------------------------------------------------------------------

   function Valid_And_Deserialize (Bytes : in Serialization.Byte_Array; Item : out T; Errant_Field : out Interfaces.Unsigned_32) return Boolean is
      Raw : constant Raw_T := To_Raw (Bytes);
   begin
      Errant_Field := First_Invalid_Field (Raw);
      if Errant_Field /= 0 then
         -- A failed validation leaves a default value in Item:
         Item := (Value_1 => 0, Value_2 => 0, Value_3 => My_Color'First, Value_4 => 0.0);
         return False;
      end if;

      -- Every field checked out, build the record from the checked fields:
      Item := (
         Value_1 => Five_Bit_Integer (Raw.Value_1),
         Value_2 => To_Signed (Raw.Value_2),
         Value_3 => My_Color'Val (Raw.Value_3),
         Value_4 => Bits_To_Float (Raw.Value_4)
      );
      return True;
   end Valid_And_Deserialize;

   -- Copy a raw twin whose every field has been checked into the record. The
   -- bytes of a valid raw twin are the representation of a valid record, so
   -- the copy is a reinterpretation SPARK cannot express, and this one line is
   -- outside the proof. Its precondition, proved at the call, is the validity
   -- of every field.
   procedure Raw_To_Record (Raw : in Raw_T; Item : out T)
      with
         Inline => True,
         -- Every field holds a value of its type.
         Pre => Is_Valid (Raw);

   procedure Raw_To_Record (Raw : in Raw_T; Item : out T) with SPARK_Mode => Off is
      function Convert is new Ada.Unchecked_Conversion (Source => Raw_T, Target => T);
   begin
      Item := Convert (Raw);
   end Raw_To_Record;

   function Valid_And_Copy (Bytes : in Serialization.Byte_Array; Item : out T; Errant_Field : out Interfaces.Unsigned_32) return Boolean is
      Raw : constant Raw_T := To_Raw (Bytes);
   begin
      Errant_Field := First_Invalid_Field (Raw);
      if Errant_Field /= 0 then
         -- A failed validation leaves a default value in Item:
         Item := (Value_1 => 0, Value_2 => 0, Value_3 => My_Color'First, Value_4 => 0.0);
         return False;
      end if;

      -- Every field checked out, the bytes are the representation of a valid record:
      Raw_To_Record (Raw, Item);
      return True;
   end Valid_And_Copy;

end Example_Record.Checked_Deserialization;

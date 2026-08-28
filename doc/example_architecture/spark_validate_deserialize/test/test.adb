-- Cross check the prototype against the generated two step form: for many byte
-- patterns, Valid_And_Deserialize must agree with Validation.Valid on validity and
-- errant field, and on success its record must equal From_Byte_Array's.
with Ada.Text_IO; use Ada.Text_IO;
with Interfaces; use Interfaces;
with Example_Record;
with Example_Record.Validation;
with Example_Record.Checked_Deserialization;
with Basic_Types;
with Ada.Unchecked_Conversion;

procedure Test is
   use type Example_Record.T;
   Bytes : Example_Record.Serialization.Byte_Array := [others => 0];
   Item_A, Item_B, Item_C : Example_Record.T;
   Valid_A, Valid_B, Valid_C : Boolean;
   Errant_A, Errant_B, Errant_C : Unsigned_32;
   Failures : Natural := 0;
   Successes : Natural := 0;
   Invalids : Natural := 0;
   Validity_Mismatches : Natural := 0;
   Shown : Natural := 0;
   function Bits is new Ada.Unchecked_Conversion (Short_Float, Unsigned_32);
   function Hex (B : Example_Record.Serialization.Byte_Array) return String is
      S : String (1 .. 3 * B'Length);
      D : constant String := "0123456789ABCDEF";
   begin
      for I in B'Range loop
         S (3 * (I - B'First) + 1) := D (Natural (B (I) / 16) + 1);
         S (3 * (I - B'First) + 2) := D (Natural (B (I) mod 16) + 1);
         S (3 * (I - B'First) + 3) := ' ';
      end loop;
      return S;
   end Hex;
   -- Simple deterministic generator:
   Seed : Unsigned_32 := 16#1234_5678#;
   function Next return Basic_Types.Byte is
   begin
      Seed := Seed * 1_664_525 + 1_013_904_223;
      return Basic_Types.Byte (Shift_Right (Seed, 24));
   end Next;
   procedure Check is
   begin
      Valid_A := Example_Record.Validation.Valid (Bytes, Errant_A);
      Valid_B := Example_Record.Checked_Deserialization.Valid_And_Deserialize (Bytes, Item_B, Errant_B);
      Valid_C := Example_Record.Checked_Deserialization.Valid_And_Copy (Bytes, Item_C, Errant_C);
      if Valid_B /= Valid_C or else Errant_B /= Errant_C or else (Valid_B and then (Item_B /= Item_C or else Bits (Item_B.Value_4) /= Bits (Item_C.Value_4))) then
         Put_Line ("MISMATCH between the two forms [" & Hex (Bytes) & "]");
         Failures := Failures + 1;
      end if;
      if Valid_A /= Valid_B or else Errant_A /= Errant_B then
         Validity_Mismatches := Validity_Mismatches + 1;
         if Shown < 12 then
            Shown := Shown + 1;
            Put_Line ("MISMATCH validity [" & Hex (Bytes) & "] generated " & Valid_A'Image & " field " & Errant_A'Image & " prototype " & Valid_B'Image & " field " & Errant_B'Image);
         end if;
         Failures := Failures + 1;
      elsif Valid_A then
         Item_A := Example_Record.Serialization.From_Byte_Array (Bytes);
         if Item_A /= Item_B or else Bits (Item_A.Value_4) /= Bits (Item_B.Value_4) then
            if Shown < 12 then
               Shown := Shown + 1;
               Put_Line ("MISMATCH value [" & Hex (Bytes) & "] generated V1" & Item_A.Value_1'Image & " V2" & Item_A.Value_2'Image & " V3 " & Item_A.Value_3'Image & " V4 bits" & Bits (Item_A.Value_4)'Image
                  & " | prototype V1" & Item_B.Value_1'Image & " V2" & Item_B.Value_2'Image & " V3 " & Item_B.Value_3'Image & " V4 bits" & Bits (Item_B.Value_4)'Image);
            end if;
            Failures := Failures + 1;
         end if;
         Successes := Successes + 1;
      else
         Invalids := Invalids + 1;
      end if;
   end Check;
begin
   -- Exhaustive over the first two bytes (all three small fields), a few float patterns:
   for B0 in Basic_Types.Byte'Range loop
      for B1 in Basic_Types.Byte'Range loop
         for F in 0 .. 7 loop
            Bytes := [B0, B1, others => 0];
            case F is
               when 0 => null;
               when 1 => Bytes (2 .. 5) := [16#3F#, 16#80#, 0, 0];     -- 1.0
               when 2 => Bytes (2 .. 5) := [16#7F#, 16#80#, 0, 0];     -- +Inf
               when 3 => Bytes (2 .. 5) := [16#7F#, 16#C0#, 0, 0];     -- NaN
               when 4 => Bytes (2 .. 5) := [16#FF#, 16#FF#, 16#FF#, 16#FF#]; -- NaN
               when 5 => Bytes (2 .. 5) := [16#80#, 0, 0, 0];          -- -0.0
               when 6 => Bytes (2 .. 5) := [0, 0, 0, 1];               -- denormal
               when 7 => Bytes (2 .. 5) := [16#C2#, 16#F6#, 16#E9#, 16#79#]; -- -123.456
            end case;
            Check;
         end loop;
      end loop;
   end loop;
   -- Random patterns:
   for I in 1 .. 200_000 loop
      for J in Bytes'Range loop
         Bytes (J) := Next;
      end loop;
      Check;
   end loop;
   Put_Line ("valid:" & Successes'Image & " invalid:" & Invalids'Image & " mismatches:" & Failures'Image & " (validity:" & Validity_Mismatches'Image & ")");
   if Failures = 0 then
      Put_Line ("passed.");
   else
      Put_Line ("FAILED.");
   end if;
end Test;

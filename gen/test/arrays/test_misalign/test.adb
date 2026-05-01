--------------------------------------------------------------------------------
-- Misalignment-resilience test for the packed-arrayValidation autocode,
-- structured specifically to be runnable on cross-compiled bareboard
-- targets, which is the real point of this file. Alignment-related bugs
-- in the autocode behave very differently per host:
--
--   * x86_64 Linux silently handles misaligned typed loads, so the same
--     bug that traps on bareboard reads "correctly" on the host. Linux
--     tests will pass even when the autocode is alignment-fragile -- so
--     a host-only regression test cannot catch this class of bug.
--
--   * Cross embedded targets  trap on misaligned
--     `flw` / `lhu` / etc., or return garbage bits depending on the
--     core. Either is a valid "erroneous" outcome per RM 13.3(13/3),
--     and either makes this test fail loudly.
--
-- Why this lives in its own directory rather than as a section of the
-- companion test/test.adb:
--
--   1. test/test.adb pulls in heavy string-formatting plumbing
--      (String_Util.To_Tuple_String, Poly_Type formatters, etc.) that
--      overflow the embedded runtime's secondary stack on bareboard.
--      This file is sized to fit.
--
--   2. The pattern is intentionally different from the rest of gen/test:
--      no `pragma Assert` (suppressible by `pragma Suppress
--      (Assertion_Check)` and ignored under `Assertion_Policy => Ignore`
--      profiles) -- instead a `Check` helper procedure that always
--      runs and increments a counter. The summary at the end is
--      AUnit-text-reporter-format ("Total Tests Run: N / Failed
--      Assertions: 0 / Unexpected Errors: 0") so the cross-test renode
--      runner can scrape pass/fail without parsing Put_Line transcripts.
--
-- Concretely the test exercises Validation.Valid / Get_Field (and the
-- Le variants) at every byte alignment offset 0..N from an aligned
-- base. A regression that re-introduces a typed view overlaid directly
-- on a possibly-misaligned address either traps on bareboard or returns
-- garbage that fails the value comparisons. Per RM 13.3(13/3):
--
--   "If an Address is specified, it is the programmer's responsibility
--   to ensure that the address is valid and appropriate for the entity
--   and its use; otherwise, program execution is erroneous."
--   (http://www.ada-auth.org/standards/22rm/html/RM-13-3.html)

with Ada.Text_IO; use Ada.Text_IO;
with Float_Array;
with Float_Array.Validation;
with Simple_Array;
with Simple_Array.Validation;
with Unaligned_Array;
with Unaligned_Array.Validation;
with Complex_Float_Array;
with Complex_Float_Array.Validation;
with Complex_Array_Le;
with Complex_Array_Le.Validation;
with Packed_F64x3;
with Packed_F64x3.Validation;
with Basic_Types; use Basic_Types;
with Interfaces; use Interfaces;

procedure Test is
   --  Big buffer, explicitly 8-aligned (we exercise an 8-byte primitive
   --  array, so 8 is the largest natural alignment we need any subtest
   --  to start from). Slicing at byte offsets 0..3 gives known-aligned
   --  and known-misaligned start addresses.
   Big : aliased Basic_Types.Byte_Array (0 .. 511) := [others => 0];
   for Big'Alignment use 8;

   --  Pass/fail accounting. A failure prints a message and bumps Failed
   --  but does not raise -- we want to see all failures, not just the
   --  first. The summary at the end is in AUnit's text-reporter format
   --  so the cross runner picks it up.
   Total : Natural := 0;
   Failed : Natural := 0;

   procedure Check (Cond : Boolean; Message : String) is
   begin
      Total := Total + 1;
      if not Cond then
         Failed := Failed + 1;
         Put_Line ("  FAIL: " & Message);
      end if;
   end Check;
begin
   Put_Line ("Validation misalignment tests on RV32IMAF_Test:");

   --------------------------------------------------------------------
   -- Float_Array -- 12 x Short_Float, F32. Byte-aligned 4-byte
   -- elements: this is the original cross-test bug shape.
   -- BE + LE.
   --------------------------------------------------------------------
   declare
      F_Bytes : constant Float_Array.Serialization.Byte_Array :=
         Float_Array.Serialization.To_Byte_Array ([others => 1.5]);
      F_Bytes_Le : constant Float_Array.Serialization_Le.Byte_Array :=
         Float_Array.Serialization_Le.To_Byte_Array ([others => 1.5]);
   begin
      for Offset in 0 .. 3 loop
         -- BE: Valid + Get_Field
         Big (Offset .. Offset + F_Bytes'Length - 1) := F_Bytes;
         declare
            Slice : Float_Array.Serialization.Byte_Array
               with Import, Convention => Ada,
                    Address => Big (Offset)'Address;
            Ignore_Errant : Unsigned_32;
            Ok : constant Boolean := Float_Array.Validation.Valid (Slice, Ignore_Errant);
         begin
            Check (Ok, "Float_Array.Valid offset" & Offset'Image);
            for Idx in 1 .. Float_Array.Length loop
               declare
                  Got : constant Basic_Types.Poly_Type :=
                     Float_Array.Validation.Get_Field (Slice, Unsigned_32 (Idx));
               begin
                  Check (Got = [0, 0, 0, 0, 0, 0, 16#C0#, 16#3F#],
                         "Float_Array.Get_Field offset" & Offset'Image
                         & " idx" & Idx'Image);
               end;
            end loop;
         end;
         Big (Offset .. Offset + F_Bytes'Length - 1) := [others => 0];

         -- LE: Valid_Le + Get_Field_Le
         Big (Offset .. Offset + F_Bytes_Le'Length - 1) := F_Bytes_Le;
         declare
            Slice : Float_Array.Serialization_Le.Byte_Array
               with Import, Convention => Ada,
                    Address => Big (Offset)'Address;
            Ignore_Errant : Unsigned_32;
            Ok : constant Boolean := Float_Array.Validation.Valid_Le (Slice, Ignore_Errant);
         begin
            Check (Ok, "Float_Array.Valid_Le offset" & Offset'Image);
            for Idx in 1 .. Float_Array.Length loop
               declare
                  Got : constant Basic_Types.Poly_Type :=
                     Float_Array.Validation.Get_Field_Le (Slice, Unsigned_32 (Idx));
               begin
                  Check (Got = [0, 0, 0, 0, 0, 0, 16#C0#, 16#3F#],
                         "Float_Array.Get_Field_Le offset" & Offset'Image
                         & " idx" & Idx'Image);
               end;
            end loop;
         end;
         Big (Offset .. Offset + F_Bytes_Le'Length - 1) := [others => 0];
      end loop;
   end;

   --------------------------------------------------------------------
   -- Packed_F64x3 -- 3 x Long_Float, F64. Byte-aligned 8-byte
   -- elements: required_alignment=8 path that the slow-path 8-byte
   -- copy must satisfy. BE + LE.
   --------------------------------------------------------------------
   declare
      D_Bytes : constant Packed_F64x3.Serialization.Byte_Array :=
         Packed_F64x3.Serialization.To_Byte_Array ([others => 1.5]);
      D_Bytes_Le : constant Packed_F64x3.Serialization_Le.Byte_Array :=
         Packed_F64x3.Serialization_Le.To_Byte_Array ([others => 1.5]);
   begin
      for Offset in 0 .. 7 loop
         -- BE
         Big (Offset .. Offset + D_Bytes'Length - 1) := D_Bytes;
         declare
            Slice : Packed_F64x3.Serialization.Byte_Array
               with Import, Convention => Ada, Address => Big (Offset)'Address;
            Ignore_Errant : Unsigned_32;
         begin
            Check (Packed_F64x3.Validation.Valid (Slice, Ignore_Errant),
                   "Packed_F64x3.Valid offset" & Offset'Image);
         end;
         Big (Offset .. Offset + D_Bytes'Length - 1) := [others => 0];

         -- LE
         Big (Offset .. Offset + D_Bytes_Le'Length - 1) := D_Bytes_Le;
         declare
            Slice : Packed_F64x3.Serialization_Le.Byte_Array
               with Import, Convention => Ada, Address => Big (Offset)'Address;
            Ignore_Errant : Unsigned_32;
         begin
            Check (Packed_F64x3.Validation.Valid_Le (Slice, Ignore_Errant),
                   "Packed_F64x3.Valid_Le offset" & Offset'Image);
         end;
         Big (Offset .. Offset + D_Bytes_Le'Length - 1) := [others => 0];
      end loop;
   end;

   --------------------------------------------------------------------
   -- Simple_Array -- 17 x Short_Int (range 1..999), U16. Byte-aligned
   -- 2-byte elements. Valid + invalid. BE + LE.
   --------------------------------------------------------------------
   declare
      Valid_Bytes : constant Simple_Array.Serialization.Byte_Array :=
         Simple_Array.Serialization.To_Byte_Array ([others => 5]);
      Valid_Bytes_Le : constant Simple_Array.Serialization_Le.Byte_Array :=
         Simple_Array.Serialization_Le.To_Byte_Array ([others => 5]);
      Invalid_Bytes : Simple_Array.Serialization.Byte_Array := Valid_Bytes;
      Invalid_Bytes_Le : Simple_Array.Serialization_Le.Byte_Array := Valid_Bytes_Le;
   begin
      Invalid_Bytes (4) := 16#FF#;
      Invalid_Bytes (5) := 16#FF#;
      Invalid_Bytes_Le (4) := 16#FF#;
      Invalid_Bytes_Le (5) := 16#FF#;
      for Offset in 0 .. 3 loop
         -- BE valid
         Big (Offset .. Offset + Valid_Bytes'Length - 1) := Valid_Bytes;
         declare
            Slice : Simple_Array.Serialization.Byte_Array
               with Import, Convention => Ada, Address => Big (Offset)'Address;
            Ignore_Errant : Unsigned_32;
         begin
            Check (Simple_Array.Validation.Valid (Slice, Ignore_Errant),
                   "Simple_Array.Valid offset" & Offset'Image);
         end;
         Big (Offset .. Offset + Valid_Bytes'Length - 1) := [others => 0];

         -- BE invalid
         Big (Offset .. Offset + Invalid_Bytes'Length - 1) := Invalid_Bytes;
         declare
            Slice : Simple_Array.Serialization.Byte_Array
               with Import, Convention => Ada, Address => Big (Offset)'Address;
            Errant : Unsigned_32;
            Ok : constant Boolean := Simple_Array.Validation.Valid (Slice, Errant);
         begin
            Check (not Ok, "Simple_Array.Valid invalid offset" & Offset'Image);
            Check (Errant = 3, "Simple_Array Errant=3 offset" & Offset'Image);
         end;
         Big (Offset .. Offset + Invalid_Bytes'Length - 1) := [others => 0];

         -- LE valid
         Big (Offset .. Offset + Valid_Bytes_Le'Length - 1) := Valid_Bytes_Le;
         declare
            Slice : Simple_Array.Serialization_Le.Byte_Array
               with Import, Convention => Ada, Address => Big (Offset)'Address;
            Ignore_Errant : Unsigned_32;
         begin
            Check (Simple_Array.Validation.Valid_Le (Slice, Ignore_Errant),
                   "Simple_Array.Valid_Le offset" & Offset'Image);
         end;
         Big (Offset .. Offset + Valid_Bytes_Le'Length - 1) := [others => 0];

         -- LE invalid
         Big (Offset .. Offset + Invalid_Bytes_Le'Length - 1) := Invalid_Bytes_Le;
         declare
            Slice : Simple_Array.Serialization_Le.Byte_Array
               with Import, Convention => Ada, Address => Big (Offset)'Address;
            Errant : Unsigned_32;
            Ok : constant Boolean := Simple_Array.Validation.Valid_Le (Slice, Errant);
         begin
            Check (not Ok, "Simple_Array.Valid_Le invalid offset" & Offset'Image);
            Check (Errant = 3, "Simple_Array Errant_Le=3 offset" & Offset'Image);
         end;
         Big (Offset .. Offset + Invalid_Bytes_Le'Length - 1) := [others => 0];
      end loop;
   end;

   --------------------------------------------------------------------
   -- Unaligned_Array -- 8 x Short_Int (range 0..999), U10. Sub-byte;
   -- always-slow-path. BE + LE.
   --------------------------------------------------------------------
   declare
      U_Valid : constant Unaligned_Array.Serialization.Byte_Array :=
         Unaligned_Array.Serialization.To_Byte_Array ([others => 7]);
      U_Valid_Le : constant Unaligned_Array.Serialization_Le.Byte_Array :=
         Unaligned_Array.Serialization_Le.To_Byte_Array ([others => 7]);
   begin
      for Offset in 0 .. 3 loop
         Big (Offset .. Offset + U_Valid'Length - 1) := U_Valid;
         declare
            Slice : Unaligned_Array.Serialization.Byte_Array
               with Import, Convention => Ada, Address => Big (Offset)'Address;
            Ignore_Errant : Unsigned_32;
         begin
            Check (Unaligned_Array.Validation.Valid (Slice, Ignore_Errant),
                   "Unaligned_Array.Valid offset" & Offset'Image);
         end;
         Big (Offset .. Offset + U_Valid'Length - 1) := [others => 0];

         Big (Offset .. Offset + U_Valid_Le'Length - 1) := U_Valid_Le;
         declare
            Slice : Unaligned_Array.Serialization_Le.Byte_Array
               with Import, Convention => Ada, Address => Big (Offset)'Address;
            Ignore_Errant : Unsigned_32;
         begin
            Check (Unaligned_Array.Validation.Valid_Le (Slice, Ignore_Errant),
                   "Unaligned_Array.Valid_Le offset" & Offset'Image);
         end;
         Big (Offset .. Offset + U_Valid_Le'Length - 1) := [others => 0];
      end loop;
   end;

   --------------------------------------------------------------------
   -- Complex_Float_Array -- record-of-floats packed element. BE only
   -- (this type is BE).
   --------------------------------------------------------------------
   declare
      CF_Bytes : constant Complex_Float_Array.Serialization.Byte_Array :=
         Complex_Float_Array.Serialization.To_Byte_Array (
            [others => (Yo => 17, F => (One => 5, Two => 21.5, Three => 50.2345))]);
   begin
      for Offset in 0 .. 3 loop
         Big (Offset .. Offset + CF_Bytes'Length - 1) := CF_Bytes;
         declare
            Slice : Complex_Float_Array.Serialization.Byte_Array
               with Import, Convention => Ada, Address => Big (Offset)'Address;
            Ignore_Errant : Unsigned_32;
         begin
            Check (Complex_Float_Array.Validation.Valid (Slice, Ignore_Errant),
                   "Complex_Float_Array.Valid offset" & Offset'Image);
         end;
         Big (Offset .. Offset + CF_Bytes'Length - 1) := [others => 0];
      end loop;
   end;

   --------------------------------------------------------------------
   -- Complex_Array_Le -- LE record-element variant. Exercises
   -- Valid_Le path for the packed-record-element case (LE only --
   -- this type is LE).
   --------------------------------------------------------------------
   declare
      CL_Bytes : constant Complex_Array_Le.Serialization_Le.Byte_Array :=
         Complex_Array_Le.Serialization_Le.To_Byte_Array (
            [others => (One => 0, Two => 19, Three => 5)]);
   begin
      for Offset in 0 .. 3 loop
         Big (Offset .. Offset + CL_Bytes'Length - 1) := CL_Bytes;
         declare
            Slice : Complex_Array_Le.Serialization_Le.Byte_Array
               with Import, Convention => Ada, Address => Big (Offset)'Address;
            Ignore_Errant : Unsigned_32;
         begin
            Check (Complex_Array_Le.Validation.Valid_Le (Slice, Ignore_Errant),
                   "Complex_Array_Le.Valid_Le offset" & Offset'Image);
         end;
         Big (Offset .. Offset + CL_Bytes'Length - 1) := [others => 0];
      end loop;
   end;

   -- AUnit text-reporter-style summary, picked up by the cross runner.
   New_Line;
   Put_Line ("Total Tests Run:   " & Total'Image);
   Put_Line ("Successful Tests:  " & Natural'Image (Total - Failed));
   Put_Line ("Failed Assertions: " & Failed'Image);
   Put_Line ("Unexpected Errors:  0");
end Test;

--------------------------------------------------------------------------------
-- Misalignment-resilience test for the packed-record Validation autocode,
-- structured specifically to be runnable on cross-compiled bareboard
-- targets, which is the real point of this file. Alignment-related bugs
-- in the autocode behave very differently per host:
--
--   * x86_64 Linux silently handles misaligned typed loads, so the same
--     bug that traps on bareboard reads "correctly" on the host. Linux
--     tests will pass even when the autocode is alignment-fragile -- so
--     a host-only regression test cannot catch this class of bug.
--
--   * Cross embedded targets can trap or return
--     garbage bits on misaligned typed loads, either of which makes
--     this test fail loudly.
--
-- Why this lives in its own directory rather than as a section of the
-- companion gen/test/records/test/test.adb (and follows a different
-- pattern than the rest of gen/test):
--
--   1. The companion test pulls in heavy string-formatting plumbing
--      that overflows the embedded runtime's secondary stack on
--      bareboard. This file is sized to fit.
--
--   2. The pattern is intentionally different: no `pragma Assert`
--      (suppressible by `pragma Suppress (Assertion_Check)` and
--      ignored under `Assertion_Policy => Ignore` profiles) -- instead
--      a `Check` helper procedure that always runs and increments a
--      counter. The summary at the end is AUnit-text-reporter-format
--      ("Total Tests Run: N / Failed Assertions: 0 / Unexpected
--      Errors: 0") so the cross-test renode runner can scrape pass/
--      fail without parsing Put_Line transcripts.
--
-- The record-template-specific thing this exercises: the record
-- validation template's "no copy needed" decision rests on
-- bit-packed-record codegen producing byte-extract reads at any byte
-- address (T'Alignment = 1, asserted at build time via the template's
-- pragma Compile_Time_Error). The Compile_Time_Error catches a future
-- change that loosens that invariant; this test catches a runtime
-- regression in the bit-extract codegen at every byte offset 0..3.
--
-- Per RM 13.3(13/3):
--   "If an Address is specified, it is the programmer's responsibility
--   to ensure that the address is valid and appropriate for the entity
--   and its use; otherwise, program execution is erroneous."
--   (http://www.ada-auth.org/standards/22rm/html/RM-13-3.html)

with Ada.Text_IO; use Ada.Text_IO;
with Always_Valid_Simple;
with Always_Valid_Simple.Validation;
with Aa;
with Aa.Validation;
with Ff;
with Ff.Validation;
with Basic_Types;
with Interfaces; use Interfaces;

procedure Test is
   --  Big buffer, explicitly 4-aligned.
   Big : aliased Basic_Types.Byte_Array (0 .. 255) := [others => 0];
   for Big'Alignment use 4;

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
   Put_Line ("Validation misalignment tests (records):");

   --------------------------------------------------------------------
   -- Always_Valid_Simple -- U8 + U16 + U32, no range checks. BE + LE.
   --------------------------------------------------------------------
   declare
      Bytes : constant Always_Valid_Simple.Serialization.Byte_Array :=
         Always_Valid_Simple.Serialization.To_Byte_Array (
            (A => 16#A5#, B => 16#1234#, C => 16#DEADBEEF#));
      Bytes_Le : constant Always_Valid_Simple.Serialization_Le.Byte_Array :=
         Always_Valid_Simple.Serialization_Le.To_Byte_Array (
            (A => 16#A5#, B => 16#1234#, C => 16#DEADBEEF#));
   begin
      for Offset in 0 .. 3 loop
         Big (Offset .. Offset + Bytes'Length - 1) := Bytes;
         declare
            Slice : Always_Valid_Simple.Serialization.Byte_Array
               with Import, Convention => Ada,
                    Address => Big (Offset)'Address;
            Ignore_Errant : Unsigned_32;
         begin
            Check (Always_Valid_Simple.Validation.Valid (Slice, Ignore_Errant),
                   "Always_Valid_Simple.Valid offset" & Offset'Image);
         end;
         Big (Offset .. Offset + Bytes'Length - 1) := [others => 0];

         Big (Offset .. Offset + Bytes_Le'Length - 1) := Bytes_Le;
         declare
            Slice : Always_Valid_Simple.Serialization_Le.Byte_Array
               with Import, Convention => Ada,
                    Address => Big (Offset)'Address;
            Ignore_Errant : Unsigned_32;
         begin
            Check (Always_Valid_Simple.Validation.Valid_Le (Slice, Ignore_Errant),
                   "Always_Valid_Simple.Valid_Le offset" & Offset'Image);
         end;
         Big (Offset .. Offset + Bytes_Le'Length - 1) := [others => 0];
      end loop;
   end;

   --------------------------------------------------------------------
   -- Aa -- range-constrained U8 + U8 + U16. Valid + invalid path.
   -- BE + LE.
   --------------------------------------------------------------------
   declare
      Valid_Bytes : constant Aa.Serialization.Byte_Array :=
         Aa.Serialization.To_Byte_Array ((One => 4, Two => 20, Three => 101));
      Valid_Bytes_Le : constant Aa.Serialization_Le.Byte_Array :=
         Aa.Serialization_Le.To_Byte_Array ((One => 4, Two => 20, Three => 101));
      Invalid_Bytes : Aa.Serialization.Byte_Array := Valid_Bytes;
      Invalid_Bytes_Le : Aa.Serialization_Le.Byte_Array := Valid_Bytes_Le;
   begin
      Invalid_Bytes (Invalid_Bytes'First) := 16#FF#;  -- One out of range
      Invalid_Bytes_Le (Invalid_Bytes_Le'First) := 16#FF#;
      for Offset in 0 .. 3 loop
         -- BE valid
         Big (Offset .. Offset + Valid_Bytes'Length - 1) := Valid_Bytes;
         declare
            Slice : Aa.Serialization.Byte_Array
               with Import, Convention => Ada, Address => Big (Offset)'Address;
            Ignore_Errant : Unsigned_32;
         begin
            Check (Aa.Validation.Valid (Slice, Ignore_Errant),
                   "Aa.Valid offset" & Offset'Image);
         end;
         Big (Offset .. Offset + Valid_Bytes'Length - 1) := [others => 0];

         -- BE invalid
         Big (Offset .. Offset + Invalid_Bytes'Length - 1) := Invalid_Bytes;
         declare
            Slice : Aa.Serialization.Byte_Array
               with Import, Convention => Ada, Address => Big (Offset)'Address;
            Errant : Unsigned_32;
            Ok : constant Boolean := Aa.Validation.Valid (Slice, Errant);
         begin
            Check (not Ok, "Aa.Valid invalid offset" & Offset'Image);
            Check (Errant = 1, "Aa Errant=1 offset" & Offset'Image);
         end;
         Big (Offset .. Offset + Invalid_Bytes'Length - 1) := [others => 0];

         -- LE valid
         Big (Offset .. Offset + Valid_Bytes_Le'Length - 1) := Valid_Bytes_Le;
         declare
            Slice : Aa.Serialization_Le.Byte_Array
               with Import, Convention => Ada, Address => Big (Offset)'Address;
            Ignore_Errant : Unsigned_32;
         begin
            Check (Aa.Validation.Valid_Le (Slice, Ignore_Errant),
                   "Aa.Valid_Le offset" & Offset'Image);
         end;
         Big (Offset .. Offset + Valid_Bytes_Le'Length - 1) := [others => 0];

         -- LE invalid
         Big (Offset .. Offset + Invalid_Bytes_Le'Length - 1) := Invalid_Bytes_Le;
         declare
            Slice : Aa.Serialization_Le.Byte_Array
               with Import, Convention => Ada, Address => Big (Offset)'Address;
            Errant : Unsigned_32;
            Ok : constant Boolean := Aa.Validation.Valid_Le (Slice, Errant);
         begin
            Check (not Ok, "Aa.Valid_Le invalid offset" & Offset'Image);
            Check (Errant = 1, "Aa Errant_Le=1 offset" & Offset'Image);
         end;
         Big (Offset .. Offset + Invalid_Bytes_Le'Length - 1) := [others => 0];
      end loop;
   end;

   --------------------------------------------------------------------
   -- Ff -- U8 + Short_Float (F32) + Long_Float (F64). The FP loads
   -- are the alignment-sensitive case on RV32. F32 is at within-record
   -- byte 1 and F64 at byte 5, so even at outer offset 0 the inner
   -- FP fields are at within-record misalignments. BE + LE.
   --------------------------------------------------------------------
   declare
      Bytes : constant Ff.Serialization.Byte_Array :=
         Ff.Serialization.To_Byte_Array (
            (One => 7, Two => 1.5, Three => 2.71828182845904523));
      Bytes_Le : constant Ff.Serialization_Le.Byte_Array :=
         Ff.Serialization_Le.To_Byte_Array (
            (One => 7, Two => 1.5, Three => 2.71828182845904523));
   begin
      for Offset in 0 .. 3 loop
         -- BE
         Big (Offset .. Offset + Bytes'Length - 1) := Bytes;
         declare
            Slice : Ff.Serialization.Byte_Array
               with Import, Convention => Ada, Address => Big (Offset)'Address;
            Ignore_Errant : Unsigned_32;
         begin
            Check (Ff.Validation.Valid (Slice, Ignore_Errant),
                   "Ff.Valid offset" & Offset'Image);
            -- Force every Get_Field path to fire its byte-extract loads.
            declare
               One : constant Basic_Types.Poly_Type :=
                  Ff.Validation.Get_Field (Slice, 1);
               Two : constant Basic_Types.Poly_Type :=
                  Ff.Validation.Get_Field (Slice, 2);
               Three : constant Basic_Types.Poly_Type :=
                  Ff.Validation.Get_Field (Slice, 3);
            begin
               Check (One (One'Last) = 7,
                      "Ff Get_Field One offset" & Offset'Image);
               Check (Two'Length > 0 and then Three'Length > 0,
                      "Ff Get_Field FP-readback offset" & Offset'Image);
            end;
         end;
         Big (Offset .. Offset + Bytes'Length - 1) := [others => 0];

         -- LE
         Big (Offset .. Offset + Bytes_Le'Length - 1) := Bytes_Le;
         declare
            Slice : Ff.Serialization_Le.Byte_Array
               with Import, Convention => Ada, Address => Big (Offset)'Address;
            Ignore_Errant : Unsigned_32;
         begin
            Check (Ff.Validation.Valid_Le (Slice, Ignore_Errant),
                   "Ff.Valid_Le offset" & Offset'Image);
            declare
               One : constant Basic_Types.Poly_Type :=
                  Ff.Validation.Get_Field_Le (Slice, 1);
               Two : constant Basic_Types.Poly_Type :=
                  Ff.Validation.Get_Field_Le (Slice, 2);
               Three : constant Basic_Types.Poly_Type :=
                  Ff.Validation.Get_Field_Le (Slice, 3);
            begin
               Check (One (One'Last) = 7,
                      "Ff Get_Field_Le One offset" & Offset'Image);
               Check (Two'Length > 0 and then Three'Length > 0,
                      "Ff Get_Field_Le FP-readback offset" & Offset'Image);
            end;
         end;
         Big (Offset .. Offset + Bytes_Le'Length - 1) := [others => 0];
      end loop;
   end;

   -- AUnit text-reporter-style summary, picked up by the cross runner.
   New_Line;
   Put_Line ("Total Tests Run:   " & Total'Image);
   Put_Line ("Successful Tests:  " & Natural'Image (Total - Failed));
   Put_Line ("Failed Assertions: " & Failed'Image);
   Put_Line ("Unexpected Errors:  0");
end Test;

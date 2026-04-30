--------------------------------------------------------------------------------
-- {{ formatType(model_name) }} {{ formatType(model_type) }} Validation Body
--
-- Generated from {{ filename }} on {{ time }}.
--------------------------------------------------------------------------------

{% if unpacked_types %}
-- Standard includes:
with Byte_Array_Util;

{% endif %}
{% if required_alignment > 1 %}
-- For runtime alignment check on Bytes' address:
with System.Storage_Elements;
{% endif %}
{% if packed_type_includes %}
-- Record Field Includes:
{% for include in packed_type_includes %}
with {{ include }}.Validation;
{% endfor %}

{% endif %}
package body {{ name }}.Validation is

   -- Packed arrays (unlike packed records) are not allowed to have
   -- Alignment => 1 unless their component size is 1, so GNAT picks
   -- a non-trivial T'Alignment for most cases. Overlaying T on a
   -- Byte_Array (natural alignment 1) at a runtime address that
   -- doesn't satisfy T'Alignment is erroneous per Ada 2022 RM
   -- 13.3(13/3):
   --
   --   "If an Address is specified, it is the programmer's
   --   responsibility to ensure that the address is valid and
   --   appropriate for the entity and its use; otherwise, program
   --   execution is erroneous."
   --   (http://www.ada-auth.org/standards/22rm/html/RM-13-3.html)
   --
   -- In practice this manifests as silent garbage on x86 hosts (GNAT
   -- folds the misalignment) and as traps or garbage reads on
   -- alignment-strict bareboard targets.
   --
   -- The autocode picks one of three patterns depending on the
   -- element shape (computed in gen/models/array.py as
   -- `required_alignment`):
   --
   --   * Packed-record element (T'Alignment = 1) -- direct overlay,
   --     no copy needed; any byte address satisfies the requirement.
   --
   --   * Byte-aligned primitive (Short_Float, Unsigned_32, ...) --
   --     fast path overlays directly when Bytes' runtime address
   --     already satisfies T'Alignment, slow path copies into an
   --     aligned local Byte_Array and overlays on the copy.
   --
   --   * Sub-byte primitive (e.g. T'Component_Size = 10) -- always
   --     copy into the aligned local. GNAT's bit-extract codegen
   --     still issues word loads under the hood, so a misaligned
   --     direct overlay would read garbage on bareboard.
   --
   -- Each Valid / Get_Field path emits a `pragma Compile_Time_Error`
   -- that fails the build if T'Alignment ever exceeds the static
   -- `required_alignment` literal -- i.e. if the model's formula is
   -- wrong for some target.

{% if endianness in ["either", "big"] %}
   function Valid (
      Bytes : in Serialization.Byte_Array;
      Errant_Field : out Unsigned_32;
      First_Index : in Unconstrained_Index_Type := T'First;
      Last_Index : in Unconstrained_Index_Type := T'Last
   ) return Boolean is
{% if required_alignment > 1 %}
      use System.Storage_Elements;
{% endif %}

      -- Walk the elements through R and set Errant_Field on the first
      -- invalid one. Errant_Field is the outer Valid's `out`
      -- parameter.
      function Valid_Through (R : in T) return Boolean is
{% if packed_type_includes %}
         E_Field : Interfaces.Unsigned_32;
{% endif %}
         Count : Interfaces.Unsigned_32 := 0;
      begin
         -- Sometimes the valid functions below will NEVER be false, since the type can never be out of range,
         -- i.e. with an Unsigned_16. If this is the case Ada warns that some code can never be executed. This
         -- is OK and we want the compiler to delete this code, so ignore the warning.
         pragma Warnings (Off, "this code can never be executed and has been deleted");

         -- Check each element:
{% if element.skip_validation %}
         -- Validation turned off for this element type.
{% elif element.is_packed_type %}
         -- Only iterate if the element type can actually be invalid.
         if not {{ element.type_package }}.Always_Valid then
            for Idx in First_Index .. Last_Index loop
               declare
                  Elem_Bytes : {{ element.type_package }}.Serialization.Byte_Array
                     with Import, Convention => Ada, Address => R (Idx)'Address;
               begin
                  if not {{ element.type_package }}.Validation.Valid (Elem_Bytes, E_Field) then
                     Errant_Field := Count * {{ element.type_model.num_fields }} + E_Field;
                     return False;
                  end if;
               end;
               Count := @ + 1;
            end loop;
         end if;
{% else %}
         for Idx in First_Index .. Last_Index loop
{% if element.format.length %}
            for Jdx in R (Idx)'Range loop
               if not R (Idx)(Jdx)'Valid then
                  Errant_Field := Count + 1;
                  pragma Annotate (GNATSAS, Intentional, "dead code", "some array elements may not be bit-constrained and thus will always be valid");
                  return False;
               end if;
            end loop;
{% else %}
            if not R (Idx)'Valid then
               Errant_Field := Count + 1;
               pragma Annotate (GNATSAS, Intentional, "dead code", "some array elements may not be bit-constrained and thus will always be valid");
               return False;
            end if;
{% endif %}
            Count := @ + 1;
         end loop;
{% endif %}

         -- Re-enable warning.
         pragma Warnings (On, "this code can never be executed and has been deleted");

         -- Everything checks out:
         Errant_Field := 0;
         return True;
      end Valid_Through;
   begin
      -- Compile-time safety assertion. The slow-path overlay below
      -- is non-erroneous per RM 13.3(13/3) iff
      --   our_literal >= T'Alignment           AND
      --   our_literal mod T'Alignment = 0
      -- Ada alignments are always powers of 2, and gen/models/
      -- array.py asserts our literal is a power of 2 too -- so the
      -- second condition follows from the first (any pow2 >= a
      -- smaller pow2 is a multiple of it). We only emit the first
      -- here because GNAT folds `T'Alignment > N` to a static
      -- expression for Compile_Time_Error but doesn't fold mod or
      -- chained equality on T'Alignment portably (some build
      -- profiles -- e.g. coverage builds and -gnaty-driven style
      -- checks -- reject those as "not known at compile time").
      -- Over-aligning (literal > T'Alignment) is allowed -- e.g.
      -- for an 80-bit sub-byte array Linux GNAT picks
      -- T'Alignment=16 while RV32 picks 2; the model emits 16 (the
      -- max we've seen) which over-aligns harmlessly on RV32.
      pragma Compile_Time_Error (T'Alignment > {{ required_alignment }},
         "T'Alignment > static literal ({{ required_alignment }}); update gen/models/array.py");

{% if required_alignment == 1 %}
      -- T'Alignment == 1: any byte address satisfies the overlay's
      -- alignment requirement, so no copy is ever needed.
      declare
         R : T with Import, Convention => Ada, Address => Bytes'Address;
      begin
         return Valid_Through (R);
      end;
{% else %}
      -- Fast path: Bytes' runtime address already satisfies
      -- T'Alignment, overlay directly -- no copy.
      if To_Integer (Bytes'Address) mod T'Alignment = 0 then
         declare
            R : T with Import, Convention => Ada, Address => Bytes'Address;
         begin
            return Valid_Through (R);
         end;
      else
         -- Slow path: copy into a Byte_Array local with alignment
         -- matching T'Alignment so the typed overlay below is not
         -- erroneous. Byte-by-byte assignment is itself alignment-
         -- safe.
         declare
            Aligned_Bytes : Serialization.Byte_Array := Bytes
               with Alignment => {{ required_alignment }};
            R : T with Import, Convention => Ada, Address => Aligned_Bytes'Address;
         begin
            return Valid_Through (R);
         end;
      end if;
{% endif %}
   exception
      -- From: http://www.adaic.org/resources/add_content/standards/05aarm/html/AA-13-9-2.html
      -- The Valid attribute may be used to check the result of calling an
      -- instance of Unchecked_Conversion (or any other operation that can
      -- return invalid values). However, an exception handler should also
      -- be provided because implementations are permitted to raise
      -- Constraint_Error or Program_Error if they detect the use of an
      -- invalid representation (see 13.9.1).
      when Constraint_Error =>
         Errant_Field := 0;
         return False;
      when Program_Error =>
         Errant_Field := 0;
         return False;
   end Valid;

{% endif %}
{% if endianness in ["either", "little"] %}
   function Valid_Le (
      Bytes : in Serialization_Le.Byte_Array;
      Errant_Field : out Unsigned_32;
      First_Index : in Unconstrained_Index_Type := T_Le'First;
      Last_Index : in Unconstrained_Index_Type := T_Le'Last
   ) return Boolean is
{% if required_alignment > 1 %}
      use System.Storage_Elements;
{% endif %}

      -- Walk the elements through R and set Errant_Field on the first
      -- invalid one. Errant_Field is the outer Valid's `out`
      -- parameter.
      function Valid_Le_Through (R : T_Le) return Boolean is
{% if packed_type_includes %}
         E_Field : Interfaces.Unsigned_32;
{% endif %}
         Count : Interfaces.Unsigned_32 := 0;
      begin
         -- Sometimes the valid functions below will NEVER be false, since the type can never be out of range,
         -- i.e. with an Unsigned_16. If this is the case Ada warns that some code can never be executed. This
         -- is OK and we want the compiler to delete this code, so ignore the warning.
         pragma Warnings (Off, "this code can never be executed and has been deleted");

         -- Check each element:
{% if element.skip_validation %}
         -- Validation turned off for this element type.
{% elif element.is_packed_type %}
         -- Only iterate if the element type can actually be invalid.
         if not {{ element.type_package }}.Always_Valid then
            for Idx in First_Index .. Last_Index loop
               declare
                  Elem_Bytes : {{ element.type_package }}.Serialization_Le.Byte_Array
                     with Import, Convention => Ada, Address => R (Idx)'Address;
               begin
                  if not {{ element.type_package }}.Validation.Valid_Le (Elem_Bytes, E_Field) then
                     Errant_Field := Count * {{ element.type_model.num_fields }} + E_Field;
                     return False;
                  end if;
               end;
               Count := @ + 1;
            end loop;
         end if;
{% else %}
         for Idx in First_Index .. Last_Index loop
{% if element.format.length %}
            for Jdx in R (Idx)'Range loop
               if not R (Idx)(Jdx)'Valid then
                  Errant_Field := Count + 1;
                  pragma Annotate (GNATSAS, Intentional, "dead code", "some array elements may not be bit-constrained and thus will always be valid");
                  return False;
               end if;
            end loop;
{% else %}
            if not R (Idx)'Valid then
               Errant_Field := Count + 1;
               pragma Annotate (GNATSAS, Intentional, "dead code", "some array elements may not be bit-constrained and thus will always be valid");
               return False;
            end if;
{% endif %}
            Count := @ + 1;
         end loop;
{% endif %}

         -- Re-enable warning.
         pragma Warnings (On, "this code can never be executed and has been deleted");

         -- Everything checks out:
         Errant_Field := 0;
         return True;
      end Valid_Le_Through;
   begin
      -- Compile-time safety assertion: our static literal
      -- (computed in gen/models/array.py) must satisfy BOTH
      --   our_literal >= T_Le'Alignment           (no under-aligning)
      --   our_literal mod T_Le'Alignment = 0      (a multiple of it)
      -- to make the slow-path overlay below non-erroneous per RM
      -- 13.3(13/3). For Ada (alignments are powers of 2) the
      -- second implies the first, but writing both explicitly is
      -- clearer at the assert site and works for any future case
      -- where the invariant changes. Over-aligning (literal >
      -- T_Le'Alignment but still a multiple) is allowed -- e.g. for
      -- an 80-bit sub-byte array Linux GNAT picks T_Le'Alignment=16
      -- while RV32 picks 2; the model emits 16 (the max we've
      -- seen) which over-aligns harmlessly on RV32.
      pragma Compile_Time_Error (T_Le'Alignment > {{ required_alignment }},
         "T_Le'Alignment > static literal ({{ required_alignment }}); update gen/models/array.py");

{% if required_alignment == 1 %}
      declare
         R : T_Le with Import, Convention => Ada, Address => Bytes'Address;
      begin
         return Valid_Le_Through (R);
      end;
{% else %}
      if To_Integer (Bytes'Address) mod T_Le'Alignment = 0 then
         declare
            R : T_Le with Import, Convention => Ada, Address => Bytes'Address;
         begin
            return Valid_Le_Through (R);
         end;
      else
         declare
            Aligned_Bytes : Serialization_Le.Byte_Array := Bytes
               with Alignment => {{ required_alignment }};
            R : T_Le with Import, Convention => Ada, Address => Aligned_Bytes'Address;
         begin
            return Valid_Le_Through (R);
         end;
      end if;
{% endif %}
   exception
      -- From: http://www.adaic.org/resources/add_content/standards/05aarm/html/AA-13-9-2.html
      -- The Valid attribute may be used to check the result of calling an
      -- instance of Unchecked_Conversion (or any other operation that can
      -- return invalid values). However, an exception handler should also
      -- be provided because implementations are permitted to raise
      -- Constraint_Error or Program_Error if they detect the use of an
      -- invalid representation (see 13.9.1).
      when Constraint_Error =>
         Errant_Field := 0;
         return False;
      when Program_Error =>
         Errant_Field := 0;
         return False;
   end Valid_Le;

{% endif %}
{% if endianness in ["either", "big"] %}
   function Get_Field (Bytes : in Serialization.Byte_Array; Field : in Interfaces.Unsigned_32) return Basic_Types.Poly_Type is
{% if element.is_packed_type %}
      Idx : constant Constrained_Index_Type := Constrained_Index_Type'First + Unconstrained_Index_Type ((Field - 1) / {{ element.type_model.num_fields }});
      Remainder : Unsigned_32 := 0;
      To_Return : Basic_Types.Poly_Type;
      -- Per-field byte offset into Bytes. Address arithmetic only --
      -- no read of Bytes happens here, so alignment doesn't matter at
      -- this level. The inner Get_Field handles its own alignment for
      -- the typed read.
      Element_Stride_Bytes : constant Natural := {{ element.type_package }}.Size_In_Bytes;
      Slice_Start : constant Natural := Bytes'First + Natural (Idx - Constrained_Index_Type'First) * Element_Stride_Bytes;
{% elif (element.size % 8) == 0 %}
      use Byte_Array_Util;
      To_Return : Basic_Types.Poly_Type := [others => 0];
      -- Per AdaCore's recommendation: copy only the bytes for the one
      -- requested element into an aligned local, then read the value
      -- through a single-element T_Unconstrained overlay. Cheaper than
      -- copying the whole Bytes buffer just to read one element. The
      -- slice's alignment must satisfy T_Unconstrained's; the
      -- Compile_Time_Error below verifies our static literal does.
      Slice_Start : constant Natural := Bytes'First + (Natural (Field) - 1) * Element_Size_In_Bytes;
      pragma Compile_Time_Error (T_Unconstrained'Alignment > {{ required_alignment }},
         "T_Unconstrained'Alignment > static literal ({{ required_alignment }}); update gen/models/array.py");
      Slice : Basic_Types.Byte_Array (0 .. Element_Size_In_Bytes - 1) :=
         Bytes (Slice_Start .. Slice_Start + Element_Size_In_Bytes - 1)
         with Alignment => {{ required_alignment }};
      Src : T_Unconstrained (Constrained_Index_Type'First .. Constrained_Index_Type'First)
         with Import, Convention => Ada, Address => Slice'Address;
{% else %}
      use Byte_Array_Util;
      To_Return : Basic_Types.Poly_Type := [others => 0];
      -- Sub-byte primitive: GNAT's bit-extract codegen still uses
      -- word loads under the hood, so reading through T at a
      -- misaligned address returns garbage on alignment-strict
      -- targets (RV32). T_Unconstrained isn't generated for sub-byte
      -- elements, so we can't use the per-element slice trick from
      -- the byte-aligned branch above -- copy the full Bytes into
      -- an aligned local matching T'Alignment instead.
      pragma Compile_Time_Error (T'Alignment > {{ required_alignment }},
         "T'Alignment > static literal ({{ required_alignment }}); update gen/models/array.py");
      Aligned_Bytes : Serialization.Byte_Array := Bytes
         with Alignment => {{ required_alignment }};
      Src : T with Import, Convention => Ada, Address => Aligned_Bytes'Address;
{% endif %}
   begin
{% if element.is_packed_type %}
      if Field > 0 then
         Remainder := ((Field - 1) mod {{ element.type_model.num_fields }}) + 1;
      end if;
      declare
         Elem_Bytes : {{ element.type_package }}.Serialization.Byte_Array
            with Import, Convention => Ada, Address => Bytes (Slice_Start)'Address;
      begin
         To_Return := {{ element.type_package }}.Validation.Get_Field (Elem_Bytes, Remainder);
      end;
{% else %}
      declare
         -- Copy field over to an unpacked var so that it is byte aligned. The value here is out of range,
         -- and we know this, so suppresss any checks by the compiler for this copy.
         pragma Suppress (Range_Check);
         pragma Suppress (Overflow_Check);
{% if (element.size % 8) == 0 %}
         Var : constant {{ element.type }} := Src (Constrained_Index_Type'First);
{% else %}
         Var : constant {{ element.type }} := Src (Src'First + Unconstrained_Index_Type (Field) - 1);
{% endif %}
         pragma Unsuppress (Range_Check);
         pragma Unsuppress (Overflow_Check);
         -- Now overlay the var with a byte array before copying it into the polytype.
{% if element.type in ["Basic_Types.Byte", "Byte"] %}
         subtype Byte_Array is Basic_Types.Byte_Array (0 .. 0);
{% else %}
         subtype Byte_Array is Basic_Types.Byte_Array (0 .. {{ element.type }}'Object_Size / Basic_Types.Byte'Object_Size - 1);
{% endif %}
         pragma Warnings (Off, "overlay changes scalar storage order");
         Overlay : constant Byte_Array with Import, Convention => Ada, Address => Var'Address;
         pragma Warnings (On, "overlay changes scalar storage order");
      begin
         Safe_Right_Copy (To_Return, Overlay);
      end;
{% endif %}
      return To_Return;
   exception
      when Constraint_Error =>
         return To_Return;
   end Get_Field;

{% endif %}
{% if endianness in ["either", "little"] %}
   function Get_Field_Le (Bytes : in Serialization_Le.Byte_Array; Field : in Interfaces.Unsigned_32) return Basic_Types.Poly_Type is
{% if element.is_packed_type %}
      Idx : constant Constrained_Index_Type := Constrained_Index_Type'First + Unconstrained_Index_Type ((Field - 1) / {{ element.type_model.num_fields }});
      Remainder : Unsigned_32 := 0;
      To_Return : Basic_Types.Poly_Type;
      -- Per-field byte offset into Bytes. Address arithmetic only --
      -- no read of Bytes happens here, so alignment doesn't matter at
      -- this level. The inner Get_Field_Le handles its own alignment
      -- for the typed read.
      Element_Stride_Bytes : constant Natural := {{ element.type_package }}.Size_In_Bytes;
      Slice_Start : constant Natural := Bytes'First + Natural (Idx - Constrained_Index_Type'First) * Element_Stride_Bytes;
{% elif (element.size % 8) == 0 %}
      use Byte_Array_Util;
      To_Return : Basic_Types.Poly_Type := [others => 0];
      -- Per AdaCore's recommendation: copy only the bytes for the one
      -- requested element into an aligned local, then read the value
      -- through a single-element T_Le_Unconstrained overlay. Cheaper
      -- than copying the whole Bytes buffer just to read one element.
      -- The slice's alignment must satisfy T_Le_Unconstrained's; the
      -- Compile_Time_Error below verifies our static literal does.
      Slice_Start : constant Natural := Bytes'First + (Natural (Field) - 1) * Element_Size_In_Bytes;
      pragma Compile_Time_Error (T_Le_Unconstrained'Alignment > {{ required_alignment }},
         "T_Le_Unconstrained'Alignment > static literal ({{ required_alignment }}); update gen/models/array.py");
      Slice : Basic_Types.Byte_Array (0 .. Element_Size_In_Bytes - 1) :=
         Bytes (Slice_Start .. Slice_Start + Element_Size_In_Bytes - 1)
         with Alignment => {{ required_alignment }};
      Src : T_Le_Unconstrained (Constrained_Index_Type'First .. Constrained_Index_Type'First)
         with Import, Convention => Ada, Address => Slice'Address;
{% else %}
      use Byte_Array_Util;
      To_Return : Basic_Types.Poly_Type := [others => 0];
      -- Sub-byte primitive: GNAT's bit-extract codegen still uses
      -- word loads under the hood, so reading through T_Le at a
      -- misaligned address returns garbage on alignment-strict
      -- targets (RV32). T_Le_Unconstrained isn't generated for
      -- sub-byte elements, so we can't use the per-element slice
      -- trick from the byte-aligned branch above -- copy the full
      -- Bytes into an aligned local matching T_Le'Alignment instead.
      pragma Compile_Time_Error (T_Le'Alignment > {{ required_alignment }},
         "T_Le'Alignment > static literal ({{ required_alignment }}); update gen/models/array.py");
      Aligned_Bytes : Serialization_Le.Byte_Array := Bytes
         with Alignment => {{ required_alignment }};
      Src : T_Le with Import, Convention => Ada, Address => Aligned_Bytes'Address;
{% endif %}
   begin
{% if element.is_packed_type %}
      if Field > 0 then
         Remainder := ((Field - 1) mod {{ element.type_model.num_fields }}) + 1;
      end if;
      declare
         Elem_Bytes : {{ element.type_package }}.Serialization_Le.Byte_Array
            with Import, Convention => Ada, Address => Bytes (Slice_Start)'Address;
      begin
         To_Return := {{ element.type_package }}.Validation.Get_Field_Le (Elem_Bytes, Remainder);
      end;
{% else %}
      declare
         -- Copy field over to an unpacked var so that it is byte aligned. The value here is out of range,
         -- and we know this, so suppresss any checks by the compiler for this copy.
         pragma Suppress (Range_Check);
         pragma Suppress (Overflow_Check);
{% if (element.size % 8) == 0 %}
         Var : constant {{ element.type }} := Src (Constrained_Index_Type'First);
{% else %}
         Var : constant {{ element.type }} := Src (Src'First + Unconstrained_Index_Type (Field) - 1);
{% endif %}
         pragma Unsuppress (Range_Check);
         pragma Unsuppress (Overflow_Check);
         -- Now overlay the var with a byte array before copying it into the polytype.
{% if element.type in ["Basic_Types.Byte", "Byte"] %}
         subtype Byte_Array is Basic_Types.Byte_Array (0 .. 0);
{% else %}
         subtype Byte_Array is Basic_Types.Byte_Array (0 .. {{ element.type }}'Object_Size / Basic_Types.Byte'Object_Size - 1);
{% endif %}
         pragma Warnings (Off, "overlay changes scalar storage order");
         Overlay : constant Byte_Array with Import, Convention => Ada, Address => Var'Address;
         pragma Warnings (On, "overlay changes scalar storage order");
      begin
         Safe_Right_Copy (To_Return, Overlay);
      end;
{% endif %}
      return To_Return;
   exception
      when Constraint_Error =>
         return To_Return;
   end Get_Field_Le;

{% endif %}
end {{ name }}.Validation;

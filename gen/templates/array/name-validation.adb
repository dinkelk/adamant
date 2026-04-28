--------------------------------------------------------------------------------
-- {{ formatType(model_name) }} {{ formatType(model_type) }} Validation Body
--
-- Generated from {{ filename }} on {{ time }}.
--------------------------------------------------------------------------------

{% if unpacked_types %}
-- Standard includes:
with Byte_Array_Util;

{% endif %}
{% if packed_type_includes %}
-- Record Field Includes:
{% for include in packed_type_includes %}
with {{ include }}.Validation;
{% endfor %}

{% endif %}
package body {{ name }}.Validation is

{% if endianness in ["either", "big"] %}
   function Valid (
      Bytes : in Serialization.Byte_Array;
      Errant_Field : out Unsigned_32;
      First_Index : in Unconstrained_Index_Type := T'First;
      Last_Index : in Unconstrained_Index_Type := T'Last
   ) return Boolean is
      -- GCC RISC-V codegen workaround. The pattern below -- overlay
      -- the *typed* packed value `T` onto the byte buffer, then read
      -- multi-byte elements/fields through the overlay -- is the only
      -- shape in Adamant where this codegen bug surfaces. For element
      -- types containing a 32-bit (or wider) field (e.g. Short_Float,
      -- Unsigned_32 in a packed array), GCC's RISC-V backend emits a
      -- single `lw` against the overlay's address, ignoring the
      -- `Alignment => 1` aspect; `-mstrict-align` does not change the
      -- emit. When `Bytes` arrives 1-byte aligned (which is universal
      -- for parameter-table and packet-buffer slices, since they are
      -- packed and start at any byte offset within their containing
      -- record), the load traps with mcause=4 (load address misaligned).
      --
      -- Why it is *not* widespread in Adamant despite Address-overlays
      -- being common: the dominant pattern is the inverse direction --
      -- Serializer's From/To_Byte_Array overlays a `Byte_Array` view
      -- on top of a typed value `T` and assigns whole arrays, so the
      -- compiler emits byte-by-byte copies and never a multi-byte
      -- typed read against a misaligned address. The trapping pattern
      -- (typed overlay onto an externally-aligned byte buffer + scalar
      -- read through the overlay) is essentially confined to these
      -- generated Validation packages.
      --
      -- Workaround: copy `Bytes` into an aliased local with explicit
      -- 4-byte alignment, then overlay the typed view onto the copy.
      -- The copy itself is `Byte_Array := Byte_Array` (byte-by-byte,
      -- alignment-safe); subsequent reads through the overlay see a
      -- 4-byte-aligned source. Costs one stack copy of the input
      -- buffer per Validation entry point. Remove this aligned-local
      -- pattern once the underlying GCC bug is fixed (track via
      -- `doc/alignment-repro/` in the consuming project).
      Aligned_Bytes : aliased Serialization.Byte_Array := Bytes;
      for Aligned_Bytes'Alignment use 4;
      -- Overlay the byte array with the packed array for element access.
      R : T with Import, Convention => Ada, Address => Aligned_Bytes'Address;
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
      -- Aligned local copy (see Valid above for the rationale).
      Aligned_Bytes : aliased Serialization_Le.Byte_Array := Bytes;
      for Aligned_Bytes'Alignment use 4;
      -- Overlay the byte array with the packed array for element access.
      R : T_Le with Import, Convention => Ada, Address => Aligned_Bytes'Address;
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
      -- Aligned local copy (see Valid above for the rationale).
      Aligned_Bytes : aliased Serialization.Byte_Array := Bytes;
      for Aligned_Bytes'Alignment use 4;
      -- Overlay the byte array with the packed array for element access.
      Src : T with Import, Convention => Ada, Address => Aligned_Bytes'Address;
{% if element.is_packed_type %}
      Idx : constant Constrained_Index_Type := Constrained_Index_Type'First + Unconstrained_Index_Type ((Field - 1) / {{ element.type_model.num_fields }});
      Remainder : Unsigned_32 := 0;
      To_Return : Basic_Types.Poly_Type;
{% else %}
      use Byte_Array_Util;
      To_Return : Basic_Types.Poly_Type := [others => 0];
{% endif %}
   begin
{% if element.is_packed_type %}
      if Field > 0 then
         Remainder := ((Field - 1) mod {{ element.type_model.num_fields }}) + 1;
      end if;
      declare
         Elem_Bytes : {{ element.type_package }}.Serialization.Byte_Array
            with Import, Convention => Ada, Address => Src (Idx)'Address;
      begin
         To_Return := {{ element.type_package }}.Validation.Get_Field (Elem_Bytes, Remainder);
      end;
{% else %}
      declare
         -- Copy field over to an unpacked var so that it is byte aligned. The value here is out of range,
         -- and we know this, so suppresss any checks by the compiler for this copy.
         pragma Suppress (Range_Check);
         pragma Suppress (Overflow_Check);
         Var : constant {{ element.type }} := Src (Src'First + Unconstrained_Index_Type (Field) - 1);
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
      -- Aligned local copy (see Valid above for the rationale).
      Aligned_Bytes : aliased Serialization_Le.Byte_Array := Bytes;
      for Aligned_Bytes'Alignment use 4;
      -- Overlay the byte array with the packed array for element access.
      Src : T_Le with Import, Convention => Ada, Address => Aligned_Bytes'Address;
{% if element.is_packed_type %}
      Idx : constant Constrained_Index_Type := Constrained_Index_Type'First + Unconstrained_Index_Type ((Field - 1) / {{ element.type_model.num_fields }});
      Remainder : Unsigned_32 := 0;
      To_Return : Basic_Types.Poly_Type;
{% else %}
      use Byte_Array_Util;
      To_Return : Basic_Types.Poly_Type := [others => 0];
{% endif %}
   begin
{% if element.is_packed_type %}
      if Field > 0 then
         Remainder := ((Field - 1) mod {{ element.type_model.num_fields }}) + 1;
      end if;
      declare
         Elem_Bytes : {{ element.type_package }}.Serialization_Le.Byte_Array
            with Import, Convention => Ada, Address => Src (Idx)'Address;
      begin
         To_Return := {{ element.type_package }}.Validation.Get_Field_Le (Elem_Bytes, Remainder);
      end;
{% else %}
      declare
         -- Copy field over to an unpacked var so that it is byte aligned. The value here is out of range,
         -- and we know this, so suppresss any checks by the compiler for this copy.
         pragma Suppress (Range_Check);
         pragma Suppress (Overflow_Check);
         Var : constant {{ element.type }} := Src (Src'First + Unconstrained_Index_Type (Field) - 1);
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

--------------------------------------------------------------------------------
-- {{ formatType(model_name) }} {{ formatType(model_type) }} Representation Body
--
-- Generated from {{ filename }} on {{ time }}.
--------------------------------------------------------------------------------

package body {{ name }}.Representation is
{% if length %}

   -- Private function which translates array into string:
   function Array_To_String is new String_Util.To_Array_String ({% if element.is_packed_type %}{{ element.type_package }}.U{% else %}{{ element.type }}{% endif %}, Constrained_Index_Type, U, Element_To_Tuple_String);
{% if endianness in ["either", "big"] %}
   function Array_To_String is new String_Util.To_Array_String ({% if element.is_packed_type %}{{ element.type_package }}.T{% else %}{{ element.type }}{% endif %}, Constrained_Index_Type, T, Element_To_Tuple_String);
{% endif %}
{% if endianness in ["either", "little"] %}
   function Array_To_String is new String_Util.To_Array_String ({% if element.is_packed_type %}{{ element.type_package }}.T_Le{% else %}{{ element.type }}{% endif %}, Constrained_Index_Type, T_Le, Element_To_Tuple_String);
{% endif %}
{% endif %}

   -- Return string representation of array elements:
   function To_String (R : in U; Prefix : in String := "") return String is
   begin
{% if length %}
      return Prefix & "{{ name }} : array {{ element.type }} (1 .. {{ length }}) => [ " & Array_To_String (R, Show_Index => True) & "]";
{% else %}
      -- For unconstrained arrays, we build a simple string representation
      declare
         Result : constant String := To_Tuple_String (R);
      begin
         return Prefix & "{{ name }} : array {{ element.type }} (" & Unconstrained_Index_Type'Image (R'First) & " .. " & Unconstrained_Index_Type'Image (R'Last) & ") => " & Result;
      end;
{% endif %}
   exception
      when Constraint_Error =>
         return Prefix & "{{ name }}.T invalid. Constraint_Error thrown.";
   end To_String;

{% if length %}
{% if endianness in ["either", "big"] %}
   function To_String (R : in T; Prefix : in String := "") return String is
   begin
      return Prefix & "{{ name }} : array {{ element.type }} (1 .. {{ length }}) => [ " & Array_To_String (R, Show_Index => True) & "]";
   exception
      when Constraint_Error =>
         return Prefix & "{{ name }}.T invalid. Constraint_Error thrown.";
   end To_String;

{% endif %}
{% if endianness in ["either", "little"] %}
   function To_String (R : in T_Le; Prefix : in String := "") return String is
   begin
      return Prefix & "{{ name }} : array {{ element.type }} (1 .. {{ length }}) => [ " & Array_To_String (R, Show_Index => True) & "]";
   exception
      when Constraint_Error =>
         return Prefix & "{{ name }}.T invalid. Constraint_Error thrown.";
   end To_String;

{% endif %}
{% endif %}
   -- Return compact representation of array as string:
   function To_Tuple_String (R : in U) return String is
   begin
{% if length %}
      return "[" & Array_To_String (R, Show_Index => False) & "]";
{% else %}
      -- For unconstrained arrays, manually build the string
      declare
         Result : String (1 .. 10000) := [others => ' '];
         Last : Natural := 1;
      begin
         Result (Last) := '[';
         for I in R'Range loop
            if I > R'First then
               Last := Last + 1;
               Result (Last .. Last + 1) := ", ";
               Last := Last + 1;
            else
               Last := Last + 1;
            end if;
            declare
               Elem_Str : constant String := Element_To_Tuple_String (R (I));
            begin
               Result (Last .. Last + Elem_Str'Length - 1) := Elem_Str;
               Last := Last + Elem_Str'Length - 1;
            end;
         end loop;
         Last := Last + 1;
         Result (Last) := ']';
         return Result (1 .. Last);
      end;
{% endif %}
   exception
      when Constraint_Error =>
         return "{{ name }}.T invalid. Constraint_Error thrown.";
   end To_Tuple_String;

{% if length %}
{% if endianness in ["either", "big"] %}
   -- Return compact representation of array as string:
   function To_Tuple_String (R : in T) return String is
   begin
      return "[" & Array_To_String (R, Show_Index => False) & "]";
   exception
      when Constraint_Error =>
         return "{{ name }}.T invalid. Constraint_Error thrown.";
   end To_Tuple_String;

{% endif %}
{% if endianness in ["either", "little"] %}
   -- Return compact representation of array as string:
   function To_Tuple_String (R : in T_Le) return String is
   begin
      return "[" & Array_To_String (R, Show_Index => False) & "]";
   exception
      when Constraint_Error =>
         return "{{ name }}.T invalid. Constraint_Error thrown.";
   end To_Tuple_String;

{% endif %}
{% endif %}
   -- Return string representation of array elements and bytes
   function Image_With_Prefix (R : in U; Prefix : in String) return String is
   begin
{% if length %}
      return To_Byte_String (R) & ASCII.LF & To_String (R, Prefix);
{% else %}
      -- For unconstrained arrays, just return the string representation
      return To_String (R, Prefix);
{% endif %}
   end Image_With_Prefix;

{% if length %}
{% if endianness in ["either", "big"] %}
   function Image_With_Prefix (R : in T; Prefix : in String) return String is
   begin
      return To_Byte_String (R) & ASCII.LF & To_String (R, Prefix);
   end Image_With_Prefix;

{% endif %}
{% if endianness in ["either", "little"] %}
   function Image_With_Prefix (R : in T_Le; Prefix : in String) return String is
   begin
      return To_Byte_String (R) & ASCII.LF & To_String (R, Prefix);
   end Image_With_Prefix;

{% endif %}
{% endif %}
   -- Return string representation of array elements and bytes (with no prefix):
   function Image (R : in U) return String is
   begin
      return Image_With_Prefix (R, "");
   end Image;

{% if length %}
{% if endianness in ["either", "big"] %}
   function Image (R : in T) return String is
   begin
      return Image_With_Prefix (R, "");
   end Image;

{% endif %}
{% if endianness in ["either", "little"] %}
   function Image (R : in T_Le) return String is
   begin
      return Image_With_Prefix (R, "");
   end Image;

{% endif %}
{% endif %}
end {{ name }}.Representation;

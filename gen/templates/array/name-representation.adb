--------------------------------------------------------------------------------
-- {{ formatType(model_name) }} {{ formatType(model_type) }} Representation Body
--
-- Generated from {{ filename }} on {{ time }}.
--------------------------------------------------------------------------------

package body {{ name }}.Representation is

{% if is_volatile_type %}
   -- Validation not supported for volatile record. Convert to a regular record for
   -- a validation checking function.
   procedure Dummy_Image is
   begin
      null;
   end Dummy_Image;
{% else %}
   -- Private function which translates array into string:
   function Array_To_String is new String_Util.To_Array_String ({% if element.is_packed_type %}{{ element.type_package }}.U{% else %}{{ element.type }}{% endif %}, {% if length > 0 %}Constrained_Index_Type{% else %}Unconstrained_Index_Type{% endif %}, U, Element_To_Tuple_String);

   -- Return string representation of array elements:
   function To_String (R : in U; Prefix : in String := "") return String is
   begin
      return Prefix & "{{ name }} : array {{ element.type }} (1 .. {{ length }}) => [ " & Array_To_String (R, Show_Index => True) & "]";
   exception
      when Constraint_Error =>
         return Prefix & "{{ name }}.T invalid. Constraint_Error thrown.";
   end To_String;

{% if endianness in ["either", "big"] %}
   function To_String (R : in T; Prefix : in String := "") return String is
   begin
      return To_String (Unpack (R), Prefix);
   end To_String;

{% endif %}
{% if endianness in ["either", "little"] %}
   function To_String (R : in T_Le; Prefix : in String := "") return String is
   begin
      return To_String (Unpack (R), Prefix);
   end To_String;

{% endif %}
   -- Return compact representation of array as string:
   function To_Tuple_String (R : in U) return String is
   begin
      return "[" & Array_To_String (R, Show_Index => False) & "]";
   exception
      when Constraint_Error =>
         return "{{ name }}.T invalid. Constraint_Error thrown.";
   end To_Tuple_String;

{% if endianness in ["either", "big"] %}
   -- Return compact representation of array as string:
   function To_Tuple_String (R : in T) return String is
   begin
      return To_Tuple_String (Unpack (R));
   end To_Tuple_String;

{% endif %}
{% if endianness in ["either", "little"] %}
   -- Return compact representation of array as string:
   function To_Tuple_String (R : in T_Le) return String is
   begin
      return To_Tuple_String (Unpack (R));
   end To_Tuple_String;

{% endif %}
   -- Return string representation of array elements and bytes
   function Image_With_Prefix (R : in U; Prefix : in String) return String is
   begin
      return To_Byte_String (R) & ASCII.LF & To_String (R, Prefix);
   end Image_With_Prefix;

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
   -- Return string representation of array elements and bytes (with no prefix):
   function Image (R : in U) return String is
   begin
      return Image_With_Prefix (R, "");
   end Image;

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

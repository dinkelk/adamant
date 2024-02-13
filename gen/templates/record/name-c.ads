--------------------------------------------------------------------------------
-- {{ formatType(model_name) }} {{ formatType(model_type) }} C/C++ Interface Spec
--
-- Generated from {{ filename }} on {{ time }}.
--------------------------------------------------------------------------------

-- Standard Includes:
with Ada.Unchecked_Conversion;
{% if includes %}

-- Custom Includes:
{% for include in includes %}
with {{ include }};
{% endfor %}
{% endif %}
{% if type_includes %}

-- Record Component Includes:
{% for include in type_includes %}
with {{ include }};
{% endfor %}
{% endif %}

{% if description %}
{{ printMultiLine(description, '-- ') }}
{% endif %}
package {{ name }}.C is
{% if preamble %}

   -- Preamble code:
   -- TODO, alias this !!
{{ printMultiLine(preamble, '   ', 10000) }}
{% endif %}

   -- Fields that are 8-bit types or 8-bit array types trigger the following warning. Obviously endianness does
   -- not apply for types of 1 byte or less, so we can ignore this warning.
   pragma Warnings (Off, "scalar storage order specified for ""T"" does not apply to component");
   pragma Warnings (Off, "scalar storage order specified for ""T_Le"" does not apply to component");
   pragma Warnings (Off, "scalar storage order specified for ""Volatile_T"" does not apply to component");
   pragma Warnings (Off, "scalar storage order specified for ""Volatile_T_Le"" does not apply to component");
{% if size == 32 or size == 16 or size == 8 %}
   pragma Warnings (Off, "scalar storage order specified for ""Atomic_T"" does not apply to component");
   pragma Warnings (Off, "scalar storage order specified for ""Atomic_T_Le"" does not apply to component");
   pragma Warnings (Off, "scalar storage order specified for ""Register_T"" does not apply to component");
   pragma Warnings (Off, "scalar storage order specified for ""Register_T_Le"" does not apply to component");
{% endif %}

   -- Unpacked C/C++ compatible type:
   type U_C is record
{% for field in fields.values() %}
{% if field.description %}
{{ printMultiLine(field.description, '      -- ') }}
{% endif %}
      {{ field.name }} : aliased {{ field.type }}{% if field.default_value %} := {{ field.default_value }}{% endif %};
{% endfor %}
   end record
      with Convention => C_Pass_By_Copy;

   -- Re-enable warning.
   pragma Warnings (On, "scalar storage order specified for ""T"" does not apply to component");
   pragma Warnings (On, "scalar storage order specified for ""T_Le"" does not apply to component");
   pragma Warnings (On, "scalar storage order specified for ""Volatile_T"" does not apply to component");
   pragma Warnings (On, "scalar storage order specified for ""Volatile_T_Le"" does not apply to component");
{% if size == 32 or size == 16 or size == 8 %}
   pragma Warnings (On, "scalar storage order specified for ""Atomic_T"" does not apply to component");
   pragma Warnings (On, "scalar storage order specified for ""Atomic_T_Le"" does not apply to component");
   pragma Warnings (On, "scalar storage order specified for ""Register_T"" does not apply to component");
   pragma Warnings (On, "scalar storage order specified for ""Register_T_Le"" does not apply to component");
{% endif %}

   -- Access type for U_C.
   type U_C_Access is access all U_C;

   -- Functions for converting between the Ada and C version of the packed type:
   function To_Ada is new Ada.Unchecked_Conversion (Source => U_C, Target => U);
   function To_C is new Ada.Unchecked_Conversion (Source => U, Target => U_C);

   -- The .C package is not supported for all Adamant packed records. We do not allow compilation in
   -- these cases.
   pragma Compile_Time_Error ({{ name }}.U'Size /= U_C'Size, "C type size not as expected.");
{% if packed_type_includes %}
   pragma Compile_Time_Error (False, "{{ name }}.C package not supported for records that contain packed type fields.");
{% endif %}

end {{ name }}.C;

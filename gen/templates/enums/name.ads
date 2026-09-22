--------------------------------------------------------------------------------
-- {{ formatType(model_name) }} {{ formatType(model_type) }} Spec
--
-- Generated from {{ filename }} on {{ time }}.
--------------------------------------------------------------------------------

{% if includes %}

-- Custom Includes:
{% for include in includes %}
with {{ include }};
{% endfor %}

{% endif %}
{% if description %}
{{ printMultiLine(description, '-- ') }}
{% endif %}
package {{ name }} is
{% if preamble %}

   -- Preamble code:
{{ printMultiLine(preamble, '   ', 10000) }}
{% endif %}

   --
   -- Enumeration types:
   --

{% for enum in enums.values() %}
   -- {{ enum.name }} Definition:
{% if enum.description %}
{{ printMultiLine(enum.description, '   -- ') }}
{% endif %}
   package {{ enum.name }} is
      -- Enumeration type definition:
      type E is (
{% for literal in enum.literals %}
         {{ "%10s"|format(literal.name) }}{{ ", " if not loop.last else "   " }}{% if literal.description %} -- {{ literal.description + "\n" }}{% else %} --{{ "\n" }}{% endif %}
{% endfor %}
      );
      -- Enumeration type values:
      for E use (
{% for literal in enum.literals %}
         {{ "%10s => %2d"|format(literal.name, literal.value) }}{{ "," if not loop.last }}
{% endfor %}
      );

      -- C compatible mirror of E for passing across a C/C++ binding. E_C has
      -- the size of a C int, the type C declares its enumerations with, and
      -- the same literal values as E.
      package C is
         type E_C is (
{% for literal in enum.literals %}
            {{ literal.name }}{{ "," if not loop.last }}
{% endfor %}
         ) with Convention => C;
         for E_C use (
{% for literal in enum.literals %}
            {{ "%10s => %2d"|format(literal.name, literal.value) }}{{ "," if not loop.last }}
{% endfor %}
         );

         -- Conversions between E and E_C. Both map by literal value.
         function To_C (Src : in E) return E_C is (E_C'Enum_Val (E'Enum_Rep (Src)))
            with Inline;

         -- A value that arrives from C may hold any int. To_Ada raises
         -- Constraint_Error when Src is not a literal of E. Check Src'Valid
         -- first to handle that case without an exception.
         function To_Ada (Src : in E_C) return E is (E'Enum_Val (E_C'Enum_Rep (Src)))
            with Inline;
      end C;
   end {{ enum.name }};

{% endfor %}
end {{ name }};

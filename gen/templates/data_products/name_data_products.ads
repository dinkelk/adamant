--------------------------------------------------------------------------------
-- {{ formatType(model_name) }} {{ formatType(model_type) }} Spec
--
-- Generated from {{ filename }} on {{ time }}.
--------------------------------------------------------------------------------

-- Standard Includes:
with Data_Product;
with Data_Product_Types;
with Sys_Time;
{% if includes %}

-- Data Product Type Includes
{% for include in includes %}
{% if include not in ["Sys_Time", "Data_Product", "Data_Product_Types"] %}
with {{ include }};
{% endif %}
{% endfor %}
{% endif %}
{% if description %}

{{ printMultiLine(description, '-- ') }}
{% endif %}
package {{ name }} is

   -- Object instance type:
   type Instance is tagged limited private;

   -----------------------------------------------
   -- Local Data Product Identifiers:
   -----------------------------------------------
   Num_Data_Products : constant Natural := {{ data_products|length }};
   type Local_Data_Product_Id_Type is (
{% for dp in data_products %}
      {{ dp.name }}_Id{{ "," if not loop.last }}
{% endfor %}
   );
   for Local_Data_Product_Id_Type use (
{% for dp in data_products %}
      {{ dp.name }}_Id => {{ loop.index0 }}{{ "," if not loop.last }}
{% endfor %}
   );

   -----------------------------------------------
   -- Setter procedures for data product IDs:
   -----------------------------------------------
   not overriding function Get_Id_Base (Self : in Instance) return Data_Product_Types.Data_Product_Id
      with Inline => True;
   -- Set the ID of every data product to the ID base plus its local ID.
   not overriding procedure Set_Id_Base (Self : in out Instance; Id_Base : in Data_Product_Types.Data_Product_Id)
      with Inline => True;
   -- Override the ID of a single data product. This is nonstandard and is only
   -- used for a data product that is an alias of another component's data
   -- product, so that both publish under the same ID. Set_Id_Base resets every
   -- ID, so an override only takes effect if it is called after Set_Id_Base.
   -- The assembly autocode makes this call after Set_Id_Bases.
   not overriding procedure Override_Id (Self : in out Instance; Local_Id : in Local_Data_Product_Id_Type; Id : in Data_Product_Types.Data_Product_Id)
      with Inline => True;

   -----------------------------------------------
   -- Getter function for global data product IDs:
   -----------------------------------------------
{% for dp in data_products %}
   not overriding function Get_{{ dp.name }}_Id (Self : in Instance) return Data_Product_Types.Data_Product_Id
      with Inline => True;
{% endfor %}

   -----------------------------------------------
   -- Data product creation functions:
   -----------------------------------------------
{% for dp in data_products %}
{% if dp.description %}
{{ printMultiLine (dp.description, '   -- ') }}
{% endif %}
   not overriding function {{ dp.name }} (Self : in Instance; Timestamp : Sys_Time.T; Item : in {{ dp.type }}) return Data_Product.T;

{% endfor %}
   -- Compile time checks to make sure types do not serialize longer than the data product buffer size:
   pragma Warnings (Off, "condition can only be True if invalid values present");
{% for dp in data_products %}
{% if dp.type_model %}
   pragma Compile_Time_Error (
      {{ dp.type_package }}.Size_In_Bytes > Data_Product_Types.Data_Product_Buffer_Type'Length,
      "Data Product '{{ dp.name }}' has argument of type '{{ dp.type }}' which has a maximum serialized length larger than the buffer size of Data_Product.T."
   );
{% else %}
   pragma Compile_Time_Error (
      (({{ dp.type   }}'Object_Size - 1) / 8 + 1) > Data_Product_Types.Data_Product_Buffer_Type'Length,
      "Data_Product '{{ dp.name }}' has argument of type '{{ dp.type }}' which has a maximum serialized length larger than the buffer size of Data_Product.T."
   );
{% endif %}
{% endfor %}
   pragma Warnings (On, "condition can only be True if invalid values present");

private
   -- Table of the ID each data product publishes under. The defaults equal the
   -- local IDs, which is what unit tests expect. Set_Id_Base and Override_Id fill
   -- in the assembly-wide IDs.
   type Id_Table is array (Local_Data_Product_Id_Type) of Data_Product_Types.Data_Product_Id;

   type Instance is tagged limited record
      Id_Base : Data_Product_Types.Data_Product_Id := 0;
      Ids : Id_Table := [
{% for dp in data_products %}
         {{ dp.name }}_Id => {{ loop.index0 }}{{ "," if not loop.last }}
{% endfor %}
      ];
   end record;

end {{ name }};

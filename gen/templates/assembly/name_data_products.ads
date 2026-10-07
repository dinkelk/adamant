--------------------------------------------------------------------------------
-- {{ formatType(model_name) }} {{ formatType(model_type) }} Spec
--
-- Generated from {{ filename }} on {{ time }}.
--------------------------------------------------------------------------------
{% if data_products %}

with Data_Product_Types; use Data_Product_Types;
{% endif %}

-- Data product related constants for the {{ name }} assembly.
package {{ name }}_Data_Products is

{% if data_products %}
   -- Assembly-wide constants:
{% for id, dp in data_products.items() %}
{% if loop.first %}
   Minimum_Data_Product_Id : constant Data_Product_Id := {{ id }};
{% endif %}
{% endfor %}
{% for id, dp in data_products.items() %}
{% if loop.last %}
   Maximum_Data_Product_Id : constant Data_Product_Id := {{ id }};
{% endif %}
{% endfor %}
   Number_Of_Data_Products : constant Natural := {{ data_products|length }};
   Number_Of_Components_With_Data_Products : constant Natural := {{ component_kind_dict['data_products']|length }};
{% if data_product_aliases %}
   Number_Of_Data_Product_Aliases : constant Natural := {{ data_product_aliases|length }};
{% endif %}

   -- List of data product ids:
{% for id, dp in data_products.items() %}
   {{ dp.suite.component.instance_name }}_{{ dp.name }} : constant Data_Product_Id := {{ dp.id }}; -- 0x{{ '%04x' % id }}
{% endfor %}
{% if data_product_aliases %}

   -- List of data product aliases. Each publishes under the id of another data product:
{% for alias in data_product_aliases %}
   {{ alias.suite.component.instance_name }}_{{ alias.name }} : constant Data_Product_Id := {{ alias.id }}; -- 0x{{ '%04x' % alias.id }} alias of {{ alias.alias_of.full_name }}
{% endfor %}
{% endif %}
{% else %}
   -- No data products in assembly...
{% endif %}

end {{ name }}_Data_Products;

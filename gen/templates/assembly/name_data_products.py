################################################################################
# {{ formatType(model_name) }} {{ formatType(model_type) }}
#
# Generated from {{ filename }} on {{ time }}.
################################################################################
{% if data_products.items() %}

# Data product ID constants:
{% for id, dp in data_products.items() %}
{{ dp.suite.component.instance_name }}_{{ dp.name }} = {{ dp.id }}
{% endfor %}
{% if data_product_aliases %}

# Data product alias ID constants. Each publishes under the ID of another data product:
{% for alias in data_product_aliases %}
{{ alias.suite.component.instance_name }}_{{ alias.name }} = {{ alias.id }}  # alias of {{ alias.alias_of.full_name }}
{% endfor %}
{% endif %}

{% endif -%}

# Reverse lookup: ID to name string
data_product_id_to_name = {
{% for id, dp in data_products.items() %}
    {{ dp.id }}: "{{ dp.suite.component.instance_name }}.{{ dp.name }}"{{ "," if not loop.last }}
{% endfor %}
}

# Forward lookup: name string to ID
data_product_name_to_id = {
{% for id, dp in data_products.items() %}
    "{{ dp.suite.component.instance_name }}.{{ dp.name }}": {{ dp.id }}{{ "," if not loop.last or data_product_aliases }}
{% endfor %}
{% for alias in data_product_aliases %}
    "{{ alias.suite.component.instance_name }}.{{ alias.name }}": {{ alias.id }}{{ "," if not loop.last }}
{% endfor %}
}
{%- if data_product_aliases %}


# Data product aliases: alias name string to the name string of the data product it publishes as
data_product_aliases = {
{% for alias in data_product_aliases %}
    "{{ alias.suite.component.instance_name }}.{{ alias.name }}": "{{ alias.alias_of.full_name }}"{{ "," if not loop.last }}
{% endfor %}
}
{%- endif %}

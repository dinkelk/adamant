from models.component import component_submodel
from util import ada
from models.submodels.ided_suite import ided_suite, ided_entity
from models.submodels.parameter import parameter
from models.exceptions import ModelException, throw_exception_with_lineno
import os.path


class data_product(ided_entity):
    def __init__(
        self, name, type, description=None, id=None,
        little_endian_allowed=False, suite=None
    ):
        super(data_product, self).__init__(
            name,
            type,
            description,
            id,
            default_value=None,
            variable_types_allowed=False,
            little_endian_allowed=little_endian_allowed,
            suite=suite,
        )

    @classmethod
    def from_ided_entity(cls, entity):
        self = entity
        return self


class data_products(component_submodel, ided_suite):
    """
    This is the object model for a data product suite. It extracts data from a
    input file and stores the data as object member variables.
    """
    def __init__(self, filename):
        """
        Initialize the data product object, ingest data, and check it by
        calling the base class init function.
        """
        # Load the object from the file:
        ided_suite.__init__(self)
        component_submodel.__init__(
            self,
            filename=filename,
            schema=os.environ["SCHEMAPATH"] + "/data_products.yaml",
        )

    def load(self):
        # Call the component submodel load:
        component_submodel.load(self)

        # Load the base class:
        name = ada.adaCamelCase(self.model_name) + "_Data_Products"
        self.load_suite_data(
            suite_name=name,
            suite_data=self.data,
            entities_name="data_products",
            type_name="type",
        )

        # Rename entities to something more descriptive:
        self.data_products = list(self.entities.values())

        # The data products declared in the model file. Only these exist in the generated
        # data products package, so only these publish under an overridden ID. Some suites
        # add data products when the assembly is set, and the component computes the IDs
        # of those from its ID base.
        self.declared_names = list(self.entities.keys())

        # The data_product_aliases instance data from the assembly model, and the
        # data products of this component instance that publish under another
        # component's data product ID.
        self.alias_data = []
        self.aliases = []

    def set_alias_instance_data(self, alias_data):
        """
        Called by component, which passes data_product_aliases instance data. The data is
        only stored here. Some suites add or replace data products when the assembly is
        set, so the names are looked up later by mark_aliases().
        """
        self.alias_data = list(alias_data or [])

    @throw_exception_with_lineno
    def mark_aliases(self):
        """
        Called by assembly before resolve_aliases() is called on any suite. Looks up each
        alias by name and marks it, so that resolve_aliases() can reject an alias of an alias
        in any suite.
        """
        for data in self.alias_data:
            name = ada.formatType(data["data_product"])
            target_name = ada.formatVariable(data["alias_of"])

            if name not in self.entities:
                raise ModelException(
                    "No data product of name '"
                    + str(name)
                    + "' exists in component '"
                    + str(self.component.instance_name)
                    + "'. Data products must be one of: "
                    + str(list(self.entities.keys()))
                )

            if name not in self.declared_names:
                valid = [n for n in self.declared_names if n in self.entities]
                raise ModelException(
                    "Data product '"
                    + str(name)
                    + "' in component '"
                    + str(self.component.instance_name)
                    + "' cannot be an alias. It is added by the component's model when the "
                    + "assembly is loaded, and the component computes its ID from the ID base. "
                    + "Only data products declared in the component's data products model can "
                    + "be aliases: "
                    + (str(valid) if valid else "none in this component.")
                )

            entity = self.entities[name]
            if entity.is_alias:
                raise ModelException(
                    "Data product '"
                    + str(name)
                    + "' in component '"
                    + str(self.component.instance_name)
                    + "' is listed more than once in data_product_aliases."
                )

            entity.alias_of_name = target_name
            self.aliases.append(entity)

    @throw_exception_with_lineno
    def resolve_aliases(self, dp_name_map):
        """
        Called by assembly after all data product IDs are assigned, passing a dictionary
        mapping full, component-instance-qualified data product names to data product
        objects. Each alias takes on the ID of its target.
        """
        for alias in self.aliases:
            alias_full_name = self.component.instance_name + "." + alias.name

            try:
                target = dp_name_map[alias.alias_of_name]
            except KeyError:
                raise ModelException(
                    "Cannot find data product '"
                    + str(alias.alias_of_name)
                    + "' for data product alias '"
                    + alias_full_name
                    + "' in assembly. Data product names should be in the form: "
                    + "Component_Instance_Name.Data_Product_Name"
                )

            if target.suite is self:
                raise ModelException(
                    "Data product alias '"
                    + alias_full_name
                    + "' cannot be an alias of a data product in the same component instance."
                )

            if target.is_alias:
                raise ModelException(
                    "Data product alias '"
                    + alias_full_name
                    + "' cannot be an alias of '"
                    + str(alias.alias_of_name)
                    + "' because that data product is itself an alias."
                )

            # Make sure the alias and its target are of the exact same type:
            if alias.type != target.type or alias.size != target.size:
                raise ModelException(
                    "Data product alias '"
                    + alias_full_name
                    + "' is an alias of '"
                    + str(alias.alias_of_name)
                    + "' but their types do not match ("
                    + alias.type
                    + " vs. "
                    + target.type
                    + "). The alias and its target types must exactly match."
                )

            alias.natural_id = alias.id
            alias.id = target.id
            alias.alias_of = target
            target.aliases.append(alias)

    def set_component(self, component):
        # Set the id bases parameter:
        component.set_id_bases_parameters.append(
            parameter(
                name="data_Product_Id_Base",
                type="Data_Product_Types.Data_Product_Id_Base",
                description="The value at which the component's data product identifiers begin.",
            )
        )

        # Store all includes for the component:
        component.base_ads_includes.extend([self.name, "Data_Product_Types"])
        component.tester_base_ads_includes.extend(
            [self.name, "Data_Product"] + self.includes
        )
        if self.basic_types:
            component.tester_base_adb_includes.append("Serializer")
        component.tester_base_adb_includes.extend(self.representation_includes)
        component.tester_template_ads_includes.extend(
            ["Printable_History", "Data_Product"] + self.representation_includes
        )

        # Do base class load:
        component_submodel.set_component(self, component)

    def get_dependencies(self):
        return component_submodel.get_dependencies(self) + \
               ided_suite.get_dependencies(self)

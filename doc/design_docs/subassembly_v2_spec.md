# Subassemblies v2 — Specification

**Status:** Draft. WHAT-only spec. Does not prescribe implementation.
**Audience:** Adamant framework contributors implementing this feature, and reviewers / testers validating the resulting design.

---

## 1. Motivation

In Adamant today, a *subassembly* is shorthand for "an `.assembly.yaml` file referenced from another `.assembly.yaml`'s `subassemblies:` list." It is a **purely organizational** YAML splitting convenience: at model load, all subassembly contents (components, connections, includes, preamble, id_bases, submodel files) are flat-merged into the parent. There is one global namespace for component instances, and a parent connection may freely name any component anywhere in the tree.

This thinness limits scaling:

- A subassembly cannot declare its own external interface — it has no concept of "what I expose vs. what is internal."
- A subassembly cannot be instantiated more than once.
- A subassembly cannot be parameterized at instantiation.
- A subassembly cannot truly hide its internals — anyone in the parent (or any sibling subassembly) may name and wire to its internal components.
- Refactoring the internals of a subassembly may break callers who happen to reference an internal name.

Subassemblies v2 promotes the construct to a **first-class abstraction at the modeling layer** while preserving the existing flat-autocode invariant. A subassembly becomes the modeling analogue of a component: it declares an interface (boundary connectors), can be parameterized (variables), can be instantiated multiple times, and encapsulates its internals.

The runtime model is unchanged: the autocoded assembly remains a flat list of concrete component instances and direct connector-to-connector connections. Boundary connectors are erased at flatten time; chains of connections that traverse one or more boundaries collapse to a single direct edge between the originating and terminating concrete component connectors.

This is a **breaking redesign**. Existing `.assembly.yaml` files used as subassemblies must be migrated to the new `.subassembly.yaml` form (see §12).

---

## 2. Glossary

| Term | Meaning |
|---|---|
| **Subassembly type** | A `.subassembly.yaml` file. Defines a reusable parameterizable group of components with a declared external boundary. |
| **Subassembly instance** | An entry in a parent assembly's (or parent subassembly's) `subassemblies:` block. Has a unique instance name and (optional) variable bindings. Multiple instances of the same type are allowed. |
| **Boundary connector** | A connector declared on a subassembly type and exposed to the outside world. Has the same shape as a component connector (`name`, `kind`, `type`, `return_type`, `count`, `priority`). |
| **Internal component** | A component listed in a subassembly's `components:` block. Encapsulated; not addressable from outside the subassembly. |
| **Parent assembly** | The top-level `.assembly.yaml` that ultimately produces the autocoded executable. Contains zero or more subassembly instances and zero or more direct components. |
| **Parent subassembly** | A `.subassembly.yaml` that contains nested subassembly instances. Same encapsulation rules apply at every nesting level. |
| **Bubbled-up dependency** | A data dependency on an internal component that is not satisfied inside the subassembly. Auto-promoted to the subassembly's external boundary; must be resolved at instantiation. |
| **Bubbled-up entity** | An ID-ed entity (event, command, parameter, data product, fault, packet) belonging to an internal component. Visible from outside via the qualified path `<sub_instance>.<internal>.<entity>` (see §6.2). |
| **Forwarding connection** | A connection inside a subassembly file that joins an internal component's connector to the subassembly's own boundary connector. Uses `forward_to_subassembly` / `forward_from_subassembly` keywords. |
| **Variable** | A named, untyped string value declared by a subassembly type. Supplied at instantiation; substituted into the subassembly's YAML before validation. |
| **Flat autocode** | The post-flatten model the Ada code generator sees: a single namespace of concrete component instances and a single list of direct component-connector-to-component-connector edges. Identical in shape to today's autocode. |

---

## 3. Subassembly model — `.subassembly.yaml`

Subassemblies use a **new schema**, distinct from `.assembly.yaml`. The file extension is `.subassembly.yaml`. A `.subassembly.yaml` file may not be the top-level model of a build — it must be referenced from a parent assembly or another subassembly.

### 3.1 Top-level fields

| Field | Required | Notes |
|---|---|---|
| `description` | optional | Human-readable description of the subassembly type. |
| `with` | optional | Manual additional Ada `with` clauses. Emitted once at flatten time (deduplicated across instances). |
| `with_adb` | optional | Manual additional `with` clauses for the `.adb`. Emitted once at flatten time. |
| `prepreamble` | optional | Ada handcode emitted before the package spec. Per-instance emission (see §8.3). |
| `preamble` | optional | Ada handcode emitted after the package spec. Per-instance emission (see §8.3). |
| `connectors` | optional | The subassembly's boundary connectors. If absent, the subassembly exposes no connectors and is wired only via variables / data flow. |
| `variables` | optional | Subassembly-level parameters consumed at instantiation; substituted into internal YAML scalars. See §7. |
| `subassemblies` | optional | Nested subassembly instances. Same shape as the parent assembly's `subassemblies:` block (§5). |
| `components` | required | Internal components. Same per-component schema as today's assembly model. At least one required. |
| `connections` | optional | Internal connections. Each is either component-to-component (within this subassembly), component-to-boundary (`forward_*` keywords; §4), or component-to-nested-subassembly-instance (treated as component-to-component at this level). |
| `id_bases` | optional | Top-level ID bases. **Permitted** but with a sharp edge: a subassembly that hardcodes `id_bases` cannot be instantiated more than once without an ID collision. Use `variables` to parameterize ID bases when multi-instance use is intended. |

### 3.2 Boundary connector declaration

Boundary connectors share the connector schema used by components today:

```yaml
connectors:
  - name: T_Recv_Sync
    description: Tick input scheduling the subassembly.
    type: Tick.T
    kind: recv_sync

  - name: Data_Out_Send
    description: Aggregated outputs leaving the subassembly.
    type: Data_Product.T
    kind: send
    count: 4

  - name: Time_Get
    type: Sys_Time.T
    return_type: Sys_Time.T
    kind: get
```

The `kind:` enum is the same as today's component connector kinds (`recv_sync`, `recv_async`, `send`, `request`, `service`, `get`, `return`, `provide`, `modify`). `count`, `priority`, `name`, `type`, `return_type`, and `description` retain today's component-connector semantics.

A boundary connector's kind is identical from both sides — there is no orientation flip. See §4 for how internal connections are written against it.

### 3.3 What a subassembly may not declare

A subassembly cannot define:

- A `main/` directory or any artifact that produces a standalone executable.
- View files that depend on the parent's full flat scope (subassembly views are scoped to the subassembly's own internals plus nested subassembly instances).

---

## 4. Connection rules

There are three kinds of connections, all expressed in the same `connections:` list inside a single file. Connections at the parent level use the same syntax as today.

### 4.1 Inside a subassembly: internal component to internal component

Identical to today.

```yaml
connections:
  - from_component: Internal_A
    from_connector: T_Send
    to_component: Internal_B
    to_connector: T_Recv_Sync
```

Both endpoints must be components defined in this subassembly's `components:` block (or boundary connectors of a nested subassembly instance — see §4.4).

### 4.2 Inside a subassembly: internal component out through a boundary connector

The internal component's invoker forwards out through the subassembly's own declared boundary connector:

```yaml
connections:
  - from_component: Internal_A
    from_connector: Some_Send
    forward_to_subassembly: Out_Boundary_Connector
    # from_index / to_index supported as today, where applicable
```

The `forward_to_subassembly:` keyword names a connector declared in this subassembly's `connectors:` block. Replaces `to_component` / `to_connector` for the side that crosses the boundary outward. The boundary connector's `kind:` must be a kind that takes data outbound (`send`, `request`, `get`, `provide`, etc.) and must match-type against the internal connector.

### 4.3 Inside a subassembly: external invocation in through a boundary connector

External invocations arriving at a boundary invokee are forwarded to an internal component:

```yaml
connections:
  - forward_from_subassembly: In_Boundary_Connector
    to_component: Internal_A
    to_connector: Some_Recv_Sync
```

The `forward_from_subassembly:` keyword names a connector declared in this subassembly's `connectors:` block. Replaces `from_component` / `from_connector` for the side that crosses the boundary inward. The boundary connector's `kind:` must be a kind that takes data inbound (`recv_sync`, `recv_async`, `service`, `return`, `modify`, etc.).

### 4.4 Inside a subassembly: wiring to a nested subassembly instance

A nested subassembly instance is, from the enclosing subassembly's vantage point, an addressable named entity exposing connectors. Wiring uses ordinary `from_component:` / `to_component:` syntax, with the instance name standing in for the component name and the boundary connector name standing in for the connector name:

```yaml
connections:
  - from_component: Internal_A
    from_connector: T_Send
    to_component: Some_Nested_Subassembly_Instance   # nested subassembly instance
    to_connector: In_Boundary_Connector              # nested's boundary connector
```

Whether `Some_Nested_Subassembly_Instance` is a component instance or a nested subassembly instance is resolved at load time against the union of names visible at this scope.

### 4.5 At the parent assembly level

A parent connection may name:

- A direct component instance defined in the parent's `components:` block.
- A subassembly instance defined in the parent's `subassemblies:` block.

In both cases the connector named by `from_connector:` / `to_connector:` is looked up against the named entity (component connector list or subassembly boundary connector list, respectively).

```yaml
connections:
  - from_component: Some_Parent_Component
    from_connector: T_Send
    from_index: 2
    to_component: Some_Subassembly_Instance     # subassembly instance
    to_connector: In_Boundary_Connector
```

### 4.6 What a connection may NOT do

- A parent connection may not name an internal component of any subassembly. The internal-component namespace is private; only that subassembly's own connections or sub-subassembly connections may reference it.
- A subassembly's internal connection may not name a component or boundary connector of a *sibling* subassembly. Cross-sibling wiring goes through the enclosing parent.
- `forward_to_subassembly` / `forward_from_subassembly` may only refer to the **enclosing** subassembly's own boundary connectors. They do not reach into a nested subassembly's boundary (use ordinary `to_component:` for that — see §4.4).

---

## 5. Parent assembly model — `subassemblies:` block

The parent assembly's `subassemblies:` list is no longer a flat list of strings. It becomes a list of maps mirroring the shape of the `components:` list, with subassembly-specific fields.

```yaml
subassemblies:
  - type: monitor_state              # required: name of the .subassembly.yaml file (no extension)
    name: Monitor_Instance           # optional: defaults to <Type>_Instance, e.g. Monitor_State_Instance
    description: ...                 # optional
    variables:                       # optional: values for variables declared by the subassembly type
      - "Tick_Period_Us => 100000"
      - "Mimu_Count => 3"
    map_data_dependencies:           # optional: resolves bubbled-up data dependencies (§9)
      - data_dependency: Convert_St_Platform_To_Body.Platform_Attitude
        data_product: Dpu_Interface_Instance.Asc_Platform_Attitude
        stale_limit_us: 0
      - data_dependency: Sunline_Ephem.Sun_Ephemeris
        data_product: Other_Subassembly_Instance.Internal_Component.Ephemeris_Data
        stale_limit_us: 0
```

| Field | Required | Notes |
|---|---|---|
| `type` | required | Subassembly type name (filename of `.subassembly.yaml` minus extension). |
| `name` | optional | Subassembly instance name. Defaults to `<Type>_Instance`. Must be unique across all components and subassembly instances at this scope. |
| `description` | optional | Free text; surfaces in views and docs. |
| `variables` | optional | Bindings for variables declared by the subassembly type. Required values must be supplied; optional ones may be omitted. Format: `"Name => Value"`. |
| `map_data_dependencies` | optional | Resolves bubbled-up data dependencies. Required if the subassembly has any required bubbled-up deps. See §9. |

`subassemblies:` may be omitted from a parent if no subassemblies are used. The same block shape applies inside a `.subassembly.yaml` for nested instances.

---

## 6. Encapsulation rules

### 6.1 Connectors: strict encapsulation, no leakage

- Internal component connectors are **private** to the subassembly. No connection at any outer scope may name them.
- The only connectors visible to outer scopes are those declared in the subassembly type's `connectors:` block.
- Renaming, removing, or restructuring an internal component's connectors is invisible to callers as long as the subassembly's declared `connectors:` block (and its forwarding wiring) is preserved.

### 6.2 ID-ed entities: leakage permitted, qualified addressing

ID-ed entities (events, commands, parameters, data products, faults, packets, data dependencies) declared on internal components are addressable from outer scopes via the qualified path:

```
<subassembly_instance_name>.<internal_component_instance_name>.<entity_name>
```

For nested subassemblies the path extends:

```
<outer_sub>.<inner_sub>.<internal_component>.<entity_name>
```

This applies to all surfaces that today reference entities by name, including:

- Parent-side `map_data_dependencies` (consumer side of the mapping).
- Parent-side `map_data_dependencies` (producer side: the `data_product:` value may be a qualified internal data product of any subassembly visible at the parent scope).
- Per-component `set_id_bases` resolution at autocode time.
- `*.product_packets.yaml`, `*.parameter_table.yaml`, `*.ccsds_router_table.yaml`, packet models, view filters, ground-system surfaces — all may name internals via the qualified path. The schemas of these files do not change beyond accepting the longer qualified names.

This leakage is intentional: ID-ed entities are inherently global at runtime (they have unique IDs in a single ID space per kind), and forcing them to be re-declared at every boundary would be high friction with no runtime benefit. Future versions may add an opt-in alias mechanism on the boundary, but it is out of scope for v2.

### 6.3 Discriminants and init values

Internal components' `discriminant`, `init`, `init_base`, `set_id_bases`, `subtasks`, `generic_types`, and `map_data_dependencies` are set inside the subassembly's `components:` block. The parent cannot reach in to override them.

To parameterize internal initialization across instances, use `variables` (§7) — substituted into the relevant internal YAML scalars at load time.

---

## 7. Variables — subassembly parameterization

A subassembly type may declare variables. Each instantiation supplies values; values are substituted as raw strings into the subassembly's internal YAML scalars before schema validation runs on the substituted result.

### 7.1 Declaration

```yaml
# inside a .subassembly.yaml
variables:
  - name: Tick_Period_Us
    description: Period of the internal ticker, in microseconds.
    required: true
  - name: Mimu_Count
    description: Number of internal MIMU averaging components.
    required: false
    default: "3"
  - name: Event_Id_Base_Value
    description: Base ID for events of the internal command router.
    required: false
    default: "1"
```

| Field | Required | Notes |
|---|---|---|
| `name` | required | Variable name. Substituted via `{{Name}}` in internal YAML scalars. |
| `description` | optional | Documentation. |
| `required` | optional | Defaults to `true`. If `true` and the instantiator does not supply a value, instantiation fails. |
| `default` | optional | String value used if `required: false` and no value is supplied. |

### 7.2 Substitution

Inside the subassembly's YAML, any scalar string may reference a variable as `{{Name}}`. Substitution is **textual** and runs **before** schema validation on the post-substitution result.

```yaml
components:
  - type: Ticker
    discriminant:
      - "Period_Us => {{Tick_Period_Us}}"

  - type: Command_Router
    set_id_bases:
      - "Event_Id_Base => {{Event_Id_Base_Value}}"

connectors:
  - name: Outputs_Send
    type: Data_Product.T
    kind: send
    count: {{Mimu_Count}}
```

Variables may appear in any scalar string in the subassembly model: `init`, `init_base`, `discriminant`, `set_id_bases`, `count`, `priority`, `type`, `name`, `map_data_dependencies` values, preamble / prepreamble text, even `connectors:` list entries.

### 7.3 Validation

- Required variables with no supplied value cause a model load error at instantiation.
- Optional variables fall back to their declared `default`.
- Type validity (e.g., is a substituted scalar actually an integer where the schema demands one?) is not checked at substitution time; the schema validator checks the post-substitution YAML, and any mismatch surfaces as a schema or compilation error.

### 7.4 Pass-through across nested subassemblies

A subassembly may declare its own variables and forward them (or expressions over them) into its nested subassembly instances:

```yaml
# outer.subassembly.yaml
variables:
  - name: Period_Us
    required: true

subassemblies:
  - type: inner
    name: Inner_Instance
    variables:
      - "Inner_Tick_Period => {{Period_Us}}"
```

Substitution at each level is independent: outer-scope variables resolve in outer-scope YAML; the resulting strings flow into inner-scope variable bindings, which then resolve inside the inner subassembly's YAML.

---

## 8. Naming and namespacing in the flat autocode

The autocoded assembly remains a flat list of concrete component instances. To preserve uniqueness across multiple instances of the same subassembly type, internal names are prefixed with the subassembly instance name at flatten time.

### 8.1 Component instances

A subassembly instance named `Core_A` containing an internal component named `Ticker_Instance` produces an autocode component named:

```
Core_A_Ticker_Instance
```

For nested subassemblies the prefix chains:

```
Outer_Instance_Inner_Instance_Ticker_Instance
```

The prefixing is mechanical and predictable. Engineers writing parent-level ID-ed-entity references (qualified path of §6.2) use the **dotted** form (`Core_A.Ticker_Instance.Some_Event`); the autocode renderer produces the underscore-flattened form.

### 8.2 Subtasks, queues, tasks

Per-component named structures (subtasks, queues, tasks, suspension objects, internal Ada constants) follow the same prefixing rule: their names in the autocode include the subassembly instance prefix.

### 8.3 Preamble / prepreamble emission

Subassembly preambles are emitted **once per instance**, with internal symbols namespaced so that two instances of the same subassembly do not collide. This may require autocode reorganization: each subassembly instance's components and preamble may be emitted into their own Ada child package (e.g., `Parent_Assembly.Core_A` / `Parent_Assembly.Core_B`), with the boundary erasure happening at the connection layer above. The exact Ada packaging strategy is an implementation question (§14).

This is the one acceptable autocode change — the user has explicitly approved repackaging of subassembly internals into their own Ada package as a means of preamble locality and symbol namespacing.

### 8.4 ID-ed entity IDs

Internal ID-ed entities continue to be allocated IDs from the single flat assembly-wide ID space, exactly as today. Auto-allocation runs over the flattened component list. Manual `set_id_bases` on internal components works as today (subject to per-instance uniqueness — hardcoded bases collide if the subassembly is instantiated more than once).

---

## 9. Bubbled-up data dependencies

A data dependency on an internal component is **resolved internally** if the internal component's `map_data_dependencies:` (or a default mapping) wires it to a data product visible inside the subassembly (an internal component, or a nested subassembly instance's internal data product).

A data dependency that is **not resolved internally** is automatically **bubbled up** to the subassembly's external boundary. It becomes part of the subassembly's "interface" and must be resolved by the instantiator.

### 9.1 Identification at the boundary

A bubbled-up dep is identified by the qualified path `<internal_component>.<dep_name>` (per the leakage rule of §6.2). This permits two internal components with the same dep name to coexist without collision and avoids requiring the subassembly author to alias every dep at the boundary.

### 9.2 Resolution at instantiation

The parent's `subassemblies:` entry for the instance carries a `map_data_dependencies:` block resolving each bubbled-up dep. Same shape as today's per-component mapping:

```yaml
- type: monitor_state
  name: Monitor_Instance
  map_data_dependencies:
    - data_dependency: Convert_St_Platform_To_Body.Platform_Attitude
      data_product: Dpu_Interface_Instance.Asc_Platform_Attitude
      stale_limit_us: 0
```

The `data_dependency:` value is the qualified internal name. The `data_product:` value is any data product visible at the parent scope (parent component or qualified internal of any subassembly instance).

### 9.3 Required vs optional

If the bubbled-up dep is `not_null` on the internal component, it is **required** at instantiation: model load fails if the parent does not map it. If it is nullable, it may be left unmapped (with an explicit `ignore` rule analogous to today's connector ignore).

### 9.4 Nesting

Bubbled-up deps propagate up nesting levels. A nested subassembly's bubbled-up deps appear at its enclosing subassembly's boundary; the enclosing subassembly may either resolve them internally (against its own components or its own boundary deps) or let them continue bubbling up to its own enclosing scope.

---

## 10. Standalone subassembly load

A `.subassembly.yaml` file is loadable as a standalone model for the purpose of producing documentation and diagrams. A standalone load:

- Validates the subassembly's own YAML against the `.subassembly.yaml` schema.
- Resolves all internal connections (component-to-component within the subassembly and forwarding connections to its declared boundary).
- Treats unmapped bubbled-up data dependencies as **warnings**, not errors. Diagrams render them as unresolved external arrows.
- Treats unconnected boundary connectors and unconnected internal connectors per the same rules as today's assembly load (warnings unless explicitly ignored).
- **Cannot** produce compiled Ada artifacts (no main, no concrete IDs assigned, no resolved external deps). `redo build/obj/...` from a subassembly directory is not a supported target.
- **Can** produce all documentation artifacts: HTML, TeX, dot/svg/eps diagrams, view renderings, descriptions.

Targets producible from a `.subassembly.yaml` directory mirror what today's assembly produces, minus Ada compilation:

```
redo build/dot/<sub>.dot
redo build/eps/<sub>.eps
redo build/svg/<sub>.svg
redo build/png/<sub>.png
redo build/html/<sub>_components.html
redo build/html/<sub>_connections.html
redo build/html/<sub>_events.html
redo build/html/<sub>_data_products.html
redo build/html/<sub>_data_dependencies.html
redo build/html/<sub>_commands.html
redo build/html/<sub>_packets.html
redo build/html/<sub>_parameters.html
redo build/html/<sub>_boundary.html              # NEW: declared boundary surface
redo build/eps/<sub>_boundary.eps                # NEW: boundary-only diagram
... etc
```

A `.subassembly.yaml`'s view files (`<view>.<sub>.view.yaml`) are scoped to that subassembly's internals plus its nested subassembly instances.

---

## 11. View / diagram surface

### 11.1 Boundary-only diagram (new)

A subassembly type generates a "boundary" diagram analogous to today's component diagram: a single labeled block with its declared boundary connectors arranged on its perimeter. Internal components are not shown. This is the canonical view that callers reference when wiring against a subassembly.

### 11.2 Internals diagram

A subassembly type also generates an "internals" diagram: today's assembly-level diagram, scoped to this subassembly's components and connections. Boundary connectors appear on the perimeter; forwarding connections render as edges from internal components to the boundary.

### 11.3 Parent assembly views: collapse / expand

Parent-level views gain a per-subassembly-instance "collapse / expand" knob. A collapsed instance renders as a single block with only its boundary connectors visible (matching the boundary diagram). An expanded instance renders its internals inline (matching today's flattened view). The exact view-schema field shape is an implementation question (§14).

### 11.4 Per-subassembly view files

Per-subassembly views (filtering, layout, show-switches) are declared in `<view>.<sub>.view.yaml` files in the subassembly's directory. They have access to the subassembly's internal components and any nested subassembly boundaries — but not the parent's full flat scope.

---

## 12. Backward compatibility and migration

This is a **breaking redesign**. There is no auto-migration path that produces semantically equivalent output for non-trivial existing subassemblies, because today's flat-merge subassemblies routinely cross what would become encapsulation boundaries (e.g., parent components named directly from internal `map_data_dependencies` blocks).

### 12.1 What breaks

- Existing `.assembly.yaml` files referenced from another `.assembly.yaml`'s `subassemblies:` list will fail to load: the parent's `subassemblies:` block now expects a list-of-maps, not a list-of-strings.
- Cross-boundary references (e.g., a subassembly's internal `map_data_dependencies` naming a parent component) will fail: encapsulation is enforced, and such references must move to the parent's `subassemblies:` entry as bubbled-up dep mappings.
- Sibling-subassembly references will fail for the same reason.

### 12.2 Migration steps

For each existing subassembly file `foo.assembly.yaml`:

1. Rename to `foo.subassembly.yaml`.
2. Add a `connectors:` block declaring the subassembly's external interface — every connector previously wired by the parent into an internal component becomes a boundary connector.
3. Convert parent connections that crossed into internals into a pair: a `forward_*` connection inside the subassembly, plus a parent connection to the new boundary connector.
4. Convert internal `map_data_dependencies` that named parent components into bubbled-up deps; move the parent-side resolution into the parent's `subassemblies:` entry.
5. If the same subassembly is to be instantiated more than once, replace any hardcoded `set_id_bases`, init values, or preamble Ada-name references with `variables` declarations and instance-side bindings.
6. Update parent `subassemblies:` block from list-of-strings to list-of-maps.

Existing top-level `.assembly.yaml` files are unaffected at the schema level; only the structure of their `subassemblies:` block changes.

### 12.3 Co-existence

`.assembly.yaml` files do not turn into subassemblies. A `.subassembly.yaml` cannot be a top-level build target. There is no shared file; the schema-extension distinction is hard.

---

## 13. Worked example

A trimmed sketch showing one subassembly type instantiated twice with different parameters and different parent-side wirings.

### 13.1 Subassembly type — `imu_chain.subassembly.yaml`

```yaml
description: One IMU chain — averaging plus majority-vote-style health check.

variables:
  - name: Time_Delta
    description: Time delta passed to the averaging stage.
    required: true
  - name: Threshold
    description: Body-rate threshold for fault detection.
    required: false
    default: "1.0"

connectors:
  - name: Tick_Recv_Sync
    type: Tick.T
    kind: recv_sync
  - name: Body_Rate_Send
    type: Nav_Att.T
    kind: send
  - name: Time_Get
    type: Sys_Time.T
    return_type: Sys_Time.T
    kind: get

components:
  - type: Average_Mimu_Data
    name: Avg
    discriminant:
      - "Time_Delta => {{Time_Delta}}"

  - type: Body_Rate_Miscompare
    name: Miscompare
    discriminant:
      - "Body_Rate_Threshold => {{Threshold}}"
    map_data_dependencies:
      - data_dependency: Imu_Body
        data_product: Avg.Imu_Body_Data
        stale_limit_us: 0
      # Star_Tracker_Attitude is not mapped here — it bubbles up.

connections:
  - forward_from_subassembly: Tick_Recv_Sync
    to_component: Avg
    to_connector: Tick_T_Recv_Sync

  - forward_from_subassembly: Tick_Recv_Sync
    to_component: Miscompare
    to_connector: Tick_T_Recv_Sync

  - from_component: Miscompare
    from_connector: Body_Rate_Send
    forward_to_subassembly: Body_Rate_Send

  - forward_from_subassembly: Time_Get
    to_component: Avg
    to_connector: Sys_Time_T_Get
```

### 13.2 Parent assembly — `flight.assembly.yaml`

```yaml
description: Flight assembly with two IMU chains.

components:
  - type: Rate_Group
    name: Fast_Rate_Group_Instance
    init_base:
      - "Tick_T_Send_Count => 2"
  - type: Time
    name: Time_Instance

subassemblies:
  - type: imu_chain
    name: Chain_A
    variables:
      - "Time_Delta => 0.01"
    map_data_dependencies:
      - data_dependency: Miscompare.Star_Tracker_Attitude
        data_product: St_Aggregate_Instance.Body_Att
        stale_limit_us: 0

  - type: imu_chain
    name: Chain_B
    variables:
      - "Time_Delta => 0.01"
      - "Threshold => 1.5"
    map_data_dependencies:
      - data_dependency: Miscompare.Star_Tracker_Attitude
        data_product: St_Aggregate_Instance.Body_Att
        stale_limit_us: 0

connections:
  - from_component: Fast_Rate_Group_Instance
    from_connector: Tick_T_Send
    from_index: 1
    to_component: Chain_A
    to_connector: Tick_Recv_Sync

  - from_component: Fast_Rate_Group_Instance
    from_connector: Tick_T_Send
    from_index: 2
    to_component: Chain_B
    to_connector: Tick_Recv_Sync

  - from_component: Chain_A
    from_connector: Time_Get
    to_component: Time_Instance
    to_connector: Time_Return

  - from_component: Chain_B
    from_connector: Time_Get
    to_component: Time_Instance
    to_connector: Time_Return
```

### 13.3 Resulting flat autocode (conceptual)

After flattening, the autocode sees:

- Components: `Fast_Rate_Group_Instance`, `Time_Instance`, `Chain_A_Avg`, `Chain_A_Miscompare`, `Chain_B_Avg`, `Chain_B_Miscompare`.
- Direct connections (a few representative ones):
  - `Fast_Rate_Group_Instance.Tick_T_Send[1] -> Chain_A_Avg.Tick_T_Recv_Sync`
  - `Fast_Rate_Group_Instance.Tick_T_Send[1] -> Chain_A_Miscompare.Tick_T_Recv_Sync`
  - `Fast_Rate_Group_Instance.Tick_T_Send[2] -> Chain_B_Avg.Tick_T_Recv_Sync`
  - `Fast_Rate_Group_Instance.Tick_T_Send[2] -> Chain_B_Miscompare.Tick_T_Recv_Sync`
  - `Chain_A_Avg.Sys_Time_T_Get -> Time_Instance.Time_Return`
  - `Chain_B_Avg.Sys_Time_T_Get -> Time_Instance.Time_Return`
- ID-ed entities flat-allocated as today; bubbled-up deps resolve to `St_Aggregate_Instance.Body_Att`'s data product ID for both chains.

The runtime model is identical to what would result from writing one big monolithic flat assembly by hand.

---

## 14. Open implementation questions

These are deliberately deferred. They are implementation choices, not user-facing semantics.

1. **Internal Ada packaging** — when emitting per-instance preambles, should each subassembly instance's internals live in its own Ada child package (`Parent.Chain_A`), or should symbols be name-mangled inline at the parent package level? Either works; the choice affects readability of generated code and the granularity of compilation units.

2. **Variable substitution mechanism** — Jinja-style `{{var}}` substitution applied to YAML text before parsing, vs. post-parse value walking with `${var}` markers. Both are viable.

3. **View collapse/expand schema** — the exact field name and shape of the per-subassembly-instance "show internals" toggle in `view.yaml`.

4. **Boundary connector arrayed-count interaction** — when a parent connects to indices `[1..3]` of an arrayed boundary connector and the subassembly internally fans those out to two different internal components (indices `[1..2] -> A`, `[3] -> B`), how is the wiring expressed inside the subassembly? Multiple `forward_from_subassembly` entries with `from_index` values seems natural.

5. **Cycle detection in nested instantiation** — subassembly type `A` instantiating subassembly type `B` instantiating subassembly type `A` must be detected and rejected.

6. **Caching / shallow-load interaction** — today's `shallow_load` mode for circular-dep resolution must continue to work in the new architecture.

7. **Error messages** — encapsulation violations (parent reaching into a subassembly internal) need clear, locatable error messages pointing at the offending YAML.

8. **`.gitignore` or build system implications** — boundary diagrams add new build outputs in subassembly directories.

9. **Ground-system integration** — Cosmos / Hydra / packetizer surfaces should continue to reference internals via the qualified `<sub>.<internal>.<entity>` path with no schema-level changes; verifying this end-to-end is implementation work.

10. **Migration tooling** — optional. A script that detects today's subassemblies, identifies their de-facto boundary (connectors and deps that cross out), and emits a starter `.subassembly.yaml` would smooth the migration but is not strictly required.

---

## 15. Out of scope for v2

These are deliberately deferred to a future iteration so that v2 remains tractable.

- **Boundary aliases for ID-ed entities** — the option to expose an internal event / data product / parameter under a renamed alias at the boundary, hiding the qualified internal path entirely. v2 leaks the qualified path as documented in §6.2.
- **Boundary contracts beyond connectors and bubbled-up deps** — e.g., boundary commands, boundary parameters declared as first-class boundary entities (rather than leaked internals). v2 surfaces these via leakage only.
- **Conditional / templated subassembly internals** — generating components based on variable values (`for i in 1..N: instantiate component X`). Requires a real templating engine, separate from the simple string substitution of v2.
- **Run-time subassembly identity** — exposing the subassembly grouping to the running system (e.g., for fault containment). v2 is purely a modeling-layer feature; the runtime sees flat components with no group identity.
- **Versioning and import resolution** — fetching a subassembly type from a registry or pinning a version. v2 resolves subassembly types only via the build path, exactly as today.

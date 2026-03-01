# Parameters Component — Code Review

**Reviewer:** Automated Expert Review  
**Date:** 2026-03-01  
**Branch:** `review/components-parameters`  
**Scope:** `src/components/parameters/` (excluding `build/`, `gen/templates/parameter_table/`, and `types/`)

---

## 1. Documentation Review

### DOC-01 — Event descriptions reuse wrong text for fetch events
- **Location:** `parameters.events.yaml`, events `Starting_Parameter_Table_Fetch` and `Finished_Parameter_Table_Fetch`
- **Original:**
  ```yaml
  - name: Starting_Parameter_Table_Fetch
    description: Starting updating of the parameters from a received memory region.
  - name: Finished_Parameter_Table_Fetch
    description: Done updating the parameters from a received memory region with following status.
  ```
- **Explanation:** These events describe a *fetch* (Get) operation, but their descriptions say "updating." This is copy-paste from the update events and will confuse operators reviewing telemetry.
- **Corrected:**
  ```yaml
  - name: Starting_Parameter_Table_Fetch
    description: Starting fetching of the parameters into a provided memory region.
  - name: Finished_Parameter_Table_Fetch
    description: Done fetching the parameters into a provided memory region with following status.
  ```
- **Severity:** Medium

### DOC-02 — Event description says "could not be updated" for fetch failure
- **Location:** `parameters.events.yaml`, event `Parameter_Fetch_Failed`
- **Original:**
  ```yaml
  - name: Parameter_Fetch_Failed
    description: A parameter value could not be updated.
  ```
- **Explanation:** This event fires on a *fetch* failure, not an update failure. The description is misleading.
- **Corrected:**
  ```yaml
  - name: Parameter_Fetch_Failed
    description: A parameter value could not be fetched.
  ```
- **Severity:** Medium

### DOC-03 — Spec comment drifted from YAML for memory region connector
- **Location:** `component-parameters-implementation.ads`, line ~23 (package-level comment)
- **Original:**
  ```ada
  -- ... The component allows updating of parameters through a table upload (via Memory_Region.T) ...
  ```
- **Explanation:** The YAML description correctly says `Memory_Region_T_Recv_Async`, but the Ada spec comment says `Memory_Region.T` (the type, not the connector). While minor, in safety-critical documentation the connector name should match the YAML to avoid confusion during reviews.
- **Corrected:**
  ```ada
  -- ... The component allows the staging and updating of parameters through a table upload (via Memory_Region_T_Recv_Async) ...
  ```
- **Severity:** Low

### DOC-04 — Component description omits "staging" in spec but includes it in YAML
- **Location:** `component-parameters-implementation.ads`, line ~23
- **Original:**
  ```ada
  -- The Parameters Component is responsible for updating and reporting the values ...
  ```
- **Explanation:** The YAML description says "staging, updating, and reporting" but the Ada spec omits "staging." The staging concept is central to the component's behavior (stage → validate → update).
- **Corrected:**
  ```ada
  -- The Parameters Component is responsible for staging, updating, and reporting the values ...
  ```
- **Severity:** Low

### DOC-05 — Memory region connector comment inconsistency between spec and YAML
- **Location:** `component-parameters-implementation.ads`, comment on `Parameters_Memory_Region_T_Recv_Async`
- **Original (spec):**
  ```ada
  -- ... For a "set" operation, the memory region length MUST match ...
  ```
- **Original (YAML):**
  ```yaml
  description: "... For either operation, the memory region length MUST match ..."
  ```
- **Explanation:** The YAML correctly states the length must match for *either* operation (Set or Get), but the Ada spec only mentions "set." The Get operation also requires a matching length (verified by the implementation's length check before the `case` statement).
- **Corrected:**
  ```ada
  -- ... For either operation, the memory region length MUST match ...
  ```
- **Severity:** Medium

---

## 2. Model Review

### MOD-01 — `parameter_table.py`: `_check_duplicate_parameters_across_tables` has O(n²) redundant re-scanning
- **Location:** `gen/models/parameter_table.py`, `_check_duplicate_parameters_across_tables()`, lines ~270–310
- **Original:**
  ```python
  for submodel_path, submodel in self.assembly.submodels.items():
      if isinstance(submodel, parameter_table) and submodel is not self:
          if not submodel.parameter_table_resolved:
              continue
          for table_entry in submodel.parameters.values():
              for param in table_entry.parameters:
                  param_name = param.name
                  if param_name in other_table_parameters:
                      # This parameter already exists in another table!
                      prev_table_name, prev_entry_id = other_table_parameters[param_name]
                      raise ModelException(...)
                  other_table_parameters[param_name] = (submodel.name, table_entry.entry_id)
  ```
- **Explanation:** The first loop checks for duplicates *among other tables* (not involving self), and will raise on duplicates between two other tables that happen to share a parameter. However, those other tables would have already checked themselves when they were loaded. More importantly, if two other tables *do* have a duplicate, this function will raise with an error message referencing neither `self.name` — confusing. The function should only check `self` against others, not others against others.
- **Corrected:**
  ```python
  # Collect all parameters from OTHER resolved tables
  other_table_parameters = {}
  for submodel_path, submodel in self.assembly.submodels.items():
      if isinstance(submodel, parameter_table) and submodel is not self:
          if not submodel.parameter_table_resolved:
              continue
          for table_entry in submodel.parameters.values():
              for param in table_entry.parameters:
                  other_table_parameters[param.name] = (submodel.name, table_entry.entry_id)

  # Only check self's parameters against the others
  for table_entry in self.parameters.values():
      for param in table_entry.parameters:
          if param.name in other_table_parameters:
              prev_table_name, prev_entry_id = other_table_parameters[param.name]
              raise ModelException(
                  f'Parameter "{param.name}" appears in parameter table "{prev_table_name}" '
                  f'(Entry_ID {prev_entry_id}) and also in parameter table "{self.name}" '
                  f'(Entry_ID {table_entry.entry_id}). ...'
              )
  ```
- **Severity:** Low

### MOD-02 — `parameter_table.py`: `store_parameter_table_entry` catches wrong exception
- **Location:** `gen/models/parameter_table.py`, `store_parameter_table_entry()` inner function
- **Original:**
  ```python
  def store_parameter_table_entry(table_entry):
      ...
      for param in table_entry.parameters:
          try:
              self.components[param.component.instance_name] = param.component
          except KeyError:
              pass
  ```
- **Explanation:** Dictionary assignment (`dict[key] = value`) never raises `KeyError` — only lookup does. The `try/except KeyError` is dead code. The assignment will always succeed, which is actually the desired behavior (building the components dict). The `try/except` should be removed for clarity.
- **Corrected:**
  ```python
  def store_parameter_table_entry(table_entry):
      ...
      for param in table_entry.parameters:
          self.components[param.component.instance_name] = param.component
  ```
- **Severity:** Low

### MOD-03 — `parameter_table.py`: Only first destination index used for grouped parameters
- **Location:** `gen/models/parameter_table.py`, end of `_resolve_parameter_table()`
- **Original:**
  ```python
  for table_entry in self.parameters.values():
      for param in table_entry.parameters:
          param.component_id = self.destinations[param.component.instance_name][0]
  ```
- **Explanation:** If a component is connected to the Parameters component on multiple arrayed connector indices, only the first index (`[0]`) is used. This is likely intentional (one component instance → one connector index), but if the same component instance name appears connected multiple times, the wrong index could be silently selected. A validation that each component maps to exactly one index would be safer.
- **Corrected:** Add a validation:
  ```python
  for table_entry in self.parameters.values():
      for param in table_entry.parameters:
          indexes = self.destinations[param.component.instance_name]
          if len(indexes) > 1:
              raise ModelException(
                  f'Component "{param.component.instance_name}" is connected to '
                  f'"{self.parameters_instance_name}" on multiple indexes: {indexes}. '
                  f'Each parameterized component must have exactly one connection.'
              )
          param.component_id = indexes[0]
  ```
- **Severity:** Medium

### MOD-04 — `parameters_packets.py`: `is` identity comparison relies on model object lifecycle
- **Location:** `gen/models/parameters_packets.py`, line ~64
- **Original:**
  ```python
  if (
      conn.to_component is self.component
      and conn.to_connector.name == "Parameters_Memory_Region_T_Recv_Async"
  ):
  ```
- **Explanation:** The comment correctly explains why `is` is used instead of `==`, but this is fragile — if model loading ever creates fresh copies of component objects, `is` will silently fail and fall through to the generic fallback. This is acceptable given the architecture but should be documented more prominently or have an explicit fallback warning.
- **Severity:** Low

---

## 3. Component Implementation Review

### IMPL-01 — `Update_Parameter` skips validation step before committing
- **Location:** `component-parameters-implementation.adb`, `Update_Parameter` command handler (~line 330–390)
- **Original:**
  ```ada
  -- OK everything looks good, let's stage the parameter.
  if Self.Stage_Parameter (Param_Entry => Param_Entry, Value => Arg.Buffer) /= Success then
     return Failure;
  end if;
  Components_To_Update (Param_Entry.Component_Id) := True;
  ...
  -- Now update all components that had parameters staged.
  for Component_Id in Components_To_Update'Range loop
     if Components_To_Update (Component_Id) then
        if Self.Update_Parameters (Component_Id => Component_Id) /= Success then
           return Failure;
        end if;
     end if;
  end loop;
  ```
- **Explanation:** The `Update_Parameter` command handler stages and then directly updates, **skipping the validate step**. In contrast, `Update_Parameter_Table` (memory region path) performs stage → validate → update. This means individual parameter updates via command bypass any component-level cross-parameter validation logic implemented in `Validate_Parameters`. If a component's `Validate_Parameters` function checks inter-parameter constraints (e.g., param_A < param_B), those constraints will not be enforced for single-parameter command updates. This is a design-level inconsistency that could allow invalid parameter combinations in flight.
- **Corrected:** Add a validation step between stage and update:
  ```ada
  -- Validate all components that had parameters staged.
  for Component_Id in Components_To_Update'Range loop
     if Components_To_Update (Component_Id) then
        if Self.Validate_Parameters (Component_Id => Component_Id) /= Success then
           return Failure;
        end if;
     end if;
  end loop;

  -- Now update all components that had parameters staged.
  for Component_Id in Components_To_Update'Range loop
     ...
  ```
- **Severity:** Critical

### IMPL-02 — Dropped invoker connector handlers are null — no telemetry on lost outbound messages
- **Location:** `component-parameters-implementation.ads`, lines ~62–72
- **Original:**
  ```ada
  overriding procedure Command_Response_T_Send_Dropped (Self : in out Instance; Arg : in Command_Response.T) is null;
  overriding procedure Parameters_Memory_Region_Release_T_Send_Dropped (Self : in out Instance; Arg : in Parameters_Memory_Region_Release.T) is null;
  overriding procedure Packet_T_Send_Dropped (Self : in out Instance; Arg : in Packet.T) is null;
  overriding procedure Event_T_Send_Dropped (Self : in out Instance; Arg : in Event.T) is null;
  overriding procedure Data_Product_T_Send_Dropped (Self : in out Instance; Arg : in Data_Product.T) is null;
  ```
- **Explanation:** If the downstream event/packet/data product/command response queues are full, messages are silently dropped with no telemetry. In a flight system, `Parameters_Memory_Region_Release_T_Send_Dropped` is particularly dangerous — a dropped memory region release means the memory will never be freed, causing a resource leak. At minimum, the memory release drop handler should attempt to send an event (acknowledging the event itself could also be dropped).
- **Corrected:** Implement at least the critical handler:
  ```ada
  overriding procedure Parameters_Memory_Region_Release_T_Send_Dropped (Self : in out Instance; Arg : in Parameters_Memory_Region_Release.T) is
  begin
     Self.Event_T_Send_If_Connected (Self.Events.Memory_Region_Dropped (Self.Sys_Time_T_Get, (Region => Arg.Region, Operation => Parameter_Enums.Parameter_Table_Operation_Type.Get)));
  end Parameters_Memory_Region_Release_T_Send_Dropped;
  ```
- **Severity:** High

### IMPL-03 — `Validate_Parameter_Table` stages parameters but never updates/rolls-back on success
- **Location:** `component-parameters-implementation.adb`, `Validate_Parameter_Table` function
- **Original:**
  ```ada
  function Validate_Parameter_Table (...) return Parameters_Memory_Region_Release.T is
  begin
     ...
     Status_To_Return := Self.Stage_Parameter_Table (Region);
     for Idx in Self.Connector_Parameter_Update_T_Provide'Range loop
        if Self.Validate_Parameters (Component_Id => Idx) /= Success then
           Status_To_Return := Parameter_Error;
        end if;
     end loop;
     ...
     return (Region => Region, Status => Status_To_Return);
  end Validate_Parameter_Table;
  ```
- **Explanation:** The validate operation stages new parameter values into downstream components' staging areas and then validates them, but **never rolls them back**. After a validate-only operation, the downstream components' staged parameters contain the validated table's values — not the previously active values. A subsequent `Update` operation (without a new `Stage`) would commit these stale staged values. This is a latent state corruption risk: if a validate is followed by an unrelated individual parameter update that calls `Update_Parameters`, the previously validated (but not intended to be committed) values could be committed. In practice, the autocoded `Process_Parameter_Update` likely overwrites staged values on the next stage, but the window exists.
- **Severity:** Medium

### IMPL-04 — `Send_Parameters_Packet` returns `Success` when packet connector is disconnected
- **Location:** `component-parameters-implementation.adb`, `Send_Parameters_Packet` function
- **Original:**
  ```ada
  function Send_Parameters_Packet (...) return Parameter_Enums.Parameter_Update_Status.E is
     To_Return : ... := Success;
  begin
     if Self.Is_Packet_T_Send_Connected then
        ...
     end if;
     return To_Return;
  end Send_Parameters_Packet;
  ```
- **Explanation:** If the packet connector is not connected, the function returns `Success` without doing anything. Callers (like `Update_Parameter_Table`) rely on this status to determine overall success. This is arguably correct (if you didn't ask for packets, not sending one isn't an error), but it means `Dump_Parameters` command will return `Success` even when no packet was produced, which may confuse operators.
- **Severity:** Low

### IMPL-05 — `Table_Update_Time` uses only seconds, losing sub-second precision
- **Location:** `component-parameters-implementation.adb`, `Update_Parameter_Table`, line ~287
- **Original:**
  ```ada
  Self.Table_Update_Time := Self.Sys_Time_T_Get.Seconds;
  ```
- **Explanation:** The `Table_Update_Time` field is `Interfaces.Unsigned_32` and only captures seconds. The `Sys_Time.T` type has a `Subseconds` field that is discarded. For parameter table forensics, sub-second precision may be needed to correlate updates with other telemetry. This is a design choice but worth noting.
- **Severity:** Low

---

## 4. Unit Test Review

### TEST-01 — No test for `Update_Parameter` with grouped parameters where first component fails but second succeeds stage
- **Location:** `test_grouped/parameters_grouped_tests-implementation.adb`, `Test_Grouped_Update_Parameters_Error`
- **Explanation:** The test only checks the case where Component_A (the first in the group) fails staging. It does not test what happens when Component_A succeeds staging but Component_B fails staging for a grouped parameter. In that scenario, `Update_Parameter` would stage Component_A, then fail on Component_B, and return `Failure` — leaving Component_A with staged but uncommitted values (similar to IMPL-03). A test verifying this behavior (and ensuring Component_A's staged values don't get committed) would be valuable.
- **Severity:** Medium

### TEST-02 — `Test_Init` uses `'Unchecked_Access` with stack-allocated parameter table entries
- **Location:** `test/parameters_tests-implementation.adb`, all `Init_*` sub-procedures in `Test_Init`
- **Original:**
  ```ada
  Parameter_Table_Entries : aliased Parameters_Component_Types.Parameter_Table_Entry_List := ...;
  ...
  T.Component_Instance.Init (Parameter_Table_Entries'Unchecked_Access, 1, False);
  ```
- **Explanation:** The parameter table entries are stack-allocated and passed via `'Unchecked_Access`. Since `Init` stores this pointer in `Self.Entries`, if the component were used after the declaring scope exits, it would be a dangling pointer. In these tests, the component is re-initialized in `Set_Up_Test` before any subsequent use, so this is safe in practice. However, for tests that expect exceptions (catching them and continuing), the component instance retains the dangling pointer. Since `Set_Up_Test` re-initializes before each test method, this is benign but fragile.
- **Severity:** Low

### TEST-03 — `Test_Grouped_Fetch_Value_Mismatch` uses `Override_Parameter_I32` without prior declaration
- **Location:** `test_grouped/parameters_grouped_tests-implementation.adb`, `Test_Grouped_Fetch_Value_Mismatch`
- **Original:**
  ```ada
  T.Component_A.Override_Parameter_I32 ((Value => 99));
  ```
- **Explanation:** This calls `Override_Parameter_I32` on `Component_A` which is a `Test_Component_1.Implementation.Instance`. This procedure is not declared in the spec file I reviewed (`component-test_component_1-implementation.ads`). It may be in the grouped test's variant of `Test_Component_1`, which has its own directory (`test_grouped/test_component_1/`). If so, this is fine — but it means the grouped test's test components differ from the base test's test components, which should be noted.
- **Severity:** Low (informational)

### TEST-04 — Missing test for data product emission on `Set_Up`
- **Location:** `test/parameters_tests-implementation.adb`
- **Explanation:** The `Test_Init` test includes `Init_Set_Up_Data_Product` which tests `Set_Up`, but only in the base test suite. The grouped test suite (`test_grouped`) does not test `Set_Up`. This is acceptable since `Set_Up` behavior doesn't differ for grouped parameters, but for completeness it could be noted.
- **Severity:** Low

### TEST-05 — No test for empty parameter table (zero entries)
- **Location:** `test/parameters_tests-implementation.adb`, `Test_Init`
- **Explanation:** All init tests use parameter tables with 5 entries. There is no test for an empty parameter table (zero entries). While the model schema requires `min: 1` parameter, the Ada `Init` procedure doesn't explicitly guard against an empty entries list. Accessing `Self.Entries.all'Last` on an empty list would fail. A defensive test would verify correct behavior or assertion.
- **Severity:** Low

---

## 5. Summary — Top 5 Issues

| # | ID | Severity | Summary |
|---|-----|----------|---------|
| 1 | IMPL-01 | **Critical** | `Update_Parameter` command skips the validate step (stage → update, no validate), allowing invalid parameter combinations to be committed in flight. The memory region path correctly does stage → validate → update. |
| 2 | IMPL-02 | **High** | All outbound connector drop handlers are `is null`, meaning a dropped `Parameters_Memory_Region_Release` causes a silent memory leak with no telemetry. |
| 3 | DOC-01 | **Medium** | Fetch event descriptions say "updating" instead of "fetching" — operator confusion in telemetry review. |
| 4 | DOC-05 | **Medium** | Memory region connector comment in Ada spec says length check only applies to "set" but implementation checks all operations. |
| 5 | MOD-03 | **Medium** | Autocoder silently picks first connector index when a component is connected on multiple indices, potentially routing parameter updates to the wrong connection. |

# Task Watchdog List Template Package Review

## Package Spec Review

**File: `name.ads`** — Jinja2 template generating an Ada package spec containing the initialization list for the task watchdog component.

### Strengths
- Clean iteration over `watchdog_list` entries with proper comma handling (`"," if not loop.last`)
- Good use of optional description rendering via `printMultiLine`
- Correctly maps each petter's YAML config fields to the `Task_Watchdog_Init_List` aggregate record fields
- User-defined `name` field is emitted as a comment for traceability

### Issues
1. **Missing space before `critical` closing delimiter**: `Critical => {{ petter.critical}}` — missing space before `}}`. While Jinja2 tolerates this, it's inconsistent with every other field in the same aggregate which uses `{{ ... }}` with spaces.
2. **Connector ID indexed at `[0]`**: `petter.connector_id[0]` is used as the array index and as the enumeration representation value. This assumes `connector_id` is always a list with at least one element. No guard or validation exists in the template if the model provides an empty or malformed `connector_id`.
3. **`watchdog_list.values()` iteration order**: The template iterates `.values()` of a dict. In Python 3.7+ dicts preserve insertion order, but this is an implicit contract — the schema doesn't document that ordering matters for connector index assignment.

---

## Implementation Review

**Files: `name_watchdog_action_cmd.record.yaml`, `name_watchdog_limit_cmd.record.yaml`**

### Strengths
- Both command records share an identical `Task_Enum_Type` preamble, creating a typed enumeration mapped to connector IDs — excellent for ground-system commanding
- Representation clauses (`for Task_Enum_Type use ...`) ensure wire-format stability
- Format specifiers (`E16`, `E8`, `U16`) are appropriate for the field sizes and match the component implementation's expectations

### Issues
4. **Duplicated preamble logic**: The `Task_Enum_Type` definition is copy-pasted identically between the action and limit command records. If a petter naming rule changes, both files must be updated in sync. This is a maintenance risk — consider a shared Jinja2 macro or include.
5. **Action command `New_Action` is `E8` but `Watchdog_Action_State.E` only uses 2 bits**: The over-sized format wastes 6 bits per command. This is a minor wire efficiency concern but may be intentional for alignment. Worth documenting the rationale.
6. **`connector_name | replace(".","_")`**: The fallback name (when `petter.name` is not defined) replaces dots with underscores. If a connector name contains other Ada-illegal identifier characters, the generated code will fail to compile. No broader sanitization is applied.

**File: `name_state_record.record.yaml`** — Generates a packed status data product record.

### Strengths
- Clever 2-bit-per-entry packing with automatic padding to nibble boundaries (`num_petters % 4`)
- Padding fields use a dedicated `Two_Bit_Padding_Type` for clarity

### Issues
7. **Padding uses `product_name` but no uniqueness check**: If two petters resolve to the same `product_name`, the generated record will have duplicate field names, causing a compile error. The template doesn't guard against this.
8. **`format: E2`** for a 2-bit enum is tight — this works but assumes downstream tooling supports 2-bit enum serialization correctly. Edge cases with unusual petter counts (e.g., exactly 4, 8, etc.) should be verified for off-by-one in padding logic.

---

## Model Review

**File: `gen/schemas/task_watchdog_list.yaml`** — Kwalify-style schema for the YAML model.

### Strengths
- Well-structured with clear field descriptions
- Proper range constraints on `limit` (1–65534, matching `U16` minus sentinel)
- `action` enum is explicit: `['disabled', 'warn', 'error_fault']`
- Minimum list length enforced (`min: 1`)

### Issues
9. **`fault_id` not conditionally required**: The schema marks `fault_id` as optional, but the component implementation requires it when `action` is `error_fault`. A petter configured with `action: error_fault` but no `fault_id` would generate code that compiles but sends faults with an uninitialized ID. The schema should enforce `fault_id` is required when `action == error_fault`.
10. **`action` defaults are implicit**: When `action` is not provided (it's not required), the template must have a default. The schema doesn't specify what that default is — it's left to the generator/template, creating ambiguity.
11. **No `name` uniqueness constraint**: Multiple petters could have the same `name`, leading to duplicate Ada enumeration literals in the generated command records — a compile-time error with no schema-level guard.

---

## Unit Test Review

**Files: `test/task_watchdog.tests.yaml`, `test/task_watchdog_tests-implementation.adb`, `test/test_assembly/test_assembly.task_watchdog_list.yaml`**

### Strengths
- Comprehensive test assembly with 3 petters covering all action types (error_fault, disabled, warn) and both critical/non-critical
- `Test_Received_Pet`: Thoroughly walks through the pet/tick lifecycle, verifying disabled connectors don't fire, warn fires once, fault fires with critical stop
- `Test_Watchdog_Petter_Check_Command`: Validates enable/disable of global pet checking, including state persistence across ticks
- `Test_Watchdog_Action_Command`: Tests action promotion, demotion, invalid transitions (no fault ID → error_fault), and out-of-range index
- `Test_Watchdog_Limit_Command`: Validates dynamic limit changes with proper data product emission
- `Test_Invalid_Command`: Verifies malformed command handling with `Length_Error`

### Issues
12. **No test for default action**: The test assembly always specifies `action` explicitly. There's no test for what happens when `action` is omitted (the default path).
13. **Connector ordering is assumed, not verified**: Tests rely on knowing the exact index-to-petter mapping (e.g., index 1 = warn petter, index 2 = critical). There's no assertion that the generated init list order matches expectations — fragile if the generator changes ordering.
14. **No boundary tests for limit values**: The schema allows limits 1–65534, but tests only use small values (1, 2, 3, 4, 5). No test exercises `limit = 1` (minimum boundary, immediate trip) or `limit = 65534` (maximum).
15. **Fault only thrown once per trip**: The test verifies a fault is sent on first detection and not re-sent (`Repeat_Failure` path), but doesn't test the reset-and-re-trigger cycle for fault-action petters (it does for warn).

---

## Summary (Top 5)

| # | Priority | Finding |
|---|----------|---------|
| 1 | **High** | `fault_id` is not conditionally required in the schema when `action` is `error_fault` — could produce runtime bugs with uninitialized fault IDs (Issue 9) |
| 2 | **Medium** | Duplicated `Task_Enum_Type` preamble across two command record templates — maintenance/divergence risk (Issue 4) |
| 3 | **Medium** | No uniqueness validation on `name` or `product_name` fields — duplicate Ada identifiers cause compile failures with no early warning (Issues 7, 11) |
| 4 | **Medium** | No unit tests for boundary limit values (1, 65534) or omitted optional fields (`action` default) (Issues 12, 14) |
| 5 | **Low** | `connector_name` sanitization only replaces dots — other Ada-illegal characters in connector names would produce invalid code (Issue 6) |

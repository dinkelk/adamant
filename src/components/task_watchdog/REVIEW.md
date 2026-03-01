# Task Watchdog — Component Code Review

**Date:** 2026-03-01  
**Reviewer:** Automated (Claude)  
**Component:** `src/components/task_watchdog`

---

## 1. Documentation

The component description in `task_watchdog.component.yaml` is clear and thorough. The LaTeX document template (`doc/task_watchdog.tex`) follows the standard Adamant pattern and references all expected sections. Event, command, data product, and fault YAML files have useful descriptions.

**Issues:**

- **D-1**: The `watchdog_action_cmd.record.yaml` file's top-level description says "information for changing the **limit**" but it actually changes the **action**. Copy-paste error from `watchdog_limit_cmd.record.yaml`.
- **D-2**: The `watchdog_state_change.record.yaml` type exists but is never referenced by any event, command, or data product. It appears to be dead/orphan configuration.
- **D-3**: The `watchdog_list.adb` package-level comment says "binary tree" (`-- This is a somewhat generic, unprotected binary tree for holding apids and filter factors for the downsampler component.`). This is copy-pasted boilerplate from another component and is completely inaccurate — it's a flat array, not a binary tree, and has nothing to do with APIDs or the downsampler.
- **D-4**: Requirements list (`task_watchdog.requirements.yaml`) does not include a requirement for the `Set_Watchdog_Action` command, though one exists for `Set_Watchdog_Limit` (requirement 5) and enable/disable (requirement 4). Incomplete traceability.

---

## 2. Model

The YAML model and Python code-generation infrastructure is well-structured. The `task_watchdog_list.py` model properly validates inputs, resolves assembly connectors, and sorts by index.

**Issues:**

- **M-1**: In `task_watchdog_list.py` model, the action validation uses `in "error_fault"` (substring test) instead of `== "error_fault"`. Because `"error_fault"` contains the substring `"fault"`, if someone hypothetically added an action named `"fault"`, the `in` check on the string `"error_fault"` would match it. More critically, the check `petter["action"] in "error_fault"` will also match substrings like `"error"`, `"fault"`, `"or"`, etc. — this is a semantic bug. It should be `== "error_fault"`.
- **M-2**: The schema (`task_watchdog_list.yaml`) makes `action` **not required** (`required: False`), but the model code accesses `petter["action"]` unconditionally. If a user omits `action`, a `KeyError` will be raised with no helpful message. Either make it required in the schema or add a default in the model.
- **M-3**: The Dummy_Fault in `task_watchdog.task_watchdog_faults.yaml` with `id: 1` is documented as a placeholder to be replaced by the watchdog list generator. This works but is fragile — if someone doesn't use the generator, the component ships with a nonsensical fault definition.

---

## 3. Implementation

The Ada implementation is generally solid. The protected object pattern correctly guards concurrent access to the watchdog entry list. Command handling is well-structured with proper validation and event/data-product reporting.

**Issues:**

- **I-1 (Severity: Medium — Logic)**: `Send_Action_Dp` has an off-by-one in `Buffer_Length` calculation. After the loop, `Product_Buffer_Index` has already been incremented past the last written byte (or is at the position of the last written byte + 1). The line `To_Send.Header.Buffer_Length := Product_Buffer_Index - Data_Product_Types.Data_Product_Buffer_Index_Type'First` computes the length as the number of bytes written. However, when the final `Record_Slot = 3` and it's also the last iteration, the index is incremented *after* the write, so the length is correct. But when the last entry does **not** land on slot 3 (i.e., partial byte at end), the byte is written and *then* `Product_Buffer_Index` is incremented — also correct. This appears sound on close inspection, but the logic is subtle and uncommented. The `if Product_Buffer_Index < ...Last then` guard prevents overflow but silently stops incrementing, which could mask a real overflow condition in pathological configurations.

- **I-2 (Severity: Medium — Safety)**: `Set_Watchdog_Limit` checks `Connector_Index <= (Pet_T_Recv_Sync_Index'First + Self.Pet_T_Recv_Sync_Count - 1)` but does **not** check the lower bound (`>= Pet_T_Recv_Sync_Index'First`). If `Connector_Index` is 0 and `Pet_T_Recv_Sync_Index'First` is 1, the index passes the upper-bound check but will cause an out-of-range access in the `Watchdog_List` array. The `Set_Watchdog_Action` command checks `>` for the upper bound (early return on failure) but also omits the lower-bound check.

- **I-3 (Severity: Low — Design)**: `Watchdog_List.Init` allocates heap memory (`new Task_Watchdog_Pet_List`) but there is no corresponding `Destroy`/`Final` procedure to deallocate it. While the component likely lives for the lifetime of the application, this is a resource leak if the component is ever torn down and re-initialized (e.g., in testing). The test `Tear_Down_Test` calls `Final_Base` but there's no `Final` on the `Watchdog_List.Instance` or the protected object.

- **I-4 (Severity: Low — Robustness)**: `Watchdog_List.Reset_Pet_Count`, `Set_Pet_Limit`, and `Set_Pet_Action` are declared as modifying procedures on `in Instance` (not `in out Instance`). They modify data through the access pointer (`Task_Watchdog_Pet_Connections`), which is technically legal in Ada but violates the semantic contract of `in` mode. This can confuse readers and static analysis tools.

- **I-5 (Severity: Medium — Safety)**: `Check_Watchdog_Pets` increments `Missed_Pet_Count` only when `count <= limit`. When `count = limit`, it increments to `limit + 1`, which means the "exact match" (`Pet_Count = Pet_Count_Limit`) branch fires exactly once, and subsequent calls see `count > limit` → `Repeat_Failure`. This is correct behavior. However, the counter saturates at `limit + 1`, which is fine, but the saturation condition (`<=`) means the counter goes one past the limit. If `Missed_Pet_Limit_Type'Last` is used as the limit (65534), then `count` would try to reach 65535, which is `Missed_Pet_Count_Type'Last` — the increment `@ + 1` could potentially overflow if the types weren't carefully ranged. Looking at the types: `Missed_Pet_Count_Type` is `0 .. 65535` and `Missed_Pet_Limit_Type` is `1 .. 65534`. So limit max = 65534, count goes to 65535 (max of count type) — this is safe by design. Good type engineering, but no comment explains this critical relationship.

- **I-6 (Severity: Low — Event Storm)**: When a critical task is in `Repeat_Failure`, `Critical_Task_Not_Petting` event is sent on **every tick**. For a 1 Hz tick rate this could flood the event bus. Consider rate-limiting or only sending on transition.

---

## 4. Unit Test

Tests are comprehensive, covering all five test cases: basic pet receipt, enable/disable commands, action change commands, limit change commands, and invalid commands. The test assembly uses 3 petters with a good mix of configurations (disabled, warn, error_fault; critical vs non-critical).

**Issues:**

- **T-1**: Tests do not exercise the lower-bound check gap identified in I-2. No test sends a `Set_Watchdog_Limit` or `Set_Watchdog_Action` command with `Index => 0` to verify the component rejects it. If `Pet_T_Recv_Sync_Index'First` is 1, index 0 would be out of range.
- **T-2**: No test verifies behavior when `Set_Watchdog_Action` transitions from `Disabled` back to `Warn` or `Error_Fault` *while* the missed pet count has already exceeded the limit. The counter is not reset on action change (unlike `Set_Pet_Limit` which resets the count). This means changing action from `Disabled` to `Warn` while count > limit would immediately trigger `Repeat_Failure` (no event), not `Warn_Failure`. This may or may not be intended but is untested.
- **T-3**: The `Pet_T_Recv_Sync` handler in the implementation uses `pragma Assert` for index validation. In production builds with assertions disabled, an out-of-range index would proceed unchecked. This is noted as "a bug in the autocode" which is reasonable, but no test verifies the assertion fires.
- **T-4**: No test covers re-initialization or the `Watchdog_List` being initialized twice (double-init would leak the first allocation per I-3).
- **T-5**: Test descriptions in `task_watchdog.tests.yaml` for `Test_Watchdog_Action_Command` says "change the action given the index" but the spec file says "change the state of the pet index." Minor inconsistency.

---

## 5. Summary — Top 5 Findings

| # | Severity | Area | Finding |
|---|----------|------|---------|
| 1 | **Medium** | Model (M-1) | `petter["action"] in "error_fault"` is a substring test, not equality — will incorrectly match substrings like `"error"`, `"fault"`, `"or"`, etc. Should be `==`. |
| 2 | **Medium** | Impl (I-2) | `Set_Watchdog_Limit` and `Set_Watchdog_Action` commands do not validate the lower bound of the connector index. Index 0 (or any value below `Pet_T_Recv_Sync_Index'First`) would pass validation and cause an array bounds violation in `Watchdog_List`. |
| 3 | **Medium** | Impl (I-6) | `Critical_Task_Not_Petting` event fires every tick during sustained failure, potentially flooding the event bus with no rate limiting. |
| 4 | **Low** | Doc (D-3) | `watchdog_list.adb` has a completely wrong package comment referencing "binary tree", "apids", and "downsampler component" — copy-paste from another component. |
| 5 | **Low** | Model (M-2) | Schema makes `action` field optional but model code accesses it unconditionally, causing an unhelpful `KeyError` if omitted. |

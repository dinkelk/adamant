# Connector_Counter_16 — Code Review

**Branch:** `review/components-connector-counter-16`
**Reviewer:** Automated (Claude)
**Date:** 2026-02-28

---

## 1. Documentation Review

### Issue 1.1 — Copy-paste comment: "8 bit" should be "16 bit"

- **File:** `component-connector_counter_16-implementation.ads`, line 19
- **Severity:** Medium
- **Original:**
  ```ada
  -- Instantiate protected 8 bit counter:
  ```
- **Explanation:** This comment was copied from `connector_counter_8` and not updated. The counter is 16 bits wide (`Interfaces.Unsigned_16`), not 8. Misleading comments in safety-critical code erode trust in the documentation and may confuse maintainers into thinking the wrong type is used.
- **Corrected:**
  ```ada
  -- Instantiate protected 16 bit counter:
  ```

### Issue 1.2 — Package name "Sixteen_Counter" is inconsistent with naming pattern

- **File:** `component-connector_counter_16-implementation.ads`, line 20
- **Severity:** Low
- **Original:**
  ```ada
  package Sixteen_Counter is new Protected_Variables.Generic_Protected_Counter (Interfaces.Unsigned_16);
  ```
- **Explanation:** The `connector_counter_8` variant uses the descriptive name `Byte_Counter` (matching the type `Basic_Types.Byte`). Here `Sixteen_Counter` is less conventional — the name describes the width rather than the type. A name like `U16_Counter` or `Word_Counter` would be more parallel. Additionally, the 8-bit variant uses `Basic_Types.Byte` while this variant uses `Interfaces.Unsigned_16` directly; using `Packed_U16.U16` or another Adamant-native type alias (if one exists) would improve consistency. This is stylistic and low severity.
- **Corrected (suggestion):**
  ```ada
  package U16_Counter is new Protected_Variables.Generic_Protected_Counter (Interfaces.Unsigned_16);
  ```
  (with corresponding rename of `Sixteen_Counter.Counter` → `U16_Counter.Counter` in the record.)

---

## 2. Model Review

### No issues found.

The `component.yaml`, `commands.yaml`, `events.yaml`, and `data_products.yaml` files are consistent with each other and with the `connector_counter_8` model (differing only in the expected `Packed_U16.T` data product type and description text). Connector definitions are complete and correctly typed.

---

## 3. Component Implementation Review

### Issue 3.1 — Data product sent before and independently of the forwarded invocation

- **File:** `component-connector_counter_16-implementation.adb`, `T_Recv_Sync` (lines 16–25)
- **Severity:** Low
- **Original:**
  ```ada
  Self.T_Send_If_Connected (Arg);
  Self.Count.Increment_Count;
  Self.Data_Product_T_Send_If_Connected (...);
  ```
- **Explanation:** The count is incremented *after* the downstream send. If `T_Send_If_Connected` is not connected (returns without sending), the count still increments. This is consistent with the `connector_counter_8` implementation and is by design (count invocations, not successful sends), so this is noted for awareness only — not a defect. The pattern is acceptable given the component's stated purpose of counting *invocations*.

### No functional defects found.

The implementation is a faithful 16-bit analogue of `connector_counter_8`. Command handling, event emission, data product updates, and `Set_Up` initialization are all correct.

---

## 4. Unit Test Review

### Issue 4.1 — No unit tests exist

- **Severity:** High
- **Explanation:** There is no `test/` directory and no test files for this component. The `connector_counter_8` sibling also lacks tests (checked for comparison), but the absence of unit tests for a safety-critical flight component is a significant gap. At minimum, tests should cover:
  1. Count increments on each `T_Recv_Sync` invocation
  2. Rollover behavior at `2^16 - 1` (65535 → 0)
  3. `Reset_Count` command resets to 0 and emits event
  4. `Invalid_Command` handler emits correct event
  5. `Set_Up` publishes initial zero count
  6. Data product value correctness at each step
  7. Behavior when downstream `T_Send` connector is not connected

---

## 5. Summary — Top 5 Issues

| # | Severity | Section | Description |
|---|----------|---------|-------------|
| 1 | **High** | §4.1 | No unit tests exist for the component |
| 2 | **Medium** | §1.1 | Copy-paste comment says "8 bit counter" instead of "16 bit counter" |
| 3 | **Low** | §1.2 | Package name `Sixteen_Counter` inconsistent with `Byte_Counter` pattern in sibling |
| 4 | **Low** | §3.1 | Count increments regardless of downstream connection status (by design, noted for awareness) |
| 5 | — | — | No further issues identified; implementation is clean and correct |

## Resolution Notes

| # | Issue | Severity | Status | Commit | Notes |
|---|-------|----------|--------|--------|-------|
| 1 | No unit tests | High | Not Fixed | e96f8ca | Needs codegen harness |
| 2 | Copy-paste "8 bit" comment | Medium | Fixed | 0c62fc8 | Corrected to 16-bit |
| 3 | Naming inconsistency | Low | Fixed | 6548c64 | Renamed to U16_Counter |
| 4 | Count regardless of connection | Low | Not Fixed | 04c6183 | By design |

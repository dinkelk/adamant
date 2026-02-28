# Router_Table Package Code Review

**Package:** `Router_Table`
**Reviewer:** Automated Ada Code Review (Safety-Critical Focus)
**Date:** 2026-02-28
**Branch:** `review/components-command-router-router-table`

---

## 1. Package Specification Review

**File:** `router_table.ads`

The specification is clean, well-documented, and provides a clear API. No issues found.

**Observations (no action required):**
- Good use of `tagged limited private` to prevent copies of the table instance.
- Enumerated status types (`Add_Status`, `Lookup_Status`) provide clear, type-safe error handling — appropriate for flight code.
- Binary tree choice is well-suited: O(log n) lookup for a table populated once at startup.

---

## 2. Package Implementation Review

**File:** `router_table.adb`

### Issue 2.1 — Sentinel value on failed lookup may alias a valid Registration_Id

**Location:** `router_table.adb`, function `Lookup_Registration_Id`, line within the `if not ... Search` branch

**Original code:**
```ada
Registration_Id := Command_Types.Command_Registration_Id'Last;
return Id_Not_Found;
```

**Explanation:**
On lookup failure, `Registration_Id` is set to `Command_Registration_Id'Last` (65535 for a U16). This is a valid value within the type's range. If a caller ignores the returned `Lookup_Status` and uses the `out` parameter directly, it could be mistaken for a real registration ID. In safety-critical code, a clearly documented or otherwise distinguished sentinel is preferable. Since `Command_Registration_Id` is a bare `Unsigned_16`, there is no out-of-band sentinel available — the real mitigation is ensuring callers always check the status, but the current value silently looks valid.

**Suggested improvement (defensive documentation):**
```ada
-- Sentinel: Registration_Id is set to 'Last on failure.
-- Callers MUST check the return status before using Registration_Id.
Registration_Id := Command_Types.Command_Registration_Id'Last;
return Id_Not_Found;
```

**Severity:** **Medium** — No runtime failure, but a latent integration hazard if callers misuse the out parameter.

---

### Issue 2.2 — No protection against use before `Init` or after `Destroy`

**Location:** `router_table.adb`, all public subprograms

**Explanation:**
All public operations (`Add`, `Lookup_Registration_Id`, `Clear`, `Get_Size`, `Get_Capacity`) delegate directly to `Self.Table` (the `Binary_Tree.Instance`). If a caller invokes any operation before `Init` or after `Destroy`, the underlying `Binary_Tree` will dereference a null access (`Tree` is initialized to `null` in the `Binary_Tree` spec). This would raise a `Constraint_Error` at runtime with no descriptive context. In safety-critical systems, a defensive precondition check or documented assertion would make the failure mode explicit and traceable.

**Suggested improvement (example for `Add`):**
```ada
function Add (Self : in out Instance; An_Entry : Command_Registration.U) return Add_Status is
   pragma Assert (Self.Table.Get_Capacity > 0, "Router_Table.Add called on uninitialized table");
   ...
```

**Severity:** **Low** — In practice the table is initialized once at startup and never destroyed during operation, but the implicit null-dereference failure mode is poor for flight-code diagnostics.

---

## 3. Model Review

**File:** `test/router_table.tests.yaml`

### Issue 3.1 — Only one test case defined

**Original:**
```yaml
tests:
  - name: Add_To_Table
    description: This unit test adds registration elements to the router table and asserts for correct table size and searching
```

**Explanation:**
A single monolithic test case covers add, duplicate rejection, table-full, lookup, not-found, and clear — all in one procedure. While this is functional, the YAML model should declare logically distinct test cases so that failures are isolated and identifiable in CI reports. A failure mid-way through `Add_To_Table` gives no granularity on *which* capability regressed.

**Severity:** **Medium** — Impacts defect localization and regression analysis.

---

## 4. Unit Test Review

**File:** `test/router_table_tests-implementation.adb`

### Issue 4.1 — Missing test: lookup and add behavior after `Clear`

**Location:** `Add_To_Table`, after the `Clear` block (end of procedure)

**Original code:**
```ada
-- Clear table:
Self.Table.Clear;
Natural_Assert.Eq (Self.Table.Get_Size, 0);
Natural_Assert.Eq (Self.Table.Get_Capacity, 3);
-- (procedure ends)
```

**Explanation:**
The test verifies that `Clear` resets the size and preserves capacity, but never verifies that:
1. A lookup after `Clear` returns `Id_Not_Found` for previously-added entries.
2. Entries can be re-added after `Clear` without error.

This is a significant gap for a safety-critical data structure — `Clear` could corrupt internal state in a way that only manifests on subsequent operations.

**Suggested addition:**
```ada
-- Verify lookup fails after clear:
Lookup_Assert.Eq (Self.Table.Lookup_Registration_Id (0, Ignore), Router_Table.Id_Not_Found);

-- Verify re-add works after clear:
Status_Assert.Eq (Self.Table.Add ((Registration_Id => 5, Command_Id => 42)), Router_Table.Success);
Natural_Assert.Eq (Self.Table.Get_Size, 1);
Lookup_Assert.Eq (Self.Table.Lookup_Registration_Id (42, Registration_Id), Router_Table.Success);
Registration_Assert.Eq (Registration_Id, 5);
```

**Severity:** **High** — Missing post-`Clear` behavioral verification for a data structure used in command routing.

---

### Issue 4.2 — No test for boundary condition: table size of 1

**Location:** `test/router_table_tests-implementation.adb` (missing test)

**Explanation:**
The test fixture allocates a table of size 3. A table of size 1 is a valid boundary case that exercises the binary tree's minimum allocation, single-element search, and immediate full condition. Off-by-one errors in the underlying sorted array are most likely to manifest at boundary sizes.

**Suggested test:**
```ada
procedure Single_Entry_Table (Self : in out Instance) is
   Tbl : Router_Table.Instance;
   Reg_Id : Command_Types.Command_Registration_Id;
begin
   Tbl.Init (1);
   Status_Assert.Eq (Tbl.Add ((Registration_Id => 7, Command_Id => 99)), Router_Table.Success);
   Status_Assert.Eq (Tbl.Add ((Registration_Id => 8, Command_Id => 100)), Router_Table.Table_Full);
   Lookup_Assert.Eq (Tbl.Lookup_Registration_Id (99, Reg_Id), Router_Table.Success);
   Registration_Assert.Eq (Reg_Id, 7);
   Tbl.Destroy;
end Single_Entry_Table;
```

**Severity:** **Medium** — Missing boundary test for minimum table size.

---

### Issue 4.3 — `Registration_Id` out-parameter not checked on `Id_Not_Found` paths

**Location:** `Add_To_Table`, the three `Id_Not_Found` lookups

**Original code:**
```ada
Lookup_Assert.Eq (Self.Table.Lookup_Registration_Id (96, Ignore), Router_Table.Id_Not_Found);
```

**Explanation:**
The test uses `Ignore` for the out parameter on failed lookups, discarding the value. The implementation deliberately sets it to `Command_Registration_Id'Last` — but no test verifies this. If the sentinel assignment is relied upon by callers (or if it is documented as a contract), it should be tested.

**Suggested addition:**
```ada
Lookup_Assert.Eq (Self.Table.Lookup_Registration_Id (96, Registration_Id), Router_Table.Id_Not_Found);
Registration_Assert.Eq (Registration_Id, Command_Types.Command_Registration_Id'Last);
```

**Severity:** **Low** — The sentinel is a defensive measure, but if it exists, it should be tested.

---

## 5. Summary — Top 5 Issues

| # | ID | Severity | Summary |
|---|-----|----------|---------|
| 1 | 4.1 | **High** | No test verifies lookup or re-add behavior after `Clear` |
| 2 | 2.1 | **Medium** | Failed-lookup sentinel (`'Last`) is indistinguishable from a valid ID |
| 3 | 3.1 | **Medium** | Single monolithic test case; no granularity in test model |
| 4 | 4.2 | **Medium** | No boundary test for minimum table size (1) |
| 5 | 4.3 | **Low** | Sentinel value on failed lookup is not verified by tests |

**Overall Assessment:** The package is well-structured and the implementation is correct for its intended use. The primary concerns are test coverage gaps — particularly the absence of post-`Clear` behavioral verification (Issue 4.1), which is significant for a command-routing data structure in flight software. The implementation itself has no functional defects; the sentinel value concern (Issue 2.1) is a defensive-coding observation rather than a bug.

## Resolution Notes

| # | Issue | Severity | Status | Commit | Notes |
|---|-------|----------|--------|--------|-------|
| 1 | Missing post-Clear test coverage | High | Fixed | 78b8a75 | Added lookup/re-add verification after Clear |
| 2 | Sentinel value ambiguity | Medium | Fixed | 02bc38a | Added defensive documentation |
| 3 | No boundary test for table size 1 | Medium | Fixed | 142c453 | Added Single_Entry_Table test case |
| 4 | Single monolithic test | Medium | Fixed | e27f73b | Implemented boundary test |
| 5 | Sentinel value untested | Low | Fixed | 30bbb48 | Verify sentinel equals 'Last |
| 6 | No precondition checks | Low | Fixed | 583b72b | Added pragma Assert on public subprograms |

# Apid_Tree Package — Code Review

## 1. Package Specification Review

### Spec-01 — Misleading Comments on Public Functions / **Low** / **apid_tree.ads:24-26**

**Original Code:**
```ada
-- Function to fetch the event range. This helps keep the component in sync with the package
function Filter_Packet ...
-- Function to get the pointer for the array. This is so that we can quickly copy the whole thing into the state packet
function Set_Filter_Factor ...
```

**Issue:** The comments are copy-paste artifacts and do not describe the actual functions. `Filter_Packet` does not "fetch the event range" and `Set_Filter_Factor` does not "get the pointer for the array."

**Proposed Fix:** Replace with accurate descriptions:
```ada
-- Determine whether to pass or filter a packet with the given APID, incrementing internal counters.
function Filter_Packet ...
-- Update the filter factor for a given APID in the tree, resetting its filter count.
function Set_Filter_Factor ...
```

---

## 2. Package Implementation Review

### Impl-01 — `pragma Assert` for Duplicate APID Detection Is Suppressible / **High** / **apid_tree.adb:26-29**

**Original Code:**
```ada
pragma Assert (not Search_Status, "Downsampler tree cannot add multiple nodes of the same APID.");
...
pragma Assert (Add_Status, "Downsampler tree too small to hold all APIDs in the input list.");
```

**Issue:** `pragma Assert` is suppressed when assertions are disabled (e.g., production builds with `-gnatp` or `pragma Suppress (All_Checks)`). Duplicate APIDs or an overfull tree would silently corrupt state. These are precondition violations on untrusted input (the configuration list), not debug-only checks.

**Proposed Fix:** Replace with explicit `if` checks that raise a descriptive exception unconditionally:
```ada
if Search_Status then
   raise Constraint_Error with "Downsampler tree cannot add multiple nodes of the same APID.";
end if;
...
if not Add_Status then
   raise Constraint_Error with "Downsampler tree too small to hold all APIDs in the input list.";
end if;
```

### Impl-02 — `Num_Passed_Packets` / `Num_Filtered_Packets` Unsigned_16 Overflow / **Medium** / **apid_tree.adb:40,46,54,59**

**Original Code:**
```ada
Self.Num_Passed_Packets := @ + 1;
Self.Num_Filtered_Packets := @ + 1;
```

**Issue:** These are `Unsigned_16` (modular type, wraps at 65535→0). After 65536 calls the counters silently wrap to zero, producing misleading telemetry. If the counters are used for anything beyond display (e.g., sequencing or anomaly detection), wrap-around could cause incorrect behavior. The counters are never reset.

**Proposed Fix:** If wrap-around is intentional, add a comment documenting that. If not, either use a wider type (`Unsigned_32`) or add saturation logic.

### Impl-03 — `Filter_Count` Unsigned_16 Overflow Breaks Filtering Logic / **High** / **apid_tree.adb:51-60**

**Original Code:**
```ada
if (Fetched_Entry.Filter_Count mod Fetched_Entry.Filter_Factor) = 0 then
...
Fetched_Entry.Filter_Count := @ + 1;
```

**Issue:** `Filter_Count` is `Unsigned_16` (modular). When it wraps from 65535 to 0, `0 mod Filter_Factor = 0` causes an extra Pass event at the wrap boundary. For a filter factor that does not evenly divide 65536, the wrap resets the modular cycle, producing an irregular pass/filter pattern around the boundary. This is a subtle long-duration correctness bug.

**Proposed Fix:** Use `mod Filter_Factor` arithmetic directly on `Filter_Count` so it stays bounded:
```ada
Fetched_Entry.Filter_Count := (@ + 1) mod Fetched_Entry.Filter_Factor;
```
This keeps `Filter_Count` in range `[0, Filter_Factor-1]` and eliminates the overflow concern entirely. Alternatively, use a wider type.

### Impl-04 — Package Is Explicitly "Unprotected" — No Thread Safety / **Low** / **apid_tree.ads:1**

**Original Code:**
```ada
-- This is a somewhat generic, unprotected binary tree ...
```

**Issue:** The spec comment acknowledges no thread safety, which is fine if the caller (the component) serializes access. This is noted for awareness — the component using this package must ensure single-threaded access or wrap calls in a protected object.

**Proposed Fix:** No code change needed; the comment is adequate. Consider adding a `-- Not task-safe.` note on the `Instance` type declaration for clarity.

---

## 3. Model Review

No YAML models to review. The `apid_tree.tests.yaml` is a test descriptor, not a data model.

---

## 4. Unit Test Review

### Test-01 — No Test for `Filter_Count` Overflow / Wrap-Around Behavior / **High** / **apid_tree_tests-implementation.adb (all tests)**

**Issue:** No test exercises the behavior when `Filter_Count` reaches `Unsigned_16'Last` (65535) and wraps to 0. This is the scenario described in Impl-03 and is the highest-risk untested path. A test should call `Filter_Packet` at least 65536 times for a single APID and verify correct pass/filter behavior across the boundary.

**Proposed Fix:** Add a dedicated test:
```ada
overriding procedure Test_Filter_Count_Overflow (Self : in out Instance);
```
that loops 65536+ times and checks the pass/filter pattern remains correct.

### Test-02 — No Test for `Num_Passed_Packets` / `Num_Filtered_Packets` Overflow / **Medium** / **apid_tree_tests-implementation.adb (all tests)**

**Issue:** The global pass/filter counters are never tested near their wrap-around boundary. The `Test_Get_Counters` test only exercises small counter values.

**Proposed Fix:** Add a test (or extend `Test_Get_Counters`) that drives counters to near-overflow and verifies expected behavior.

### Test-03 — No Test for Empty Init List / **Low** / **apid_tree_tests-implementation.adb**

**Issue:** No test initializes the tree with an empty list (`Downsample_List'Length = 0`). This would verify the tree handles the degenerate case gracefully — all APIDs should return `Invalid_Id`.

**Proposed Fix:** Add a test with an empty init list and verify `Filter_Packet` returns `Invalid_Id` for any APID.

### Test-04 — No Test for Single-Element Init List / **Low** / **apid_tree_tests-implementation.adb**

**Issue:** All tests use 3-4 element lists. A single-element list is a boundary case for the binary tree.

**Proposed Fix:** Add a test with a single-element init list.

---

## 5. Summary — Top 5 Highest-Severity Findings

| # | ID | Severity | Title |
|---|------|----------|-------|
| 1 | Impl-03 | **High** | `Filter_Count` Unsigned_16 wrap-around silently corrupts the pass/filter modular cycle after 65536 packets for a single APID |
| 2 | Impl-01 | **High** | `pragma Assert` for duplicate-APID and tree-full checks can be suppressed in production builds |
| 3 | Test-01 | **High** | No test exercises `Filter_Count` overflow/wrap-around behavior |
| 4 | Impl-02 | **Medium** | Global pass/filter counters wrap at Unsigned_16'Last with no documentation or mitigation |
| 5 | Test-02 | **Medium** | No test exercises global counter overflow behavior |

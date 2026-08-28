# CCSDS Downsampler — Component Code Review

**Reviewer:** Automated (Claude)
**Date:** 2026-02-28
**Component:** `src/components/ccsds_downsampler`

---

## 1. Documentation Review

### 1.1 — Component Description Quality
**Severity:** Low
**Location:** `ccsds_downsampler.component.yaml`, description field
**Issue:** The description is a single run-on paragraph. The phrase "adding them to a binary tree with the filter factor" is grammatically awkward. "less than a couple hundred" is vague for a sizing recommendation.
**Proposed Fix:** Break into shorter sentences. Provide a concrete upper-bound recommendation (e.g., "fewer than 200 entries") rather than "a couple hundred."

### 1.2 — Event Name Inconsistency
**Severity:** Low
**Location:** `ccsds_downsampler.events.yaml` — `Modified_Factor_Filter`
**Original Code:** `name: Modified_Factor_Filter`
**Issue:** The command is `Modify_Filter_Factor` but the success event reverses the word order to `Modified_Factor_Filter`. The failure event uses `Factor_Filter_Change_Failed_Invalid_Apid`. The naming is inconsistent and confusing. "Factor Filter" vs "Filter Factor" throughout.
**Proposed Fix:** Rename event to `Filter_Factor_Modified` (or `Modify_Filter_Factor_Success`) and `Filter_Factor_Change_Failed_Invalid_Apid` for consistency with the command name and the field name `Filter_Factor`.

### 1.3 — Generator Documentation Refers to "Data Products" in Filter List Description
**Severity:** Low
**Location:** `test/test_assembly/test_downsample_list.ccsds_downsampler_filters.yaml` line 2
**Original Code:** `description: Data products for the ccsds downsampler component.`
**Issue:** This description is copy-pasted from the data products YAML. It should describe the downsampler filter list, not data products.
**Proposed Fix:** Change to something like: `description: Downsampled packet filter list for the CCSDS downsampler unit test.`

---

## 2. Model Review

### 2.1 — Python Model Error Messages Will Raise TypeError
**Severity:** Medium
**Location:** `gen/models/ccsds_downsampler_filters.py`, lines 11 and 18
**Original Code:**
```python
raise ModelException(
    "Downsampler List Apid larger than 11 bits: '" + self.apid + "'."
)
```
**Issue:** `self.apid` is an integer (from YAML). String concatenation with `+` on an integer raises `TypeError` in Python, so these validation error paths are broken. The same bug exists for `self.filter_factor`. The validation will crash with a confusing `TypeError` instead of a helpful `ModelException`.
**Proposed Fix:**
```python
raise ModelException(
    "Downsampler List Apid larger than 11 bits: '" + str(self.apid) + "'."
)
```
Or use f-strings: `f"Downsampler List Apid larger than 11 bits: '{self.apid}'."`. Apply to both error messages.

### 2.2 — Duplicate Detection Uses Mixed Key Types
**Severity:** Low
**Location:** `gen/models/ccsds_downsampler_filters.py`, lines 59-70
**Original Code:**
```python
if the_products.name not in self.filter_products:
    if the_products.apid not in self.filter_products:
        self.filter_products[the_products.apid] = the_products
```
**Issue:** The dictionary is keyed by `apid` (integer), but the first check tests `name` (string) against integer keys, which will never match. The name-duplicate check is therefore dead code and duplicate names will not be caught. Only the `apid` duplicate check is effective.
**Proposed Fix:** Either maintain a separate set for names, or key the dictionary by name instead. For example:
```python
seen_names = set()
for packet in self.data["downsampled_packets"]:
    the_products = filter_entry(packet)
    if the_products.name in seen_names:
        raise ModelException(...)
    if the_products.apid in self.filter_products:
        raise ModelException(...)
    seen_names.add(the_products.name)
    self.filter_products[the_products.apid] = the_products
```

### 2.3 — Template Generates Array Indexed from 0 but Type Uses `Data_Product_Id range <>`
**Severity:** Low
**Location:** `gen/templates/ccsds_downsampler_filters/name.ads`
**Original Code:** `{{ loop.index0 }} => (`
**Issue:** The generated array is indexed starting at 0 using `Data_Product_Id` which is presumably a natural/positive type. The `Ccsds_Downsample_Packet_List` type uses `Data_Product_Id range <>` for the index. This works but couples the filter list array indexing to data product ID semantics, which is conceptually confusing — the array index is not actually a data product ID.
**Proposed Fix:** Consider using `Natural range <>` or `Positive range <>` for the list index type unless the coupling to `Data_Product_Id` is intentional for data product offset calculations.

---

## 3. Component Implementation Review

### 3.1 — Unsigned_16 Counter Overflow (Passed/Filtered Counts)
**Severity:** High
**Location:** `apid_tree/apid_tree.adb` — `Num_Filtered_Packets` and `Num_Passed_Packets` fields
**Original Code:**
```ada
Self.Num_Passed_Packets := @ + 1;
...
Self.Num_Filtered_Packets := @ + 1;
```
**Issue:** Both counters are `Unsigned_16` and will silently wrap around to 0 after 65,535 packets. For a flight system processing telemetry, this threshold can be reached in minutes. The wrap-around causes the data product to report incorrect (lower) counts, and ground operators could misinterpret the telemetry. The same values are reported as data products (`Total_Packets_Filtered`, `Total_Packets_Passed`) so the telemetry will be misleading.
**Proposed Fix:** Either (a) use a wider type (e.g., `Unsigned_32` or `Unsigned_64`) for the counters and data products, or (b) implement saturation arithmetic that clamps at `Unsigned_16'Last`, or (c) document the rollover behavior as intentional and add a rollover event.

### 3.2 — Filter_Count Overflow Changes Filtering Behavior
**Severity:** High
**Location:** `apid_tree/apid_tree.adb`, `Filter_Packet` function, line `Fetched_Entry.Filter_Count := @ + 1;`
**Original Code:**
```ada
if (Fetched_Entry.Filter_Count mod Fetched_Entry.Filter_Factor) = 0 then
   -- Pass
...
Fetched_Entry.Filter_Count := @ + 1;
```
**Issue:** `Filter_Count` is `Unsigned_16`. When it wraps from 65,535 to 0, `0 mod N = 0` causes an extra packet to pass through the filter. For a filter factor of 3, the normal cadence is pass-filter-filter-pass-filter-filter-..., but at the wrap boundary it becomes pass-filter-filter-...-pass-**pass**-filter-filter, creating an anomalous double-pass. For safety-critical downsampling (e.g., bandwidth-constrained downlinks), this is a silent behavioral change.
**Proposed Fix:** Reset `Filter_Count` to 0 when it reaches `Filter_Factor` (use modular counting: `Filter_Count := (Filter_Count + 1) mod Filter_Factor`) to prevent unbounded growth. Or use a wider type.

### 3.3 — Data Product ID Calculation Depends on Binary Tree Insertion Order
**Severity:** Medium
**Location:** `component-ccsds_downsampler-implementation.adb`, `Send_Filter_Data_Product`
**Original Code:**
```ada
Dp_Id := Self.Data_Products.Get_Id_Base + Data_Product_Id (Tree_Index - 1) + Data_Product_Id (Ccsds_Downsampler_Data_Products.Num_Data_Products);
```
**Issue:** This assumes `Tree_Index` (the position in the binary tree's internal array) corresponds to the data product ID offset. The data products are generated in YAML-order by `downsampler_data_products.py`, and the binary tree indices depend on insertion order (which happens to be YAML-order via the generated array). However, this is an implicit and fragile coupling — if the `Binary_Tree` implementation changes its storage strategy (e.g., self-balancing), or if the init list is reordered at runtime, the data product IDs will be wrong, publishing filter factor values under the wrong APID's data product.
**Proposed Fix:** Store an explicit mapping from tree index to data product ID offset, or store the data product index in the tree entry itself.

### 3.4 — Redundant `null;` Statement
**Severity:** Informational
**Location:** `component-ccsds_downsampler-implementation.adb`, `Invalid_Command` procedure
**Original Code:**
```ada
      Self.Event_T_Send_If_Connected (...);
      null;
   end Invalid_Command;
```
**Issue:** The `null;` after the event send is dead code.
**Proposed Fix:** Remove the `null;` statement.

### 3.5 — Protected Object Calls Get_Tree_Entry Outside Protection for Data Product Send
**Severity:** Medium
**Location:** `component-ccsds_downsampler-implementation.adb`, `Modify_Filter_Factor`
**Original Code:**
```ada
Self.Apid_Entries.Set_Filter_Factor (Arg.Apid, Arg.Filter_Factor, Index, Status);
...
Self.Send_Filter_Data_Product (Self.Apid_Entries.Get_Tree_Entry (Index), Index);
```
**Issue:** `Set_Filter_Factor` and `Get_Tree_Entry` are separate protected calls. Between them, another task could call `Filter_Packet` and modify the entry's `Filter_Count`. The data product would then report a stale or inconsistent snapshot. While the component is `passive` (no task), if it's invoked from multiple tasks via `recv_sync`, the protected object protects individual calls but not the sequence. The `Set_Filter_Factor` resets `Filter_Count` to 0, but by the time `Get_Tree_Entry` executes, another caller could have incremented it.
**Proposed Fix:** Add a protected procedure that atomically sets the filter factor and returns the updated entry, or accept the minor race as documented behavior.

---

## 4. Unit Test Review

### 4.1 — No Test for Counter Overflow/Wraparound
**Severity:** Medium
**Location:** `apid_tree/test/apid_tree_tests-implementation.adb` and `test/ccsds_downsampler_tests-implementation.adb`
**Issue:** No unit test exercises the behavior when `Num_Passed_Packets`, `Num_Filtered_Packets`, or `Filter_Count` reach `Unsigned_16'Last` (65,535). Given the severity of findings 3.1 and 3.2, a test that demonstrates and verifies the expected overflow behavior is essential.
**Proposed Fix:** Add a test that sends enough packets to overflow at least `Filter_Count` for a specific APID (can set count close to max via repeated filtering or by exposing a test hook), and verify the behavior at the boundary.

### 4.2 — No Test for Filter Factor of `Unsigned_16'Last` (65535)
**Severity:** Low
**Location:** `test/ccsds_downsampler_tests-implementation.adb`
**Issue:** The tests cover filter factors of 0, 1, 2, 3, 4, 5 but never test extreme values like 65535. A filter factor of 65535 means only 1 in every 65535 packets passes — this is a valid operational scenario that should be verified.
**Proposed Fix:** Add a test case with `Filter_Factor => 65535` and verify only the first packet passes, the next 65534 are filtered, then one passes again.

### 4.3 — Tester Dispatch_Data_Product Discards Dynamic DP Identity
**Severity:** Low
**Location:** `test/component-ccsds_downsampler-implementation-tester.adb`, `Dispatch_Data_Product`
**Original Code:**
```ada
overriding procedure Dispatch_Data_Product (Self : in out Instance; Dp : in Data_Product.T) is
   Dispatch_To : constant Dispatch_Data_Product_Procedure := Data_Product_Id_Table (Ccsds_Downsampler_Data_Products.Local_Data_Product_Id_Type'First);
begin
   Dispatch_To (Component.Ccsds_Downsampler_Reciprocal.Base_Instance (Self), Dp);
end Dispatch_Data_Product;
```
**Issue:** All data products (including dynamically-generated per-APID filter factor DPs) are dispatched to the handler for the *first* static data product ID. This means the per-APID data products are not individually validated through typed history packages. The test only validates them via raw `Data_Product_T_Recv_Sync_History` byte comparison. While functional, this means type-specific assertion (via `Total_Packets_Filtered_History` / `Total_Packets_Passed_History`) is not exercised for dynamic DPs. This is a reasonable workaround but limits test specificity.
**Proposed Fix:** Acceptable as-is given the dynamic nature, but consider adding explicit assertions on the dynamic DP content via deserialization in the test body.

### 4.4 — Tests Don't Verify Event Payloads for Success Cases
**Severity:** Low
**Location:** `test/ccsds_downsampler_tests-implementation.adb`, `Test_Modify_Filter_Factor`
**Original Code:**
```ada
Natural_Assert.Eq (T.Modified_Factor_Filter_History.Get_Count, 1);
```
**Issue:** The test checks that the `Modified_Factor_Filter` event was emitted (count check) but never asserts the event *payload* (the `Filter_Factor_Cmd_Type.T` value). A bug that emits the wrong APID or filter factor in the event would go undetected.
**Proposed Fix:** Add payload assertions, e.g.:
```ada
Filter_Factor_Cmd_Type_Assert.Eq (T.Modified_Factor_Filter_History.Get (1), (Apid => 100, Filter_Factor => 1));
```

---

## 5. Summary — Top 5 Highest-Severity Findings

| # | Severity | Finding | Location |
|---|----------|---------|----------|
| 1 | **High** | `Filter_Count` overflow (Unsigned_16) silently causes an extra packet to pass through the filter at the 65,535 boundary, breaking the downsampling cadence | `apid_tree.adb`, `Filter_Packet` (§3.2) |
| 2 | **High** | `Num_Passed_Packets` / `Num_Filtered_Packets` counters (Unsigned_16) wrap to 0, causing telemetry data products to report incorrect values | `apid_tree.adb` / `apid_tree.ads` (§3.1) |
| 3 | **Medium** | Data product ID calculation implicitly depends on binary tree internal array ordering matching YAML-order; fragile coupling that breaks if tree implementation changes | `component-ccsds_downsampler-implementation.adb`, `Send_Filter_Data_Product` (§3.3) |
| 4 | **Medium** | Python model error messages use string concatenation on integers, causing `TypeError` instead of helpful `ModelException` when validation fails | `gen/models/ccsds_downsampler_filters.py` (§2.1) |
| 5 | **Medium** | No unit tests for counter overflow behavior, leaving the two highest-severity issues completely unvalidated | Tests (§4.1) |

---

## Resolution Notes

| # | Issue | Severity | Status | Commit | Notes |
|---|-------|----------|--------|--------|-------|
| 1.1 | Component Description Quality | Low | Fixed | `2141925` | |
| 1.2 | Event Name Inconsistency | Low | Fixed | `95a428f` | |
| 1.3 | Generator Documentation Refers to "Data Products" | Low | Fixed | `b1fc95c` | |
| 2.1 | Python Model TypeError in Validation | Medium | Fixed | `8bacc8d` | |
| 2.2 | Duplicate Detection Uses Mixed Key Types | Low | Fixed | `78a215c` | |
| 2.3 | Array Index Type Semantics | Low | Fixed | `770254f` | |
| 3.1 | Counter Overflow Saturation (Unsigned_16) | High | Fixed | `d761187` | |
| 3.2 | Filter_Count Overflow Causes Double-Pass | High | Fixed | `f2368f5` | |
| 3.3 | Fragile DP ID Coupling to Tree Index | Medium | Fixed | `d8a01c8` | |
| 3.4 | Redundant null Statement | Informational | Fixed | `0157b94` | |
| 3.5 | Protected Object Race in Modify_Filter_Factor | Medium | Fixed | `fc0fc01` | |
| 4.1 | No Test for Counter Overflow | Medium | Fixed | `05a7015` | |
| 4.2 | No Test for Extreme Filter Factor 65535 | Low | Fixed | `66d6378` | |
| 4.3 | Tester Dispatch_Data_Product Discards Dynamic DP Identity | Low | Fixed | `ec6fb02` | |
| 4.4 | Tests Don't Verify Event Payloads | Low | Fixed | `beb0fd9` | |

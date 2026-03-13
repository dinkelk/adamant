# CCSDS Router Component — Code Review

**Reviewer:** Automated Expert Review  
**Date:** 2026-02-28  
**Component:** `src/components/ccsds_router`

---

## 1. Documentation Review

**Component YAML description:** Clear and thorough. Documents the routing purpose, binary search lookup, sync/async reception, the acknowledged race condition between sync and async paths, and the autocoder for table generation.

**Requirements (`ccsds_router.requirements.yaml`):** Three requirements are listed. They cover routing, sequence count warnings, and duplicate dropping. However:

- **DOC-1 (Info):** There is no explicit requirement covering the `Report_Unrecognized_APIDs` configuration parameter behavior (suppressing events/error packets for unrecognized APIDs). This feature is tested in `test_unrecognized_apid` but has no corresponding requirement.
- **DOC-2 (Info):** There is no requirement covering the forwarding of unrecognized-APID packets out the dedicated `Unrecognized_Ccsds_Space_Packet_T_Send` connector. The component description mentions it, but the requirements do not.
- **DOC-3 (Info):** The queue overflow / dropped packet behavior is not captured in requirements.

**Overall:** Documentation is good. The race condition between sync/async paths is honestly acknowledged. Minor gaps in requirements traceability noted above.

---

## 2. Model Review

**Component YAML (`ccsds_router.component.yaml`):**

- Connectors are well-defined. The variable-size arrayed output (`count: 0`) is appropriate for a router with configurable destinations.
- The `Unrecognized_Ccsds_Space_Packet_T_Send` connector is explicitly named, which is correct since it needs to be distinct from the arrayed send connector.
- Init parameters are clear with a sensible default for `Report_Unrecognized_APIDs`.

**Events YAML:** Four events covering unrecognized APID, dropped packet (queue overflow), unexpected sequence count, and dropped duplicate. Appropriate parameter types.

**Packets YAML:** Single error packet of type `Ccsds_Space_Packet.T`. Appropriate.

**Types (`ccsds_router_types.ads`):**

- **MODEL-1 (Low):** `Destination_Table_Access` is a general access type pointing to a mutable aliased array. This is standard in the Adamant framework for init-time configuration, but it means the caller must ensure the pointed-to data has appropriate lifetime. The access type is not `access constant`, so the component could theoretically modify the destination table through the pointer, though it does not. Making it `access constant` would be a minor safety improvement.

**Generator / Autocoder (`gen/`):**

- The model, generator, schema, and template are well-structured.
- The schema enforces at least one table entry (`min: 1`) and validates `sequence_check` enum values.
- The model correctly checks for duplicate APIDs and verifies that destination components actually exist in the assembly.
- **MODEL-2 (Info):** The `router_table_entry.__init__` has a mutable default argument (`destinations=[]`). This is a classic Python pitfall, though in this case the list is immediately copied via the list comprehension so it is benign.

---

## 3. Component Implementation Review

**File:** `component-ccsds_router-implementation.adb`

### Init Procedure

- Validates destination indexes are within the arrayed connector range — good defensive check.
- Checks for duplicate APIDs via search before insert — good.
- Uses `pragma Assert` for validation, which means checks are removed if assertions are disabled. This is the Adamant convention and is acceptable.

### Routing Logic (`Ccsds_Space_Packet_T_Recv_Sync`)

- Binary tree search by APID, then iterates destinations — correct.
- Sequence count checking and duplicate detection logic is clear.

### **IMPL-1 (Medium): Duplicate detection checks stale `Last_Sequence_Count` after `Warn_Sequence_Count` already updated it.**

In the `Drop_Dupes` case:

```ada
when Drop_Dupes =>
   -- Warn via event if unexpected sequence count found:
   Self.Warn_Sequence_Count (Table_Entry_Found, Found_Entry_Index, Arg.Header);
   -- Check for duplicate; report and drop if necessary:
   declare
      use Ccsds_Primary_Header;
      Last_Sequence_Count : ... renames Table_Entry_Found.Last_Sequence_Count;
   begin
      if Arg.Header.Sequence_Count = Last_Sequence_Count then
```

`Warn_Sequence_Count` updates `Last_Sequence_Count` in the binary tree via `Self.Table.Set(...)` **before** the duplicate check occurs. However, the duplicate check reads from `Table_Entry_Found` which is a **local copy** returned by `Search`, not the tree itself. So `Table_Entry_Found.Last_Sequence_Count` still holds the **old** value (the value before `Warn_Sequence_Count` was called).

**Effect:** The duplicate check compares the incoming sequence count against the *previous* packet's sequence count (the old `Last_Sequence_Count`), which is actually the correct semantic for detecting duplicates — "is this packet's sequence count identical to the last one we saw?" This works correctly **by accident** of the copy semantics: `Table_Entry_Found` is a snapshot taken before the update. If this were a reference/pointer instead of a copy, the logic would break. The code is fragile and its correctness depends on an implicit assumption about copy-vs-reference behavior that is not documented.

### **IMPL-2 (Low): First packet after init always triggers sequence count warning for `Warn` and `Drop_Dupes` modes.**

`Last_Sequence_Count` is initialized to `Ccsds_Sequence_Count_Type'Last`. For a 14-bit field this is 16383. The first packet received will almost certainly not have sequence count 0 (which is `Last + 1` mod wraparound), so `Warn_Sequence_Count` will fire an `Unexpected_Sequence_Count_Received` event on the very first packet.

Looking at the tests: `Test_Sequence_Count_Warning` sends the first packet with sequence count 1, and the expected sequence count is 0 (`Last + 1` wrapping), so the first packet indeed triggers a warning. The tests confirm this is **intentional** behavior. However, there is no comment in the implementation explaining this design choice, and for operational systems this initial spurious warning could be confusing.

### **IMPL-3 (Low): `Warn_Sequence_Count` unconditionally updates `Last_Sequence_Count` even when called from the `Drop_Dupes` path for a packet that will be dropped.**

When a duplicate is detected in `Drop_Dupes` mode, `Warn_Sequence_Count` has already been called and updated `Last_Sequence_Count` to the current (duplicate) sequence count. Since the duplicate has the same value, this update is idempotent and harmless. But if the logic were ever changed (e.g., to not update on duplicates), this ordering dependency could cause bugs.

### Async Handler

`Ccsds_Space_Packet_T_Recv_Async` simply delegates to the sync handler — clean and correct.

### Dropped Handlers

- `Ccsds_Space_Packet_T_Recv_Async_Dropped` properly reports the dropped packet with event and error packet.
- All outgoing send-side dropped handlers are `is null` — acceptable for a router that can't meaningfully handle downstream failures.

---

## 4. Unit Test Review

### Test Suite 1: `test/` (Unrecognized connector NOT connected)

**Test_Initialization:** Tests nominal init, out-of-range destination index (two variants), and duplicate APID. Good coverage of error paths via assertion exceptions.

**Test_Nominal_Routing:** Exercises all 8 APIDs in the table through both sync and async paths. Validates routing to correct output connector indexes using per-connector histories. Thorough.

**Test_Unrecognized_Id:** Tests packets with APID 0 and 9 (not in table) via sync and async. Verifies event and error packet generation. Note: since the `Unrecognized_Ccsds_Space_Packet_T_Send` connector is NOT connected in this test suite, the forwarding-to-unrecognized-connector behavior is NOT tested here (that's covered in the second suite).

**Test_Dropped_Packet:** Fills the async queue then sends one more to trigger overflow. Verifies the dropped packet event and error packet.

**Test_Sequence_Count_Warning:** Exercises `Warn` mode APIDs (3, 4, 5, 6, 7, 8) with non-sequential sequence counts. Validates event contents including expected vs. received sequence counts.

- **TEST-1 (Medium): `Warn` mode APIDs 4, 5, and 6 are tested for sequence count warnings but they are configured as `warn`, `drop_dupes`, and `drop_dupes` respectively in the routing table. The test exercises them all the same way (non-duplicate, non-sequential) which is fine for the warning aspect, but APID 7 (`no_check`) is also tested here — it is sent packets with non-sequential sequence counts and correctly produces no events. Good.**

**Test_Duplicate_Packet_Drop:** Tests `Drop_Dupes` mode (APIDs 5, 6) by sending packets with identical consecutive sequence counts. Verifies that duplicates are dropped (not routed) and that appropriate events/error packets are generated. Also tests that `Warn`-mode APID 3 does NOT drop duplicates (only warns). Good boundary testing.

### Test Suite 2: `test_unrecognized_apid/` (Unrecognized connector IS connected)

**Test_Unrecognized_Id:** Verifies that unrecognized packets are forwarded out the dedicated connector AND reported via event/error packet.

**Test_Unrecognized_Id_No_Report:** Verifies that with `Report_Unrecognized_APIDs => False`, packets are still forwarded but NO events or error packets are generated. Good coverage of the configuration flag.

### Test Gaps

- **TEST-2 (Medium): No test for sequence count wraparound.** The 14-bit sequence count field wraps from 16383 to 0. No test verifies that a packet with sequence count 0 following one with sequence count 16383 is treated as the expected next value (no warning). This is an important edge case for long-duration missions.
- **TEST-3 (Low): No test for an APID with `Destinations => null` (empty destination list) when the APID IS in the table.** APID 8 with `ignore` destination exercises this in practice via the autocoder, but the unit test doesn't verify that the packet is silently consumed without routing (it only checks sequence count warnings for APID 8). The routing check (`Check_Routing` showing no change on connectors) implicitly covers this.
- **TEST-4 (Low): No test for concurrent sync+async packet reception** for the same APID with sequence count checking. The implementation's documented race condition is never exercised. While this is acknowledged as unlikely, a test demonstrating the potential corruption would serve as useful documentation.
- **TEST-5 (Info): Test packets are declared as mutable package-level variables** with `Header.Sequence_Count` being modified in-place across tests. Since `Set_Up_Test`/`Tear_Down_Test` reinitializes the component for each test, and tests run sequentially, this is safe. But it makes the tests order-dependent in a subtle way (each test assumes specific initial values for the mutable packets).

---

## 5. Summary — Top 5 Highest-Severity Findings

| # | ID | Severity | Description |
|---|-----|----------|-------------|
| 1 | IMPL-1 | **Medium** | Duplicate detection in `Drop_Dupes` mode relies on copy semantics of `Table_Entry_Found` being a snapshot before `Warn_Sequence_Count` updates the tree. Correctness is accidental and fragile — a refactor to reference semantics would silently break duplicate detection. Recommend reordering: check for duplicate BEFORE calling `Warn_Sequence_Count`, or add a clear comment documenting the dependency. |
| 2 | TEST-2 | **Medium** | No test for sequence count wraparound (16383 → 0). This is a critical edge case for CCSDS systems in long-duration missions where sequence counters will naturally wrap. |
| 3 | TEST-1 | **Medium** | Test coverage for `Drop_Dupes` mode only exercises identical consecutive duplicates. No test for the boundary where a legitimate retransmission occurs after an intervening packet (seq A, seq B, seq A — should this warn but not drop?). Current implementation correctly only drops consecutive duplicates, but this isn't explicitly tested. |
| 4 | IMPL-2 | **Low** | First packet after initialization always triggers a spurious `Unexpected_Sequence_Count_Received` event for `Warn` and `Drop_Dupes` mode APIDs. This is by design but undocumented in the implementation. Consider adding a comment or initializing `Last_Sequence_Count` to `first_received - 1` on first reception. |
| 5 | MODEL-1 | **Low** | `Destination_Table_Access` is `access all` (mutable) rather than `access constant`. While the component never writes through this pointer, `access constant` would provide compile-time enforcement of immutability. |

## Resolution Notes

| # | Issue | Severity | Status | Commit | Notes |
|---|-------|----------|--------|--------|-------|
| 1 | Fragile duplicate detection ordering (IMPL-1) | Medium | Fixed | 8139c7c | Reordered to capture flag before update |
| 2 | No sequence count wraparound test (TEST-2) | Medium | Fixed | ff622d2 | Added wraparound test |
| 3 | No non-consecutive duplicate test (TEST-1) | Medium | Fixed | 95d578c | Added A,B,A pattern test |
| 4 | First-packet spurious warning (IMPL-2) | Low | Fixed | 6c98c10 | Added documenting comment |
| 5 | Idempotent update ordering (IMPL-3) | Low | Fixed | f404462 | Added documenting comment |
| 6 | Destination_Table_Access mutability (MODEL-1) | Low | Fixed | 71c6128 | Changed to access constant |
| 7 | Null destination routing test (TEST-3) | Low | Fixed | 84ecbf0 | Added test case |
| 8 | Concurrent test (TEST-4) | Low | Not Fixed | 41a2666 | Requires tasking infrastructure |
| 9 | Mutable default argument (MODEL-2) | Info | Fixed | 87886e4 | Fixed Python mutable default |
| 10-13 | DOC/TEST items | Info | Not Fixed | — | Process coordination / acceptable as-is |

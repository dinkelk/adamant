# Sequence Store Component - Code Review

**Reviewer:** Automated Code Review  
**Date:** 2026-03-01  
**Component:** `src/components/sequence_store`  
**Verdict:** Generally well-engineered with a few notable concerns

---

## 1. Documentation Review

The component is well-documented. The `sequence_store.component.yaml` provides a clear description of purpose, connectors, and initialization parameters. Events and commands YAML files have meaningful descriptions. The `sequence_store.requirements.yaml` captures key functional requirements.

**Findings:**

| # | Severity | Finding |
|---|----------|---------|
| D1 | Low | Command description in the `.ads` spec says _"These are the commands for the **Parameter** Store component"_ (line in `Command_T_Recv_Async` region and command handler region). Should read "Sequence Store". This is a copy-paste artifact from another component. |
| D2 | Low | Requirements are high-level and lack traceability IDs. No requirement covers the activate/deactivate functionality or the duplicate-ID rejection behavior, which are core safety features. |

---

## 2. Model Review

The YAML models (records, enums, component definition) are clean and consistent. The 32-bit and 64-bit type variants are properly separated. The `Slot_Valid_Type` enum wisely includes an `Undefined` value (value 3) to handle corrupted 2-bit MRAM fields — good defensive design.

**Findings:**

| # | Severity | Finding |
|---|----------|---------|
| M1 | Low | `Slot_Number` type range is `0 .. 65_535` but `Packed_Slot_Number` uses `U16` format. This is consistent, but the component uses `pragma Assert` to enforce zero-indexing at init. If a deployment ever uses a non-zero-indexed array, the assert fires at runtime rather than being caught at compile time. This is acceptable given the framework's design. |

---

## 3. Component Implementation Review

### 3.1 Protected Object (`Protected_Sequence_Lookup_B_Tree`)

The protected object correctly provides mutual exclusion between the async store path and the synchronous fetch service connector. The `Find_Sequence` function (not procedure) correctly uses a function barrier, allowing concurrent reads when no writer is active — good design for a service connector.

### 3.2 Sequence Store Write Path

**Findings:**

| # | Severity | Finding |
|---|----------|---------|
| I1 | **Medium** | **Validity marked before copy completes.** In `Sequence_Store_Memory_Region_Store_T_Recv_Async`, the slot header's validity is set to `Valid` *before* the actual sequence data is copied into the slot (`Slot_Bytes (0 .. Sequence_Size - 1) := Sequence_Bytes`). If the system resets or power is lost between the header write and the data copy, the slot will appear valid in MRAM but contain incomplete data. The header validity should be written *after* the data copy to maintain consistency. In NV storage contexts, this ordering matters for fault tolerance. |
| I2 | **Medium** | **Fetch returns `Length` from potentially corrupted MRAM header.** `Get_Sequence_Memory_Region` reads `Slot_Header.Seq_Header.Length` directly from the memory-mapped slot to form the returned `Memory_Region.T`. If MRAM is corrupted and `Length` is larger than the actual slot, the returned memory region could point beyond the slot boundary. A fetching component that trusts this length could read/execute out-of-bounds data. Consider clamping the returned length to `min(Seq_Header.Length, Slot.Length - Num_Slot_Meta_Bytes)`. |
| I3 | **Low** | **No event emitted for duplicate ID deactivation at startup.** During `Init`, when a duplicate active sequence ID is found, the slot is silently deactivated. No event is emitted (events may not be connected at init time). This is understandable given lifecycle constraints, but the comment acknowledges it's an anomalous condition. Consider logging this in `Set_Up` if the condition was detected. |
| I4 | **Low** | **`Dropped` handler null bodies for send connectors.** `Command_Response_T_Send_Dropped`, `Sequence_Store_Memory_Region_Release_T_Send_Dropped`, `Packet_T_Send_Dropped`, and `Event_T_Send_Dropped` are all null. If the release connector is full and the release is dropped, the upstream component will never know its memory region can be reclaimed — a potential resource leak. This is likely acceptable given system design (these are typically synchronous or large-queued), but worth noting. |
| I5 | **Low** | **O(n²) overlap check in Init.** The overlap check iterates all pairs, comparing each pair twice (once as (A,B) and once as (B,A)). For typical small slot counts this is fine, but could be halved by starting the inner loop at `Idx + 1`. Minor efficiency concern only. |

### 3.3 Activate/Deactivate Logic

The activate path correctly prevents duplicate active sequence IDs via the B-tree. The deactivate path intentionally ignores `Remove_Sequence` failure status, which is safe since the goal is removal regardless.

### 3.4 Concurrency

The `Sequence_Store_Memory_Region_Fetch_T_Service` connector is a service (synchronous call from another task). It accesses `Active_Sequence_List.Find_Sequence` (protected function) and then calls `Get_Sequence_Memory_Region` which reads from the slot memory. The store path writes to slot memory in `Sequence_Store_Memory_Region_Store_T_Recv_Async`. Since a slot must be inactive to be written and must be active to be fetched, these operations are mutually exclusive by design — **the concurrency model is sound**.

---

## 4. Unit Test Review

The test suite is thorough and covers:
- ✅ Initialization (nominal, empty, bad index, too small, overlapping, CRC check at startup, duplicate IDs)
- ✅ Dump summary packet contents
- ✅ Activate/deactivate nominal and failure paths (out-of-range, duplicate ID)
- ✅ Slot CRC checking (individual and all)
- ✅ Sequence write (nominal, invalid slot, active slot, CRC error, length error, region larger than sequence)
- ✅ Sequence fetch (active, inactive, not found, after activate/deactivate)
- ✅ Queue overflow handling
- ✅ Invalid command

**Findings:**

| # | Severity | Finding |
|---|----------|---------|
| T1 | **Medium** | **No test for concurrent fetch during store.** The service connector `Fetch` can be called from a different task while `Store` is executing. While the design prevents this (slot must be inactive for store, active for fetch), there is no test that exercises concurrent access to validate the protected object behavior under contention. |
| T2 | **Low** | **No test for `Check_Slots_At_Startup = True` with `Dump_Slot_Summary_At_Startup = True` via `Set_Up`.** The `Init_Check_Slots_At_Startup` sub-test calls `Init` but never calls `Set_Up` afterward, so the startup dump path after CRC checking is untested in combination. |
| T3 | **Low** | **Test assembly uses different init params than unit test fixture.** The test assembly YAML uses `Check_Slots_At_Startup => False` and `Dump_Slot_Summary_At_Startup => False`, while the unit test `Set_Up_Test` uses `Check_Slots_At_Startup => False` and `Dump_Slot_Summary_At_Startup => True`. Not a bug, but could cause confusion. |
| T4 | **Low** | **`Slot_4_Memory` and `Slot_5_Memory` declared in `Test_Slots` but `Slot_4_Memory` is never used.** `Slot_5_Memory` is used for the too-small test via `Slot_5_Header`, but `Slot_4_Memory` appears to be dead code. |

---

## 5. Summary — Top 5 Findings

| Rank | ID | Severity | Category | Finding |
|------|----|----------|----------|---------|
| 1 | I1 | **Medium** | Safety | Slot validity header written *before* data copy. Power loss between header write and data copy leaves MRAM in inconsistent state (slot marked Valid with incomplete data). |
| 2 | I2 | **Medium** | Safety | `Get_Sequence_Memory_Region` trusts MRAM `Length` field without bounds clamping. Corrupted length could cause out-of-bounds memory access by fetching component. |
| 3 | T1 | **Medium** | Testing | No concurrency test exercises the protected object under contention between fetch (service) and store/activate (async) paths. |
| 4 | D1 | **Low** | Documentation | Copy-paste error: command handler comments reference "Parameter Store" instead of "Sequence Store". |
| 5 | I4 | **Low** | Robustness | Null drop handlers on send connectors (especially `Memory_Region_Release`) could silently lose resource release notifications. |

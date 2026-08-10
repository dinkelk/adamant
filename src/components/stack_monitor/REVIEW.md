# Stack Monitor Component — Code Review

**Reviewer:** Automated (Claude)
**Date:** 2026-03-01
**Component:** `src/components/stack_monitor`

---

## 1. Documentation

| # | Severity | Finding |
|---|----------|---------|
| D1 | **Low** | `stack_monitor.data_products.yaml` description says "Data products for the **CPU Monitor** component" — copy-paste error; should say "Stack Monitor". |
| D2 | **Low** | Several test assertion comments say "Check the packet, make sure all zeros" even when non-zero values are expected (e.g., after filling stacks to 63%, 90%, 100%). Misleading for maintainers. |
| D3 | **Low** | The LaTeX document (`doc/stack_monitor.tex`) is a thin shell referencing `build/tex/` includes — fine structurally, but no prose design rationale is provided beyond the auto-generated description. |

---

## 2. Model (YAML Definitions)

| # | Severity | Finding |
|---|----------|---------|
| M1 | **Low** | `stack_monitor.stack_monitor_packets.yaml` declares the `Stack_Usage_Packet` with no explicit type field; the type is injected at assembly time by the custom `stack_monitor_packets` Python model. This is correct but undocumented — a comment in the YAML would help future maintainers. |
| M2 | **Low** | Only one command (`Set_Packet_Period`) exists. There is no command to force an immediate one-shot packet dump, which could be useful for diagnostics. Not a defect, but a capability gap. |

---

## 3. Implementation

| # | Severity | Finding |
|---|----------|---------|
| I1 | **Medium** | **Off-by-one in percentage calculation.** `Calculate_Stack_Percent_Usage` computes `(Stack_Bytes'Last - Index) * 100 / Stack_Bytes'Last`. For a 1000-byte stack (`'Last` = 999), if 999 bytes are used (`Index` = 0), the result is `(999 * 100) / 999 = 100` ✓. But if `Index` = `Stack_Bytes'Last` (fully clean), it returns `0 * 100 / 999 = 0` ✓. The denominator should arguably be `Stack_Bytes'Length` (= `Stack_Size`) rather than `Stack_Bytes'Last` (= `Stack_Size - 1`) for mathematical precision, though the error is ≤0.1% for stacks >100 bytes. Functionally benign but semantically imprecise. |
| I2 | **Medium** | **Backtrack search may read beyond valid cached index.** In `Calculate_Stack_Percent_Usage`, the search loop starts at `Stack_Index` and subtracts 100 repeatedly. If `Stack_Index` is near the top of the stack (close to `Stack_Bytes'Last`) — say a task shrunk its stack usage — the 21-byte forward scan (`Start_Index + 1..20`) could read into *used* stack space and falsely conclude a good start was found. In practice the pattern `0xCC` is unlikely to appear in 21 consecutive used bytes, but this is a probabilistic assumption, not a guarantee. |
| I3 | **Medium** | **Race condition on live stack reads.** The component reads a task's stack memory (overlaid `Stack_Bytes`) while the task is running. The task could be actively writing to its stack during the scan. Since this is a monitoring/diagnostic component and results are approximate percentages, this is acceptable in practice, but it's worth documenting the inherent TOCTOU nature. |
| I4 | **Low** | **`Stack_Indexes` cache only moves forward.** The cached index optimization assumes stack usage monotonically increases (stack grows). If a task's stack usage *decreases* between ticks (deep call returns), the cached index may point into used space, causing the backtrack loop to execute. This is handled correctly by the backtrack logic but means the cache provides no benefit in stack-shrinking scenarios. Functionally correct, just suboptimal. |
| I5 | **Low** | **`Final` only deallocates `Stack_Indexes` in testing mode** (via `Safe_Deallocator.Deallocate_If_Testing`). `Packet_To_Send` is stack-allocated in the instance record, so that's fine. The `Tasks` access is borrowed (not owned), so not freeing it is correct. No leak. |
| I6 | **Low** | **Counter increment after send.** `Tick_T_Recv_Sync` calls `Is_Count_At_Period` first, then `Increment_Count` at the end. This means the first tick always triggers a packet (count starts at period). This is intentional per the `Protected_Periodic_Counter` pattern but worth noting: the very first tick after init or period change always sends a packet immediately. |

---

## 4. Unit Tests

| # | Severity | Finding |
|---|----------|---------|
| T1 | **Medium** | **No test for `Null_Address` stack.** `Calculate_Stack_Percent_Usage` has a guard for `Task_Data.Stack_Address = System.Null_Address` returning 0, but no test exercises this branch. |
| T2 | **Medium** | **No test for `Set_Up` being called in normal flow.** `Test_Packet_Period` calls `Set_Up` explicitly, but `Test_Stack_Monitoring` never calls it. The initial data product update path is only partially tested. |
| T3 | **Low** | **No negative/boundary test for stack shrinkage.** Tests only grow stack usage monotonically. The backtrack logic in `Calculate_Stack_Percent_Usage` is never exercised by a scenario where stack usage decreases between ticks. |
| T4 | **Low** | **Test modifies `Task_Info` fields directly** (`Stack_Size`, `Secondary_Stack_Size`) after `Init`, which changes state the component cached during `Init` (specifically `Buffer_Length`). This works because `Buffer_Length` was set from the original `Task_List'Length` (count of tasks, not stack sizes), but it's fragile — if the implementation ever cached per-task stack sizes at init time, these tests would silently become invalid. |
| T5 | **Low** | **`Stack_Usage_Packet_History` is initialized but never checked** in any test. The packet dispatch presumably populates it, but no assertion validates it. |

---

## 5. Summary

The Stack Monitor component is **well-structured and functionally sound**. The architecture follows Adamant conventions cleanly: YAML model definitions, autocoded connectors, protected periodic counter for thread-safe period management, and a reasonable test suite.

**Key strengths:**
- Clean separation of primary vs. secondary stack monitoring
- Efficient cached-index optimization for stack scanning
- Proper defensive checks (null address, zero size, oversized usage)
- Good command/event/data-product integration

**Key concerns:**
- The `0xCC` pattern-matching approach for stack watermarking is inherently probabilistic (I2) — a task writing 21+ consecutive `0xCC` bytes could fool the monitor. This is a known limitation of watermark-based stack monitoring, not unique to this component.
- Missing test coverage for null-address stacks (T1) and stack shrinkage scenarios (T3)
- Copy-paste error in data products description (D1)

**Overall assessment:** Production-ready with minor documentation fixes and additional test cases recommended. No critical issues found.

| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 0 |
| Medium | 5 |
| Low | 10 |

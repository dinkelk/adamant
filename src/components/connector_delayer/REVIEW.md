# Connector Delayer — Code Review

**Component:** `src/components/connector_delayer`  
**Date:** 2026-02-28  
**Branch:** `review/components-connector-delayer`

---

## 1. Documentation Review

### DOC-01 — LaTeX includes sections that don't apply (Low)

**File:** `doc/connector_delayer.tex`, lines for Interrupts, Commands, Parameters, Data Products, Data Dependencies, Packets, Faults  
**Original code:**
```latex
\subsection{Interrupts}
\input{build/tex/connector_delayer_interrupts.tex}
...
\subsection{Commands}
\input{build/tex/connector_delayer_commands.tex}
...
\subsection{Faults}
\input{build/tex/connector_delayer_faults.tex}
```
**Explanation:** This component has no interrupts, commands, parameters, data products, data dependencies, packets, or faults. Including these sections produces empty or "N/A" sections that clutter the document and could confuse readers. Most other simple Adamant components omit inapplicable sections.  
**Suggested fix:** Remove subsections that are not relevant, or add a comment noting they are auto-generated boilerplate if that is the project convention.  
**Severity:** Low

### DOC-02 — Test descriptions don't mention the delay behavior (Low)

**File:** `connector_delayer.tests.yaml`  
**Original code:**
```yaml
- name: Test_Queued_Call
  description: This unit test invokes the async connector and makes sure the arguments are passed through asynchronously, as expected.
```
**Explanation:** The test actually verifies the delay behavior (1.4s delay, measured with `Ada.Real_Time.Clock`), but the description only mentions async pass-through. The description should mention that the configured delay is exercised and wall-clock time is measured.  
**Severity:** Low

---

## 2. Model Review

### MOD-01 — Dropped_Message event carries no payload identifying what was dropped (Medium)

**File:** `connector_delayer.events.yaml`  
**Original code:**
```yaml
events:
  - name: Dropped_Message
    description: The queue overflowed and the incoming data was dropped.
```
**Explanation:** In a flight system, when a message is dropped, operators need to know *which* data was lost. The event carries no parameter (no ID, no sequence counter, no drop count). While the generic type `T` may not be directly serializable as an event param, a drop counter or queue depth at the time of the drop would significantly aid diagnosis. Compare with other Adamant components that include a status or counter in overflow events.  
**Suggested fix:** Consider adding a `param_type` to the event (e.g., a packed record with a cumulative drop count) or at minimum document why no payload is provided.  
**Severity:** Medium

### MOD-02 — No connector for a drop-count data product (Low)

**File:** `connector_delayer.component.yaml`  
**Explanation:** The component has no data product connector and thus no way to telemetry-report cumulative drop counts or delay configuration. For a flight component, a data product showing the number of dropped messages would be valuable for monitoring health.  
**Suggested fix:** Consider adding a `Data_Product_T_Send` connector and a `Drop_Count` data product.  
**Severity:** Low

---

## 3. Component Implementation Review

### IMPL-01 — Sleep is performed while holding the dequeue context, blocking all other queued items (High)

**File:** `component-connector_delayer-implementation.adb`, lines 27–33  
**Original code:**
```ada
overriding procedure T_Recv_Async (Self : in out Instance; Arg : in T) is
begin
   -- Delay first:
   if Self.Delay_Us > 0 then
      Sleep.Sleep_Us (Self.Delay_Us);
   end if;

   -- Forward the incoming data along:
   Self.T_Send (Arg);
end T_Recv_Async;
```
**Explanation:** `T_Recv_Async` is the handler invoked during queue dispatch. While this procedure sleeps, the component's task is blocked, meaning no other queued item can be dispatched. If 3 items are queued and `Delay_Us = 1_400_000` (1.4 s), they will be dispatched serially with a total wall-clock time of **3 × 1.4 s = 4.2 s**. The component description says it can be used "as an alarm, transmitting data N µs after receipt," but the actual delay from receipt is `(queue_position × Delay_Us)`, not simply `Delay_Us`. This is not a bug per se (the YAML description does say "the delay time begins right after the element is dequeued"), but the higher-level description is misleading about the alarm use case. For safety-critical code, the cumulative blocking behavior should be prominently documented so system designers account for worst-case latency.  
**Suggested fix:** Add a prominent note in the component YAML description and/or the `.tex` design document clarifying that the delay is **per-dequeue**, so N queued items incur N × Delay_Us total latency. Example:
```
Note: The delay is applied after each dequeue operation, so N queued items
will take at least N × Delay_Us total time to dispatch. System designers
must account for this cumulative latency.
```
**Severity:** High

### IMPL-02 — `Delay_Us` parameter type `Natural` allows zero but component description says "delays transmission" (Low)

**File:** `connector_delayer.component.yaml`, init parameters  
**Original code:**
```yaml
- name: Delay_Us
  description: The amount of time to delay prior to transmission in microseconds.
  type: Natural
```
**Explanation:** The component description explicitly addresses the zero case ("When configured to sleep for zero microseconds, this component behaves identically to the Connector Queuer"), and the implementation guards with `if Self.Delay_Us > 0`. This is consistent. No issue—noted for completeness only.  
**Severity:** N/A (no issue)

### IMPL-03 — `T_Recv_Async_Dropped` uses `Ignore : T renames Arg` but `Arg` is not otherwise used (Low)

**File:** `component-connector_delayer-implementation.adb`, lines 36–40  
**Original code:**
```ada
overriding procedure T_Recv_Async_Dropped (Self : in out Instance; Arg : in T) is
   Ignore : T renames Arg;
begin
   Self.Event_T_Send_If_Connected (Self.Events.Dropped_Message (Self.Sys_Time_T_Get));
end T_Recv_Async_Dropped;
```
**Explanation:** The `Ignore` rename is the Adamant convention for suppressing unused-parameter warnings. This is fine and consistent with project style. No issue.  
**Severity:** N/A (no issue)

---

## 4. Unit Test Review

### TEST-01 — `Test_Queued_Call` measures delay via wall-clock but has no assertion on the duration (High)

**File:** `test/connector_delayer_tests-implementation.adb`, `Test_Queued_Call` procedure  
**Original code:**
```ada
The_Time_1 := Clock;
Natural_Assert.Eq (T.Dispatch_All, 1);
The_Time_2 := Clock;
Dur := The_Time_2 - The_Time_1;
Put_Line ("Took: " & Dur'Image);
```
**Explanation:** The test measures elapsed time and prints it, but never asserts that the delay was at least `Delay_Us` (1.4 s). This means the test would pass even if `Sleep.Sleep_Us` were a no-op. For a component whose sole purpose is delaying, verifying the actual delay is essential. At minimum, assert `Dur >= Ada.Real_Time.Microseconds (1_400_000)` for the single-dispatch case and `Dur >= Ada.Real_Time.Microseconds (2_800_000)` for the two-dispatch case.  
**Suggested fix:**
```ada
-- After dispatching 1 item with 1.4s delay:
pragma Assert (Dur >= Ada.Real_Time.Microseconds (1_400_000),
   "Delay too short: expected >= 1.4s");
```
**Severity:** High

### TEST-02 — No test for `Delay_Us = 0` (the Connector Queuer equivalence mode) (Medium)

**File:** `test/connector_delayer_tests-implementation.adb`  
**Explanation:** The component description explicitly states "When configured to sleep for zero microseconds, this component behaves identically to the Connector Queuer." There is no test case that initializes the component with `Delay_Us => 0` and verifies immediate pass-through (near-zero dispatch time). This is a documented behavior contract that is untested.  
**Suggested fix:** Add a `Test_Zero_Delay` test case that initializes with `Delay_Us => 0`, sends data, dispatches, and asserts the data arrives with negligible latency.  
**Severity:** Medium

### TEST-03 — No test for dropped-message event content or Sys_Time correctness (Medium)

**File:** `test/connector_delayer_tests-implementation.adb`, `Test_Full_Queue`  
**Original code:**
```ada
Natural_Assert.Eq (T.Event_T_Recv_Sync_History.Get_Count, 1);
Natural_Assert.Eq (T.Dropped_Message_History.Get_Count, 1);
```
**Explanation:** The test checks that one event was emitted, but doesn't verify the event's ID or timestamp. It doesn't verify that `Sys_Time_T_Return` was called (i.e., that the event timestamp was fetched via the `Sys_Time_T_Get` connector). Checking `Sys_Time_T_Return_History.Get_Count = 1` would confirm the time connector was invoked.  
**Suggested fix:**
```ada
-- Verify system time was fetched for the event:
Natural_Assert.Eq (T.Sys_Time_T_Return_History.Get_Count, 1);
```
**Severity:** Medium

### TEST-04 — Queue size is tightly coupled to 3 elements; no boundary test at exactly capacity (Low)

**File:** `test/connector_delayer_tests-implementation.adb`, `Set_Up_Test`  
**Original code:**
```ada
Self.Tester.Init_Base (Queue_Size => Self.Tester.Component_Instance.Get_Max_Queue_Element_Size * 3);
```
**Explanation:** The queue is sized for exactly 3 elements. `Test_Full_Queue` fills all 3 and drops the 4th. There's no test that verifies behavior when exactly at capacity (3 items queued, then successfully dispatching one and re-queuing). This is a minor gap.  
**Severity:** Low

---

## 5. Summary — Top 5 Issues

| # | ID | Severity | Summary |
|---|-----|----------|---------|
| 1 | TEST-01 | **High** | Delay duration is measured but never asserted — the core delay functionality is effectively untested. |
| 2 | IMPL-01 | **High** | Cumulative blocking (N × Delay_Us) when multiple items are queued is not documented; misleading "alarm" use-case description. |
| 3 | TEST-02 | **Medium** | No test for the explicitly documented `Delay_Us = 0` (Connector Queuer equivalence) mode. |
| 4 | TEST-03 | **Medium** | Dropped-message test doesn't verify event content or that `Sys_Time_T_Get` was invoked. |
| 5 | MOD-01 | **Medium** | `Dropped_Message` event carries no payload (no drop count, no identifying info) for flight diagnosis. |

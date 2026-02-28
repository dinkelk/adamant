# Connector Queuer — Code Review

**Component:** `connector_queuer`
**Branch:** `review/components-connector-queuer`
**Date:** 2026-02-28
**Reviewer:** Automated (Claude)

---

## 1. Documentation Review

### DOC-01 — Typo in implementation spec comment: "front of the a"
- **File:** `component-connector_queuer-implementation.ads`, line 5
- **Original:**
  ```
  The component allows a queue to be added in front of the a synchronous connector in any component.
  ```
- **Explanation:** "front of the a" should be "front of a". This same typo is present in the tester spec header comment and the component.yaml description.
- **Corrected:**
  ```
  The component allows a queue to be added in front of a synchronous connector in any component.
  ```
- **Severity:** Low

### DOC-02 — LaTeX document includes inapplicable sections
- **File:** `doc/connector_queuer.tex`
- **Original:**
  ```latex
  \subsection{Interrupts}
  \input{build/tex/connector_queuer_interrupts.tex}
  ...
  \subsection{Commands}
  \input{build/tex/connector_queuer_commands.tex}
  \subsection{Parameters}
  \input{build/tex/connector_queuer_parameters.tex}
  ...
  \subsection{Data Products}
  \input{build/tex/connector_queuer_data_products.tex}
  \subsection{Packets}
  \input{build/tex/connector_queuer_packets.tex}
  ```
- **Explanation:** This component has no interrupts, commands, parameters, data products, or packets. Including these sections (even if the generated tex files say "None") adds clutter and may confuse readers into thinking the component has these interfaces. If the Adamant template requires them, this is acceptable — but if optional, they should be removed.
- **Severity:** Low

---

## 2. Model Review

### MOD-01 — Event `Dropped_Message` has no parameter for diagnostics
- **File:** `connector_queuer.events.yaml`
- **Original:**
  ```yaml
  events:
    - name: Dropped_Message
      description: The queue overflowed and the incoming data was dropped.
  ```
- **Explanation:** The event carries no parameter (no `param_type`). When this event fires, operators have no way to determine *which* data was dropped or the queue depth at the time of the drop. For a safety-critical system, a counter or sequence number parameter would aid anomaly investigation. This is a design-level observation — the framework may not support a generic-typed event parameter, so this may be intentional.
- **Severity:** Medium

---

## 3. Component Implementation Review

### IMPL-01 — `Ignore` rename in `T_Recv_Async_Dropped` suppresses unused-parameter warning but discards potentially useful diagnostic data
- **File:** `component-connector_queuer-implementation.adb`, lines 15–16
- **Original:**
  ```ada
  overriding procedure T_Recv_Async_Dropped (Self : in out Instance; Arg : in T) is
     Ignore : T renames Arg;
  begin
     -- Throw event:
     Self.Event_T_Send_If_Connected (Self.Events.Dropped_Message (Self.Sys_Time_T_Get));
  end T_Recv_Async_Dropped;
  ```
- **Explanation:** The dropped `Arg` value is silently discarded. While the event is sent, there is no logging or telemetry of what was dropped. In a flight context, this makes post-anomaly reconstruction harder. If the framework supports it, consider logging the dropped argument or at minimum incrementing a data product counter tracking cumulative drops.
- **Severity:** Medium

### IMPL-02 — No drop counter or data product for monitoring queue health
- **File:** `component-connector_queuer-implementation.adb` (component-wide)
- **Explanation:** The component has no data product tracking the number of dropped messages. In long-duration missions, transient `Dropped_Message` events could be missed if the event system itself is overloaded. A cumulative drop counter data product would provide a reliable, pollable indicator of queue health. This is a design enhancement recommendation.
- **Severity:** Medium

The core implementation (`T_Recv_Async` forwarding via `Self.T_Send`) is correct and minimal. No logic errors found.

---

## 4. Unit Test Review

### TEST-01 — `Test_Full_Queue` does not verify the dropped message content or count value
- **File:** `test/connector_queuer_tests-implementation.adb`, `Test_Full_Queue` procedure
- **Original:**
  ```ada
  -- Expect next one to be dropped:
  T.Expect_T_Send_Dropped := True;
  T.T_Send (((13, 13), 13));

  -- Check events:
  Natural_Assert.Eq (T.Event_T_Recv_Sync_History.Get_Count, 1);
  Natural_Assert.Eq (T.Dropped_Message_History.Get_Count, 1);
  ```
- **Explanation:** The test verifies that *an* event was emitted and the drop handler was called, but does not assert on the event's timestamp or content. It also does not verify that `T_Send_Dropped_Count` reached 1 after the drop. While the tester infrastructure tracks this counter, the test never asserts on it.
- **Corrected (add after existing assertions):**
  ```ada
  Natural_Assert.Eq (T.T_Send_Dropped_Count, 1);
  ```
- **Severity:** Low

### TEST-02 — No test for multiple consecutive drops
- **File:** `test/connector_queuer_tests-implementation.adb`
- **Explanation:** Only a single drop is tested. There is no test that fills the queue, drops multiple messages in succession, and verifies the event count matches. The tester's `Expect_T_Send_Dropped` flag is a one-shot boolean (reset to `False` after one drop in `T_Send_Dropped`), so attempting a second consecutive drop without re-setting the flag would trigger a test assertion failure. This limits test coverage of sustained overload scenarios.
- **Corrected:** Add a test case that sets `Expect_T_Send_Dropped := True` before each additional send, or refactor the flag to a counter-based mechanism, and assert multiple drops produce multiple events.
- **Severity:** Medium

### TEST-03 — No test for `Dispatch_N` function
- **File:** `test/connector_queuer_tests-implementation.adb`
- **Explanation:** The tester provides a `Dispatch_N` primitive for partial queue draining, but no test exercises it. All tests use `Dispatch_All`. Testing partial dispatch would verify correct FIFO ordering under incremental dequeue.
- **Severity:** Low

### TEST-04 — Tester `Dropped_Message` handler pushes hardcoded zero instead of meaningful data
- **File:** `test/component-connector_queuer-implementation-tester.adb`, lines 91–96
- **Original:**
  ```ada
  overriding procedure Dropped_Message (Self : in out Instance) is
     Arg : constant Natural := 0;
  begin
     Self.Dropped_Message_History.Push (Arg);
  end Dropped_Message;
  ```
- **Explanation:** The history always records `0`. If the event were later extended with a parameter, this would silently discard it. The hardcoded value provides no diagnostic utility. This is a minor tester hygiene issue — the history merely serves as a call counter here.
- **Severity:** Low

---

## 5. Summary — Top 5 Issues

| # | ID | Severity | Summary |
|---|------|----------|---------|
| 1 | MOD-01 | **Medium** | `Dropped_Message` event carries no parameter for diagnostics, limiting anomaly investigation. |
| 2 | IMPL-02 | **Medium** | No data product for cumulative drop count — transient events may be missed in flight. |
| 3 | TEST-02 | **Medium** | No test for multiple consecutive queue drops; one-shot flag limits overload testing. |
| 4 | IMPL-01 | **Medium** | Dropped argument value is silently discarded with no logging or telemetry. |
| 5 | TEST-01 | **Low** | `Test_Full_Queue` never asserts on `T_Send_Dropped_Count` after a drop. |

**Overall Assessment:** The component is clean, minimal, and correct for its purpose. The implementation has no logic errors. The issues identified are primarily around observability (lack of drop counting / diagnostics) and test completeness (no multi-drop or partial-dispatch tests). For a simple passthrough queuer, these are reasonable design trade-offs, but in a safety-critical context the observability gaps (MOD-01, IMPL-02) warrant consideration.

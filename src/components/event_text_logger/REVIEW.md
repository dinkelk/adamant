# Event Text Logger — Component Code Review

**Component:** `src/components/event_text_logger`
**Date:** 2026-02-28
**Reviewer:** Automated (Claude)

---

## 1. Documentation Review

The LaTeX document (`doc/event_text_logger.tex`) follows the standard Adamant component document template and includes all expected sections (Description, Requirements, Design, Unit Tests, Appendix). No issues found — all sections reference the appropriate `build/tex/` generated inputs.

The YAML description and the Ada spec comment block are consistent with each other.

**No issues found.**

---

## 2. Model Review

**File:** `event_text_logger.component.yaml`

### Issue 2.1 — Assembly description typo

| Field | Detail |
|---|---|
| **Location** | `test/event_assembly/event_assembly.assembly.yaml`, line 2 |
| **Original** | `description: This is an assembly for testing the text_to_events component.` |
| **Explanation** | The description says "text_to_events" but this assembly tests the **event_text_logger** component. The name is reversed. |
| **Corrected** | `description: This is an assembly for testing the event_text_logger component.` |
| **Severity** | **Low** |

No other model issues. The component YAML is minimal and correct — single `recv_async` connector of type `Event.T`, active execution, discriminant with access-to-function type.

---

## 3. Component Implementation Review

**Files:** `component-event_text_logger-implementation.ads`, `component-event_text_logger-implementation.adb`

### Issue 3.1 — `Ignore` rename on `Self` is misleading / dead

| Field | Detail |
|---|---|
| **Location** | `component-event_text_logger-implementation.adb`, lines 14 and 20 |
| **Original** | `Ignore : Instance renames Self;` (in both `Event_T_Recv_Async` and `Event_T_Recv_Async_Dropped`) |
| **Explanation** | The `Ignore` rename is the Adamant convention for suppressing "unreferenced" warnings when `Self` is unused. However, **both procedures actually use `Self`** (`Self.Event_To_Text` and implicitly via `Arg`). The rename is unnecessary and misleading — a reader may assume `Self` is intentionally unused when it is not. In `Event_T_Recv_Async`, `Self.Event_To_Text` is accessed directly, so `Self` is clearly referenced. In `Event_T_Recv_Async_Dropped`, `Self` is the tagged-type parameter and is still referenced (even if only for dispatching). Since the code compiles without warnings, the compiler already knows `Self` is used; the rename just adds confusion. |
| **Corrected** | Remove the `Ignore` line from both procedures. |
| **Severity** | **Low** |

### Issue 3.2 — No validation or protection against exception propagation from `Event_To_Text`

| Field | Detail |
|---|---|
| **Location** | `component-event_text_logger-implementation.adb`, line 15 |
| **Original** | `Put_Line (Standard_Error, Self.Event_To_Text.all (Arg));` |
| **Explanation** | The `Event_To_Text` function is a user-supplied callback accessed via discriminant. If this function raises an exception (e.g., for an unrecognized event ID, or a Constraint_Error in string formatting), the exception will propagate out of the async receive handler. In a safety-critical flight context with an active task, an unhandled exception could terminate the component's task and silently stop all future event logging — a loss of telemetry. Consider wrapping the call in an exception handler that prints a fallback message (e.g., raw event ID and hex dump) so the logger degrades gracefully rather than dying. |
| **Corrected** | ```ada overriding procedure Event_T_Recv_Async (Self : in out Instance; Arg : in Event.T) is begin Put_Line (Standard_Error, Self.Event_To_Text.all (Arg)); exception when E : others => Put_Line (Standard_Error, "Event_Text_Logger: exception converting event ID " & Event_Types.Event_Id'Image (Arg.Header.Id) & " to text."); end Event_T_Recv_Async; ``` |
| **Severity** | **Medium** |

The implementation is otherwise clean and minimal, which is appropriate for a logging-only component.

---

## 4. Unit Test Review

**Files:** `test/tests-implementation.adb`, `test/component-event_text_logger-implementation-tester.adb`

### Issue 4.1 — No assertion on output content; test only checks dispatch count

| Field | Detail |
|---|---|
| **Location** | `test/tests-implementation.adb`, `Test_Event_Printing`, lines 38–43 |
| **Original** | ```ada Cnt := T.Dispatch_All; Natural_Assert.Eq (Cnt, 3); ``` |
| **Explanation** | The test sends three events, dispatches them, and asserts only that three items were dispatched. It never validates that the correct text was printed to `Standard_Error`. A bug in the `Event_To_Text` function or in the `Put_Line` formatting would not be caught. For a more meaningful test, capture or redirect `Standard_Error` and verify the output strings contain the expected event text. Alternatively, at minimum, verify no exceptions were raised by the callback (which the current test does implicitly, but only by accident). |
| **Corrected** | At minimum, add a comment acknowledging this is a smoke test. Ideally, redirect `Standard_Error` to a string buffer and assert expected substrings. |
| **Severity** | **Medium** |

### Issue 4.2 — No test for the dropped-event path

| Field | Detail |
|---|---|
| **Location** | `test/tests-implementation.adb` (missing test) |
| **Original** | Only `Test_Event_Printing` exists. |
| **Explanation** | The component implements `Event_T_Recv_Async_Dropped` which prints a warning when the queue is full. This path is never exercised in the unit tests. The tester already has `Expect_Event_T_Send_Dropped` and `Event_T_Send_Dropped_Count` infrastructure to support this, but no test fills the queue and verifies the dropped message handling. |
| **Corrected** | Add a test that: (1) creates the component with a minimal queue size, (2) sends enough events to overflow the queue, (3) asserts `Event_T_Send_Dropped_Count > 0`, and (4) dispatches remaining items. |
| **Severity** | **Medium** |

### Issue 4.3 — Tester resets `Expect_Event_T_Send_Dropped` after first drop

| Field | Detail |
|---|---|
| **Location** | `test/component-event_text_logger-implementation-tester.adb`, lines 38–39 |
| **Original** | ```ada Self.Event_T_Send_Dropped_Count := @ + 1; Self.Expect_Event_T_Send_Dropped := False; ``` |
| **Explanation** | After the first dropped event, `Expect_Event_T_Send_Dropped` is set back to `False`. If multiple events are dropped in sequence (which is the realistic scenario when a queue overflows), the second drop will trigger the assertion failure `"The component's queue filled up..."`. The tester should either not auto-reset the flag, or use a counter-based expectation (e.g., `Expected_Drop_Count`). |
| **Corrected** | Remove `Self.Expect_Event_T_Send_Dropped := False;` or change the mechanism to a counter: ```ada if Self.Event_T_Send_Dropped_Count < Self.Expected_Drop_Count then Self.Event_T_Send_Dropped_Count := @ + 1; else pragma Assert (False, "More drops than expected!"); end if; ``` |
| **Severity** | **High** |

---

## 5. Summary — Top 5 Issues

| # | ID | Severity | Location | Summary |
|---|---|---|---|---|
| 1 | 4.3 | **High** | Tester `Event_T_Send_Dropped`, line 39 | Tester resets drop-expected flag after first drop, making multi-drop tests impossible and causing false assertion failures. |
| 2 | 3.2 | **Medium** | Implementation `.adb`, line 15 | No exception handler around user-supplied `Event_To_Text` callback; unhandled exception kills the logger task. |
| 3 | 4.1 | **Medium** | `Test_Event_Printing` | Test only asserts dispatch count, never validates printed output content. |
| 4 | 4.2 | **Medium** | Test suite (missing) | No test for the queue-full / dropped-event path. |
| 5 | 2.1 | **Low** | `event_assembly.assembly.yaml`, line 2 | Description says "text_to_events" instead of "event_text_logger". |

# Interrupt Servicer — Code Review

**Branch:** `review/components-interrupt-servicer`
**Date:** 2026-02-28
**Reviewer:** Automated (Claude)

---

## 1. Documentation Review

### 1.1 component.yaml Description vs. Implementation Spec Comment

| | |
|---|---|
| **Location** | `component-interrupt_servicer-implementation.ads`, line 7 |
| **Original** | `-- This is the Interrupt Servicer component. It is attached to an interrupt and sends out a Tick.T every time the interrupt is triggered.` |
| **Explanation** | The comment hardcodes "Tick.T" as the output type, but the component is generic over `Interrupt_Data_Type`. The YAML description correctly says "user-defined generic data type." The spec comment is misleading — it suggests only `Tick.T` is ever sent, which is false for any non-Tick instantiation. |
| **Corrected** | `-- This is the Interrupt Servicer component. It is attached to an interrupt and sends out an Interrupt_Data_Type every time the interrupt is triggered.` |
| **Severity** | **Medium** |

### 1.2 Tester Spec Repeats Same Incorrect Comment

| | |
|---|---|
| **Location** | `test/component-interrupt_servicer-implementation-tester.ads`, line 7 |
| **Original** | `-- This is the Interrupt Servicer component. It is attached to an interrupt and sends out a Tick.T every time the interrupt is triggered.` |
| **Explanation** | Same stale "Tick.T" comment duplicated in the tester spec. |
| **Corrected** | `-- Interrupt Servicer component tester. See component spec for description.` |
| **Severity** | **Low** |

### 1.3 Tester Connector Comment Says "tick" Instead of Generic Type

| | |
|---|---|
| **Location** | `test/component-interrupt_servicer-implementation-tester.ads`, line 28 |
| **Original** | `-- The tick send connection.` |
| **Explanation** | The connector sends the generic `Interrupt_Data_Type`, not specifically a "tick." This comment is copied from a Tick-specific instantiation and is incorrect for the generic component. |
| **Corrected** | `-- The data send connection.` (matching the YAML) |
| **Severity** | **Low** |

### 1.4 Same Stale Comment in Tester Body

| | |
|---|---|
| **Location** | `test/component-interrupt_servicer-implementation-tester.adb`, `Interrupt_Data_Type_Recv_Sync` procedure comment |
| **Original** | `-- The tick send connection.` |
| **Explanation** | Same issue as 1.3, repeated in the body. |
| **Corrected** | `-- The data send connection.` |
| **Severity** | **Low** |

### 1.5 YAML Connector Description Says "data send" but Context Doc Says "timestamping"

No actual issue — the context document (`interrupt_servicer_context.tex`) correctly describes both connectors. Documentation is otherwise thorough and well-structured.

---

## 2. Model Review

### 2.1 component.yaml — No Issues Found

The model is clean:
- Generic parameters with `optional: True` on `Set_Interrupt_Data_Time` and a `null` default — correct.
- Discriminant correctly specifies `Custom_Interrupt_Procedure`.
- Connectors are minimal and correct (one `send`, one `get`).
- Interrupt declared with proper description.
- `execution: active` is correct for a task-based component.
- `with: Interrupt_Handlers` properly declares the dependency.

### 2.2 requirements.yaml — Adequate

Four requirements covering: interrupt attachment, custom handler invocation, data forwarding, and internal task. These match the implementation. No gaps identified.

---

## 3. Component Implementation Review

### 3.1 Timestamp Set Even When `Set_Interrupt_Data_Time` Is Null (by design, but worth noting)

| | |
|---|---|
| **Location** | `component-interrupt_servicer-implementation.adb`, lines 12–15 |
| **Original** | `if Self.Is_Sys_Time_T_Get_Connected then Set_Interrupt_Data_Time (Interrupt_Data, Self.Sys_Time_T_Get); end if;` |
| **Explanation** | The guard checks whether the `Sys_Time_T_Get` connector is connected, which is the correct runtime check. When `Set_Interrupt_Data_Time` defaults to `null`, the call is a no-op. The YAML documentation correctly advises users not to connect the time connector when the null default is used. This is a **sound design** — no issue. |
| **Severity** | N/A |

### 3.2 Timing: `Sys_Time_T_Get` Called After `Wait` Returns, Not at Interrupt Time

| | |
|---|---|
| **Location** | `component-interrupt_servicer-implementation.adb`, line 14 |
| **Original** | `Set_Interrupt_Data_Time (Interrupt_Data, Self.Sys_Time_T_Get);` |
| **Explanation** | The timestamp is captured *after* the task is released from `Wait`, not at interrupt time. There is inherent latency between the interrupt firing (which calls the custom handler inside the protected object) and the task resuming and calling `Sys_Time_T_Get`. For safety-critical timing, users should capture time *inside* the custom interrupt handler procedure (via the `Custom_Interrupt_Procedure` discriminant) rather than relying on this post-wait timestamp. The YAML documentation hints at this ("Usually, this type will be used to capture data related to an interrupt in the interrupt handler. Often, a timestamp... will be included") but the `Set_Interrupt_Data_Time` generic parameter's description implies the framework handles it accurately — which may mislead users into thinking the timestamp is captured at interrupt time. |
| **Corrected** | Add a clarifying note to the `Set_Interrupt_Data_Time` description: *"Note: This timestamp is captured after the task resumes, not at interrupt time. For precise interrupt timing, capture the timestamp inside the Custom_Interrupt_Procedure instead."* |
| **Severity** | **Medium** |

### 3.3 Implementation Is Minimal and Correct

The `Cycle` procedure is only 5 effective lines. The logic is straightforward:
1. Block on `Wait` (released by interrupt handler's `Signaled := True`).
2. Optionally set timestamp.
3. Send data downstream.

No resource leaks, no unprotected shared state, no race conditions. The `Interrupt_Data_Type_Send_Dropped` is overridden as `null` — acceptable for a generic component where the downstream queue policy is assembly-specific.

---

## 4. Unit Test Review

### 4.1 Only One Test Case

| | |
|---|---|
| **Location** | `test/tests.interrupt_servicer.tests.yaml` |
| **Explanation** | There is a single test (`Test_Interrupt_Handling`) that covers the happy path: 5 interrupts → 5 ticks with correct count and timestamp. Missing test scenarios include: (a) behavior when `Sys_Time_T_Get` is *not* connected (null `Set_Interrupt_Data_Time`), (b) rapid-fire interrupts without sleep to test potential signal loss, (c) interrupt before task is started. For a safety-critical component, broader scenario coverage is expected. |
| **Corrected** | Add test cases for: disconnected time connector, burst interrupts, and edge-case timing. |
| **Severity** | **Medium** |

### 4.2 Sleep-Based Synchronization Is Fragile

| | |
|---|---|
| **Location** | `test/tests-implementation.adb`, `Sleep_A_Bit` (500ms delay) |
| **Original** | `Wait_Time : constant Ada.Real_Time.Time_Span := Ada.Real_Time.Microseconds (500_000);` |
| **Explanation** | The test relies on a 500ms sleep to yield the CPU to the component task. On a heavily loaded CI machine or under-provisioned target, this could be insufficient, leading to flaky test failures. While pragmatic for interrupt testing, this is a known fragility. The value is generous enough that it's unlikely to fail in practice, but the pattern is worth noting. |
| **Severity** | **Low** |

### 4.3 No Assertion on `Sys_Time_T_Return_History`

| | |
|---|---|
| **Location** | `test/tests-implementation.adb`, `Test_Interrupt_Handling` |
| **Explanation** | The tester records `Sys_Time_T_Return_History` but the test never asserts on it. Verifying that the time connector was called exactly 5 times would strengthen the test and confirm the `Is_Sys_Time_T_Get_Connected` guard works. |
| **Corrected** | Add: `Natural_Assert.Eq (T.Sys_Time_T_Return_History.Get_Count, 5);` |
| **Severity** | **Low** |

---

## 5. Summary — Top 5 Issues

| # | Severity | Location | Issue |
|---|----------|----------|-------|
| 1 | **Medium** | `implementation.adb:14` / YAML | Timestamp captured post-`Wait`, not at interrupt time; documentation implies it's at interrupt time. Misleading for safety-critical timing. |
| 2 | **Medium** | `implementation.ads:7`, `tester.ads:7` | Hardcoded "Tick.T" in comments; component is generic over `Interrupt_Data_Type`. |
| 3 | **Medium** | `tests.yaml` | Only one test case; no coverage of disconnected time connector, burst interrupts, or edge cases. |
| 4 | **Low** | `tests-implementation.adb` | `Sys_Time_T_Return_History` is populated but never asserted on — missed verification opportunity. |
| 5 | **Low** | `tester.ads:28`, `tester.adb` | Connector comment says "tick send" instead of "data send" — stale from Tick-specific usage. |

**Overall Assessment:** This is a clean, minimal, well-designed component. The implementation is concise and correct. The primary concerns are documentation accuracy (stale Tick.T references) and the potential for users to misunderstand when the timestamp is captured. Test coverage is functional but narrow for a safety-critical component.

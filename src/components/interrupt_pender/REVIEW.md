# Interrupt Pender — Code Review

**Component:** `src/components/interrupt_pender`
**Date:** 2026-02-28
**Reviewer:** Automated (Claude)

---

## 1. Documentation Review

### 1.1 — Stale comment in implementation spec

| Field | Value |
|---|---|
| **File** | `component-interrupt_pender-implementation.ads` |
| **Line** | Top comment block (line 6) |
| **Severity** | Low |

**Original:**
```ada
-- This is the Interrupt Pender component. It is attached to an interrupt and provides a connector which will block any component that invokes it until an interrupt is triggered. When an interrupt occurs the component will return a Tick to the waiting component. This component should be made passive in order to function properly.
```

**Explanation:** The comment says the component "will return a Tick" but the component is generic and returns `Interrupt_Data_Type`, not necessarily a `Tick.T`. This is misleading for maintainers who instantiate with a non-Tick type.

**Corrected:**
```ada
-- This is the Interrupt Pender component. It is attached to an interrupt and provides a connector which will block any component that invokes it until an interrupt is triggered. When an interrupt occurs the component will return an Interrupt_Data_Type to the waiting component. This component should be made passive in order to function properly.
```

### 1.2 — Same stale "Tick" comment in tester spec

| Field | Value |
|---|---|
| **File** | `test/component-interrupt_pender-implementation-tester.ads` |
| **Line** | Package-level comment (line 12) |
| **Severity** | Low |

Same issue as 1.1 — the tester spec comment also says "return a Tick" instead of "return an Interrupt_Data_Type".

### 1.3 — Requirement does not mention timestamp insertion

| Field | Value |
|---|---|
| **File** | `interrupt_pender.requirements.yaml` |
| **Severity** | Medium |

**Explanation:** The implementation has a feature: if `Sys_Time_T_Get` is connected, the component calls `Set_Interrupt_Data_Time` to stamp the interrupt data with a time. This behavior is described in the `component.yaml` description and the context tex doc, but is not captured in any requirement. For a safety-critical component, all functional behaviors should be traceable to requirements.

**Suggested addition:**
```yaml
  - text: When the Sys_Time_T_Get connector is connected, the component shall set the time in the interrupt data type using the provided Set_Interrupt_Data_Time procedure after an interrupt is received.
```

### 1.4 — Context diagram assembly missing Sys_Time connection

| Field | Value |
|---|---|
| **File** | `doc/assembly/context.assembly.yaml` |
| **Severity** | Low |

**Explanation:** The example assembly instantiates `Interrupt_Pender` with `Set_Interrupt_Data_Time => Tick_Interrupt_Handler.Set_Tick_Time`, implying the timestamp feature is used, but the assembly does not show a `Sys_Time_T_Get` connection. A reader following this example would get a component that fetches time via an unconnected connector (the `Is_Sys_Time_T_Get_Connected` guard protects at runtime, but the diagram is incomplete as documentation).

---

## 2. Model Review

### 2.1 — No issues found

The `interrupt_pender.component.yaml` model is well-structured. The generic parameters, discriminant, interrupt definition, and connector types are correct and consistent with the implementation. The `return` connector kind and `get` connector for `Sys_Time.T` properly model the blocking and time-fetch semantics.

---

## 3. Component Implementation Review

### 3.1 — Timestamp taken after `Wait` returns, not inside interrupt handler

| Field | Value |
|---|---|
| **File** | `component-interrupt_pender-implementation.adb` |
| **Lines** | 13–16 |
| **Severity** | High |

**Original:**
```ada
      -- Wait for the interrupt to release this task:
      Self.The_Signal.Wait (To_Return);

      -- Get the time of the interrupt and store it in the interrupt data:
      if Self.Is_Sys_Time_T_Get_Connected then
         Set_Interrupt_Data_Time (To_Return, Self.Sys_Time_T_Get);
      end if;
```

**Explanation:** The timestamp is fetched *after* the task is unblocked from `Wait`, not at the point the interrupt fires. The comment says "time of the interrupt" but this captures time-of-wake-up, which includes scheduling latency. For an interrupt-pended architecture, the calling task may not be scheduled immediately after the protected entry barrier opens, introducing non-deterministic jitter in the timestamp. The documentation (`component.yaml`) explicitly says "The Interrupt Pender will automatically insert the timestamp into the custom type", suggesting it should be the interrupt time.

The proper fix would be to fetch time inside the protected `Handler` procedure (or immediately after the custom procedure in the `Task_Signal.Handler`). However, that would require changes to the `Interrupt_Handlers` core package and the `Sys_Time_T_Get` connector cannot be called from interrupt context. Given the architectural constraint, the component should at minimum update its documentation to clearly state the timestamp reflects wake-up time, not interrupt time. If true interrupt-time timestamps are needed, the user's custom interrupt handler should capture time directly (e.g., reading a hardware clock register).

**Recommendation:** Update the `component.yaml` description and the code comment to say "the time is captured when the waiting task resumes, not at the instant the interrupt fires" so users understand the jitter implications. Alternatively, provide a mechanism to capture time inside the interrupt handler itself.

### 3.2 — No initialization subprogram

| Field | Value |
|---|---|
| **File** | `component-interrupt_pender-implementation.ads` |
| **Severity** | Low |

**Explanation:** The component has no `Init` procedure. This is acceptable because the protected object `The_Signal` is initialized via discriminants at elaboration. Noting for completeness — no issue.

---

## 4. Unit Test Review

### 4.1 — Test only covers the `Tick.T` instantiation; `Set_Interrupt_Data_Time` not exercised

| Field | Value |
|---|---|
| **File** | `test/tests-implementation.ads`, lines 26–28 |
| **Severity** | High |

**Original:**
```ada
   package Component_Package is new Component.Interrupt_Pender (Tick.T);
```

**Explanation:** The generic is instantiated with only the `Interrupt_Data_Type` parameter; `Set_Interrupt_Data_Time` defaults to `null`. This means the timestamp-setting code path (`if Self.Is_Sys_Time_T_Get_Connected then Set_Interrupt_Data_Time(...)`) is never exercised — `Set_Interrupt_Data_Time` is a no-op. The `Sys_Time_T_Get` connector *is* connected in the tester, so the `Is_Sys_Time_T_Get_Connected` check returns `True` and the call executes, but does nothing. The timestamp behavior documented in `component.yaml` is untested.

**Corrected:** Add a second test (or modify the existing instantiation) that provides a real `Set_Interrupt_Data_Time` procedure and verifies the returned `Interrupt_Data_Type` contains the expected timestamp:
```ada
   package Component_Package is new Component.Interrupt_Pender (Tick.T, Tick_Interrupt_Handler.Set_Tick_Time);
```

### 4.2 — Interrupt handler zeroes out Time field, making timestamp verification impossible

| Field | Value |
|---|---|
| **File** | `test/tester_interrupt_handler.adb`, lines 8–11 |
| **Severity** | Medium |

**Original:**
```ada
   procedure Handler (Data : in out Tick.T) is
      use Interfaces;
   begin
      -- Increment the count:
      Data.Count := @ + 1;
      -- Increment the time:
      Data.Time := (0, 0);
   end Handler;
```

**Explanation:** The comment says "Increment the time" but the code sets `Data.Time := (0, 0)`, which zeroes it. This is not incrementing. More importantly, even if `Set_Interrupt_Data_Time` were properly wired (see 4.1), the custom handler runs first inside `Task_Signal.Handler`, then after `Wait` returns the component would set the time — but here the time is explicitly zeroed in the handler which executes *before* the component sets it. The comment is simply wrong.

**Corrected:**
```ada
      -- Zero out the time (will be set by the component after wake-up):
      Data.Time := (0, 0);
```

### 4.3 — Only one test case for the entire component

| Field | Value |
|---|---|
| **File** | `test/tests.interrupt_pender.tests.yaml` |
| **Severity** | Medium |

**Explanation:** There is a single test (`Test_Interrupt_Handling`) which tests two scenarios: interrupt-before-wait and interrupt-after-wait. Missing test scenarios include:
- Timestamp correctness when `Set_Interrupt_Data_Time` is provided
- Multiple rapid interrupts (verifying last-wins / drop semantics documented in context tex)
- Behavior when `Sys_Time_T_Get` is *not* connected

### 4.4 — Test uses hardcoded 500ms sleeps making it timing-sensitive

| Field | Value |
|---|---|
| **File** | `test/tests-implementation.adb`, lines 52–56 |
| **Severity** | Low |

**Original:**
```ada
      procedure Sleep_A_Bit is
         Wait_Time : constant Ada.Real_Time.Time_Span := Ada.Real_Time.Microseconds (500_000);
```

**Explanation:** The test relies on 500ms sleeps for task scheduling. On a heavily loaded CI system this could theoretically be insufficient, though 500ms is generous. This is a common pattern in interrupt testing so noting as Low severity.

---

## 5. Summary — Top 5 Issues

| # | Severity | Section | Description |
|---|---|---|---|
| 1 | **High** | 3.1 | Timestamp is captured after task wakes (scheduling jitter), not at interrupt time. Documentation claims "interrupt time" — either fix the timing or fix the docs. |
| 2 | **High** | 4.1 | `Set_Interrupt_Data_Time` generic parameter defaults to null in tests, so the timestamp feature is completely untested. |
| 3 | **Medium** | 1.3 | Timestamp-insertion behavior has no corresponding requirement — untraceable in a safety-critical context. |
| 4 | **Medium** | 4.2 | Test interrupt handler comment says "Increment the time" but code zeroes it; misleading for maintainers. |
| 5 | **Medium** | 4.3 | Only one test case; no coverage of timestamp path, rapid-interrupt drop semantics, or disconnected `Sys_Time_T_Get`. |

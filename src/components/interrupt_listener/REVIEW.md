# Interrupt Listener — Code Review

**Component:** `src/components/interrupt_listener`
**Date:** 2026-02-28
**Reviewer:** Automated (Claude)

---

## 1. Documentation Review

### 1.1 — Spec Comment Describes Wrong Behavior (High)

**File:** `component-interrupt_listener-implementation.ads`, lines 8–9

**Original:**
```ada
-- This is the Interrupt Listener component. It is attached to an interrupt and provides a connector which will give the caller a count. The count includes the number of times the interrupt has occurred since the last invocation of the connector. If the count reaches the maximum of a Natural, it stops incrementing. This component should be made passive in order to function properly.
```

**Explanation:** This comment describes the behavior of an `Interrupt_Counter` (count-and-reset on read, Natural saturation). The actual implementation uses `Task_Signal`, whose `Get_Data` simply returns the current `Internal_Data` — there is no internal count, no reset-on-read, and no Natural saturation logic in this component. The comment is dangerously misleading for anyone maintaining or integrating this component in a safety-critical system.

**Corrected:**
```ada
-- This is the Interrupt Listener component. It is attached to an interrupt and provides a connector which returns the latest interrupt data to the caller. Each time the interrupt fires, a user-supplied custom procedure is invoked with the internal data as an in-out parameter. External components may query the current data at any time via the return connector. This component should be made passive in order to function properly.
```

**Severity:** High

---

### 1.2 — Tester Spec Comment is Stale / Inaccurate (Low)

**File:** `test/component-interrupt_listener-implementation-tester.ads`, lines 8–9

**Original:**
```ada
-- This is the Interrupt Listener component. This component contains an internal piece of data (of generic type) which should be altered by a custom interrupt procedure passed in at instantiation. External components can request the latest version of this data at any time. A common use for this component might be to manage a counter, where the custom procedure increments the count with each interrupt, and the requester of the count uses the count to determine if an interrupt has been received.
```

**Explanation:** This comment is a near-duplicate of the `component.yaml` description but says "should be altered" where the YAML says "is set." Minor inconsistency but worth aligning for a safety-critical codebase.

**Severity:** Low

---

### 1.3 — component.yaml Interrupt Description is Misleading (Medium)

**File:** `interrupt_listener.component.yaml`, interrupt section

**Original:**
```yaml
interrupts:
  - name: interrupt
    description: This component counts the number of times this interrupt occurs.
```

**Explanation:** The component does not count interrupts itself. Counting is entirely the responsibility of the user-supplied custom interrupt procedure. The description should reflect what the component actually does: invoke the custom handler on each interrupt.

**Corrected:**
```yaml
interrupts:
  - name: interrupt
    description: When this interrupt fires, the component invokes the user-supplied custom interrupt handler with the internal data.
```

**Severity:** Medium

---

## 2. Model Review

### 2.1 — `Task_Signal` Used Where `Interrupt_Counter` or a Simpler Construct Would Be More Appropriate (Medium)

**File:** `component-interrupt_listener-implementation.ads`, line 30

**Original:**
```ada
The_Signal : Custom_Interrupt_Handler_Package.Task_Signal (Interrupt_Priority, Interrupt_Id, Custom_Interrupt_Procedure);
```

**Explanation:** The component only ever calls `Get_Data` on the protected object. It never calls `Wait`. The `Task_Signal` type maintains a `Signaled` boolean barrier that is set `True` on every interrupt but never consumed (since `Wait` is never called), leaving dead internal state. For a polling/return pattern, using `Task_Signal` is semantically misleading — it implies a wait/signal paradigm that is not used. If the component is truly meant to be polled, the `Interrupt_Counter` type (which also lives in `Interrupt_Handlers`) would be more appropriate, or a dedicated polling-only protected type should be created.

This is a design-level observation. The current code is functionally correct and thread-safe, but the mismatch between the chosen mechanism (`Task_Signal` — designed for blocking waits) and the actual usage pattern (non-blocking polling via `Get_Data`) could confuse future maintainers and masks intent.

**Severity:** Medium

---

## 3. Component Implementation Review

### 3.1 — No Issues Found

The implementation body is minimal and correct:

```ada
overriding function Interrupt_Data_Type_Return (Self : in out Instance) return Interrupt_Data_Type is
begin
   return Self.The_Signal.Get_Data;
end Interrupt_Data_Type_Return;
```

`Get_Data` is a function on a protected object, so it is thread-safe. The return connector correctly delegates to the protected object. No logic errors.

---

## 4. Unit Test Review

### 4.1 — Test Asserts Timestamp is (0, 0) Due to Handler Hardcoding (Medium)

**File:** `test/tester_interrupt_handler.adb`, line 10

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

**Explanation:** The comment says "Increment the time" but the code sets `Data.Time` to `(0, 0)` every time — it does not increment anything. This means the test never exercises or validates the `Time` field meaningfully. If the intent is to test that data flows through correctly, the handler should set `Time` to a non-trivial value (or the comment should say "Reset the time" to match the code).

**Corrected (align comment to code):**
```ada
   -- Reset the time (not under test):
   Data.Time := (0, 0);
```

**Or (make it meaningful):**
```ada
   -- Set time to a recognizable sentinel:
   Data.Time := (1, 2);
```

**Severity:** Medium

---

### 4.2 — No Test for Concurrent Access (Low)

**Explanation:** The requirements state that it is "acceptable to connect many components up to the same Interrupt Listener `Interrupt_Data_Type_Return` connector, as this is a thread safe operation" (per the context documentation). However, no test exercises concurrent reads from multiple tasks. While thread safety is guaranteed by the Ada protected object semantics, a concurrent access test would provide confidence at the integration level.

**Severity:** Low

---

### 4.3 — Count Overflow Not Tested (Low)

**Explanation:** The spec comment (Issue 1.1) claims count saturates at `Natural'Last`. Even though this is the user handler's responsibility (not the component's), if the documentation is corrected and overflow is considered a user concern, this can be ignored. However, if `Interrupt_Counter` is adopted (Issue 2.1), its `Natural'Last` saturation should be tested.

**Severity:** Low

---

### 4.4 — Sleep-Based Synchronization is Fragile (Low)

**File:** `test/tests-implementation.adb`, `Sleep_A_Bit` procedure

**Original:**
```ada
procedure Sleep_A_Bit is
   Wait_Time : constant Ada.Real_Time.Time_Span := Ada.Real_Time.Microseconds (500_000);
   ...
```

**Explanation:** The test uses a 500 ms sleep to yield the CPU after sending an interrupt. On a heavily loaded CI machine, this could theoretically be insufficient. This is a known pattern in interrupt testing and is acceptable for unit tests, but worth noting.

**Severity:** Low

---

## 5. Summary — Top 5 Issues

| # | Section | Issue | Severity |
|---|---------|-------|----------|
| 1 | 1.1 | Spec comment describes count-and-reset behavior that does not exist in the implementation (describes `Interrupt_Counter`, not `Task_Signal`) | **High** |
| 2 | 2.1 | `Task_Signal` (blocking wait pattern) used for a polling-only component; `Signaled` flag is dead state | **Medium** |
| 3 | 1.3 | `component.yaml` interrupt description claims the component counts interrupts; counting is the user handler's job | **Medium** |
| 4 | 4.1 | Test handler comment says "Increment the time" but code resets it to `(0, 0)`; `Time` field never meaningfully tested | **Medium** |
| 5 | 4.2 | No concurrent-access test despite documentation claiming thread-safe multi-reader support | **Low** |

## Resolution Notes

| # | Issue | Severity | Status | Commit | Notes |
|---|-------|----------|--------|--------|-------|
| 1 | Spec comment wrong behavior | High | Fixed | - | Rewrote to match actual impl |
| 2 | Task_Signal design mismatch | Medium | Not Fixed | - | Design-level change |
| 3 | YAML interrupt description | Medium | Fixed | - | Corrected |
| 4 | Test comment mismatch | Medium | Fixed | - | Corrected |
| 5 | Tester spec comment stale | Low | Fixed | - | Aligned |
| 6 | No concurrent test | Low | Not Fixed | - | Needs infra |
| 7 | Count overflow untested | Low | Not Fixed | - | User handler responsibility |
| 8 | Sleep-based sync | Low | Not Fixed | - | Acceptable pattern |

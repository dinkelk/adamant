# Code Review: `Arm_State` Package

**Reviewer:** Automated (Claude)
**Date:** 2026-02-28
**Branch:** `review/components-command-protector-arm-state`

---

## 1. Package Specification Review

### Issue 1.1 — `Get_State` has an `out` parameter on a protected function

- **File:** `arm_state.ads`, line 12
- **Severity:** High
- **Code:**
  ```ada
  function Get_State (The_Timeout : out Packed_Arm_Timeout.Arm_Timeout_Type) return Command_Protector_Enums.Armed_State.E;
  ```
- **Explanation:** In Ada, protected functions provide concurrent read access (multiple callers may execute simultaneously). However, `Get_State` has an `out` parameter, which means it modifies caller-visible state. While Ada 2012+ technically allows `out` parameters on functions, using one on a **protected function** is semantically misleading: callers expect a read-only lock, yet the function writes to `The_Timeout`. This compiles, but it undermines the concurrent-readers contract. If the intent is truly read-only, a separate function for the timeout would be clearer. If mutual exclusion is needed, this should be a procedure.
- **Suggested fix:** Split into two protected functions, or change to a procedure:
  ```ada
  -- Option A: Two functions
  function Get_State return Command_Protector_Enums.Armed_State.E;
  function Get_Timeout return Packed_Arm_Timeout.Arm_Timeout_Type;

  -- Option B: Procedure (gets exclusive lock)
  procedure Get_State (The_State : out Command_Protector_Enums.Armed_State.E;
                       The_Timeout : out Packed_Arm_Timeout.Arm_Timeout_Type);
  ```

**No other specification issues found.** The private data is well-initialized with safe defaults (Unarmed, timeout = 0).

---

## 2. Package Implementation Review

### Issue 2.1 — `Arm` does not validate zero timeout

- **File:** `arm_state.adb`, lines 17–22
- **Severity:** Medium
- **Code:**
  ```ada
  procedure Arm (New_Timeout : in Packed_Arm_Timeout.Arm_Timeout_Type) is
  begin
     State := Command_Protector_Enums.Armed_State.Armed;
     Timeout := New_Timeout;
  end Arm;
  ```
- **Explanation:** If `New_Timeout` is 0 (`Arm_Timeout_Type'First`), the system transitions to `Armed` but with a zero timeout. On the next `Decrement_Timeout` call, the `Timeout > Arm_Timeout_Type'First` check is false, so the system stays `Armed` indefinitely — the timeout never fires and the state never returns to `Unarmed` via timeout. In a safety-critical command protector, an armed state that never times out could allow a protected command to be executed long after the operator intended.
- **Suggested fix:**
  ```ada
  procedure Arm (New_Timeout : in Packed_Arm_Timeout.Arm_Timeout_Type) is
  begin
     -- Only arm if timeout is positive; a zero timeout is meaningless.
     if New_Timeout > Packed_Arm_Timeout.Arm_Timeout_Type'First then
        State := Command_Protector_Enums.Armed_State.Armed;
        Timeout := New_Timeout;
     end if;
  end Arm;
  ```
  Alternatively, document that the caller is responsible for ensuring a non-zero timeout, and/or raise an event.

### Issue 2.2 — `Decrement_Timeout` silently does nothing when Armed with zero timeout

- **File:** `arm_state.adb`, lines 39–62
- **Severity:** Medium (related to 2.1)
- **Code:**
  ```ada
  when Armed =>
     if Timeout > Arm_Timeout_Type'First then
        Timeout := @ - 1;
        if Timeout = Arm_Timeout_Type'First then
           State := Command_Protector_Enums.Armed_State.Unarmed;
           Timed_Out := True;
        end if;
     end if;
  ```
- **Explanation:** If the system is `Armed` and `Timeout` is already 0 (see Issue 2.1), this entire branch is skipped. The system reports `Timed_Out = False` and `New_State = Armed`, yet the timeout is 0. This is a stuck state that can only be exited via explicit `Unarm`. Combined with Issue 2.1, this creates a latent safety concern.
- **Suggested fix:** Add an `else` clause to handle the already-zero case:
  ```ada
  if Timeout > Arm_Timeout_Type'First then
     Timeout := @ - 1;
     if Timeout = Arm_Timeout_Type'First then
        State := Command_Protector_Enums.Armed_State.Unarmed;
        Timed_Out := True;
     end if;
  else
     -- Armed with zero timeout — force unarm as defensive measure
     State := Command_Protector_Enums.Armed_State.Unarmed;
     Timed_Out := True;
  end if;
  ```

### Issue 2.3 — `Unarm` assumes `Arm_Timeout_Type'First` is zero

- **File:** `arm_state.adb`, line 31
- **Severity:** Low
- **Code:**
  ```ada
  Timeout := Arm_Timeout_Type'First;
  ```
- **Explanation:** The comment says "Set the timeout to zero" but uses `'First`. Currently `Arm_Timeout_Type` is `0 .. 255` so `'First = 0`. If the range ever changes to start at a non-zero value, this would be incorrect. Using a named constant (e.g., `Arm_Timeout_Zero`) or an explicit literal `0` would be more robust, though the risk is low given the YAML-defined type.

**No other implementation issues found.** The `case` statement covers all `Armed_State` literals explicitly, and the decrement uses `@ - 1` only after confirming the value is positive, preventing underflow.

---

## 3. Model Review

No YAML models are present within the `arm_state/` directory itself. The dependent types (`Packed_Arm_Timeout`, `Command_Protector_Enums`) are defined in `../types/` and are outside the scope of this package review. They were consulted for context only.

---

## 4. Unit Test Review

**No unit tests found.** There is no `test/` subdirectory under `arm_state/`.

### Issue 4.1 — Missing unit tests

- **Severity:** High
- **Explanation:** This is a safety-critical protected object managing arm/disarm state with timeout logic. The following scenarios should be tested:
  1. Initial state is `Unarmed` with timeout = 0.
  2. `Arm` transitions to `Armed` with correct timeout.
  3. `Unarm` transitions to `Unarmed` and resets timeout.
  4. `Decrement_Timeout` counts down correctly and transitions to `Unarmed` at zero.
  5. `Decrement_Timeout` when already `Unarmed` is a no-op.
  6. **Edge case:** `Arm` with timeout = 0 (exposes Issue 2.1).
  7. **Edge case:** `Arm` with timeout = 1 (immediate timeout on first decrement).
  8. **Edge case:** `Arm` with timeout = 255 (`Arm_Timeout_Type'Last`).
  9. Re-arming while already armed resets the timeout.

---

## 5. Summary — Top 5 Highest-Severity Findings

| # | Severity | Issue | Location |
|---|----------|-------|----------|
| 1 | **High** | `Get_State` is a protected function with `out` parameter — misleading concurrency semantics | `arm_state.ads:12` |
| 2 | **High** | No unit tests for safety-critical arm/timeout logic | `arm_state/` (missing test dir) |
| 3 | **Medium** | `Arm(0)` creates a stuck Armed state that never times out | `arm_state.adb:17–22` |
| 4 | **Medium** | `Decrement_Timeout` silently ignores Armed state with zero timeout | `arm_state.adb:46–55` |
| 5 | **Low** | `Unarm` assumes `Arm_Timeout_Type'First = 0` — fragile if type range changes | `arm_state.adb:31` |

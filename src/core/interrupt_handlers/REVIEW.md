# Code Review: `Interrupt_Handlers` Package

**Reviewed:** 2026-03-01
**Files:** `interrupt_handlers.ads`, `interrupt_handlers.adb`

## Summary

Generic Ada package providing two protected-object patterns for interrupt handling: `Task_Signal` (blocking wait/signal) and `Interrupt_Counter` (non-blocking poll/reset). A user-supplied generic type `T` and custom interrupt procedure are threaded through both, giving flexibility for arbitrary interrupt-handler payloads.

## Strengths

- **Clean generic design.** The `T` parameter + `Interrupt_Procedure_Type` callback gives maximum reuse without sacrificing type safety.
- **Saturation-safe counter.** `Interrupt_Counter.Handler` caps at `Natural'Last` instead of overflowing — good defensive practice.
- **Null procedure convenience.** `Null_Interrupt_Procedure` / its access value let callers opt out of custom handler logic cleanly.
- **Well-documented spec.** Top-level package comment and inline comments clearly explain intent and usage patterns.
- **Correct barrier usage.** `Task_Signal.Wait` uses an entry barrier on `Signaled`, and resets it atomically on exit — textbook signal/wait.

## Issues & Recommendations

### Medium

1. **`Internal_Data` is uninitialized.** Both protected types declare `Internal_Data : T;` with no default. If `T` has no implicit default, `Get_Data` or `Wait` can return garbage before `Set_Data` or the first interrupt. Consider requiring an `Initial_Data` discriminant or a default value generic formal.

2. **`Task_Signal` drops interrupts while a waiter is processing.** If an interrupt fires between `Wait` returning and the task calling `Wait` again, `Signaled` was reset to `False` inside the entry body but the new interrupt sets it to `True` — that's fine. However if *two* interrupts fire before re-entry, one is silently lost. Document this limitation or add a count.

3. **Counter saturation is silent.** When `Count = Natural'Last`, further interrupts are counted via the custom procedure but the count is clamped. There's no way for the caller to know interrupts were lost. Consider a saturated flag or use a wider type.

### Low

4. **`Null_Interrupt_Procedure_Access` is a variable, not a constant.** It could be accidentally overwritten. Declare as:
   ```ada
   Null_Interrupt_Procedure_Access : constant Interrupt_Procedure_Type := Null_Interrupt_Procedure'Access;
   ```

5. **No `pragma Preelaborate` or `Pure`.** If the framework supports it, adding an elaboration pragma would tighten usage constraints and catch elaboration-order issues earlier. (May not be feasible due to `Ada.Interrupts` dependency.)

6. **`Get_Count` is a function (no side effects) but `Get_Count_And_Reset` is a procedure.** Consistent — just noting that callers who only want to peek at the count can accidentally miss the reset variant. Naming is clear enough; no action needed.

## Verdict

Solid, well-structured interrupt-handling abstraction. The main actionable items are initializing `Internal_Data` (#1) and making `Null_Interrupt_Procedure_Access` a constant (#4). The rest are hardening suggestions for high-reliability contexts.

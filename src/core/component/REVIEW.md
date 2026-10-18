# Code Review: `Component` (Core Framework Package)

**Reviewed:** 2026-03-01  
**Files:** `component.ads`, `component.adb`

## Summary

This is the base abstract type for all Adamant components. It defines `Core_Instance` (the root tagged type), an `Active_Task` for cyclic execution, queue-usage introspection stubs, and a `Set_Up` hook. The package is small and well-scoped.

**Overall assessment: Solid design, a few items worth examining.**

---

## Findings

### 1. `Active_Task` — Loop Condition Appears Inverted (High)

```ada
Ada.Synchronous_Task_Control.Suspend_Until_True (Signal.all);
while not Ada.Synchronous_Task_Control.Current_State (Signal.all) loop
   Class_Self.all.Cycle;
   ...
end loop;
```

`Suspend_Until_True` blocks until the signal is set to `True`, then **atomically resets it to `False`**. So after the suspend, `Current_State` returns `False`, and the `while not False` → `while True` loop runs indefinitely. This *works* — but only because the signal is never set again (the loop never terminates normally).

**Concern:** If the intent is for the signal to also serve as a *shutdown* mechanism (set it to `True` again to stop the loop), the current logic is correct. But:
- The idiom is non-obvious; a comment explaining termination semantics would help.
- There is no graceful shutdown path visible — once running, the task loops forever unless aborted or the signal is externally toggled. If the framework relies on task abort for shutdown, this is fine but worth documenting.
- If `Signal` is set to `True` from *outside* between `Cycle` calls, the task exits silently with no cleanup hook.

**Recommendation:** Add a comment documenting the intended shutdown protocol. Consider whether a `Tear_Down` or `Finalize` null procedure (like `Set_Up`) would be useful.

### 2. Queue Introspection via `pragma Assert` (Medium)

`Get_Queue_Current_Percent_Used` and `Get_Queue_Maximum_Percent_Used` fail with `pragma Assert (False, ...)`. This means:

- If assertions are **disabled** at compile time (common in release builds), the assert is a no-op, the function falls through, and returns `Byte'Last` (255 / 100% — a misleading "queue full" signal).
- The GNATSAS annotation suppresses the static analysis warning, but doesn't address runtime behavior with assertions off.

**Recommendation:** Use `raise Program_Error with "..."` instead of `pragma Assert (False, ...)` to guarantee failure regardless of assertion policy. Alternatively, if `Byte'Last` is the intended safe fallback for production, document that explicitly and remove the assert.

### 3. Thread Safety of Queue Functions (Medium)

`Get_Queue_Current_Percent_Used` and `Get_Queue_Maximum_Percent_Used` take `in out` mode on `Self`. The spec comment notes these are used by a queue monitor component as a "backdoor convenience to bypass the connector system." When overridden by a queued component:

- The overriding implementation must be thread-safe since it will be called from the queue monitor's task context while the component's own task may be concurrently accessing the queue.
- This contract is implicit — there's no documentation or language-level enforcement.

**Recommendation:** Document the thread-safety requirement in the spec comments for these functions. Consider whether `in` mode (with synchronized internal access) would better express the intent.

### 4. `Class_Self` Dispatching in Task (Low)

`Class_Self.all.Cycle` performs a dispatching call within the task body. This is correct and idiomatic for the pattern. However:

- If `Cycle` raises an unhandled exception, the task silently terminates (Ada default behavior for unhandled task exceptions). There's no exception handler or logging.
- `Task_Util.Update_Secondary_Stack_Usage` is called after `Cycle` — if `Cycle` raises, this update is skipped (minor, since the task is dead anyway).

**Recommendation:** Consider adding an exception handler in the task loop that logs the exception before re-raising or terminating, to aid debugging in embedded/flight contexts.

### 5. Documentation (Low)

- The package-level comment is minimal. A brief description of the component lifecycle (`Init → Set_Up → Cycle loop`) and the passive-vs-active distinction would help newcomers.
- `Component_List` / `Component_List_Access` are declared but their usage context isn't documented.

---

## Positive Notes

- **Clean OOP design:** Abstract tagged type with dispatching `Cycle` is a textbook Ada pattern for framework extensibility.
- **`Set_Up` as `is null`:** Elegant — subclasses override only if needed, no boilerplate.
- **Task discriminants:** Exposing priority, stack size, and secondary stack size as discriminants gives the assembly full control. Good for embedded/real-time.
- **`limited` tagged type:** Correctly prevents copying of component instances.
- **GNATSAS annotations:** Shows attention to static analysis hygiene.

---

## Summary Table

| # | Finding | Severity | Category |
|---|---------|----------|----------|
| 1 | Task loop termination semantics unclear | High | Documentation / Correctness |
| 2 | `pragma Assert(False)` disabled in release | Medium | Edge Case / Correctness |
| 3 | Thread-safety contract for queue functions undocumented | Medium | Thread Safety |
| 4 | No exception handler in task loop | Low | Robustness |
| 5 | Minimal package/lifecycle documentation | Low | Documentation |

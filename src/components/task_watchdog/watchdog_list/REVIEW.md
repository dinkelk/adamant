# Code Review: watchdog_list

**Package:** `src/components/task_watchdog/watchdog_list`
**Language:** Ada (`.ads` / `.adb`)
**Files reviewed:** `watchdog_list.ads`, `watchdog_list.adb`, `.all_path`
**Date:** 2026-03-01

---

## Summary

`Watchdog_List` is a tagged limited type that manages an array of task-watchdog entries. Each entry tracks a connector's missed-pet count against a configurable limit and returns a status (`Petting`, `Warn_Failure`, `Fault_Failure`, `Repeat_Failure`, or `Disable`) when checked. The package supports runtime reconfiguration of limits and actions.

## Strengths

1. **Clear API** — The spec exposes a small, well-named set of procedures/functions with obvious intent.
2. **Bounded increment** — `Missed_Pet_Count` is only incremented up to `Missed_Pet_Limit`, preventing overflow on repeated failures.
3. **Initialization assertion** — `Init` asserts the list is non-empty, catching misconfiguration early.
4. **Separation of first-failure vs. repeat** — Distinguishing the exact-threshold tick (`Warn_Failure`/`Fault_Failure`) from subsequent ticks (`Repeat_Failure`) is a clean pattern for one-shot event emission.

## Issues

### High

| # | Issue | Location | Detail |
|---|-------|----------|--------|
| 1 | **Stale body comment** | `watchdog_list.adb` line 2 | Comment says *"generic, unprotected binary tree for holding apids and filter factors for the downsampler component"* — this is clearly copy-pasted from another package and is misleading. |
| 2 | **No thread safety** | Entire package | The type is `tagged limited` but not `protected`. Multiple tasks calling `Check_Watchdog_Pets` (which reads **and writes** `Missed_Pet_Count`) and `Reset_Pet_Count` concurrently will race. The spec comment mentions "protected fashion" but nothing enforces it. If the caller (Task_Watchdog component) serializes access externally, this should be documented prominently. |
| 3 | **Mutating through `in` mode parameter** | `Reset_Pet_Count`, `Check_Watchdog_Pets` | `Self` is declared `in Instance` yet the body writes through the access type (`Self.Task_Watchdog_Pet_Connections(…) := …`). This is technically legal in Ada (the pointer is not changed, only the pointed-to data), but it is semantically deceptive — readers expect `in` to be read-only. Consider using `in out` to signal mutation honestly. |

### Medium

| # | Issue | Location | Detail |
|---|-------|----------|--------|
| 4 | **Heap allocation without deallocation** | `Init` | `new Task_Watchdog_Pet_List` is allocated but never freed. Calling `Init` twice leaks the first allocation. Consider adding a `Destroy`/`Finalize` procedure or guarding against re-init. |
| 5 | **`pragma Assert (False)` in dead branch** | `Check_Watchdog_Pets`, `Disabled` case | A `pragma Assert` compiles away when assertions are off. In production this would silently fall through. Use `raise Program_Error` instead for truly unreachable code. |
| 6 | **Index range assumption** | `Init` | The new array is allocated with range `First .. First + Length - 1` of the *init list's* indices, which works, but if `Connector_Index_Type` is a constrained subtype starting at a value other than the init list's first index, callers could be surprised. A comment clarifying the expected indexing convention would help. |

### Low / Style

| # | Issue | Detail |
|---|-------|--------|
| 7 | **`@` target name (Ada 2022)** | `Missed_Pet_Count := @ + 1` uses Ada 2022 syntax. Fine if the project baseline is Ada 2022, but worth noting for portability. |
| 8 | **No range check on `Index` parameter** | All public subprograms accept a bare `Connector_Index_Type` — an out-of-range index will raise `Constraint_Error` from the array access. A precondition or explicit check with a clearer error message would improve debuggability. |
| 9 | **Unused `.all_path` file** | File exists but is empty. Confirm whether the build system requires it or if it's stale. |

## Recommendations

1. **Fix the copy-paste comment** in the body — trivial but important for maintainability.
2. **Document the concurrency contract** — either make the type protected or add a clear comment/precondition that external serialization is required.
3. **Switch `in` → `in out`** on mutating procedures for honesty.
4. **Replace `pragma Assert(False)`** with `raise Program_Error with "unreachable";`
5. **Add a `Destroy` or re-init guard** to prevent memory leaks.

# Code Review: `src/core/task` — Core Task Abstraction Layer

**Date:** 2026-03-01
**Reviewer:** Claude (automated review)
**Scope:** `task/`, `task/bareboard/`, `task/linux/`

---

## Overview

This package provides Adamant's task abstraction layer: task metadata types, inter-task synchronization primitives, stack initialization/monitoring utilities, and platform-specific adapters for bareboard and Linux targets.

**Files reviewed:**

| File | Purpose |
|------|---------|
| `task_types.ads` | Core data types for task metadata |
| `task_synchronization.ads/adb` | Protected-object synchronization primitives |
| `task_util.ads/adb` | Task initialization & stack painting |
| `secondary_stack_util.ads` | Platform-abstract secondary stack query |
| `bareboard/stack_margin.ads` | Stack margin constant (from `Configuration`) |
| `bareboard/secondary_stack_util.adb` | Bareboard impl via `System.Secondary_Stack` |
| `linux/stack_margin.ads` | Stack margin constant (hardcoded 12 KB) |
| `linux/secondary_stack_util.adb` | Linux impl via `GNAT.Secondary_Stack_Info` |

---

## Package-by-Package Analysis

### 1. `task_types` (Shared)

Clean record type capturing everything needed for runtime task monitoring: Adamant task number, Ada runtime ID, priority, stack address/size, and secondary stack usage.

**Strengths:**
- Well-documented fields.
- `Task_Info_List` with `not null` access constraint prevents null entries.

**Observations:**
- `Task_Number` upper bound of 65,535 is generous; unlikely to be a problem.
- `Priority` has no default initializer (unlike other fields). Intentional, since there's no sensible default, but worth noting—uninitialized use would be caught by Ada's type system only if the compiler enforces it.

### 2. `task_synchronization` (Shared)

Three progressively richer protected objects:

1. **`Wait_Release_Object`** — Simple gate: one task waits, another releases.
2. **`Wait_Release_Timeout_Object`** — Adds timeout signaling and `Is_Waiting` query.
3. **`Wait_Release_Timeout_Counter_Object`** — Adds a periodic counter-based timeout (three-task pattern).

**Strengths:**
- Clean, well-documented layered design. Each object builds logically on the previous one.
- `Reset` on every object allows reuse without re-creation.
- `Timeout` only fires if a task is actually waiting—prevents spurious releases.
- Auto-reset of `Do_Release` inside `Wait` entry bodies prevents stale signals.

**Observations:**
- All three objects support only **single-waiter** semantics (entry barrier is a simple boolean). Multiple concurrent waiters on the same object would have undefined ordering. This appears intentional for Adamant's component model but is not explicitly documented as a constraint.
- `Wait_Release_Timeout_Counter_Object.Increment_Timeout_If_Waiting`: the `>=` comparison means a `Timeout_Limit` of 0 triggers immediately on the first increment. This is correct but could surprise users—worth a comment or assertion.
- No inheritance/tagged-type relationship between the three objects. Given they're protected types, this is an Ada limitation, not a design flaw.

### 3. `task_util` (Shared)

Initializes task metadata and paints the stack with `0xCC` bytes for high-water-mark monitoring.

**Strengths:**
- Defensive assertions: minimum 2 KB stack, stack size > margin.
- Stack painting via `Set_Stack_Pattern` is a proven embedded technique.
- `Volatile` on the stack array prevents the compiler from optimizing away the writes.
- GNATSAS annotation on the intentional address escape—good practice.

**Observations:**
- **Assumption: stack grows downward.** Asserted at runtime (`Stack_Start'Address - Stack_End_Address >= 0`), which is correct for ARM and x86, but worth documenting as a platform constraint.
- `Stack_Start` is `Unsigned_32` initialized to `0xDDDDDDDD`—its address is used as the stack top reference. Clever, but subtle. A comment explaining *why* this variable's address approximates the stack top would help future readers.
- `Secondary_Stack_Address` is always set to `Null_Address` with a "currently unused" comment. If it's never populated, consider whether the field should exist in `Task_Info` or be gated behind a feature flag.

### 4. `secondary_stack_util` (Platform-Split)

Thin abstraction over GNAT-internal secondary stack introspection.

| Platform | Implementation |
|----------|---------------|
| Bareboard | `System.Secondary_Stack.SS_Get_Max` (internal GNAT unit, warnings suppressed) |
| Linux | `GNAT.Secondary_Stack_Info.SS_Get_Max` (public GNAT library) |

**Observations:**
- Bareboard version has an explicit pragma comment acknowledging version-dependence—good.
- Both convert to `Natural` without range checking. `SS_Get_Max` returns `Long_Long_Integer` (bareboard) or similar. If the value exceeds `Natural'Last` (~2 GB), this would raise `Constraint_Error`. Extremely unlikely in practice but technically unbounded.

### 5. `stack_margin` (Platform-Split)

| Platform | Value | Source |
|----------|-------|--------|
| Bareboard | `Configuration.Stack_Margin` | External config |
| Linux | `12_288` (12 KB) | Hardcoded |

**Observations:**
- Linux margin is hardcoded with a comment explaining the 10 KB+ empirical threshold. The 12 KB value provides 20% headroom—reasonable.
- Bareboard delegates to `Configuration`, allowing per-target tuning. Good separation of concerns.

---

## Architecture Assessment

**Platform abstraction pattern:** The spec (`secondary_stack_util.ads`, shared) is in the parent directory; platform bodies live in `bareboard/` and `linux/`. The build system selects the correct body. Clean and idiomatic for Ada cross-platform work.

**Design philosophy:** Minimal, low-overhead, zero-allocation. Everything is statically sized or stack-allocated. No heap usage. Appropriate for flight/embedded software.

---

## Summary of Findings

| # | Severity | Finding |
|---|----------|---------|
| 1 | **Low** | Single-waiter constraint on synchronization objects is implicit—should be documented |
| 2 | **Info** | `Timeout_Limit = 0` triggers immediate timeout on first increment—edge case worth a comment |
| 3 | **Info** | Stack-grows-down assumption is asserted but not documented as a platform requirement |
| 4 | **Info** | `Secondary_Stack_Address` field is always `Null_Address`—consider removing or documenting future intent |
| 5 | **Info** | `Priority` field in `Task_Info` lacks a default initializer (all other fields have one) |

## Verdict

**Well-designed, clean, production-quality code.** The task abstraction layer is minimal and focused. Synchronization primitives are correct and well-structured. Platform split is clean. The few observations above are minor documentation/hardening suggestions, not defects.

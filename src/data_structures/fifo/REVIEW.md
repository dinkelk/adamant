# Code Review: Fifo & Heap Packages

## 1. Fifo Package

### Overview
Generic circular-buffer FIFO with dynamic allocation (`Init`/`Destroy` lifecycle). Clean, minimal API with status-returning `Push`/`Pop`/`Peek`.

### Strengths
- **Correct circular buffer**: `(Head + Count) mod Length` for push index, `(Head + 1) mod Length` for pop — textbook ring buffer.
- **Good API design**: Enum return types (`Push_Status`, `Pop_Status`) instead of exceptions for expected conditions (full/empty). Caller can't ignore the status since it's a function return.
- **High-water mark tracking** (`Max_Count`) — useful for runtime sizing analysis.
- **`Peek` reuse in `Pop`** avoids code duplication.
- **GNATSAS annotation** on `Peek` documents the intentional unset out-parameter on the `Empty` path.

### Issues

| Severity | Issue |
|----------|-------|
| **Medium** | `Clear` does not reset `Max_Count`. This is likely intentional (high-water mark survives clears) but is undocumented and could surprise users who expect `Clear` to fully reset state. |
| **Medium** | No null-check on `Self.Items` in any operation. Calling `Push`/`Pop`/`Is_Full`/`Get_Depth` before `Init` or after `Destroy` will raise `Constraint_Error` with no helpful message. A precondition or explicit check would improve debuggability. |
| **Low** | `Peek` leaves `Value` uninitialized on the `Empty` path. The pragma annotation acknowledges this, but callers must be careful not to read `Value` when `Empty` is returned. Consider defaulting `Value` to avoid any accidental use of uninitialized data in non-SPARK builds. |
| **Low** | `Instance` is `tagged` but not `limited`. Users could accidentally copy a FIFO, creating two instances sharing the same heap-allocated `Items` pointer (aliasing bug). Should be `tagged limited`. |
| **Nit** | Ada 2022 `@` syntax (`Self.Count := @ + 1`) is used — fine if the project baseline is Ada 2022, but worth noting for portability. |

### Test Coverage
Tests cover: init, fill, empty, peek-before-pop, wrap-around (double fill/empty cycle), clear, destroy. Reasonably thorough. Missing: boundary test with depth=1, max_count verification after clear.

---

## 2. Heap Package

### Overview
Generic stable max-heap with O(log n) push/pop. Stability ensured via an `Order` counter stamped on each inserted node. Well-documented header comments.

### Strengths
- **Stability guarantee**: The `Order` field plus tie-breaking in `Max` ensures FIFO ordering among equal-priority elements — a valuable property that many heap implementations lack.
- **Order reset on drain**: Resetting `Order` to 0 when the heap empties is good housekeeping against `Unsigned_32` rollover.
- **Defensive assertions**: Loop iteration bounds (`Max_Iter`), index validity checks throughout `Heapify` and `Push`.
- **Non-recursive `Heapify`**: Avoids stack growth concerns in embedded/safety-critical contexts.
- **Clean separation**: Comparison functions supplied as generic formals — flexible and type-safe.
- **`tagged limited`**: Correctly prevents copying (unlike `Fifo`).

### Issues

| Severity | Issue |
|----------|-------|
| **Medium** | `Order` rollover (`Unsigned_32`) is acknowledged but not handled. After 4 billion pushes without fully draining, the order wraps and stability breaks silently. For long-lived heaps, consider `Unsigned_64` or detecting the wrap. |
| **Medium** | `Clear` resets `Max_Count` to 0, but `Fifo.Clear` does not. The two packages have inconsistent semantics for the high-water mark on clear. Pick one convention. |
| **Low** | `Get_Right_Child_Index` doc comment says "left child" (copy-paste from `Get_Left_Child_Index`). |
| **Low** | `Push` comment says "The current element is less than the parent" but the logic is swapping when the new element is *greater* than the parent (bubbling up). The comment has the comparison direction inverted. |
| **Low** | No null-check on `Self.Tree` before access. Same pre-`Init` / post-`Destroy` vulnerability as Fifo. |
| **Nit** | `pragma Inline` on local subprograms (`Get_Parent_Index`, etc.) is applied old-style after the body. Ada 2012+ `with Inline => True` aspect (used elsewhere in the same file) is more consistent. |
| **Nit** | Test uses all identical elements for the push/pop cycle — good for stability testing but doesn't exercise heapify reordering on pop with diverse priorities in a single deep sequence. The "mixed priority" test at size=5 is adequate but small. |

### Test Coverage
Tests cover: init, empty pop, fill to capacity, reject on full, pop ordering, peek, priority ordering, same-priority FIFO ordering, mixed priorities, destroy/reset. Solid coverage for a unit test. Could benefit from: larger heap exercising deeper tree paths, interleaved push/pop sequences, and a stress test near `Unsigned_32` rollover.

---

## Cross-Cutting Observations

1. **Inconsistent `Clear` semantics**: Fifo preserves `Max_Count` across `Clear`; Heap resets it. Document or unify.
2. **`Safe_Deallocator` dependency**: Both use `Deallocate_If_Testing` — memory is only freed during testing. This is presumably an embedded-systems pattern (allocate once, never free in production). Fine, but worth a comment for newcomers.
3. **No thread safety**: Both are explicitly unprotected. Fifo's header says so; Heap's does not. Add a similar note to Heap.
4. **Fifo should be `limited`**: The missing `limited` on Fifo's `Instance` is the most actionable bug — it enables unsafe shallow copies of the internal access type.

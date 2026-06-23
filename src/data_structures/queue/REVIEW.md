# Data Structures Queue Family — Code Review

**Date:** 2026-03-01
**Packages reviewed:**
1. `queue` — Generic protected FIFO queue
2. `variable_queue` — Protected queue for variable-length byte arrays
3. `labeled_queue` — Variable queue with per-element labels
4. `priority_queue` — Unprotected heap-backed priority queue
5. `protected_priority_queue` — Protected wrapper over priority_queue
6. `protected_variables` — Common protected variable/counter patterns

---

## Architecture Overview

The packages form a coherent family of thread-safe data structures for the Adamant framework:

```
Queue (fixed-type FIFO)
Variable_Queue (variable-length byte FIFO, backed by Circular_Buffer)
  └─ Labeled_Queue (adds per-element label, backed by Circular_Buffer.Labeled_Queue)
Priority_Queue (unprotected, heap-backed, O(log n))
  └─ Protected_Priority_Queue (protected wrapper with blocking)
Protected_Variables (simple protected variable/counter patterns)
```

All queue types follow a consistent pattern:
- Non-blocking operations returning status enumerations
- Blocking (`_Block`) variants using `Ada.Synchronous_Task_Control.Suspension_Object`
- Typed generic push/pop/peek via address overlay optimization
- Variable-length typed variants accepting a `Serialized_Length` function
- Metadata/introspection (count, max count, percent used, high water mark)

---

## Strengths

### 1. Consistent, Defensive API Design
Every operation returns a fine-grained status enumeration rather than raising exceptions. Status types are per-function (e.g. `Push_Status`, `Pop_Type_Status`) so callers only handle relevant failure modes. This is excellent for safety-critical code.

### 2. Ravenscar Awareness
The blocking variants gracefully handle `Program_Error` from Ravenscar's single-waiter restriction on suspension objects, returning `Error` instead of propagating. Well-documented in comments.

### 3. Zero-Copy Optimization
The typed push/pop/peek functions use `Address` overlay to avoid double-copying data. The `pragma Warnings (Off/On, "overlay changes scalar storage order")` pairs are correctly scoped and well-justified in comments.

### 4. Suspension Object Signaling Inside Protected Objects
Releasing `Not_Empty`/`Not_Full` inside the protected body ensures priority-correct wake-up behavior. This is a subtle but important design choice, clearly documented.

### 5. Protected_Variables Package
Clean, minimal, useful. The periodic counter pattern (`Generic_Protected_Periodic_Counter`) with automatic modular wrap and period-based triggering is a nice abstraction for embedded systems.

### 6. Good Test Coverage
All packages have test drivers. The queue test exercises blocking paths (with harness coordination), fill/empty cycles, and metadata. Variable_queue and labeled_queue tests are substantial (364/433 lines).

---

## Issues & Recommendations

### Critical

#### C1. Priority_Queue.Get_Max_Count Returns Heap Capacity, Not Max Count
```ada
function Get_Max_Count (Self : in Instance) return Natural is
begin
   return Self.Priority_Heap.Get_Maximum_Size;  -- This is capacity, not high water mark
end Get_Max_Count;
```
The `Max_Count` field exists on the record but is **never updated** during Push. The `Get_Max_Count` function delegates to the heap's `Get_Maximum_Size` which likely returns *capacity* (the allocated size), not the historical maximum. Compare with `Queue` which uses `My_Fifo.Get_Max_Count`. The field `Self.Max_Count` is only reset in `Clear` but never written during `Push`.

**Fix:** Update `Max_Count` in `Push` after a successful heap insertion:
```ada
if Self.Get_Count > Self.Max_Count then
   Self.Max_Count := Self.Get_Count;
end if;
```
Then return `Self.Max_Count` from `Get_Max_Count`. Also need to verify what `Priority_Heap_Package.Get_Maximum_Size` actually returns.

#### C2. Priority_Queue.Pop Calls Return_Index_To_Pool Before Pop
```ada
-- Return storage index. This needs to be done before the pop in order
-- to not invalidate the assertions made within.
Self.Return_Index_To_Pool (Element.Queue_Buffer_Index);
-- Ok, now pop the element off the heap.
declare
   Ignore : Heap_Element;
   Ret2 : constant Boolean := Self.Priority_Heap.Pop (Ignore);
```
The comment says this ordering is intentional for assertion validity, but it means the index is "returned" while the element conceptually still exists on the heap. If `Priority_Heap.Pop` were to fail (shouldn't after a successful peek, but defensively), the index pool would be corrupted. The data is still safely copied from `Self.Queue.all(Element.Queue_Buffer_Index)` after the pop, so it works in practice, but the ordering is fragile.

### Moderate

#### M1. Variable_Queue/Labeled_Queue Metadata Functions Take `in out` Mode Unnecessarily
```ada
function Num_Bytes_Free (Self : in out Instance) return Natural
```
All metadata query functions on `Variable_Queue` and `Labeled_Queue` use `in out` mode for `Self`, even though they only read data. This prevents calling them on constant references. The `Queue` and `Priority_Queue` packages correctly use `in` mode. This appears to be because Ada protected functions (read-only) are accessed through a protected *object* which requires a variable reference, but the outer tagged-type wrapper could still use `in` if the protected type were accessed differently.

**Impact:** Can't query metadata from a constant view of the queue. Inconsistent with `Queue` and `Priority_Queue`.

#### M2. Massive Code Duplication Between Variable_Queue and Labeled_Queue
`Labeled_Queue` is essentially a copy-paste of `Variable_Queue` with an added `Label` parameter threaded through every function. The body implementations are nearly identical. This creates a maintenance burden — any bug fix must be applied in both places.

**Recommendation:** Consider whether `Labeled_Queue` could be implemented as a thin wrapper around `Variable_Queue` that prepends the label bytes to each element, or use a shared internal generic.

#### M3. Massive Code Duplication in Typed Generic Functions
The `Push_Type`, `Push_Type_Block`, `Peek_Type`, `Peek_Type_Block`, `Pop_Type`, `Pop_Type_Block` and their variable-length counterparts are nearly identical across `Variable_Queue`, `Labeled_Queue`, and `Protected_Priority_Queue`. Each is ~15-20 lines of boilerplate with the same overlay pattern. This is repeated 8-12 times per package.

#### M4. Protected_Priority_Queue Has No Peek_Type Generic Functions
Unlike `Variable_Queue` and `Labeled_Queue` which provide typed peek functions, `Protected_Priority_Queue` only offers `Peek_Length` (priority + byte count) with no typed peek. This is an asymmetry — there's `Pop_Type` but no `Peek_Type`.

#### M5. Priority_Queue.Num_Bytes_* Assumes Uniform Element Sizes
```ada
function Num_Bytes_Used (Self : in Instance) return Natural is
begin
   return Self.Priority_Heap.Get_Size * Self.Queue.all (Self.Queue.all'First)'Length;
end Num_Bytes_Used;
```
This multiplies count × slot size, which reports *allocated* bytes, not *used* bytes (since elements can be smaller than the slot). The comment on `Num_Bytes_Free` in `Protected_Priority_Queue` says "this should be used as information only" which partially mitigates this, but it could mislead users who compare against actual data sizes.

### Minor

#### m1. Typo in Labeled_Queue Spec Comment
```ada
-- peaking of variable sized byte arrays
```
Should be "peeking".

#### m2. Typo in Labeled_Queue Status Comment
```ada
-- so the called only has to handle
```
Should be "caller".

#### m3. Queue Test Has Commented-Out Ravenscar Blocking Tests
The blocking error path tests (`Push_Error`, `Pop_Error`) are commented out because they require Ravenscar + GDB. This means the `Error` return paths of `Push_Block`/`Pop_Block`/`Peek_Block` are never tested in automated runs.

#### m4. No Protected_Variables Tests
There is no `test/` directory under `protected_variables/`. The patterns are simple enough that correctness is fairly obvious, but formal tests would catch edge cases (e.g., `Increment_Count` near modular overflow, `Is_Count_At_Period` when period=1 or count=0).

#### m5. Generic_Protected_Counter_Decrement Uses `range <>` But Comment Says "modular type"
```ada
-- A generic counter whose members are set/fetched/incremented in a thread safe way.
generic
   -- Any modular type
   type T is range <>;
```
The comment says "modular type" but `range <>` is a signed integer type. The decrement makes more sense with signed integers (avoiding modular underflow), but the comment is misleading.

#### m6. Protected_Periodic_Counter.Increment_Count Silently No-ops When Period=0
```ada
procedure Increment_Count (To_Add : in T := 1) is
begin
   if Period > 0 then
      Count := (@ + To_Add) mod Period;
   end if;
end Increment_Count;
```
If `Period = 0`, the count is never incremented. This is arguably correct (disabled counter), but there's no documentation explaining this behavior.

#### m7. Priority_Queue Exception Handlers in Percent_Used Are Too Broad
```ada
exception
   when others =>
      return 100;
```
Catching all exceptions to return 100% is defensive but could mask real bugs. A `Constraint_Error` handler would be more precise.

---

## Summary

| Severity | Count | Key Theme |
|----------|-------|-----------|
| Critical | 2 | Max count tracking bug in priority_queue; fragile pop ordering |
| Moderate | 5 | Code duplication; `in out` mode inconsistency; missing peek generics |
| Minor | 7 | Typos, missing tests, comment inaccuracies |

**Overall assessment:** Well-engineered, safety-conscious queue family with good Ravenscar support and clear documentation. The main concerns are the `Priority_Queue.Get_Max_Count` bug (C1), significant code duplication across the variable-length queue variants, and inconsistent parameter modes. The `Protected_Variables` package is clean and useful. All packages would benefit from the `protected_variables` getting a test suite.

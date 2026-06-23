# Code Review: circular_buffer & protected_circular_buffer

**Date:** 2026-03-01
**Packages reviewed:**
- `Circular_Buffer` (spec, body, `Labeled_Queue` child)
- `Protected_Circular_Buffer` (spec, body)
- Tests: `test_circular/`, `test_queue/`, `test_labeled_queue/`

---

## Architecture Summary

`Circular_Buffer` provides a layered inheritance hierarchy:

```
Base (tagged private) — raw byte ring buffer
├── Circular — exposes push/pop/peek + overwrite + Make_Full
└── Queue_Base — adds item count tracking + length-prefixed elements
    ├── Queue — variable-length byte-array queue
    └── Labeled_Queue.Instance (generic child) — queue with per-element label
```

`Protected_Circular_Buffer` wraps `Circular_Buffer.Circular` in an Ada protected object for thread safety, exposing push/pop/peek plus generic typed-push helpers.

---

## Strengths

1. **Clean layered design.** Base consolidates shared buffer logic; derived types add only the behavior they need. Empty `null record` extensions with method additions are idiomatic Ada OOP.

2. **Dual initialization modes.** Both heap allocation (`Init(Size)`) and externally-owned memory (`Init(Bytes)`) are supported, with `Allocated` flag controlling deallocation. Good for embedded targets with static memory pools.

3. **Overwrite support.** The circular buffer's `Overwrite` parameter on `Push` correctly advances `Head` when old data is displaced — essential for telemetry/logging ring buffers.

4. **Serialization overlay optimization.** Using `with Import, Convention => Ada, Address => X'Address` to overlay byte arrays on typed variables avoids double copies for length/label serialization. Effective for performance-critical embedded code.

5. **Dump functions.** `Dump`, `Dump_Newest`, `Dump_Oldest`, `Dump_Memory` returning a 2-element `Pointer_Dump` array (to handle wrap-around) is a pragmatic API for inspection without copying.

6. **Thorough test coverage.** Tests exercise empty operations, zero-length arrays, full buffers, rollovers, multiple rollovers, overwrites, dump functions, make-full, peek offsets, and labeled queue label/length correctness. Edge cases are well-covered.

7. **Metadata tracking.** High-water-mark tracking (`Max_Count`, `Max_Num_Bytes_Used`, `Max_Percent_Used`) is useful for runtime diagnostics in embedded systems.

---

## Issues

### High Severity

**H1. `Peek` with large `Offset` can index out of bounds.**
In `Base.Peek`, `Current_Head` is computed as `Self.Head + Offset` without modular reduction. When `Offset` causes `Current_Head > Self.Bytes'Last`, the subsequent array indexing (`Self.Bytes(Current_Head .. End_Index)`) will raise `Constraint_Error`. The wrap-around recovery path (the `if Num_Bytes_To_Copy < Num_Bytes_Returned` branch) handles some cases via negative `Num_Bytes_To_Copy`, but this relies on `Current_Head` being usable as an index, which it isn't when it exceeds `Self.Bytes'Last`.

This is partially masked because `Queue_Base.Peek_Bytes` and `Queue.Peek` only call `Base.Peek` with offsets that fit within `Count`, but `Circular.Peek` exposes the raw offset to callers.

*Recommendation:* Apply `mod Self.Bytes'Length` to `Current_Head` and handle the two-part wrap-around copy explicitly (as `Push` already does).

**H2. `Do_Pop` allocates a throwaway buffer on the stack.**
```ada
Ignore_Bytes : Basic_Types.Byte_Array (0 .. Bytes_To_Pop - 1);
```
This allocates up to the entire buffer size on the stack just to discard the bytes. For large buffers this risks stack overflow.

*Recommendation:* Implement a dedicated `Advance_Head` procedure that adjusts `Head` and `Count` without copying data.

**H3. Protected_Circular_Buffer `Peek` has incorrect parameter mode.**
```ada
function Peek (Bytes : out Basic_Types.Byte_Array; ...) return Pop_Status;
```
The protected function declares `Bytes` as `out`, but Ada protected functions cannot have `out` or `in out` parameters (they provide read-only access). This should not compile under strict Ada rules. If it does compile (GNAT extension/leniency), the semantics are suspect.

*Recommendation:* Change `Peek` to a protected procedure with `out` parameters, consistent with `Push` and `Pop` which are already procedures.

### Medium Severity

**M1. `Max_Count` not reset on `Clear`.**
`Base.Clear` resets `Head` and `Count` but not `Max_Count`. `Queue_Base.Clear` resets `Item_Count` but not `Item_Max_Count`. This means the high-water mark persists across clears, which may be intentional (lifetime HWM) but is undocumented and could confuse users who expect `Clear` to fully reset state.

*Recommendation:* Document the behavior explicitly, or add a `Reset_Statistics` procedure.

**M2. `Destroy` calls `Clear` but doesn't null the pointer when not `Allocated`.**
After `Destroy`, `Self.Bytes` may point to freed or external memory. Subsequent accesses (e.g., `Is_Full`, `Num_Bytes_Total`) would dereference a potentially dangling pointer.

*Recommendation:* Set `Self.Bytes := null` in `Destroy` unconditionally, and add null checks to accessors (some like `Current_Percent_Used` already check, but most don't).

**M3. `Protected_Circular_Buffer` only wraps `Circular`, not `Queue` or `Labeled_Queue`.**
There is no thread-safe queue variant. Users needing a protected queue must build their own wrapper.

*Recommendation:* Consider adding `Protected_Queue` and `Protected_Labeled_Queue`, or document that users should wrap at a higher level.

**M4. Integer overflow in `Current_Percent_Used` / `Max_Percent_Used`.**
`(Self.Count * 100)` can overflow `Integer` when `Count` exceeds ~21 million. The `exception when others => return 100` catch-all masks this, but silent exception handling is fragile and could hide real bugs.

*Recommendation:* Use `Long_Integer` or `Interfaces.Unsigned_64` for the multiplication, or compute as `Count / (Length / 100)` to avoid overflow.

**M5. `Push_Type` uses `T'Object_Size` which may include padding.**
`T'Object_Size / Byte'Object_Size` computes the in-memory size including padding, not the logical serialized size. For types with representation clauses this is likely correct, but for unpacked records it may push garbage padding bytes onto the buffer.

*Recommendation:* Document that `T` must be a packed/representation-claused type, or use `T'Size` with appropriate rounding.

### Low Severity

**L1. `Safe_Deallocator.Deallocate_If_Testing` only frees in testing.**
The name implies memory is only freed during testing. In production, heap-allocated buffers will leak on `Destroy`. This is presumably intentional for embedded targets (no deallocation), but could surprise general-purpose users.

**L2. Redundant status translation in `Protected_Circular_Buffer`.**
The protected body manually cases on each status value to translate between `Circular_Buffer.Push_Status` and `Protected_Circular_Buffer.Push_Status`. Since the enumerations are identical (`Success`, `Too_Full` / `Success`, `Empty`), a simple unchecked conversion or shared type would be cleaner.

**L3. Test code has commented-out sections.**
`test_queue/test.adb` has a large commented-out block for heap queue testing. Either enable it or remove it.

**L4. No test for `Protected_Circular_Buffer`.**
There are no tests under `protected_circular_buffer/`. Thread-safety wrappers should have at least basic functional tests and ideally concurrent stress tests.

**L5. `Queue` test uses only externally-allocated memory.**
The heap-allocation path (`Init(Size)`) is commented out in `test_queue/test.adb`, so it has no test coverage.

---

## Minor Style / Documentation Notes

- The spec comments say "If not enough space remains on the internal buffer to **read** store" — should be "to store".
- `Push_Length` increments `Item_Count` before the data push. If the subsequent `Base.Push` were to fail (it can't by design, but defensively), the count would be wrong. Consider incrementing after both pushes succeed.
- `Peek_Bytes` silently returns 0 bytes when `Offset >= Num_Bytes_To_Read` rather than signaling an error. This is fine but worth documenting.
- The `Pointer_Dump` type is a fixed-size array of 2 — consider using a discriminated record or documenting that the second element is null when no wrap occurs.

---

## Summary

| Category | Count |
|----------|-------|
| High     | 3     |
| Medium   | 5     |
| Low      | 5     |

The core circular buffer is well-designed and thoroughly tested for its primary use case (embedded byte-level ring buffers). The main concerns are: potential index-out-of-bounds in `Peek` with large offsets (H1), wasteful stack allocation in `Do_Pop` (H2), and the protected buffer's `Peek` parameter mode (H3). The protected wrapper is thin and functional but lacks tests and queue-level variants.

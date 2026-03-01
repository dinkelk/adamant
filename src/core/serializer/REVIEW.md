# Code Review: `src/core/serializer`

**Date:** 2026-03-01  
**Reviewer:** Gus's AI assistant

---

## Overview

A family of generic Ada packages for converting arbitrary types to/from byte arrays and streams via address overlays. Four main packages plus a shared types package:

| Package | Purpose |
|---|---|
| `Serializer` | Fixed-size type ↔ `Byte_Array` via overlays |
| `Stream_Serializer` | Fixed-size type ↔ `Ada.Streams` |
| `Variable_Serializer` | Variable-length type ↔ `Byte_Array` (caller supplies length functions) |
| `Variable_Stream_Serializer` | Variable-length type ↔ `Ada.Streams` |
| `Serializer_Types` | Shared `Serialization_Status` enum |

## Strengths

1. **Clean generic design.** Each package is parameterized only on what it needs — `Variable_*` variants accept length-computation functions as formal parameters, keeping the core logic reusable.
2. **Good documentation.** The spec comments in `Serializer` and `Variable_Serializer` thoroughly explain overlay usage, performance trade-offs, and when to use checked vs. unchecked variants.
3. **Correct use of `Object_Size`.** The rationale for `Object_Size` over `Size` is documented with a GCC reference link — important for embedded targets.
4. **Scalar storage order handling.** The `pragma Warnings (Off/On, "overlay changes scalar storage order")` blocks are applied consistently with a clear justification comment.
5. **GNATSAS annotations.** False-positive suppression for validity checks on overlay-initialized variables is present where needed.
6. **Ravenscar-compatible.** The test uses `pragma Profile (Ravenscar)`, confirming the packages work under restricted tasking.

## Issues

### High

1. **`To_Byte_Array_Unchecked` function variant copies the *exact* serialized length, not `Dest'Length`.**  
   `serializer.adb` — the procedure `To_Byte_Array_Unchecked(Dest, Src)` does `Dest := Overlay`, which will raise `Constraint_Error` if `Dest'Length /= Serialized_Length`. The "unchecked" name implies it should handle mismatched sizes, but only the range-slicing variants (`From_Byte_Array_Unchecked`) actually do this. The `To_Byte_Array_Unchecked` procedure should slice into `Dest(Dest'First .. Dest'First + Serialized_Length - 1)` for consistency.

2. **`Variable_Serializer.To_Byte_Array` length check uses `'Last - 'First + 1` instead of `'Length`.**  
   The comment says this handles null arrays, but for a null `Basic_Types.Byte_Array` where `'Last < 'First`, the expression `Dest'Last - Dest'First + 1` can underflow (wraps in unsigned, or goes negative in signed Natural causing `Constraint_Error`). Using `Natural'Max(0, Dest'Last - Dest'First + 1)` or just `Dest'Length` (which Ada defines as 0 for null ranges) would be safer.

3. **`Variable_Stream_Serializer.Deserialize` ignores `Ada.Streams.Read` byte count.**  
   The `Ignore` out-parameter from `Ada.Streams.Read` is discarded both times. If the stream provides fewer bytes than requested (short read), the output will contain uninitialized overlay data. This is a potential correctness/safety issue in real stream scenarios (sockets, partial file reads).

### Medium

4. **`From_Byte_Array` function in `Serializer` leaves `To_Return` partially uninitialized on padded types.**  
   If `T` has padding bits (e.g., due to alignment), only the overlay bytes are written. The variable is stack-allocated and not zeroed first, so padding bytes are indeterminate. For embedded/safety-critical contexts, consider initializing `To_Return` to a default or zeroing the overlay first.

5. **`Stream_Serializer.Deserialize` also ignores the `Last` out-parameter from `Ada.Streams.Read`.**  
   Same short-read concern as #3 but for the fixed-size variant. At minimum, assert that `Ignore = expected_last`.

6. **`Variable_Stream_Serializer.Deserialize` instantiates `Stream_Serializer` inside `Serialize` on every call.**  
   The `package Static_Serializer is new Stream_Serializer(T)` inside `Serialize` is re-elaborated per call. Moving it to package body scope would be cleaner and avoids repeated generic instantiation overhead (though the compiler likely optimizes this away).

### Low

7. **Inconsistent naming.** `Serialized_Length` is a constant in `Serializer`/`Stream_Serializer` but a formal function in `Variable_*` packages. The `Variable_Serializer` formals are named `Serialized_Length_T` and `Serialized_Length_Byte_Array` while `Variable_Stream_Serializer` just uses `Serialized_Length`. Consider consistent naming across the family.

8. **No test coverage for `Variable_Stream_Serializer`.** The test program covers `Serializer`, `Stream_Serializer`, and `Variable_Serializer` but not `Variable_Stream_Serializer`.

9. **Test uses hardcoded `/tmp/file1.bin`.** Non-portable and could collide with parallel test runs. Consider using a temp-file utility.

10. **Known test limitation documented but not resolved.** The comment in `Test_Stream_Serializer` notes a GNAT compiler bug preventing an equality assertion. If this was a historical issue, it may be worth retesting with current GNAT versions.

11. **Typo in comment.** `serializer.adb` line in `From_Byte_Array` function: "turn of analysis" → "turn off analysis".

## Architecture Notes

- The overlay-based approach avoids `Unchecked_Conversion` and its associated compiler warnings, while achieving the same effect. Good trade-off for an embedded framework.
- The split between checked (`Byte_Array` subtype enforces exact size) and unchecked (`Basic_Types.Byte_Array` with arbitrary bounds) variants is a solid API pattern.
- The variable-length design delegates length computation to the caller via generic formals — this is flexible but means correctness depends entirely on the supplied length functions. There's no way to validate them at instantiation time.

## Summary

Well-structured, well-documented generic serialization library appropriate for embedded/Ravenscar Ada. The main concerns are around short-read handling in stream variants, the `To_Byte_Array_Unchecked` procedure not actually being "unchecked" w.r.t. destination size, and the null-array length check in `Variable_Serializer`. The test suite is reasonable but should be extended to cover `Variable_Stream_Serializer` and edge cases (empty arrays, short streams).

# Unit Test Infrastructure — Code Review

Reviewer: Claude | Date: 2026-03-01

---

## 1. `deallocation` — Safe_Deallocator

**Purpose:** Generic wrapper around `Ada.Unchecked_Deallocation` that deallocates on test targets but is a no-op on production/bareboard targets. Eliminates preprocessor conditionals.

**Design:** Clean dual-body pattern (production vs testing `.adb`) selected by build path. The spec suppresses expected warnings for the production null implementation.

**Strengths:**
- Elegant solution to the deallocation restriction problem on Ravenscar/bareboard targets
- Zero runtime cost in production — the null body compiles away
- Well-documented rationale in the spec

**Issues:**
- **(Minor)** The `Ignore : Name renames X` in the production body is an idiomatic way to suppress "unreferenced" warnings, but a `pragma Unreferenced` would be more explicit about intent.

**Rating: Excellent** — Simple, correct, well-motivated.

---

## 2. `file_logger` — File_Logger

**Purpose:** Timestamped file logging for unit tests. Opens a file, writes lines prefixed with seconds-since-epoch, closes.

**Strengths:**
- Auto-creates parent directory if missing
- Guards against writing to a closed file
- Clean tagged-type interface

**Issues:**
- **(Medium)** The epoch calculation `Clock - Time_Of(1970,...)` computes UTC seconds as a `Duration`, but `Ada.Calendar.Clock` returns *local* time on most GNAT implementations, not UTC. The logged timestamps will be offset by the local timezone. Consider `Ada.Calendar.Formatting.Image` or an explicit UTC conversion.
- **(Medium)** `Log` silently drops writes if the file isn't open. An assertion or at least a warning would aid debugging.
- **(Minor)** The spec comment says "generic, unprotected statistics data structure" — this appears to be a copy-paste artifact; it's a file logger, not a statistics structure.
- **(Minor)** `Log` takes `Self : in Instance` (not `in out`) but logically mutates file state. This works because `File_Type` is internally a pointer, but it's semantically misleading. Consider `in out`.
- **(Minor)** No flushing — log entries may be lost on crash.

**Rating: Adequate** — Functional but has a timezone bug and stale documentation.

---

## 3. `history` — History, History.Printable, Printable_History

**Purpose:** Generic bounded buffer that records a sequence of values for test verification. Child package adds pretty-printing. Convenience wrapper simplifies instantiation.

**Strengths:**
- Clean generic design with good separation (core / printable / convenience wrapper)
- Uses `Safe_Deallocator` for proper cleanup across targets
- Assertion messages are helpful and user-facing
- Has its own unit test suite (good practice for infrastructure code)

**Issues:**
- **(Medium)** `History.Push` calls `Assert` (which raises) then has `if not Self.Is_Full` — the `if` is dead code since `Assert` already failed. Remove the redundant guard or change the assertion to a soft check.
- **(Minor)** `To_String` and `Print` in `History.Printable` take `Self : in out` but don't modify `Self`. Should be `in`.
- **(Minor)** `Init` allocates but there's no protection against double-init (would leak the first allocation).
- **(Minor)** The test (`history_tests-implementation.adb`) only tests `History`, not `History.Printable` or `Printable_History`.

**Rating: Good** — Well-structured; a few minor dead-code and mutability issues.

---

## 4. `interrupts` — Interrupt_Sender

**Purpose:** Allows unit tests to programmatically send interrupts on Linux by wrapping the internal GNAT unit `System.Interrupt_Management.Operations`.

**Strengths:**
- Correctly suppresses portability warnings with paired `pragma Warnings` on/off
- Linux-only path marker (`.Linux_path`) makes the constraint visible to the build system

**Issues:**
- **(Low)** No documentation of which interrupt IDs are safe to use or expected behavior. A brief comment with a usage example would help test authors.
- **(Low)** Relies on an internal GNAT unit whose API may change across compiler versions. This is acknowledged but worth noting.

**Rating: Good** — Minimal, correct, appropriately scoped.

---

## 5. `smart_assert` — Smart_Assert, Basic_Assertions

**Purpose:** Rich assertion library layered on AUnit. Provides type-safe `Eq`/`Neq`/`Gt`/`Ge`/`Lt`/`Le` comparisons with pretty-printed failure messages, source location tracking, and safe fallback when used outside AUnit context.

**Strengths:**
- Excellent generics design: `Basic` (any `=`), `Discrete` (ordered), `Float` (epsilon-aware)
- Automatic source file/line capture via `GNAT.Source_Info` defaults — great DX
- Graceful degradation outside AUnit (catches `Storage_Error`, falls back to stderr + `Assertion_Error`)
- `Basic_Assertions` pre-instantiates for all common types — very convenient
- Float equality with configurable epsilon is a thoughtful touch

**Issues:**
- **(Medium)** `Float.Eq` uses `T'Small` as default epsilon, but `'Small` is a fixed-point attribute, not floating-point. For `digits` types, `T'Small` may not be defined or meaningful on all compilers. `T'Model_Epsilon` would be the correct floating-point attribute.
- **(Minor)** The `Constraint_Error` handler in `Call_Assert` re-raises `Constraint_Error` after calling `Assert(False, ...)`. If assertions are enabled, the `Assert(False)` already raises — the explicit `raise Constraint_Error` changes the exception identity. This is documented but the control flow is subtle.
- **(Minor)** `Float` comment says "integer, modular, or enumeration" — copy-paste from `Discrete`.

**Rating: Very Good** — The best-designed package in this set. The `T'Small` issue should be verified.

---

## 6. `string_util` — String_Util

**Purpose:** String formatting utilities (hex conversion, byte array display, trimming, padding, whitespace normalization). Dual implementation: full-featured Linux body and minimal bareboard (bb) body.

**Strengths:**
- Clean spec shared across platforms with platform-specific bodies
- `To_Byte_String` generic is clever — serialize any type to hex via `Serializer`
- `To_Array_String` with optional index display is useful for test output

**Issues:**
- **(Medium)** The bareboard `Pad_Zeros` is a no-op (returns `Source` unpadded) and `To_Array_String` ignores `Show_Index` and just returns `R'Image`. These are silent behavioral differences that could cause confusing test failures if bareboard tests rely on formatted output.
- **(Medium)** The bareboard `Replace_White_Space` has different semantics — it replaces each whitespace character individually (no collapsing of consecutive spaces), whereas the Linux version collapses runs of whitespace into a single replacement character. This behavioral divergence is undocumented.
- **(Minor)** The bareboard `Natural_2_Hex_String` ignores `Width` and returns decimal, not hex. The function name is misleading on that target.
- **(Minor)** `Bytes_To_String` in the Linux body allocates a fixed-size `Toreturn` string assuming 3 chars per byte; this is correct but brittle if the hex width ever changes.

**Rating: Adequate** — Linux implementation is solid. Bareboard implementation has significant semantic divergences that should be documented or reconciled.

---

## 7. `termination_handler` — Unit_Test_Termination_Handler

**Purpose:** Installs a fallback task termination handler during elaboration so that abnormally terminating or exception-killed tasks produce visible error output instead of dying silently.

**Strengths:**
- Uses `Elaborate_Body` and elaboration-time handler registration to avoid race conditions — exactly right
- Distinguishes normal/abnormal/unhandled-exception termination
- `pragma Unreferenced` pattern in test runners makes it trivial to include

**Issues:**
- **(Low)** Normal termination handler is commented out. This is fine for noise reduction, but a debug/verbose mode could be useful.
- **(Low)** No `GNAT.OS_Lib.OS_Exit(1)` or similar on abnormal/exception termination — the test process may still exit with code 0 even if a task died. This could mask failures in CI.

**Rating: Good** — Clean, correct, solves a real Ada testing pain point.

---

## Summary

| Package | Rating | Key Issue |
|---|---|---|
| deallocation | ⭐⭐⭐⭐⭐ Excellent | — |
| file_logger | ⭐⭐⭐ Adequate | Timezone bug, stale docs |
| history | ⭐⭐⭐⭐ Good | Dead code in Push, missing printable tests |
| interrupts | ⭐⭐⭐⭐ Good | — |
| smart_assert | ⭐⭐⭐⭐½ Very Good | `T'Small` may be wrong for float epsilon |
| string_util | ⭐⭐⭐ Adequate | Silent behavioral divergence across platforms |
| termination_handler | ⭐⭐⭐⭐ Good | May not set nonzero exit code on task death |

### Cross-Cutting Observations

1. **Consistent dual-target pattern:** The production/testing and Linux/bb body separation is a well-established pattern used consistently across these packages. The build system path markers (`.all_path`, `.Linux_path`, `.bb_path`) make target selection clear.

2. **AUnit coupling:** Several packages (`history`, `smart_assert`) depend on AUnit at the library level. This is fine for test infrastructure but means these packages cannot be used in non-AUnit contexts without the `Smart_Assert` fallback mechanism.

3. **No task safety:** `File_Logger` and `History` are not thread-safe. This is acceptable for typical unit test usage but should be documented.

4. **Code quality is high overall.** The generics design in `smart_assert` is particularly well done. The main area for improvement is the bareboard `string_util` implementations where degraded functionality is silent.

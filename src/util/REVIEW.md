# Utility Packages Code Review

Reviewed: 2026-03-01

---

## 1. Byte_Array_Util

**Purpose:** Bit- and byte-level manipulation of `Byte_Array` and 32-bit poly types — safe copying, bit-field extraction, and insertion with arbitrary bit offsets/sizes.

### Strengths
- **Robust boundary handling.** `Safe_Right_Copy` / `Safe_Left_Copy` gracefully handle mismatched sizes and empty arrays. Postconditions on the function variants provide provable guarantees.
- **Thorough validation.** `Extract_Poly_Type` and `Set_Poly_Type` validate offset+size against array bounds before any bit manipulation, returning typed status enums instead of raising exceptions.
- **Truncation control.** `Set_Poly_Type` exposes an explicit `Truncation_Allowed` flag — callers must opt in to lossy behavior. Good for safety-critical contexts.
- **Excellent test coverage.** Tests exercise byte-aligned, non-byte-aligned, signed extraction with sign-extension, truncation, round-trip set+extract sweeps across all offsets, and all error paths.
- **Static analysis friendliness.** `pragma Assert` hints and `Signed_Length` helper aid SPARK/GNATprove reasoning.

### Issues & Suggestions

| # | Severity | Description |
|---|----------|-------------|
| 1 | **Minor** | `Safe_Right_Copy` / `Safe_Left_Copy` procedure forms discard the return value into `Ignore`. This is fine functionally but the `Ignore` naming convention is inconsistent — some Adamant code uses `Ignore_`, some uses `Ignore`. Pick one project-wide. |
| 2 | **Minor** | `Bit_Mask` will produce incorrect results if `Num_Ones = 8` due to `Unsigned_8` overflow (`Shift_Left(1, 8) = 0` in 8-bit). This path is never reached in practice because `Mod_1_8` maps 8→8 and the mask is only applied to partial bytes, but the implicit contract is fragile. Consider a comment or a precondition. |
| 3 | **Low** | The `Extract_Poly_Type` / `Set_Poly_Type` functions assume big-endian poly type layout. This is documented in comments but not enforced by type system. A named constant or aspect would make the contract machine-checkable. |
| 4 | **Low** | `Natural'First` is used where `0` is clearly meant. While equivalent, literal `0` is more readable in non-boundary contexts. |

### Verdict: **Good** — well-tested, defensive, suitable for flight/embedded use.

---

## 2. Monitor

**Purpose:** Two-state (Green/Red) hysteresis monitor with configurable persistence thresholds for each transition direction, plus enable/disable.

### Strengths
- **Simple, correct state machine.** The logic cleanly separates Green→Red (consecutive false predicates) and Red→Green (consecutive true predicates) with independent thresholds.
- **Saturation guard.** `Persistence_Count` is capped at `Natural'Last` to prevent overflow.
- **Clean API.** `Check` returns a `Check_Status` that distinguishes steady-state from transition edges — callers can trigger actions on `Green_To_Red` / `Red_To_Green` without tracking prior state.
- **Solid tests** covering both directions, intermittent predicates that reset counters, enable/disable toggling, and threshold reconfiguration.

### Issues & Suggestions

| # | Severity | Description |
|---|----------|-------------|
| 1 | **Minor** | `Set_Persistance_Thresholds` resets state from Red→Green silently. This is documented by behavior in tests but not in comments. If a caller changes thresholds mid-operation expecting to stay Red, they'll be surprised. Consider documenting or making it configurable. |
| 2 | **Minor** | Typo: "Persistance" should be "Persistence" in all identifiers (`Green_To_Red_Persistance_Threshold`, etc.). The internal record field is spelled correctly (`Persistence_Count`), making it inconsistent. |
| 3 | **Low** | Comment typo in body: "transitioining" → "transitioning", "counterss" → "counters". |
| 4 | **Low** | `Check` is a function with side effects (mutates `Self`). In Ada convention, a procedure with an out parameter or in-out Self would be more idiomatic. This is a style choice but worth noting. |

### Verdict: **Good** — simple, correct, well-tested.

---

## 3. Moving_Average

**Purpose:** Generic running statistics (mean, variance, max) over a configurable sliding window, instantiable with any floating-point type.

### Strengths
- **Efficient O(1) updates.** Running sum and sum-of-squares avoid re-scanning the buffer on each sample.
- **Configurable computation.** `Calculate_Variance` and `Calculate_Max` flags let callers skip unnecessary work.
- **Resizable window.** `Change_Sample_Calculation_Size` allows runtime adjustment within the pre-allocated storage.
- **Good test coverage** including rollover, reset, size changes, and uninitialized safety.

### Issues & Suggestions

| # | Severity | Description |
|---|----------|-------------|
| 1 | **Medium** | **Variance can go negative due to floating-point drift.** The formula `(sum_sq / n) - mean²` is numerically unstable. For safety-critical use, Welford's online algorithm would be more robust. |
| 2 | **Medium** | **Max tracking is reset only when `Head = 0`**, not when the actual max sample exits the window. This means `Max` can be stale (too high) for up to a full window period, or reset too early if a new non-max sample arrives at head=0. The test actually shows `Max` resetting to 1.0 on rollover, which is correct for the *implementation* but potentially misleading for users expecting a true running max. |
| 3 | **Minor** | **Heap allocation** (`new Statistic_Items`) in `Init` with deallocation only via `Safe_Deallocator.Deallocate_If_Testing` — meaning in non-test builds, memory is never freed. This is fine for embedded (allocate-once) but should be documented. |
| 4 | **Minor** | `Calculate_Mean` calls `Calculate_Mean_Variance_Max` and discards variance/max. When `Calculate_Variance` and `Calculate_Max` are False, the overhead is minimal, but the API suggests the caller should set those flags — this coupling should be documented. |
| 5 | **Low** | `Init` uses `pragma Assert` for parameter validation, which can be compiled out. For a library, `raise Constraint_Error` or a status return would be safer. |
| 6 | **Low** | `Items_Length` is `Positive` initialized to `Positive'First` (1) — safe but semantically confusing before `Init` is called. |

### Verdict: **Adequate** — works for its use case but the variance and max algorithms have known numerical/logical limitations.

---

## 4. Sleep

**Purpose:** Convenience wrappers around `delay until` using `Ada.Real_Time`.

### Strengths
- **Uses `delay until`** (absolute time) rather than `delay` (relative), which is the correct pattern for Ravenscar/real-time systems to avoid drift.
- **Clean, minimal API.** Three entry points: raw `Time_Span`, milliseconds, microseconds.

### Issues & Suggestions

| # | Severity | Description |
|---|----------|-------------|
| 1 | **Low** | No unit tests. Timing utilities are hard to test precisely, but a smoke test (sleep 10ms, verify elapsed ≥ 10ms) would add confidence. |
| 2 | **Low** | Each procedure computes `Clock + Duration` — if the caller computes duration and passes it in, there's a small window between Clock read and delay. This is inherent to the pattern and acceptable, but worth noting for nanosecond-sensitive use. |

### Verdict: **Good** — trivial, correct, no issues.

---

## 5. Socket

**Purpose:** TCP/IPv4 client socket wrapper around `GNAT.Sockets` with hostname resolution and stream-based I/O.

### Strengths
- **Clean connect/disconnect lifecycle** with `Is_Connected` state tracking.
- **Hostname vs IP auto-detection** via `Is_Ip_Address` parser.
- **Socket option `Reuse_Address`** set by default — good for rapid reconnect scenarios.
- **Integration tests** (test_read / test_write) using `socat` for end-to-end validation.

### Issues & Suggestions

| # | Severity | Description |
|---|----------|-------------|
| 1 | **Medium** | **`pragma Assert(False, ...)` in exception handler.** The catch-all `when E : others` in `Connect` will terminate the program in production if assertions are enabled. Should use a proper error reporting mechanism or at minimum set `Connected := False` and log. |
| 2 | **Medium** | **Unused `with Interfaces.C; pragma Unreferenced`** at the top of `socket.adb` — dead import, should be removed. |
| 3 | **Minor** | `Is_Ip_Address` is simplistic — accepts strings like `999.999.999.999`. For a utility library this is acceptable since `Inet_Addr` will validate further, but it's worth a comment. |
| 4 | **Minor** | No timeout on `Connect_Socket` — can block indefinitely on unreachable hosts. |
| 5 | **Low** | `Disconnect` swallows `Socket_Error` silently. Acceptable for cleanup but could log in debug builds. |
| 6 | **Low** | Type definitions in `types/` (YAML-based `socket_address.record.yaml`, `ip_v4_address.array.yaml`) are auto-generated record/array specs — clean and consistent with the Adamant type system. |

### Verdict: **Adequate** — functional but the `pragma Assert(False)` in the exception handler is a real concern for production use.

---

## 6. Stopwatch

**Purpose:** CPU-time and wall-clock elapsed time measurement via start/stop/result pattern.

### Strengths
- **Dual timers.** `Cpu_Timer_Instance` (execution time only) and `Wall_Timer_Instance` (real time) cover both profiling needs.
- **Functional and procedural `Start`** — can initialize inline (`Timer := Stopwatch.Start`) or mutate in place.
- **`Representation` child package** provides `Image` for human-readable output, cleanly separated.

### Issues & Suggestions

| # | Severity | Description |
|---|----------|-------------|
| 1 | **Minor** | **No unit tests.** Even a basic test that starts, sleeps, stops, and checks `Result > 0` would be valuable. |
| 2 | **Minor** | Record fields are fully public (not private). Callers can directly manipulate `Start_Time` / `Stop_Time`, bypassing the API. Consider making the type private with public operations only. |
| 3 | **Low** | `Result` called before `Stop` returns a meaningless value (`CPU_Time_First - start`). A `Stopped` boolean or precondition would catch misuse. |
| 4 | **Low** | `Representation.Image` duplicates logic for both timer types — could be a single generic or use `Time_Span` directly. Minor DRY concern. |

### Verdict: **Good** — simple, useful, low risk.

---

## Summary

| Package | Rating | Key Concern |
|---------|--------|-------------|
| Byte_Array_Util | ★★★★☆ | Bit_Mask edge case at size=8 |
| Monitor | ★★★★☆ | Spelling inconsistency; silent state reset on threshold change |
| Moving_Average | ★★★☆☆ | Numerically unstable variance; approximate max tracking |
| Sleep | ★★★★☆ | No tests (but trivial) |
| Socket | ★★★☆☆ | `pragma Assert(False)` in exception handler; dead import |
| Stopwatch | ★★★★☆ | No tests; public record fields |

**Overall:** Solid embedded utility library. The packages are well-structured with consistent Ada style. The main actionable items are the `Moving_Average` variance algorithm and the `Socket` exception handling pattern.

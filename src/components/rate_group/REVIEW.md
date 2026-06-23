# Rate Group Component — Code Review

**Reviewer:** Automated (Claude)
**Date:** 2026-03-01
**Component:** `src/components/rate_group`

---

## 1. Documentation Review

The component YAML description is clear and well-written. It explains the purpose (periodic scheduling of downstream components), the active execution model, and the watchdog pet connector. Init parameters are well-documented with rationale for the delay-ticks feature.

**Findings:**

- **Low — Event description copy-paste error.** The `Max_Execution_Time_Exceeded` event description in `rate_group.events.yaml` says "…with the maximum **cycle** time as the Time…" — should say "maximum **execution** time." This is misleading to operators interpreting telemetry.
- **Low — LaTeX doc not reviewed.** `doc/rate_group.tex` / `.pdf` were not analyzed (binary/LaTeX), but the YAML-level docs are the authoritative source for code generation.

---

## 2. Model Review

### Component YAML (`rate_group.component.yaml`)

The model is well-structured. The `recv_async` connector for the incoming tick correctly implies a queue, and the arrayed `send` connector with `count: 0` (assembly-determined) is appropriate.

**Findings:**

- **Low — No severity levels on events.** The `rate_group.events.yaml` does not specify severity/criticality for events. `Cycle_Slip` and `Incoming_Tick_Dropped` are operationally significant and should be marked at a higher severity than informational time-exceeded events. (This may be a framework convention; flag if severity is supported.)

### Record Types

- `cycle_slip_param`: `Num_Slips` is `Unsigned_16` — see finding in §3.
- `full_queue_param`: Appropriate fields.
- `time_exceeded`: Contains `Delta_Time.T` and count — appropriate.
- `timing_report`: Contains max and recent-max wall/execution times — clean design.

---

## 3. Component Implementation Review

### `Init`

Straightforward assignment of parameters. No issues.

### `Tick_T_Recv_Async` (main execution path)

**Findings:**

| # | Severity | Finding |
|---|----------|---------|
| 1 | **High** | **`Num_Cycle_Slips` overflow (Unsigned_16).** The cycle slip counter is `Unsigned_16` and is incremented without overflow protection. In a long-running mission with a misbehaving rate group, this will wrap around to 0 after 65,535 slips, producing a misleading event parameter. The `Cycle_Slip_Param.Num_Slips` field is also `Unsigned_16`. For a safety-critical system, a saturating counter or wider type should be used. |
| 2 | **Medium** | **`To_Delta_Time` return status silently discarded.** The `Ignore` variable is used to discard the return status of `To_Delta_Time` in 6 call sites. If the `Time_Span` exceeds the representable range of `Delta_Time.T`, the conversion fails silently, and an incorrect (likely zero or clamped) value is reported in the timing data product or event. At minimum, a diagnostic event should be issued on conversion failure, or an assertion should guard this. |
| 3 | **Medium** | **`Ticks_Since_Startup` overflow (Unsigned_16).** If `Timing_Report_Delay_Ticks` is set to `Unsigned_16'Last` (65535), `Ticks_Since_Startup` will reach 65534, be incremented to 65535, then on the next tick `Ticks_Since_Startup >= Timing_Report_Delay_Ticks` becomes True and timing starts. However, if delay were somehow larger (not possible with Unsigned_16 but worth noting the design is safe by type constraint). More practically: if delay is 65535, the counter works but wastes ~18 hours at 1 Hz before timing begins. Not a bug, but worth a range note. |
| 4 | **Medium** | **Wall clock `Cycle_Time` computed after execution completes.** `Stop_Wall_Time` is fetched via `Sys_Time_T_Get` *after* stopping the CPU timer and *after* the pet send. The wall-clock measurement includes the overhead of the pet and timer stop, inflating the reported cycle time slightly. In a tight real-time system this could cause spurious `Max_Cycle_Time_Exceeded` events. Consider capturing wall time immediately after the loop. |
| 5 | **Low** | **Cycle slip check position.** The cycle slip check (`Queue.Num_Elements > 0`) occurs at the very end of `Tick_T_Recv_Async`, after timing calculations and data product sends. A tick could arrive on the queue during the timing/DP overhead rather than during the actual rate group execution, producing a false cycle slip. Moving the check immediately after the component invocation loop (before timing logic) would be more precise. |
| 6 | **Low** | **`Num_Ticks` not reset on timing delay expiry.** When `Ticks_Since_Startup` finally reaches `Timing_Report_Delay_Ticks`, `Num_Ticks` starts at 0 and increments. This is correct, but there's an implicit coupling: if `Init` is called more than once (re-initialization), `Num_Ticks` retains its old value since `Init` doesn't reset it. The record default (0) only applies at elaboration. |

### `Tick_T_Recv_Async_Dropped` / `Tick_T_Send_Dropped`

Clean — event issued with appropriate context. No issues.

---

## 4. Unit Test Review

### Test Coverage

| Test | What it covers |
|------|---------------|
| `Nominal` | Basic tick dispatch to 2 of 3 connected components, pet, no cycle slip |
| `Cycle_Slip_Trigger` | Two ticks queued before dispatch → slip detected; slip counter increments |
| `Time_Reporting` | Time exceeded events fire on first tick; data product sent |
| `Full_Queue` | Downstream full queue → correct events with correct indices |
| `Test_Dropped_Tick` | Rate group's own queue full → `Incoming_Tick_Dropped` events |

**Findings:**

| # | Severity | Finding |
|---|----------|---------|
| 1 | **High** | **`Time_Reporting` test is largely commented out.** Two-thirds of the test is commented out with the note "We can no longer test the following since we are using Ada.Real_Time and Ada.Execution_Time instead of Sys_Time arithmetic." This means **multi-cycle timing behavior (increasing wall time, stable execution time, different deltas) is untested.** The recent-max reset logic, the periodic data product emission over multiple cycles, and the interaction between cycle time vs. execution time are all unverified. This is a significant coverage gap for the component's primary diagnostic feature. |
| 2 | **Medium** | **No test for `Timing_Report_Delay_Ticks > 0`.** All tests use `Timing_Report_Delay_Ticks => 0`, so the startup-delay logic path (`Ticks_Since_Startup` counting) is never exercised. A test should verify that timing reports are suppressed during the delay period. |
| 3 | **Medium** | **No test for `Ticks_Per_Timing_Report > 1`.** Tests always use `Ticks_Per_Timing_Report => 1`, so the periodic-report counter logic (`Num_Ticks` accumulation and reset) is never tested for the multi-tick case. |
| 4 | **Medium** | **No test for `Issue_Time_Exceeded_Events => False`.** Tests always set this to `True`. The suppression path is untested. |
| 5 | **Low** | **No test for `Ticks_Per_Timing_Report => 0` (disabled reporting).** The zero-disables-reporting path is never exercised. |
| 6 | **Low** | **Tester has unused `with String_Util`.** Minor — `String_Util` is used in `Dispatch_All`/`Dispatch_N` logging, so this is actually used. No issue. |
| 7 | **Low** | **Disconnected connector (index 2) only tested indirectly.** The `Connect` procedure deliberately leaves index 2 unconnected, and `Nominal` checks that only 2 ticks are sent (not 3). This implicitly tests `Is_Tick_T_Send_Connected`, but a more explicit assertion or comment would improve clarity. |

---

## 5. Summary — Top 5 Findings

| # | Severity | Location | Finding |
|---|----------|----------|---------|
| 1 | **High** | `implementation.adb:Tick_T_Recv_Async` | `Num_Cycle_Slips` (Unsigned_16) can overflow/wrap without detection in long-running missions, producing misleading telemetry. Use saturating arithmetic or a wider type. |
| 2 | **High** | `tests-implementation.adb:Time_Reporting` | Most of the timing test is commented out. Multi-cycle timing behavior, recent-max resets, and execution-vs-wall-time discrimination are untested. |
| 3 | **Medium** | `implementation.adb:Tick_T_Recv_Async` | `To_Delta_Time` return status silently discarded at 6 call sites. Conversion failures produce silently incorrect timing data. |
| 4 | **Medium** | `tests-implementation.adb` | No test coverage for `Timing_Report_Delay_Ticks > 0`, `Ticks_Per_Timing_Report > 1`, or `Issue_Time_Exceeded_Events => False` — three of the component's four configurable behaviors. |
| 5 | **Medium** | `implementation.adb:Tick_T_Recv_Async` | Wall clock stop time captured after pet send and CPU timer stop, slightly inflating reported cycle time and potentially causing spurious time-exceeded events. |

## Resolution Notes

| # | Issue | Severity | Status | Commit | Notes |
|---|-------|----------|--------|--------|-------|
| 1 | Cycle slip counter overflow | High | Fixed | a69c37b | Saturating counter prevents wrap |
| 2 | Timing test commented out | High | Not Fixed | - | Requires Ada.Real_Time test infrastructure |
| 3 | Tick count 0 on Init | Medium | Not Fixed | - | Initial condition, acceptable |
| 4 | Silent dropped sends | Medium | Not Fixed | - | Requires event YAML addition |

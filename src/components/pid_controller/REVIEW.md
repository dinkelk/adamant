# PID Controller Component — Code Review

**Reviewer:** Automated Review  
**Date:** 2026-03-01  
**Component:** `src/components/pid_controller`

---

## 1. Documentation Review

| # | Severity | Finding |
|---|----------|---------|
| D1 | Low | The `pid_controller.tests.yaml` description for `Test_Pid_Controller` is incomplete: *"This test is a basic test to make sure that the controller"* — sentence is truncated. |
| D2 | Low | The diagnostic subpacket record fields use the name `Measured_Angle`, `Reference_Angle`, and `Current_Out_Angle`, but the component description and control interface speak in terms of generic "values" (Commanded_Value, Measured_Value, Output_Value). The angle-specific naming leaks a domain assumption into a supposedly generic PID component. |
| D3 | Low | The `pid_controller.packets.yaml` packet entry for `Pid_Controller_Diagnostic_Packet` has no `type` field defining the packet structure. The packet buffer is manually constructed at runtime. While functional, this bypasses Adamant's packet auto-generation and makes the packet format implicit rather than declarative. |

## 2. Model Review

| # | Severity | Finding |
|---|----------|---------|
| M1 | Medium | **`Moving_Average_Init_Samples` is `Integer` but semantically must be ≥ −1.** The init parameter accepts any `Integer`. Passing values like −2 or `Integer'First` is not validated; the behavior depends entirely on the `Moving_Average` library. There is no range constraint or precondition check. |
| M2 | Medium | **No validation that `I_Min_Limit ≤ I_Max_Limit`.** The `Validate_Parameters` function unconditionally returns `Valid`. If a user sets `I_Min_Limit > I_Max_Limit`, the integral clamping logic becomes a no-op (the value will satisfy neither branch of the if/elsif), allowing unbounded integral windup — the very thing the limits are meant to prevent. |
| M3 | Low | All six PID parameters default to 0.0 (gains) or ±`Short_Float'Large` (limits). With all gains at zero, the output is purely the feed-forward value. This is safe but may surprise users who expect non-zero defaults. The `Short_Float'Large` default for limits is effectively "no limit," which is acceptable but could mask a missing configuration. |

## 3. Component Implementation Review

| # | Severity | Finding |
|---|----------|---------|
| C1 | **Critical** | **Derivative filter can diverge.** The derivative term is computed as: `D_out = D_prev * (1.0 - N * dt) + (error - error_prev) * D_gain * N`. If `N_Filter * Time_Step > 2.0` (e.g., N=500 at 100 Hz → N·dt=5.0), the factor `(1.0 - N·dt)` becomes a large negative number, causing the derivative term to oscillate with growing amplitude each cycle. This is a discrete-time stability issue — the bilinear (Tustin) or backward-Euler discretization would be safe, but the forward-Euler form used here is conditionally unstable. For a safety-critical controller, this can cause actuator runaway. There is no runtime check or parameter validation on the N_Filter value relative to the time step. |
| C2 | **High** | **Integral term uses previous-cycle error (backward integration), but first-iteration integral is always zero regardless of initial error magnitude.** On the first call (`First_Iteration = True`), `Control_Error_Prev` is reset to 0, so the integral contribution on that cycle is `I_Gain * dt * 0.0 = 0.0`. This is technically correct for a fresh start, but the integral uses `Control_Error_Prev` (rectangular/backward Euler), meaning the *current* cycle's error is never integrated until the *next* cycle. Combined with the derivative term also using the previous error, the very first control output after `First_Iteration` is only `P * error + feed_forward` — the I and D terms are always one step delayed. This is a known property of this discretization but is not documented. |
| C3 | **High** | **`Short_Float` (32-bit IEEE 754) precision for integral accumulation.** The integral term accumulates over potentially thousands of cycles. With `Short_Float` providing ~7 decimal digits of precision, a large accumulated integral (e.g., near the windup limit) plus a small `I_Gain * dt * error` increment can lose significance. For long-running controllers this can cause the integrator to "stick" — new small errors no longer change the accumulated value. Using `Float` (also 32-bit on most targets) or `Long_Float` (64-bit) for the accumulator would mitigate this. |
| C4 | Medium | **`Init` uses `pragma Assert` for `Control_Frequency > 0.0`.** In production builds with assertions disabled (`-gnatp`), a zero or negative frequency would silently produce `Time_Step = +Inf` or `NaN`, leading to nonsensical control outputs. A proper runtime check raising `Constraint_Error` or a dedicated exception would be safer. |
| C5 | Medium | **No NaN/Inf guard on inputs or outputs.** If `Measured_Value` or `Commanded_Value` is NaN (e.g., from a failed sensor), all subsequent computations propagate NaN silently. The control output will be NaN, which is sent downstream. Safety-critical controllers typically check for non-finite values and enter a safe fallback mode. |
| C6 | Medium | **Diagnostic packet buffer index is 0-based with manual offset arithmetic.** The computation `Diagnostic_Packet_Index := (Diagnostic_Subpacket_Count * Subpacket_Length) + Header_Length` is correct but fragile. An off-by-one in subpacket count or a change to the subpacket size could cause buffer overrun. The overflow check `(index + subpacket_size) > Buffer'Length` prevents writing past the end, but the logic is subtle and has no defensive assertion. |
| C7 | Low | **`Diagnostic_Counter` is a protected decrementing counter but `Diag_Count` is read via `Get_Count` and then separately decremented.** Between the `Get_Count` and `Decrement_Count` calls, if this component were ever invoked from multiple tasks (currently it's `recv_sync` so single-threaded), a TOCTOU race would exist. Currently safe due to the synchronous connector model, but the use of a protected counter for a single-threaded path is misleading. |

## 4. Unit Test Review

| # | Severity | Finding |
|---|----------|---------|
| T1 | **High** | **No test for derivative filter stability/instability.** Given the critical finding C1, there is no test that exercises a large `N_Filter` value relative to the control frequency. A test with `N_Filter` such that `N * dt > 1.0` would immediately reveal divergent behavior. |
| T2 | **High** | **No test for `I_Min_Limit > I_Max_Limit` (inverted limits).** Per finding M2, this misconfiguration silently disables windup protection. A test should verify the component either rejects or handles this gracefully. |
| T3 | Medium | **`Set_Up_Test` has the `Init` call commented out.** Each test body calls `Init` individually, which is fine, but the commented-out line `--Self.Tester.Component_Instance.Init(...)` in `Set_Up_Test` is dead code that could confuse maintainers about whether setup is complete. |
| T4 | Medium | **No test for NaN/Inf input behavior.** There are no tests that feed `Short_Float'Last`, `0.0/0.0`, or other edge-case floating-point values to verify the component doesn't produce unsafe outputs. |
| T5 | Medium | **No test for `Control_Frequency` edge cases in `Init`.** Zero, negative, and very small frequencies are not tested. The `pragma Assert` is the only guard (see C4). |
| T6 | Low | **`Test_Pid_Controller` uses magic numbers for expected outputs (13.0, 48.794, -109.53).** These are hand-calculated but not documented in comments showing the derivation. If the PID algorithm changes, it's unclear whether these values are still correct. |
| T7 | Low | **No test for `Destroy` of `Protected_Moving_Average`.** `Tear_Down_Test` calls `Final_Base` on the tester but does not explicitly verify that the moving average memory is freed. If `Moving_Average` allocates heap memory, a leak could go undetected. |

## 5. Summary — Top 5 Findings

| Rank | ID | Severity | Finding |
|------|----|----------|---------|
| 1 | C1 | **Critical** | Derivative filter uses forward-Euler discretization that is unstable when `N_Filter * Time_Step > 2.0`. No validation prevents this, risking actuator runaway. |
| 2 | M2 | **High** | `Validate_Parameters` does not check `I_Min_Limit ≤ I_Max_Limit`. Inverted limits silently disable integral windup protection. |
| 3 | C3 | **High** | 32-bit `Short_Float` integral accumulator loses precision over long control runs, causing the integrator to "stick" and stop responding to small errors. |
| 4 | C5 | Medium | No NaN/Inf detection on inputs or outputs. A failed sensor propagates NaN through the entire control chain silently. |
| 5 | T1 | **High** | No unit test exercises the derivative filter stability boundary, leaving the critical C1 defect undetectable by the test suite. |

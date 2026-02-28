# Command Protector Component — Code Review

**Reviewer:** Automated Expert Review  
**Date:** 2026-02-28  
**Branch:** `review/components-command-protector`

---

## 1. Documentation Review

The component description in the YAML and `.ads` spec are thorough and accurate. The LaTeX document is a standard template pulling from generated build artifacts — no issues.

**Minor comment inaccuracy:**

| # | Location | Severity | Details |
|---|----------|----------|---------|
| D1 | `component-command_protector-implementation.ads:14` | Low | Comment says "Commands that are not on the protected commands list **they will be** forwarded" — grammatically awkward. Should be "…protected commands list **will be** forwarded." Same wording repeated in the `Command_T_To_Forward_Recv_Sync` procedure comment. |

---

## 2. Model Review

### component.yaml

The model is well-structured. Connectors, commands, events, data products, and packets are all consistent with the implementation.

**No issues found.**

### commands.yaml

| # | Location | Severity | Details |
|---|----------|----------|---------|
| M1 | `command_protector.commands.yaml` | Low | The Arm command description states "A timeout value of zero implies infinite timeout" but the `packed_arm_timeout.record.yaml` field description says "The timeout value (in ticks)" with no mention of zero-means-infinite semantics. The special zero-case should be documented in the type description as well for clarity. |

### requirements.yaml

| # | Location | Severity | Details |
|---|----------|----------|---------|
| M2 | `command_protector.requirements.yaml`, requirement 4 | Medium | Requirement: "The component shall exit the armed state upon receipt of any command, **unless it is another arm command.**" The implementation does **not** implement this exception — sending an Arm command while armed will **not** re-arm the component via `Command_T_To_Forward_Recv_Sync`; the Arm command arrives on the separate `Command_T_Recv_Sync` connector and always succeeds. However, if a *non-protected, non-arm* command is forwarded while armed, the component transitions to unarmed. The requirement text is misleading because the Arm command never arrives on the forwarding connector — the "unless" clause is vacuously true but confusing. Consider rewording for accuracy. |
| M3 | `command_protector.requirements.yaml`, requirement 7 | Low | States "0 to 255 seconds (in 1 second intervals)" but the timeout is actually in **ticks**, not seconds. The mapping of ticks to seconds depends on the tick rate configured at the assembly level. The requirement should say "ticks" or clarify the assumed tick period. |

### types

**No issues found.** Enums, packed records are clean and correctly sized.

---

## 3. Component Implementation Review

### arm_state.ads / arm_state.adb

| # | Location | Severity | Details |
|---|----------|----------|---------|
| I1 | `arm_state.ads:10` | Medium | `Get_State` is declared as a **function** of the protected type, but it has an `out` parameter (`The_Timeout`). In Ada, protected functions provide concurrent read access (multiple readers allowed). Having an `out` parameter on a function is legal but semantically unusual — it implies the function has a side-channel output while being called concurrently. This is safe here because `The_Timeout` is derived from private state that only changes under procedure (exclusive) access. However, it is an unconventional pattern that could confuse maintainers. A more conventional approach would be to either (a) make it a procedure, or (b) return a record containing both state and timeout. |

### component-command_protector-implementation.adb

| # | Location | Severity | Details |
|---|----------|----------|---------|
| I2 | `component-command_protector-implementation.adb:105-106` (in `Command_T_To_Forward_Recv_Sync`, Armed branch) | **High** | **Race condition between `Get_State` and subsequent operations.** The armed state is read via `Get_State` at the top of the procedure (line ~87), then if `Armed`, the command is forwarded and `Unarm` is called. Because this component is declared `passive` (no task, no queue), all connectors are synchronous and called in the caller's thread. If `Tick_T_Recv_Sync` and `Command_T_To_Forward_Recv_Sync` can be called from **different tasks** (e.g., a tick task and a command routing task), there is a TOCTOU race: the state could be `Armed` when read but timeout to `Unarmed` between the read and the `Unarm` call. The `Unarm` procedure itself is safe (idempotent), but the **decision to forward a protected command** was made on stale state. **Mitigation:** If the component is always invoked from a single task (common in Adamant passive component usage), this is not exploitable. If multi-task invocation is possible, the check-and-act should be atomic — e.g., a single protected operation `Try_Forward` that returns whether to forward. |
| I3 | `component-command_protector-implementation.adb:122,143` | **Medium** | **Unsigned_16 counter overflow.** `Protected_Command_Forward_Count` and `Protected_Command_Reject_Count` are `Interfaces.Unsigned_16` and are incremented with `@ + 1`. If either counter reaches `65535` and is incremented again, it wraps to 0 (Interfaces.Unsigned_16 uses modular arithmetic). This silent wraparound could be misleading in telemetry. Consider saturating at `Unsigned_16'Last` or using a wider type. |

**Original code (line ~122):**
```ada
Self.Protected_Command_Forward_Count := @ + 1;
```
**Suggested fix (saturating):**
```ada
if Self.Protected_Command_Forward_Count < Interfaces.Unsigned_16'Last then
   Self.Protected_Command_Forward_Count := @ + 1;
end if;
```
Same pattern for `Protected_Command_Reject_Count` at line ~143.

| # | Location | Severity | Details |
|---|----------|----------|---------|
| I4 | `component-command_protector-implementation.adb:87-90` | Low | **Two calls into the protected object for one logical operation.** `Get_State` is called to read the state, then later `Unarm` is called. Between these two calls the lock is released. As noted in I2, this is a potential issue under concurrent access. Even in single-task scenarios, combining these into a single protected call would be cleaner. |

---

## 4. Unit Test Review

The test suite covers the key scenarios well:

- ✅ Initialization (nominal, empty list, duplicate IDs)
- ✅ Unprotected command forwarding (unarmed and armed states)
- ✅ Protected command acceptance (armed state)
- ✅ Protected command rejection (unarmed state, with error packet)
- ✅ Timeout behavior (decrement, expiry, infinite timeout with 0)
- ✅ Invalid command handling

| # | Location | Severity | Details |
|---|----------|----------|---------|
| T1 | `command_protector_tests-implementation.adb` | Medium | **Missing test: Arm while already armed.** There is no test that sends a second Arm command while the component is already armed (e.g., to reset the timeout). This is a valid operational scenario — an operator might re-arm with a different timeout. The behavior should be verified (the current implementation would overwrite the timeout and remain armed). |
| T2 | `command_protector_tests-implementation.adb` | Medium | **Missing test: Arm command sent to the forwarding connector.** If by misconfiguration or operator error, an Arm command (matching the component's own command ID) appears on the `Command_T_To_Forward_Recv_Sync` connector, it would be treated as a regular command, potentially protected or not. Testing this boundary would be valuable. |
| T3 | `command_protector_tests-implementation.adb` | Low | **Missing test: Counter rollover.** No test verifies behavior when `Protected_Command_Reject_Count` or `Protected_Command_Forward_Count` approach or reach `Unsigned_16'Last`. Given finding I3, this should be tested. |
| T4 | `command_protector_tests-implementation.adb`, `Test_Protected_Command_Accept`, line with comment "Send a command not in the protected list:" | Low | **Misleading comment.** The comment says "Send a command **not** in the protected list" but `Cmd.Header.Id` is set to `19`, which **is** in the protected list `[4, 19, 77, 78]`. The test assertions are correct (it expects acceptance and forward-count increment), so the code is right but the comment is wrong. |

**Original comment:**
```ada
-- Send a command not in the protected list:
Cmd.Header.Id := 19;
```
**Corrected:**
```ada
-- Send a command IN the protected list:
Cmd.Header.Id := 19;
```

---

## 5. Summary — Top 5 Findings

| Rank | ID | Severity | Summary |
|------|----|----------|---------|
| 1 | I2 | **High** | TOCTOU race on armed state: `Get_State` then `Unarm` are not atomic. Under concurrent multi-task invocation, a protected command could be forwarded after the armed state has timed out. |
| 2 | I3 | **Medium** | `Unsigned_16` telemetry counters silently wrap around at 65535, producing misleading telemetry in long-duration missions. |
| 3 | M2 | **Medium** | Requirement 4 ("unless it is another arm command") is misleading given the actual connector topology — the Arm command never flows through the forwarding path. |
| 4 | T1 | **Medium** | No unit test for re-arming while already armed (timeout reset scenario). |
| 5 | T4 | **Low** | Incorrect comment in `Test_Protected_Command_Accept` — says "not in the protected list" for command ID 19 which is protected. |

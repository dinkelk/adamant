# Time At Tone Master — Component Review

**Date:** 2026-03-01
**Reviewer:** Automated (Claude)

## Summary

The Time At Tone Master implements the master side of a Time-at-Tone (TaT) clock synchronization protocol in Ada/Adamant. It sends a "time message" (predicted tone arrival time) followed by a "tone message" after a configurable delay, allowing a slave component to stuff its clock. The design is clean, well-documented, and follows Adamant component conventions consistently.

## Architecture & Design

**Strengths:**
- Clear separation of concerns — the component outputs generic `Tick.T` messages, making it transport-agnostic (CCSDS packets, GPIO pulses, etc.)
- Passive execution model is appropriate; sync triggered by external tick
- Configurable sync period, wait time, and initial enable state via `Init`
- Protected variables (`Protected_Natural_Counter`, `Protected_Boolean`) properly guard state shared between the synchronous tick handler and command handler
- `Sync_Once` command is a thoughtful addition for testing/commissioning

**Observations:**
- The component uses `delay until` inside `Tick_T_Recv_Sync`, which blocks the calling task for `Wait_Time_Ms`. This is by design (documented), but callers must be aware this is a blocking synchronous connector — it will hold up the tick source for the delay duration.
- `Transaction_Count` is not protected, but this is safe because it's only accessed in `Tick_T_Recv_Sync` (single synchronous invocation path). Correct as-is.

## Potential Issues

1. **`Ignore` on `Sys_Time.Arithmetic.Add` return status** — The result of adding `Wait_Time` to `Current_Sys_Time` could overflow (e.g., subseconds wrapping past a second boundary). The status is explicitly discarded (`Ignore`). If overflow occurs, `Time_Message_Time` may be incorrect. Consider at minimum logging an event on error status.

2. **Dropped message handlers are null** — All `*_Dropped` procedures are `is null`. If the time or tone message is dropped due to a full queue, the sync transaction silently proceeds (transaction count increments, data product updates). The slave would miss a sync with no indication on the master side. Consider emitting an event on drop.

3. **`delay until` in a passive component** — While documented, this is unusual for a passive component. The blocking delay ties up the caller's task. If `Wait_Time_Ms` is large, this could cause deadline misses in the calling task. The design relies on the integrator understanding this.

4. **Re-calling `Init` at runtime** — `Test_Enable_Disabled` and `Test_Sync_Once` re-call `Init` on the component instance mid-test. While fine for testing, `Init` resets `Transaction_Count` implicitly (via default record value? — actually it doesn't, `Init` doesn't touch `Transaction_Count`). The `Send_Counter` and `Do_Sync_Once` are reset though. This is consistent but worth noting: `Init` is not idempotent with respect to all state.

## Requirements Coverage

| Requirement | Coverage |
|---|---|
| Send time message at configurable rate | ✅ `Sync_Period` init param, tested in `Test_Time_Sync` |
| Send tone after configurable delay | ✅ `Wait_Time_Ms` init param, `delay until` in tick handler |
| Send transaction once on command | ✅ `Sync_Once` command, tested in `Test_Sync_Once` |
| Data product for transaction count | ✅ `Tone_Messages_Sent` data product, updated after each tone |

All 4 requirements have corresponding tests. Requirements traceability is solid.

## Test Quality

- **4 test cases** covering: periodic sync, enable/disable, sync-once, and invalid command handling
- Tests verify message counts, timestamps (with epsilon tolerance), transaction counters, data products, events, and command responses
- Good coverage of the disable→enable state transition
- Tests verify that no messages leak when disabled (101 ticks with zero messages)
- The `Eps` tolerance of 48 microseconds for time assertions is reasonable for a 5ms delay

**Minor gap:** No explicit test for the case where `Sync_Once` is issued while the component is *enabled* and the periodic counter is about to fire. Both would trigger in the same tick — the `or else Do_Once` means it fires, but the counter also advances. Not a bug, but an untested edge case.

## Types

- `tat_state` — Simple enum record (Enabled/Disabled), 8-bit packed. Clean.
- `tat_time_message` / `tat_tone_message` — Identical structures (Sys_Time + U32 counter). Could arguably be a single type, but having separate types improves semantic clarity and allows independent evolution. Fine as-is.
- Note: The actual connectors use `Tick.T` rather than these custom types. The custom types appear to be defined for documentation/downstream use but aren't directly used by this component's connectors.

## YAML Definitions

All YAML files (component, commands, events, data products, requirements, tests) are well-structured and consistent. Descriptions are clear and match the implementation.

## Overall Assessment

**Quality: High.** This is a well-implemented, well-tested Adamant component. The design is intentionally simple and generic. The main area for improvement is handling edge cases around the `Sys_Time.Arithmetic.Add` overflow and dropped messages — both are silent failure modes that could be addressed with informational events.

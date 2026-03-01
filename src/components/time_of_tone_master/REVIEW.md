# Time of Tone Master — Component Review

**Date:** 2026-03-01  
**Reviewer:** Adamant (automated)

## Summary

The Time of Tone Master is a passive component implementing the master side of a Time-at-Tone (TaT) clock synchronization protocol. It is an alternate to the standard `Time_At_Tone_Master` component, designed for systems where the exact tone-departure timestamp can be captured externally (e.g., at a serial port or hardware interface) and fed back via the `Tone_Message_Sys_Time_T_Recv_Sync` connector, yielding higher accuracy.

## Architecture & Design

| Aspect | Assessment |
|---|---|
| Execution model | Passive — correct for a tick-driven, synchronous component |
| Connector design | Clean separation: tick input, external tone-time input, tone/time message outputs, command/event/DP infrastructure |
| Init parameters | `Sync_Period` (tick divisor) and `Enabled_State` — sensible defaults (1, Enabled) |
| Thread safety | Protected variables (`Protected_Natural_Counter`, `Protected_Boolean`) guard state shared between the tick handler and command handlers — appropriate |
| Naming | Component is "Time **of** Tone" while the protocol and events reference "Time **at** Tone" — minor inconsistency, but documented and intentional |

## Strengths

1. **Two-phase sync with external timestamp support.** The optional `Tone_Message_Sys_Time_T_Recv_Sync` connector allows a lower-level driver to supply the precise tone-departure time, decoupling accuracy from software latency.
2. **Well-structured command interface.** Enable, Disable, and Sync_Once cover operational needs cleanly. Sync_Once is a thoughtful addition for testing/commissioning.
3. **Comprehensive data products.** Tone count, time count, and state are all published, giving full observability.
4. **`_If_Connected` pattern used throughout.** All send connectors use the optional-send idiom, so unconnected outputs don't cause runtime errors.
5. **Thorough unit tests.** Five tests covering nominal tone/time flow, enable/disable toggling, sync-once, and invalid command rejection. All assertion-based with history inspection.

## Issues & Observations

### Medium

1. **Tone and Time message counters can wrap without notification.**  
   `Tone_Message_Count` and `Time_Message_Count` are `Unsigned_32` and use `@ + 1` with no overflow check or event. At high tick rates this could silently wrap. Consider emitting a warning event on wrap or using a saturating increment.

2. **`Tone_Message_Count` is not protected.**  
   `Tone_Message_Count` and `Time_Message_Count` are plain record fields, not protected variables. `Tick_T_Recv_Sync` and `Tone_Message_Sys_Time_T_Recv_Sync` are both `recv_sync` connectors — if they can be invoked from different callers concurrently (e.g., different tasks calling synchronous connectors), there is a potential data race. If the execution model guarantees single-threaded access this is fine, but it should be documented.

3. **`Tone_Message_Sys_Time_T_Recv_Sync` has no guard on enabled state.**  
   Time messages are sent unconditionally whenever a tone timestamp arrives, even if TaT is disabled. If the external driver sends a stale/spurious timestamp while disabled, a time message will still be emitted. Consider gating on the enabled state or at least documenting this as intentional.

### Low

4. **`Send_Counter.Increment_Count` is called after the sync check in `Tick_T_Recv_Sync`.**  
   This means the very first tick (count = 0) triggers a sync. This is likely intentional (sync immediately on startup), but the behavior depends on `Is_Count_At_Period` semantics at count 0. Worth a comment.

5. **Dropped-message handlers are all null.**  
   The `*_Dropped` procedures are null bodies. For a time-critical synchronization component, silently dropping tone or time messages could cause slave clock drift. Consider at least logging an event on `Tone_Message_Send_Dropped` or `Time_Message_Send_Dropped`.

6. **No test for the disabled startup path's data products.**  
   `Set_Up_Test` always inits with `Enabled`. The `Test_Enable_Disabled` test re-inits with `Disabled` mid-test but doesn't verify initial Set_Up data products for the disabled case in isolation. Minor gap.

### Cosmetic

7. **Comment in `Tone_Message_Sys_Time_T_Recv_Sync` says "Send the tone message" but actually sends the *time* message.** (Line: `Self.Time_Message_Send_If_Connected (Message)` preceded by `-- Send the tone message:`). Copy-paste error in comment.

8. **`Disable_Time_At_Tone` command handler comment says "This enables" instead of "This disables"** in the spec file (line above `overriding function Disable_Time_At_Tone`). Another copy-paste comment error.

## Test Coverage

| Test | What it covers |
|---|---|
| `Test_Tone_Message` | Periodic tone output at sync period = 3, count incrementing, data products |
| `Test_Time_Message` | Time message output on external timestamp receipt, count incrementing |
| `Test_Enable_Disabled` | Disable → no messages; re-init + enable → messages resume at period = 1 |
| `Test_Sync_Once` | Disabled state + Sync_Once triggers exactly one tone, then stops |
| `Test_Invalid_Command` | Bad command length → Length_Error response + Invalid_Command_Received event |

**Missing coverage:**
- Overflow/wrap of message counters
- Behavior when `Tone_Message_Sys_Time_T_Recv_Sync` is called while disabled
- Dropped message scenarios
- Sync_Once while already enabled (interaction with periodic sync)

## Recommendations

1. Add a comment or event for counter wrap behavior.
2. Document thread-safety assumptions for the unprotected counters.
3. Fix the two copy-paste comment errors (items 7 & 8).
4. Consider gating time-message output on enabled state, or document why it's ungated.
5. Add a test for Sync_Once while enabled to verify it doesn't double-fire or interfere with the periodic counter.

## Verdict

**Solid component.** Clean design, good use of Adamant patterns, thorough tests. The issues found are minor-to-medium and mostly relate to edge-case robustness and comment accuracy. No blocking defects.

## Resolution Notes

| # | Issue | Severity | Status | Commit | Notes |
|---|-------|----------|--------|--------|-------|
| 1 | Copy-paste "tone" → "time" | Low | Fixed | 7d9925f | Comment correction |
| 2 | "enables" → "disables" | Low | Fixed | 1607244 | Comment correction |
| 3 | First-tick sync undocumented | Low | Fixed | b2a0560 | Added inline comment |
| 4 | Time messages when disabled | Medium | Fixed | 7ed4f9e | Gated on enabled state |
| 5 | Thread-safety assumption | Medium | Fixed | 39511ca | Documented assumption |

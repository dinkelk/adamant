# CCSDS Serial Interface — Code Review

## 1. Documentation Review

| # | Finding | Severity |
|---|---------|----------|
| D1 | README.md says "one serial interface component" but doesn't name it or describe the sync-pattern framing protocol. Users must read source to understand the wire format. | Low |
| D2 | The `Cpu_Usage` and `Count` fields in the instance record, and the CPU-measurement logic in `Ccsds_Space_Packet_T_Recv_Async`, are entirely undocumented — not in README, component.yaml, or LaTeX doc. There is no telemetry connector to expose `Cpu_Usage`, so the measurement is computed but never observable. | Medium |
| D3 | The `Listener` subtask comment in the spec says it "spin locks" at lowest priority, which is an important operational constraint, but this is not captured in the component.yaml description or README. | Low |

## 2. Model Review

| # | Finding | Severity |
|---|---------|----------|
| M1 | `Ccsds_Space_Packet_T_Recv_Async_Dropped` is `is null`. For a serial interface, silently dropping outbound packets with no event or counter is a potential observability gap. Consider emitting an event or incrementing a data product. | Medium |
| M2 | No data-product connectors are defined, so `Cpu_Usage` computed in the implementation is dead data — never reported anywhere. Either add a data-product connector or remove the computation. | Medium |

## 3. Component Implementation Review

| # | Finding | Severity |
|---|---------|----------|
| I1 | **Race condition on shared state between tasks.** `Listener` writes `Self.Listener_Task_Id` and `Self.Task_Id_Set` from the listener subtask, while `Ccsds_Space_Packet_T_Recv_Async` reads them from the main queue-dispatch task. There is no synchronization (protected object, atomic pragma, or suspension object) guarding these fields. On a multi-core system this is a data race that could yield stale/torn reads of `Task_Id`. | **High** |
| I2 | **CPU measurement is in the wrong procedure.** The CPU-usage measurement of the *listener* task is performed inside `Ccsds_Space_Packet_T_Recv_Async`, which runs on the *queue-dispatch* task — not the listener task. It reads `Self.Listener_Task_Id` to measure CPU time, but the measurement is triggered by send traffic (every 200 packets), not by listener activity. If no packets are sent, the measurement never runs. If sends are bursty, measurements are bursty. This seems like a design mistake — the measurement should probably live in the `Listener` procedure itself or be timer-driven. | **High** |
| I3 | **`Cpu_Usage` is computed but never used.** The field is written every 200 sends but there is no telemetry/data-product connector to export it. It is dead code. | Medium |
| I4 | **`Count` field name collision / confusion.** The instance record has a field `Self.Count` and the `Listener` procedure declares a local variable also named `Count`. While Ada scoping rules make this unambiguous, it harms readability and is error-prone during maintenance. | Low |
| I5 | **`Listener` processes exactly one packet per invocation.** After finding the sync pattern and reading one packet, the procedure returns. If the subtask framework calls `Listener` in a loop (which the task type implies), this is fine, but if bytes arrive faster than the re-invocation cadence, the `Bytes_Without_Sync` counter resets each call, causing the `Have_Not_Seen_Sync_Pattern` event to report byte counts that reset to zero on every successful packet — potentially misleading for operators debugging sync-loss scenarios. | Low |
| I6 | **No timeout or upper bound on sync search.** The sync-pattern search loop in `Listener` will spin/block indefinitely consuming bytes without ever yielding if the incoming stream never contains the sync pattern. The `Have_Not_Seen_Sync_Pattern` event fires every 20 bytes, but there is no abort or back-off mechanism. On a noisy line this could flood the event bus. | Medium |
| I7 | **Packet.Data not fully initialized before send.** After reading the header and data portion `(0 .. Packet_Length)`, the remaining bytes of `Packet.Data` are uninitialized (default zero for the type, but only if the type has a default — `Ccsds_Space_Packet.T` likely does via aggregate defaults). If the downstream consumer relies on `Packet_Length` to bound the valid region this is acceptable, but sending a record with partially meaningful data is a latent information-leak risk. | Low |

## 4. Unit Test Review

| # | Finding | Severity |
|---|---------|----------|
| T1 | **No test for `Packet_Send_Failed` event path.** The send test (`test_write`) only sends a valid packet. There is no test that sends a packet with an invalid CCSDS header to verify the `Packet_Send_Failed` event is emitted. | Medium |
| T2 | **No test for `Packet_Recv_Failed` event path.** The receive test (`test_read`) only exercises a valid packet. There is no test verifying that an oversized `Packet_Length` triggers `Packet_Recv_Failed`. | Medium |
| T3 | **No test for `Have_Not_Seen_Sync_Pattern` event.** No test sends garbage bytes before the sync pattern to verify this event fires correctly. | Medium |
| T4 | **No test for `Interpacket_Gap_Ms` init parameter.** The init parameter is never exercised; all tests use the default (0). | Low |
| T5 | **No test for `Ccsds_Space_Packet_T_Recv_Async_Dropped`.** Queue-full behavior on the async receive connector is never tested. | Low |
| T6 | **Write test does not verify output content.** `Test_Packet_Send` dispatches 4 packets but never asserts on the bytes actually written to the serial port. Verification relies on external `expected.txt` diff via the `test.do` script, making the test fragile and non-self-contained. The test also doesn't verify that the sync pattern is prepended. | Medium |
| T7 | **Write test uses a null reporter.** `test_write/test.adb` uses a custom `Null_Reporter` that suppresses all AUnit output, meaning test failures may be silently swallowed unless the exit code is checked by the harness. This is risky. | Medium |
| T8 | **Read test relies on `delay` for synchronization.** `Test_Packet_Receive` uses `delay Duration (0.5)` to wait for the listener task, which is timing-dependent and could cause flaky failures on slow or loaded systems. | Low |

## 5. Summary — Top 5 Highest-Severity Findings

| Rank | ID | Severity | Summary |
|------|----|----------|---------|
| 1 | I1 | **High** | Data race: `Listener_Task_Id` and `Task_Id_Set` written by listener task, read by dispatch task with no synchronization. |
| 2 | I2 | **High** | CPU-usage measurement of the listener task is performed in the wrong procedure (send handler instead of listener), making it semantically incorrect and traffic-dependent. |
| 3 | I3/M2 | Medium | `Cpu_Usage` is computed but never exported — dead code with no telemetry connector. |
| 4 | T1/T2/T3 | Medium | All three event paths (`Packet_Send_Failed`, `Packet_Recv_Failed`, `Have_Not_Seen_Sync_Pattern`) lack unit test coverage. |
| 5 | T7 | Medium | Write test uses a null reporter that silently swallows AUnit failures. |

## Resolution Notes

| # | Issue | Severity | Status | Commit | Notes |
|---|-------|----------|--------|--------|-------|
| 1 | Race condition on shared state | High | Fixed | cc5d518 | Added synchronization |
| 2 | CPU measurement in wrong procedure | High | Fixed | b7f6e69 | Moved to correct context |
| 3 | Undocumented Cpu_Usage/Count | Medium | Fixed | f043383 | Added documentation |
| 4 | Dropped packet handler silent | Medium | Fixed | ea76c66 | Added handling |
| 5 | Cpu_Usage computed but never exported | Medium | Fixed | 124aa3d | Addressed dead code |
| 6 | No upper bound on sync search | Medium | Fixed | 79aa573 | Added bound |
| 7 | No Packet_Send_Failed test | Medium | Fixed | 031ef92 | Added test |
| 8 | No Packet_Recv_Failed test | Medium | Fixed | 10b4ad5 | Added test |
| 9 | No Have_Not_Seen_Sync_Pattern test | Medium | Fixed | e68c9a0 | Added test |
| 10 | Write test no content verification | Medium | Fixed | 8626d55 | Added verification |

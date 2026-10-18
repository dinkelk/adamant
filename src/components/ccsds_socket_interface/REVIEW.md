# Code Review: Ccsds_Socket_Interface Component

**Reviewer:** Automated Code Review  
**Date:** 2026-02-28  
**Component:** `src/components/ccsds_socket_interface`

---

## 1. Documentation Review

### 1.1 Component YAML Description
- **Adequate.** The component description clearly explains the purpose: TCP/IP socket bridge for CCSDS packets with an internal listener task.
- **Minor:** Init parameter `Addr` default is `"\"127.0.0.1\""` (escaped quotes in YAML) — works but could be cleaner with YAML quoting.

### 1.2 Spec File Comment Mismatch
- **Issue (LOW):** The `.ads` file comment says *"The data send and receive connectors are of a generic buffer type, Com_Packet, so that data of an arbitrary format can be sent via this component."* This is stale — the component uses `Ccsds_Space_Packet.T`, not `Com_Packet`. The YAML description is correct; the spec comment was not updated.

### 1.3 Events YAML
- **Issue (LOW):** `Packet_Send_Failed` and `Packet_Recv_Failed` descriptions say *"because it has an invalid CCSDS header"* — but the actual failure comes from serialization/deserialization failure, which could have causes beyond an invalid header (e.g., stream errors, truncated data). The descriptions are misleading.

### 1.4 LaTeX Documentation
- **Adequate.** Standard template that pulls from generated build artifacts.

---

## 2. Model Review

### 2.1 Component YAML Model
- **Adequate.** Connectors, subtask, and init parameters are well-defined.
- **No issues** with connector definitions.

---

## 3. Component Implementation Review

### 3.1 `Convert_Socket_Address` — Index Mapping Assumption
- **Issue (MEDIUM):** The loop `for I in Gnat_Ip'Range loop ... Adamant_Ip'First + (I - Gnat_Ip'First)` assumes both arrays have the same length. If `Gnat_Ip` has more elements than `Adamant_Ip` (or vice versa), this would silently corrupt or raise `Constraint_Error`. While currently safe (both are 4-byte IPv4), the code has no assertion or comment documenting this assumption. A `pragma Assert` that the lengths match would be defensive.

### 3.2 `Init` — Double Init Without Cleanup
- **Issue (MEDIUM):** `Init` can be called multiple times (as demonstrated in test_write where Init is called twice with different ports). The second call overwrites `Self.Addr` and `Self.Port` without disconnecting an existing connection. If the first `Init` succeeded, the old socket connection is leaked — `Connect` calls `Self.Sock.Connect` on a potentially already-connected socket. The behavior depends on the `Socket.Instance` implementation, but the component should explicitly disconnect before reconnecting.

### 3.3 `Disconnect` — Event Naming Semantics
- **Issue (LOW):** `Disconnect` emits `Socket_Not_Connected` which semantically means "connection failed." Using the same event for both "failed to connect" and "lost connection during operation" conflates two distinct conditions. A separate `Socket_Disconnected` event would improve observability.

### 3.4 `Listener` — Zero-Length Packet Silently Dropped
- **Issue (MEDIUM):** In `Listener`, after successful deserialization, packets with `Packet_Length = 0` are silently discarded (`if Packet.Header.Packet_Length > 0`). Per CCSDS 133.0-B-2, `Packet_Length` of 0 means 1 byte of data (the field is "number of octets minus 1"). A valid CCSDS packet can have `Packet_Length = 0`. This filter incorrectly drops valid single-byte-data packets. If the intent is to filter uninitialized headers, this check is too broad.

### 3.5 `Listener` — No Reconnection Attempt When Disconnected
- **Issue (LOW):** When `Listener` finds the socket disconnected, it sleeps for 1 second but does not attempt reconnection. Only the `Ccsds_Space_Packet_T_Recv_Async` (send path) attempts reconnection. This creates an asymmetry: the receive path never recovers on its own. If no packets are being sent, the listener will spin-sleep forever without reconnecting.

### 3.6 `Ccsds_Space_Packet_T_Recv_Async_Dropped` — Null Handler
- **Issue (LOW):** The dropped-message handler is `is null`. Dropped packets on the async queue are silently lost with no event or counter. For a ground interface component, this is an observability gap — operators have no way to know packets were dropped.

### 3.7 Thread Safety — Concurrent Access to `Self.Sock`
- **Issue (HIGH):** The `Listener` subtask and the main task (servicing `Ccsds_Space_Packet_T_Recv_Async`) both access `Self.Sock` concurrently without synchronization. `Listener` calls `Is_Connected`, `Stream`, `Disconnect` while the main task calls `Is_Connected`, `Connect`, `Stream`, `Disconnect`. This is a data race. If `Socket.Instance` is not internally thread-safe (and typical GNAT socket wrappers are not), concurrent `Connect`/`Disconnect`/`Stream` operations can cause undefined behavior. This is the most critical finding.

---

## 4. Unit Test Review

### 4.1 Test Structure
- Two test suites: `test_read` (receive path) and `test_write` (send path), using external `socat` processes for socket endpoints. This is a reasonable integration-test approach.

### 4.2 Missing Test Coverage — Functional Gaps
- **Issue (MEDIUM):** No test for `Packet_Send_Failed` event. `test_write` sends a `Packet_Bad` but only when the socket is disconnected (so it's dropped before reaching serialization). There is no test that triggers serialization failure on a connected socket.
- **Issue (MEDIUM):** No test for `Packet_Recv_Failed` event. The receive test only sends valid data.
- **Issue (LOW):** No test for `Socket_Error` exception handling (disconnect-on-error path) in either send or receive paths.
- **Issue (LOW):** No test for `Ccsds_Space_Packet_T_Recv_Async_Dropped` (queue overflow).
- **Issue (LOW):** `Final` procedure is never explicitly tested.

### 4.3 Timing-Dependent Tests
- **Issue (LOW):** The read test uses `delay Duration (0.5)` to wait for the listener task to process data. This is inherently racy — on a slow or loaded system, 500ms may not be enough. There's no polling/synchronization mechanism to confirm the packet was received before asserting.

### 4.4 test_write — No Assertion on Failed-Send Path
- **Issue (MEDIUM):** In `Test_Packet_Send`, when packets are sent while disconnected, the test asserts `Dispatch_All` returns 1 but does not verify that `Packet_Send_Failed` was (or was not) emitted, nor does it verify the socket reconnection behavior. The 4 packets sent to the disconnected socket just vanish without any assertion on what happened to them.

### 4.5 test_read Tester vs test_write Tester — History Depth Discrepancy
- **Issue (INFO):** `test_read` tester uses `Depth => 10` for histories; `test_write` uses `Depth => 100`. Inconsistent but functionally harmless given test sizes.

---

## 5. Summary — Top 5 Highest-Severity Findings

| # | Severity | Section | Finding |
|---|----------|---------|---------|
| 1 | **HIGH** | 3.7 | **Data race on `Self.Sock`**: Listener subtask and main task concurrently access the socket instance without synchronization. Can cause undefined behavior. |
| 2 | **MEDIUM** | 3.4 | **Valid CCSDS packets dropped**: `Packet_Length = 0` filter in `Listener` drops valid single-data-byte packets per CCSDS spec (field is N-1 encoded). |
| 3 | **MEDIUM** | 3.2 | **Double Init leaks connection**: Calling `Init` twice without disconnect leaks the first socket connection. |
| 4 | **MEDIUM** | 4.2/4.4 | **No tests for error events**: `Packet_Send_Failed` and `Packet_Recv_Failed` events are never exercised in tests; failed-send path has no assertions. |
| 5 | **MEDIUM** | 3.5 | **Listener never reconnects**: Receive path does not attempt reconnection; only the send path does. System cannot recover receive capability without send traffic. |

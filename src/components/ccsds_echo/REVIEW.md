# Code Review: Ccsds_Echo Component

**Reviewer:** Automated Review  
**Date:** 2026-02-28  
**Component:** `src/components/ccsds_echo`

---

## 1. Documentation Review

### 1.1 — YAML Description Adequate
**Severity:** Info  
**Location:** `ccsds_echo.component.yaml`  
**Issue:** Documentation is clear and sufficient. The component description, connector descriptions, and packet descriptions accurately reflect the implementation behavior.  
**Proposed Fix:** None required.

---

## 2. Model Review

### 2.1 — No Event or Status Connector for Dropped Packets
**Severity:** Medium  
**Location:** `ccsds_echo.component.yaml`  
**Original Code:**
```yaml
connectors:
  - description: The CCSDS receive connector.
    type: Ccsds_Space_Packet.T
    kind: recv_sync
  - description: The packet send connector.
    type: Packet.T
    kind: send
  - description: The system time is retrieved via this connector.
    return_type: Sys_Time.T
    kind: get
```
**Issue:** The component has no `event` or `data_product` connectors. When `Packet_T_Send_Dropped` is invoked (downstream queue full), the drop is silently ignored (`is null`). In a flight system, silent data loss with no telemetry indication is a safety concern — operators would have no visibility that echoed packets are being lost.  
**Proposed Fix:** Add an event connector and emit an event in `Packet_T_Send_Dropped` to report the drop, or at minimum add a data product connector with a drop counter. Example:
```yaml
  - description: Events are sent out of this connector.
    type: Event.T
    kind: send
```

### 2.2 — No Command or Configuration Interface
**Severity:** Low  
**Location:** `ccsds_echo.component.yaml`  
**Issue:** The component has no enable/disable mechanism. Once connected, it echoes all CCSDS packets unconditionally. In bandwidth-constrained downlink scenarios, there is no way to suppress echo output without disconnecting the component. This may be acceptable for a simple utility component but limits operational flexibility.  
**Proposed Fix:** Consider adding a command connector with an enable/disable command, or document that this is intentional and suppression is handled at the assembly level.

---

## 3. Component Implementation Review

### 3.1 — Silent Drop of Packets on Full Queue
**Severity:** High  
**Location:** `component-ccsds_echo-implementation.ads:25`  
**Original Code:**
```ada
overriding procedure Packet_T_Send_Dropped (Self : in out Instance; Arg : in Packet.T) is null;
```
**Issue:** When the downstream packet queue is full, `Packet_T_Send_Dropped` silently discards the packet with no logging, event, counter, or any observable side effect. This is the most significant finding: in an operational scenario, an overloaded downlink could silently lose echoed telemetry with zero indication to flight operators or ground systems. This violates the general Adamant pattern of reporting dropped messages.  
**Proposed Fix:** Implement the procedure to emit an event or increment a counter:
```ada
overriding procedure Packet_T_Send_Dropped (Self : in out Instance; Arg : in Packet.T) is
begin
   Self.Event_T_Send_If_Connected (Self.Events.Packet_Dropped (Self.Sys_Time_T_Get));
end Packet_T_Send_Dropped;
```
This requires adding an event connector to the model (see Finding 2.1).

### 3.2 — Use of `_Truncate` Variant Without Validation or Warning
**Severity:** Medium  
**Location:** `component-ccsds_echo-implementation.adb:12`  
**Original Code:**
```ada
Self.Packet_T_Send_If_Connected (Self.Packets.Echo_Packet_Truncate (Self.Sys_Time_T_Get, Arg));
```
**Issue:** The `Echo_Packet_Truncate` function will silently truncate CCSDS packets that exceed the Adamant packet payload size. If a large CCSDS packet is received, the echoed version will be silently truncated, producing an incomplete/corrupted echo with no indication to the receiver. This undermines the "echo" contract — the ground system expects an exact copy but may receive a truncated one.  
**Proposed Fix:** Either:
1. Emit an event when truncation occurs (check `Arg` length against the packet capacity before calling), or
2. Use a non-truncating variant and handle the length error explicitly, or
3. Document the maximum CCSDS packet size that can be echoed without truncation so integrators can verify at the assembly level.

### 3.3 — Synchronous Receive with Downstream Send
**Severity:** Low  
**Location:** `component-ccsds_echo-implementation.adb:12`  
**Issue:** The `recv_sync` connector means this handler runs in the caller's task context. The `Packet_T_Send_If_Connected` call enqueues to a downstream queue, which is generally safe. However, if the send connector is also synchronous in a particular assembly configuration, this could introduce unexpected blocking or priority inversion in the caller's context. This is an integration-level concern rather than a component bug.  
**Proposed Fix:** Document that this component executes in the caller's context and integrators should ensure the downstream packet consumer does not introduce blocking.

---

## 4. Unit Test Review

### 4.1 — No Unit Tests Exist
**Severity:** High  
**Location:** `src/components/ccsds_echo/` (no `test/` directory)  
**Issue:** There are no unit tests for this component. While the implementation is simple (single procedure, one line of logic), the following behaviors are untested:
1. **Nominal echo:** A CCSDS packet is received and a corresponding Adamant packet is sent.
2. **Truncation behavior:** A CCSDS packet larger than the echo packet capacity is handled.
3. **Disconnected send:** Behavior when the send connector is not connected.
4. **Packet content fidelity:** The echoed packet data matches the input CCSDS packet.
5. **Timestamp correctness:** The packet header timestamp comes from `Sys_Time_T_Get`.

Even for trivial components, unit tests serve as regression protection and executable documentation.  
**Proposed Fix:** Create a `test/` directory with tests covering at minimum: nominal echo, content fidelity, truncation, and disconnected-connector behavior.

---

## 5. Summary — Top 5 Highest-Severity Findings

| # | Severity | Finding | Location |
|---|----------|---------|----------|
| 1 | **High** | No unit tests exist | Component `test/` directory missing |
| 2 | **High** | `Packet_T_Send_Dropped` silently discards packets with no observable indication | `implementation.ads:25` |
| 3 | **Medium** | No event/data_product connector to report anomalies (drops, truncation) | `ccsds_echo.component.yaml` |
| 4 | **Medium** | `Echo_Packet_Truncate` silently truncates oversized packets with no warning | `implementation.adb:12` |
| 5 | **Low** | No enable/disable command; echo is always active when connected | `ccsds_echo.component.yaml` |

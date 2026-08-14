# Memory Dumper Component — Code Review

**Reviewer:** Automated Safety-Critical Code Review  
**Date:** 2026-02-28  
**Branch:** `review/components-memory-dumper`

---

## 1. Documentation Review

### DOC-01 — Stale comments in `Test_Invalid_Address`

- **Location:** `test/memory_dumper_tests-implementation.adb`, multiple locations (lines with `-- Send command to crc entire first region:`)
- **Original Code:**
  ```ada
  -- Send command to crc entire first region:
  Region := (Address => Region_1_Address - Storage_Offset (1), Length => Region_1'Length);
  ```
  and:
  ```ada
  -- Send command to crc entire first region:
  Region := (Address => Region_2_Address - Storage_Offset (1), Length => Region_1'Length + 2);
  ```
  and:
  ```ada
  -- Send command to crc entire first region:
  Region := (Address => Region_2_Address + Storage_Offset (5), Length => 16);
  ```
  and:
  ```ada
  -- Send command to crc entire first region:
  Region := (Address => Region_2_Address + Storage_Offset (5), Length => 15);
  ```
- **Explanation:** The comment `-- Send command to crc entire first region:` is copy-pasted throughout the test but the code is exercising invalid regions, partial regions, and Region_2—not "entire first region." This is misleading during review and debugging.
- **Corrected Code:** Update each comment to match the actual intent (the `Put_Line` below each already has a better description):
  ```ada
  -- Send command with address out of range:
  -- Send command with everything out of range:
  -- Send command with region extending past boundary:
  -- Send command with valid sub-region of region 2:
  ```
- **Severity:** Low

### DOC-02 — Stale comments: "One error event should have been returned"

- **Location:** `test/memory_dumper_tests-implementation.adb`, multiple locations after successful command dispatches at the end of `Test_Invalid_Address`
- **Original Code:**
  ```ada
  -- One error event should have been returned.
  Natural_Assert.Eq (T.Event_T_Recv_Sync_History.Get_Count, 13);
  ```
- **Explanation:** The final block tests a *valid* region (both CRC and Dump succeed), yet the comment says "One error event should have been returned." The 13 events include 10 error + 3 success events. The comment is incorrect and confusing.
- **Corrected Code:**
  ```ada
  -- Success events should have been returned (no additional error events).
  ```
- **Severity:** Low

### DOC-03 — Missing `with String_Util` usage explanation in tester

- **Location:** `test/component-memory_dumper-implementation-tester.adb`, line 4
- **Explanation:** `with String_Util;` is used only for `Trim_Both` in logging. This is fine but noting it is auto-generated boilerplate—no action needed.
- **Severity:** _Informational (no issue)_

### DOC-04 — Requirements lack traceability IDs

- **Location:** `memory_dumper.requirements.yaml`
- **Original Code:**
  ```yaml
  requirements:
    - text: The component shall dump a memory region on command.
    - text: The component shall crc a memory region on command.
    - text: The component shall reject commands to dump or crc memory in off-limit regions.
  ```
- **Explanation:** Requirements have no unique identifiers (e.g., `REQ-MD-001`), making formal traceability to tests and design difficult. While the YAML schema may not require an `id` field, safety-critical processes benefit from explicit requirement IDs.
- **Corrected Code:**
  ```yaml
  requirements:
    - id: REQ-MD-001
      text: The component shall dump a memory region on command.
    - id: REQ-MD-002
      text: The component shall crc a memory region on command.
    - id: REQ-MD-003
      text: The component shall reject commands to dump or crc memory in off-limit regions.
  ```
- **Severity:** Medium

---

## 2. Model Review

### MDL-01 — Unused `Memory_Dump_Packet` packet definition

- **Location:** `memory_dumper.packets.yaml`
- **Original Code:**
  ```yaml
  packets:
    - name: Memory_Dump_Packet
      description: This packet contains memory.
  ```
- **Explanation:** The component sends memory dumps via the `Memory_Dump_Send` connector (type `Memory_Packetizer_Types.Memory_Dump`), not via this packet. The `Memory_Dump_Packet` is defined in the packets YAML and a packet history is generated in the tester, but neither the implementation nor the tests ever produce or assert on this packet. The only use of `Memory_Dumper_Packets` in tests is to call `Get_Memory_Dump_Packet_Id`, which provides the ID used in the `Memory_Dump` record's `Id` field. The packet itself appears to exist solely to allocate a packet ID. If this is intentional, the description should say so; otherwise this is dead model infrastructure.
- **Corrected Code:** Either document the purpose:
  ```yaml
  packets:
    - name: Memory_Dump_Packet
      description: Provides the packet ID used when sending memory dumps via the Memory_Dump_Send connector.
  ```
  Or remove if unused.
- **Severity:** Low

### MDL-02 — Component model is clean

- The `component.yaml` correctly declares all connectors with appropriate types and kinds. The `init` parameter uses `not_null: true` which matches the spec's `not null` access parameter. Commands, events, and data products are well-structured. No issues found.
- **Severity:** _Informational (no issue)_

---

## 3. Component Implementation Review

### IMP-01 — `Crc_Memory` calls `Sys_Time_T_Get` three times for one command

- **Location:** `component-memory_dumper-implementation.adb`, `Crc_Memory` function
- **Original Code:**
  ```ada
  if Memory_Manager_Types.Is_Region_Valid (Arg, Self.Regions, Ptr, Ignore) then
     Self.Event_T_Send_If_Connected (Self.Events.Crcing_Memory (Self.Sys_Time_T_Get, Arg));
     -- Calculate CRC:
     Crc := Crc_16.Compute_Crc_16 (Ptr);
     -- Report CRC:
     declare
        Time : constant Sys_Time.T := Self.Sys_Time_T_Get;
     begin
        Self.Event_T_Send_If_Connected (Self.Events.Memory_Crc (Time, ...));
        Self.Data_Product_T_Send_If_Connected (Self.Data_Products.Crc_Report (Time, ...));
     end;
     return Success;
  else
     Self.Event_T_Send_If_Connected (Self.Events.Invalid_Memory_Region (Self.Sys_Time_T_Get, Arg));
  ```
- **Explanation:** In the success path, `Sys_Time_T_Get` is called twice (once for `Crcing_Memory` event, once for the `declare` block). In the failure path it's called once more. The second `declare` block correctly captures a single timestamp for the CRC event and data product (good). However, the `Crcing_Memory` event gets a different timestamp than the CRC result event/data product. If time consistency across all artifacts of a single command execution matters, a single timestamp should be captured at the top. This also has a minor performance implication (extra connector invocation).
- **Corrected Code:**
  ```ada
  if Memory_Manager_Types.Is_Region_Valid (Arg, Self.Regions, Ptr, Ignore) then
     declare
        Time : constant Sys_Time.T := Self.Sys_Time_T_Get;
     begin
        Self.Event_T_Send_If_Connected (Self.Events.Crcing_Memory (Time, Arg));
        Crc := Crc_16.Compute_Crc_16 (Ptr);
        Self.Event_T_Send_If_Connected (Self.Events.Memory_Crc (Time, (Region => (Address => Arg.Address, Length => Arg.Length), Crc => Crc)));
        Self.Data_Product_T_Send_If_Connected (Self.Data_Products.Crc_Report (Time, (Region => (Address => Arg.Address, Length => Arg.Length), Crc => Crc)));
     end;
     return Success;
  ```
- **Severity:** Medium

### IMP-02 — `Dump_Memory` similarly calls `Sys_Time_T_Get` without reuse opportunity

- **Location:** `component-memory_dumper-implementation.adb`, `Dump_Memory` function
- **Original Code:**
  ```ada
  Self.Event_T_Send_If_Connected (Self.Events.Dumping_Memory (Self.Sys_Time_T_Get, Arg));
  ```
- **Explanation:** Only one timestamp call in the success path here, so this is less severe. However, for consistency with the pattern recommended in IMP-01, capturing `Time` once at the top of each branch would be cleaner.
- **Severity:** Low

### IMP-03 — `Command_T_Recv_Async_Dropped` is null — no telemetry on dropped commands

- **Location:** `component-memory_dumper-implementation.ads`
- **Original Code:**
  ```ada
  overriding procedure Command_T_Recv_Async_Dropped (Self : in out Instance; Arg : in Command.T) is null;
  ```
- **Explanation:** If the component's async queue is full and a command is dropped, no event or telemetry is generated. In a safety-critical flight system, silently dropping commands is a significant observability gap. An operator would have no indication that a memory dump command was lost. Consider emitting an event or incrementing a counter.
- **Corrected Code:**
  ```ada
  overriding procedure Command_T_Recv_Async_Dropped (Self : in out Instance; Arg : in Command.T);
  ```
  With a body that sends a "command dropped" event (if the event connector is connected).
- **Severity:** High

### IMP-04 — Other `*_Dropped` handlers are null — no telemetry on dropped outputs

- **Location:** `component-memory_dumper-implementation.ads`
- **Original Code:**
  ```ada
  overriding procedure Command_Response_T_Send_Dropped (Self : in out Instance; Arg : in Command_Response.T) is null;
  overriding procedure Memory_Dump_Send_Dropped (Self : in out Instance; Arg : in Memory_Packetizer_Types.Memory_Dump) is null;
  overriding procedure Data_Product_T_Send_Dropped (Self : in out Instance; Arg : in Data_Product.T) is null;
  overriding procedure Event_T_Send_Dropped (Self : in out Instance; Arg : in Event.T) is null;
  ```
- **Explanation:** If any outgoing connector drops a message, it is silently lost. In particular, `Memory_Dump_Send_Dropped` means a dump result could vanish without trace. `Event_T_Send_Dropped` is inherently hard to report (you can't send an event about a dropped event), but the others deserve consideration. This is a common Adamant pattern so it may be acceptable depending on project conventions, but worth flagging for safety-critical systems.
- **Severity:** Medium

### IMP-05 — Implementation is otherwise clean

- Memory region validation is delegated to `Memory_Manager_Types.Is_Region_Valid` which properly gates both dump and CRC operations. The `Ignore` out parameter (index) is correctly unused. Command response is always sent. `_If_Connected` guards are used for all optional connectors. No uninitialized state, no race conditions in the active component pattern.
- **Severity:** _Informational (no issue)_

---

## 4. Unit Test Review

### TST-01 — No test for `Command_T_Recv_Async_Dropped` behavior

- **Location:** `test/memory_dumper_tests-implementation.adb` (missing test)
- **Explanation:** The tester has infrastructure for `Expect_Command_T_Send_Dropped` and `Command_T_Send_Dropped_Count`, but no test exercises the scenario where the component's queue is full and a command is dropped. This should be tested to verify the dropped handler (especially if IMP-03 is addressed and the handler becomes non-null).
- **Corrected Code:** Add a test that fills the component queue and sends an additional command, then asserts the dropped count increments and (if IMP-03 is implemented) an appropriate event is emitted.
- **Severity:** Medium

### TST-02 — `Packets` variable unused except for ID in `Test_Nominal_Dumping`

- **Location:** `test/memory_dumper_tests-implementation.adb`, `Test_Nominal_Dumping`
- **Original Code:**
  ```ada
  Packets : Memory_Dumper_Packets.Instance;
  ```
- **Explanation:** A local `Packets` instance is created just to call `Get_Memory_Dump_Packet_Id`. This works but is slightly wasteful—the same ID is available from `T.Packets.Get_Memory_Dump_Packet_Id` (via the tester). Minor style issue.
- **Severity:** Low

### TST-03 — No test for boundary-exact region (address + length == region end exactly)

- **Location:** `test/memory_dumper_tests-implementation.adb`
- **Explanation:** The `Test_Invalid_Address` test checks many invalid cases and one valid sub-region, but doesn't explicitly test the exact boundary case: a request starting at the very last byte of a region with length 1, or a request that spans exactly the full region boundary. While `Test_Nominal_Dumping` does test full-region dumps, an explicit boundary test in the invalid-address test procedure would strengthen confidence in the boundary validation logic.
- **Severity:** Low

### TST-04 — Test_Invalid_Address has a misleading final block comment

- **Location:** `test/memory_dumper_tests-implementation.adb`, end of `Test_Invalid_Address`
- **Original Code:**
  ```ada
  -- One error event should have been returned.
  Natural_Assert.Eq (T.Event_T_Recv_Sync_History.Get_Count, 13);
  Natural_Assert.Eq (T.Memory_Dump_Recv_Sync_History.Get_Count, 1);
  Natural_Assert.Eq (T.Data_Product_T_Recv_Sync_History.Get_Count, 1);
  ```
- **Explanation:** Already covered in DOC-02. The assertions themselves are correct—the comment is wrong. The final block successfully CRCs and dumps a valid region, producing 3 new events (1 Crcing_Memory + 1 Memory_Crc + 1 Dumping_Memory = 3, total 13), 1 dump, and 1 data product. The code is correct; the comment is misleading.
- **Severity:** Low

---

## 5. Summary — Top 5 Issues

| # | ID | Severity | Location | Description |
|---|-----|----------|----------|-------------|
| 1 | IMP-03 | **High** | `implementation.ads` | `Command_T_Recv_Async_Dropped` is null — dropped commands produce no telemetry, creating an observability gap in flight. |
| 2 | IMP-01 | **Medium** | `implementation.adb`, `Crc_Memory` | `Sys_Time_T_Get` called multiple times per command; timestamps may be inconsistent across event and data product for the same CRC operation. |
| 3 | IMP-04 | **Medium** | `implementation.ads` | All outbound `*_Dropped` handlers are null — dropped memory dumps and command responses are silently lost. |
| 4 | DOC-04 | **Medium** | `requirements.yaml` | Requirements lack unique IDs, hindering formal traceability in a safety-critical context. |
| 5 | TST-01 | **Medium** | `test/` (missing) | No unit test exercises the queue-full / command-dropped scenario. |

## Resolution Notes

| # | Issue | Severity | Status | Commit | Notes |
|---|-------|----------|--------|--------|-------|
| 1 | Null Command_Dropped handler | High | Fixed | - | Added event + handler |
| 2 | Multiple Sys_Time calls | Medium | Fixed | - | Single timestamp |
| 3 | All *_Dropped null | Medium | Not Fixed | - | Needs model regen |
| 4 | No requirement IDs | Medium | Fixed | - | Added REQ-MD-001–003 |
| 5 | No queue-full test | Medium | Not Fixed | - | Needs codegen |
| 6-11 | Low items | Low | Mixed | - | Comments, descriptions, variable cleanup |

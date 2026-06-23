# Memory Packetizer — Code Review

**Component:** `src/components/memory_packetizer`
**Date:** 2026-03-01
**Reviewer:** Automated (Claude)
**Branch:** `review/components-memory-packetizer`

---

## 1. Documentation Review

### DOC-01 — Init parameter description says "single second" instead of "single time period"
- **File:** `memory_packetizer.component.yaml`, line in `Max_Packets_Per_Time_Period` description
- **Original:**
  ```yaml
  description: The maximum number of packets that this component will produce in a single second. The component will stop producing packets if the threshold is met, until the end of a second period has elapsed.
  ```
- **Explanation:** The init also accepts `Time_Period_In_Seconds` (default 1), so the period is not necessarily one second. The description should say "time period" rather than "single second" / "second period" to match the actual behavior.
- **Corrected:**
  ```yaml
  description: The maximum number of packets that this component will produce in a single time period. The component will stop producing packets if the threshold is met, until the end of the current time period has elapsed.
  ```
- **Severity:** Low

### DOC-02 — Same "single second" wording in .ads Init comment
- **File:** `component-memory_packetizer-implementation.ads`, Init comment block
- **Original:**
  ```ada
  -- Max_Packets_Per_Time_Period : Natural - The maximum number of packets that this component will produce in a single second. The component will stop producing packets if the threshold is met, until the end of a second period has elapsed.
  ```
- **Corrected:** Replace "single second" with "single time period" and "second period" with "time period", matching DOC-01.
- **Severity:** Low

### DOC-03 — Typo "over the measure" in .adb Init comment
- **File:** `component-memory_packetizer-implementation.adb`, Init comment
- **Original:**
  ```ada
  -- Time_Period_In_Seconds : Positive - The time period in seconds over which the measure the number of packets produced.
  ```
- **Corrected:**
  ```ada
  -- Time_Period_In_Seconds : Positive - The time period in seconds over which to measure the number of packets produced.
  ```
- **Severity:** Low

### DOC-04 — Typo "Sent" instead of "Set" in .adb Init body
- **File:** `component-memory_packetizer-implementation.adb`, line inside `Init`
- **Original:**
  ```ada
  -- Sent the maximum packet rate:
  ```
- **Corrected:**
  ```ada
  -- Set the maximum packet rate:
  ```
- **Severity:** Low

### DOC-05 — LaTeX document has no Data Products section
- **File:** `doc/memory_packetizer.tex`
- **Explanation:** The document includes sections for Commands and Events but omits a Data Products subsection. Since the component defines a `Max_Packets_Per_Time_Period` data product, the document should include it for completeness.
- **Corrected:** Add after the Events subsection:
  ```latex
  \subsection{Data Products}
  \input{build/tex/memory_packetizer_data_products.tex}
  ```
- **Severity:** Low

---

## 2. Model Review

### MOD-01 — No issues found

The `component.yaml` model is well-structured. Connector types and kinds are correct. Init parameters have sensible defaults. The commands, events, data products, and requirements YAML files are consistent with the implementation. The `Memory_Packetizer_Types` package correctly defines the `Memory_Dump` record with an `Id` and `Memory_Pointer`.

---

## 3. Component Implementation Review

### IMPL-01 — Sequence count not incremented for untracked packet IDs across multi-packet dumps
- **File:** `component-memory_packetizer-implementation.adb`, `Memory_Dump_Recv_Async`, inner sequence count increment
- **Original:**
  ```ada
  -- Increment the sequence count, only if we are tracking this id's sequence count:
  if Sequence_Count_Entry_Index >= Self.Sequence_Count_List'First and then
      Sequence_Count_Entry_Index <= Self.Sequence_Count_List'Last
  then
     Sequence_Count := @ + 1;
  end if;
  ```
- **Explanation:** When `Get_Sequence_Count_Entry_Index` returns 0 (max IDs exceeded), the local `Sequence_Count` is never incremented. This means **all packets** within a single multi-packet dump of an untracked ID will carry `Sequence_Count = 0`, making it impossible for the ground to determine packet ordering or detect missing packets within that dump. This contradicts the general design intent of sequence counts distinguishing packets.
- **Corrected:**
  ```ada
  -- Always increment the local sequence count so packets within
  -- a single dump are distinguishable, even if the id is untracked:
  Sequence_Count := @ + 1;
  ```
- **Severity:** Medium

### IMPL-02 — `Max_Packets_Per_Time_Period = 0` causes infinite loop
- **File:** `component-memory_packetizer-implementation.adb`, `Memory_Dump_Recv_Async`
- **Original:**
  ```ada
  if Self.Num_Packets_Sent >= Self.Max_Packets_Per_Time_Period then
     -- Sleep until the end of this period:
     delay until Self.Next_Period_Start;
     ...
     Self.Num_Packets_Sent := 0;
  end if;
  ```
- **Explanation:** `Max_Packets_Per_Time_Period` is `Natural` (i.e. can be 0). If set to 0, the condition `0 >= 0` is always true after resetting `Num_Packets_Sent` to 0, causing the component to spin in an infinite sleep-wake loop, never sending any packets and never draining its queue. This can also be triggered at runtime via the `Set_Max_Packet_Rate` command. In a flight system this would effectively hang the component's task.
- **Corrected:** Either:
  - Change `Max_Packets_Per_Time_Period` from `Natural` to `Positive` in init and command argument types, or
  - Add a guard: if `Max_Packets_Per_Time_Period = 0`, skip rate limiting and send no packets (return immediately), or emit an event and reject the value.
  
  Preferred (reject at command level):
  ```ada
  overriding function Set_Max_Packet_Rate (Self : in out Instance; Arg : in Packets_Per_Period.T) return Command_Execution_Status.E is
     use Command_Execution_Status;
     The_Time : constant Sys_Time.T := Self.Sys_Time_T_Get;
  begin
     if Arg.Max_Packets = 0 then
        -- TODO: emit an appropriate event for invalid rate
        return Failure;
     end if;
     -- Set the rate:
     Do_Set_Max_Packet_Rate (Self, Arg.Max_Packets, Arg.Period);
     ...
  ```
- **Severity:** High

### IMPL-03 — `Set_Max_Packet_Rate` command is not thread-safe with the packetization loop
- **File:** `component-memory_packetizer-implementation.adb`
- **Explanation:** Both `Memory_Dump_Recv_Async` and `Command_T_Recv_Async` (which calls `Set_Max_Packet_Rate`) are dispatched from the same async queue on the same task, so they execute sequentially. A command can only be processed between full dump packetizations, not mid-dump. This means the rate change won't take effect until the current dump finishes, which could be a long time for large memory regions. This is inherent to the single-task active component design and is **not a bug**, but it is worth noting that rate changes during a large dump are deferred. No code change needed.
- **Severity:** N/A (design note, not an issue)

### IMPL-04 — Packet_T_Send_Dropped and other send-dropped handlers are null
- **File:** `component-memory_packetizer-implementation.ads`
- **Original:**
  ```ada
  overriding procedure Packet_T_Send_Dropped (Self : in out Instance; Arg : in Packet.T) is null;
  ```
- **Explanation:** If the downstream packet consumer's queue is full, packets are silently dropped with no event, no counter, and no telemetry. For a safety-critical flight component performing memory dumps (potentially for anomaly investigation), silent data loss is problematic. At minimum, an event should be emitted and a counter maintained.
- **Corrected:** Implement `Packet_T_Send_Dropped` to emit an event and/or increment a data product counter tracking dropped packets.
- **Severity:** Medium

### IMPL-05 — `Time_Period_S` field has no default initializer
- **File:** `component-memory_packetizer-implementation.ads`
- **Original:**
  ```ada
  Time_Period_S : Positive; -- in seconds
  ```
- **Explanation:** Unlike other fields in the record which have defaults, `Time_Period_S` has no default. If the component is used before `Init` is called, reading this field would yield an uninitialized value. While this would be a usage error, defensive initialization is preferred in safety-critical code.
- **Corrected:**
  ```ada
  Time_Period_S : Positive := 1; -- in seconds
  ```
- **Severity:** Low

---

## 4. Unit Test Review

### TEST-01 — Test uses wrong packet index for last-packet buffer length check (copy-paste error)
- **File:** `test/memory_packetizer_tests-implementation.adb`, `Test_Nominal_Packetization`, second round of content checks (~line area for packets 12 and 16)
- **Original:**
  ```ada
  Byte_Array_Assert.Eq (T.Packet_T_Recv_Sync_History.Get (12).Buffer (Mem_Region_Length .. T.Packet_T_Recv_Sync_History.Get (4).Header.Buffer_Length - 1), [0 .. Packet_Data_Length / 2 - 1 => 4]);
  ```
  and
  ```ada
  Byte_Array_Assert.Eq (T.Packet_T_Recv_Sync_History.Get (16).Buffer (Mem_Region_Length .. T.Packet_T_Recv_Sync_History.Get (8).Header.Buffer_Length - 1), [0 .. Packet_Data_Length / 2 - 1 => 4]);
  ```
- **Explanation:** The upper bound of the buffer slice for packet 12 incorrectly references packet **4**'s `Buffer_Length`, and packet 16 references packet **8**'s. It should reference its own packet's `Buffer_Length`. This works by coincidence because packets 4, 8, 12, and 16 all have the same buffer length (they are all the last/short packet of identical-sized dumps). However, this is a copy-paste error that masks real validation — if the lengths ever differed, the test would check the wrong slice.
- **Corrected:**
  ```ada
  Byte_Array_Assert.Eq (T.Packet_T_Recv_Sync_History.Get (12).Buffer (Mem_Region_Length .. T.Packet_T_Recv_Sync_History.Get (12).Header.Buffer_Length - 1), [0 .. Packet_Data_Length / 2 - 1 => 4]);
  ...
  Byte_Array_Assert.Eq (T.Packet_T_Recv_Sync_History.Get (16).Buffer (Mem_Region_Length .. T.Packet_T_Recv_Sync_History.Get (16).Header.Buffer_Length - 1), [0 .. Packet_Data_Length / 2 - 1 => 4]);
  ```
- **Severity:** Medium

### TEST-02 — No test for zero-length memory dump
- **File:** `test/memory_packetizer_tests-implementation.adb`
- **Explanation:** There is no test case for a zero-length `Memory_Pointer`. If `Byte_Array_Pointer.Length` returns 0, the while loop in `Memory_Dump_Recv_Async` is skipped entirely, but sequence count tracking still allocates a slot. This edge case should be tested to confirm no packets are emitted and no side effects occur.
- **Severity:** Low

### TEST-03 — No test for `Max_Packets_Per_Time_Period = 0`
- **File:** `test/memory_packetizer_tests-implementation.adb`
- **Explanation:** Relates to IMPL-02. There is no test that exercises the `Max_Packets_Per_Time_Period = 0` scenario via init or command. This would expose the infinite loop bug.
- **Severity:** Medium

### TEST-04 — No test for sequence count rollover
- **File:** `test/memory_packetizer_tests-implementation.adb`
- **Explanation:** `Sequence_Count_Mod_Type` is a modular type that will wrap around. There is no test verifying correct behavior at the rollover boundary. For flight code, confirming rollover behavior is important for ground system compatibility.
- **Severity:** Low

### TEST-05 — Test_Max_Packet_Id_Exceeded checks sequence counts of 0 for untracked IDs across multi-packet dumps
- **File:** `test/memory_packetizer_tests-implementation.adb`, `Test_Max_Packet_Id_Exceeded`
- **Original:**
  ```ada
  Sequence_Count_Assert.Eq (T.Packet_T_Recv_Sync_History.Get (9).Header.Sequence_Count, 0);
  Sequence_Count_Assert.Eq (T.Packet_T_Recv_Sync_History.Get (10).Header.Sequence_Count, 0);
  ```
- **Explanation:** This test *validates* the behavior flagged in IMPL-01 — that both packets within a single multi-packet dump of an exceeded-ID carry sequence count 0. If IMPL-01 is fixed, this test assertion must be updated to expect incrementing sequence counts (0, 1).
- **Severity:** Medium (linked to IMPL-01)

---

## 5. Summary — Top 5 Issues

| # | ID | Severity | Description |
|---|-----|----------|-------------|
| 1 | IMPL-02 | **High** | `Max_Packets_Per_Time_Period = 0` causes infinite sleep-wake loop, hanging the component task. Reachable via command at runtime. |
| 2 | IMPL-01 | **Medium** | Untracked packet IDs emit all packets in a multi-packet dump with sequence count 0, preventing ground from ordering or gap-detecting within the dump. |
| 3 | IMPL-04 | **Medium** | `Packet_T_Send_Dropped` is null — downstream packet drops are silently lost with no telemetry. |
| 4 | TEST-01 | **Medium** | Copy-paste error: packet 12/16 content checks reference packet 4/8's buffer length instead of their own. Passes by coincidence. |
| 5 | TEST-03 | **Medium** | No test for `Max_Packets_Per_Time_Period = 0`, leaving the infinite-loop bug (IMPL-02) undetected. |

## Resolution Notes

| # | Issue | Severity | Status | Commit | Notes |
|---|-------|----------|--------|--------|-------|
| 1 | Zero rate infinite loop | High | Fixed | fd40e21 | Returns Failure + event |
| 2 | Sequence count stuck at 0 | Medium | Fixed | a48eb15 | Always increment |
| 3 | Null Packet_T_Send_Dropped | Medium | Fixed | b4c5016 | Added event handler |
| 4 | Copy-paste test error | Medium | Fixed | 8c04859 | Corrected refs |
| 5 | No zero-rate test | Medium | Fixed | 3c2384e | Added test |
| 6 | Untracked ID assertions | Medium | Fixed | 91339ef | Updated expectations |
| 7-14 | Low items | Low | Mixed | - | Doc fixes, defaults, zero-length test |

# Event Packetizer — Code Review

**Component:** `src/components/event_packetizer`
**Branch:** `review/components-event-packetizer`
**Date:** 2026-02-28
**Reviewer:** Automated (Claude)

---

## 1. Documentation Review

### DOC-1 — Test description says "3 internal packets" but test uses 2 (Low)

**File:** `test/event_packetizer.tests.yaml`, line for `Test_Nominal_Packetization`
**Also:** `test/event_packetizer_tests-implementation.ads`

**Original:**
```yaml
  - name: Test_Nominal_Packetization
    description: This unit test exercises the nominal behavior of the event packetizer with 3 internal packets.
```

**Explanation:** The description states "3 internal packets" but the test body calls `Init (Num_Internal_Packets => 2, ...)`. The description is misleading.

**Corrected:**
```yaml
  - name: Test_Nominal_Packetization
    description: This unit test exercises the nominal behavior of the event packetizer with 2 internal packets.
```

**Severity:** Low

### DOC-2 — Comment says "third tick" when first tick sends packet (Low)

**File:** `test/event_packetizer_tests-implementation.adb`, inside `Test_Partial_Packet_Timeout_Of_1`

**Original:**
```ada
      -- Send some ticks and expect packet on third tick:
      T.Tick_T_Send (A_Tick);
      Natural_Assert.Eq (T.Packet_T_Recv_Sync_History.Get_Count, 1);
```

**Explanation:** With `Partial_Packet_Timeout => 1`, the packet is sent on the very first tick, not the third. The comment was copy-pasted from `Test_Partial_Packet_Timeout`.

**Corrected:**
```ada
      -- Send a tick and expect packet on first tick (timeout of 1):
      T.Tick_T_Send (A_Tick);
      Natural_Assert.Eq (T.Packet_T_Recv_Sync_History.Get_Count, 1);
```

**Severity:** Low

### DOC-3 — Second "third tick" comment in Test_Partial_Packet_Timeout_Of_1 (Low)

**File:** `test/event_packetizer_tests-implementation.adb`, inside `Test_Partial_Packet_Timeout_Of_1`, second occurrence

**Original:**
```ada
      -- Send some ticks and expect packet on third tick:
      T.Tick_T_Send (A_Tick);
      Natural_Assert.Eq (T.Packet_T_Recv_Sync_History.Get_Count, 2);
```

**Explanation:** Same copy-paste issue; the packet fires on the first tick with timeout=1.

**Corrected:**
```ada
      -- Send a tick and expect packet on first tick (timeout of 1):
```

**Severity:** Low

---

## 2. Model Review

### MOD-1 — No event connector for reporting dropped events or internal errors (Medium)

**File:** `event_packetizer.component.yaml`

**Explanation:** The component drops events silently when buffers are full and only reports via a data product counter. In safety-critical systems, an event (telemetry annotation) should be emitted when events begin being dropped, and ideally when the buffers are nearly full. Without an Event_T_Send connector, operators have no way to receive an asynchronous alert. The data product is only updated on tick, which may be too late for real-time monitoring.

**Corrected:** Add an `Event.T` send connector and emit an event on first drop after a non-drop state.

**Severity:** Medium

### MOD-2 — Component description references "partial packet timeout" but `events_packet` packet has no field/description for timeout semantics (Low)

**File:** `event_packetizer.packets.yaml`

**Original:**
```yaml
  - name: Events_Packet
    description: This packet contains events as subpackets.
```

**Explanation:** The description is minimal. It would benefit from noting that the packet may be partially filled (due to timeout or command) and describing the sub-packet layout (serialized Event_Header + param bytes, repeated).

**Severity:** Low

---

## 3. Component Implementation Review

### IMPL-1 — `Destroy` does not reset `Initialized` flag — use-after-free (Critical)

**File:** `component-event_packetizer-implementation.adb`, inside `Protected_Packet_Array.Destroy`

**Original:**
```ada
      procedure Destroy is
         procedure Free_If_Testing is new Safe_Deallocator.Deallocate_If_Testing (Object => Packet_Array, Name => Packet_Array_Access);
      begin
         -- Free packet array from heap:
         Free_If_Testing (Packets);

         -- Reset other variables:
         Index := Packet_Array_Index'First;
         Num_Packets_Full := 0;
         Events_Dropped := 0;
         New_Packets_Dropped := False;
      end Destroy;
```

**Explanation:** After `Destroy`, the `Initialized` flag remains `True`. If any event arrives after `Destroy` (e.g., during shutdown sequencing), `Insert_Event` will proceed past the `if Initialized` guard and dereference the now-null (or deallocated) `Packets` pointer, causing a segfault or storage error. In a safety-critical system, this is a use-after-destroy vulnerability.

**Corrected:**
```ada
      procedure Destroy is
         procedure Free_If_Testing is new Safe_Deallocator.Deallocate_If_Testing (Object => Packet_Array, Name => Packet_Array_Access);
      begin
         -- Mark as uninitialized first, so concurrent access is safe:
         Initialized := False;

         -- Free packet array from heap:
         Free_If_Testing (Packets);

         -- Reset other variables:
         Index := Packet_Array_Index'First;
         Num_Packets_Full := 0;
         Events_Dropped := 0;
         New_Packets_Dropped := False;
      end Destroy;
```

**Severity:** Critical

### IMPL-2 — `Events_Dropped` counter can silently wrap around from `Unsigned_32'Last` to 0 (High)

**File:** `component-event_packetizer-implementation.adb`, inside `Increment_Events_Dropped`

**Original:**
```ada
         procedure Increment_Events_Dropped is
         begin
            Events_Dropped := @ + 1;
            New_Packets_Dropped := True;
         end Increment_Events_Dropped;
```

**Explanation:** `Events_Dropped` is `Unsigned_32`. If it reaches `Unsigned_32'Last` (4,294,967,295), the next increment wraps to 0 due to modular arithmetic. The telemetry would then report 0 dropped events, misleading operators. While unlikely in short missions, long-duration flights with persistent event storms could trigger this. A saturating counter is the standard approach in flight software.

**Corrected:**
```ada
         procedure Increment_Events_Dropped is
         begin
            if Events_Dropped < Unsigned_32'Last then
               Events_Dropped := @ + 1;
            end if;
            New_Packets_Dropped := True;
         end Increment_Events_Dropped;
```

**Severity:** High

### IMPL-3 — `Get_Bytes_Available` adds `Buffer'First` to `Buffer_Length`, producing wrong result when `Buffer'First /= 0` (Medium)

**File:** `component-event_packetizer-implementation.adb`, inside `Protected_Packet_Array.Get_Bytes_Available`

**Original:**
```ada
            Num_Bytes_Occupied_In_Current_Packet := Packets (Index).Header.Buffer_Length + Packets (Index).Buffer'First;
            return Num_Bytes_Not_Full - Num_Bytes_Occupied_In_Current_Packet;
```

**Explanation:** `Buffer_Length` already represents the number of bytes occupied (set via `Current_Index - Buffer'First`). Adding `Buffer'First` again converts it to an absolute index, not a byte count. This only works correctly when `Buffer'First = 0`. If `Packet_Buffer_Type'First` is ever non-zero, the returned bytes-available will be too small by `Buffer'First` bytes. This is a latent defect — current Adamant packet buffers start at 0, but the code is not robust to future changes.

**Corrected:**
```ada
            Num_Bytes_Occupied_In_Current_Packet := Packets (Index).Header.Buffer_Length;
            return Num_Bytes_Not_Full - Num_Bytes_Occupied_In_Current_Packet;
```

**Severity:** Medium

### IMPL-4 — `Invalid_Command` silently triggers `Send_Packet` behavior instead of reporting failure (Medium)

**File:** `component-event_packetizer-implementation.adb`, `Invalid_Command` procedure

**Original:**
```ada
   overriding procedure Invalid_Command (Self : in out Instance; Cmd : in Command.T; Errant_Field_Number : in Unsigned_32; Errant_Field : in Basic_Types.Poly_Type) is
      ...
   begin
      -- ... let's just forget this error happened and send the packet anyways.
      Self.Send_Packet_Next_Tick := True;
   end Invalid_Command;
```

**Explanation:** An invalid command (wrong length, garbled data) silently triggers operational behavior. In safety-critical systems, invalid commands should be rejected and reported, not treated as valid. A corrupted command bus could cause unintended packet sends. The comment acknowledges this is a shortcut.

**Corrected:**
```ada
   overriding procedure Invalid_Command (Self : in out Instance; Cmd : in Command.T; Errant_Field_Number : in Unsigned_32; Errant_Field : in Basic_Types.Poly_Type) is
      pragma Unreferenced (Errant_Field_Number);
      pragma Unreferenced (Errant_Field);
   begin
      -- Reject invalid commands. Do not trigger any behavior.
      Self.Command_Response_T_Send_If_Connected ((
         Source_Id        => Cmd.Header.Source_Id,
         Registration_Id  => Self.Command_Reg_Id,
         Command_Id       => Cmd.Header.Id,
         Status           => Command_Execution_Status.Failure));
   end Invalid_Command;
```

**Severity:** Medium

### IMPL-5 — `Next_Packet` uses `Packet_Array_Index'Last` (`Positive'Last`) instead of `Packets'Last` for increment guard (Low)

**File:** `component-event_packetizer-implementation.adb`, inside `Insert_Event.Next_Packet`

**Original:**
```ada
            if Index < Packet_Array_Index'Last then
               Index := @ + 1;
            end if;
            -- Check for roll over:
            if Index > Packets'Last then
               Index := Packets'First;
            end if;
```

**Explanation:** The first check guards against `Positive` overflow, not against exceeding the actual array bounds. This works because the second check handles wrap-around, but it's misleading. The intent is circular buffer advancement; the code should directly express that.

**Corrected:**
```ada
            if Index >= Packets'Last then
               Index := Packets'First;
            else
               Index := @ + 1;
            end if;
```

**Severity:** Low

### IMPL-6 — `Packet_T_Send_Dropped` is null — dropped outgoing packets are silently lost (Medium)

**File:** `component-event_packetizer-implementation.ads`

**Original:**
```ada
   overriding procedure Packet_T_Send_Dropped (Self : in out Instance; Arg : in Packet.T) is null;
```

**Explanation:** If the downstream packet queue is full, the fully-formed event packet is silently discarded with no telemetry, no counter increment, and no event. The component tracks *input* event drops but not *output* packet drops. In a congested system, this means data loss with no visibility.

**Severity:** Medium

### IMPL-7 — `Bytes_Available` data product sampled before `Pop_Packet` — reports stale value (Low)

**File:** `component-event_packetizer-implementation.adb`, `Tick_T_Recv_Sync`

**Original:**
```ada
      -- Get the current amount of storage in the event buffer for use later:
      Bytes_Available := Self.Packet_Array.Get_Bytes_Available;

      -- Grab a partial packet if commanded...
      ...Pop_Packet...
      ...

      -- Send out the free space within the component before the packet was popped
      if Self.Previous_Bytes_Available /= Bytes_Available then
         Self.Data_Product_T_Send_If_Connected (Self.Data_Products.Bytes_Available (Self.Sys_Time_T_Get, (Value => Bytes_Available)));
```

**Explanation:** The bytes-available value is captured *before* the pop, so the data product always reflects the state before the tick handler ran. The comment even acknowledges this: "before the packet was popped." This means after popping a full packet, the freed space won't appear in telemetry until the *next* tick. This is a design choice but may confuse operators monitoring buffer health.

**Severity:** Low

---

## 4. Unit Test Review

### TEST-1 — No test for `Invalid_Command` handler (Medium)

**File:** `test/event_packetizer_tests-implementation.adb`

**Explanation:** The `Invalid_Command` handler contains non-trivial logic (setting `Send_Packet_Next_Tick := True`) but is never exercised by any test. A test should send a command with an incorrect length and verify the resulting behavior.

**Severity:** Medium

### TEST-2 — No test for `Packet_T_Send_Dropped` / downstream queue full scenario (Medium)

**File:** `test/event_packetizer_tests-implementation.adb`

**Explanation:** The null `Packet_T_Send_Dropped` handler is never tested. A test should verify component behavior when the downstream packet connector is full or disconnected.

**Severity:** Medium

### TEST-3 — No test for `Destroy` followed by event insertion (High)

**File:** `test/event_packetizer_tests-implementation.adb`

**Explanation:** Given the critical bug in IMPL-1 (`Initialized` not reset on `Destroy`), a test that calls `Destroy` then sends events would immediately catch this defect. No such test exists.

**Severity:** High

### TEST-4 — Test uses both `Event_Header.T'Object_Size / 8` and `Event_Header.Serialization.Serialized_Length` interchangeably (Medium)

**File:** `test/event_packetizer_tests-implementation.adb`, multiple locations

**Example:**
```ada
      for Idx in 1 .. (Packet_Types.Packet_Buffer_Type'Length / (Event_Header.T'Object_Size / 8 + Event_3.Header.Param_Buffer_Length)) - 1 loop
```
vs.
```ada
      Bytes_Sent := @ + (Event_Header.Serialization.Serialized_Length + Event_3.Header.Param_Buffer_Length);
```

**Explanation:** `Object_Size / 8` gives the in-memory size of the Ada type (which may include padding), while `Serialization.Serialized_Length` gives the wire-format size. The implementation uses `Serialized_Length` for packing events into packets. If these values ever diverge (e.g., due to alignment changes), the loop iteration counts in tests will be wrong, producing false passes or failures. Tests should consistently use `Serialized_Length` to match the implementation.

**Corrected:** Replace all occurrences of `Event_Header.T'Object_Size / 8` with `Event_Header.Serialization.Serialized_Length` in the test body.

**Severity:** Medium

### TEST-5 — `Event_3` param buffer has values beyond `Param_Buffer_Length` (Low)

**File:** `test/event_packetizer_tests-implementation.adb`

**Original:**
```ada
   Event_3 : constant Event.T := (Header => ((1, 2), 3, 3), Param_Buffer => [0 => 1, 1 => 2, 2 => 3, 3 => 4, 4 => 5, 5 .. 11 => 6, others => 0]);
   -- Event header + 3 bytes, 14 bytes.
```

**Explanation:** `Param_Buffer_Length` is 3, meaning only bytes 0..2 are semantically valid. But the buffer initializes indices 3..11 with non-zero values. While harmless (the component only reads up to `Param_Buffer_Length`), it is confusing and could mask bugs where too many bytes are inadvertently copied.

**Corrected:**
```ada
   Event_3 : constant Event.T := (Header => ((1, 2), 3, 3), Param_Buffer => [0 => 1, 1 => 2, 2 => 3, others => 0]);
```

**Severity:** Low

---

## 5. Summary — Top 5 Issues

| # | ID | Severity | Summary |
|---|------|----------|---------|
| 1 | IMPL-1 | **Critical** | `Destroy` does not reset `Initialized` — post-destroy event insertion dereferences freed memory |
| 2 | IMPL-2 | **High** | `Events_Dropped` counter wraps at `Unsigned_32'Last`, reporting 0 drops to operators |
| 3 | TEST-3 | **High** | No test for destroy-then-use scenario, which would catch the Critical IMPL-1 bug |
| 4 | IMPL-4 | **Medium** | `Invalid_Command` silently triggers `Send_Packet` instead of rejecting the malformed command |
| 5 | IMPL-3 | **Medium** | `Get_Bytes_Available` adds `Buffer'First` to `Buffer_Length` — latent defect if buffer is non-zero-indexed |

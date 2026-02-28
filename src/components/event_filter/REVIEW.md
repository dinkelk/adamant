# Event Filter Component — Code Review

**Branch:** `review/components-event-filter`
**Date:** 2026-02-28
**Reviewer:** Automated

---

## 1. Documentation Review

### DOC-01 — Misleading comment about thread safety (Medium)

**File:** `component-event_filter-implementation.adb`, `Tick_T_Recv_Sync`, line within the `Send_Packet` block

**Original:**
```ada
-- Grab the bytes from the package. As a note, this is not thread safe, but is done for speed. It is assumed that we will not be changing states while the packet is being sent.
```

**Explanation:** The call `Self.Event_Entries.Get_Entry_Array` is made *inside* the protected object, so the call itself is serialized. However, the returned `Byte_Array_Access` (a pointer) is then used *outside* the protected object (passed to `Self.Packets.Event_Filter_State_Packet`) with no lock held. The comment acknowledges the race but treats it as acceptable. In safety-critical code, this is a design concern worth documenting as a known limitation with a rationale (e.g., "single-writer via synchronous execution model"), not just a casual aside.

**Recommendation:** Either strengthen the comment with a formal safety rationale, or copy the byte array inside the protected call.

**Severity:** Medium

### DOC-02 — Component description init section has empty `description` field (Low)

**File:** `event_filter.component.yaml`, `init.description`

**Original:**
```yaml
init:
  description:
```

**Explanation:** The init section's `description` field is blank. It should describe what initialization does (e.g., "Initializes the event filter with the given ID range and default filter list").

**Corrected:**
```yaml
init:
  description: Initializes the event filter with the given ID range and optionally a list of event IDs to filter by default.
```

**Severity:** Low

### DOC-03 — Dump_Event_States_Received event description says "decrement cycle" (Low)

**File:** `event_filter.events.yaml`

**Original:**
```yaml
  - name: Dump_Event_States_Received
    description: Event that indicates the process of building the packet that stores the event states has started and will send the packet once we go through a decrement cycle.
```

**Explanation:** The phrase "decrement cycle" is meaningless in this component's context. The packet is sent on the next tick. This appears to be copy-paste from a different component.

**Corrected:**
```yaml
    description: Event that indicates a request to dump the event filter state packet has been received. The packet will be sent on the next tick.
```

**Severity:** Low

---

## 2. Model Review

### MOD-01 — No event-severity levels defined (Low)

**File:** `event_filter.events.yaml`

**Explanation:** None of the events specify a severity/criticality level (e.g., `Warning`, `Informational`). While the Adamant framework may have defaults, explicitly setting severity on events like `Filter_Event_Invalid_Id` (which indicates an operator error) versus `Filtered_Event` (purely informational) improves ground system integration and telemetry triage.

**Severity:** Low

### MOD-02 — Requirements lack unique identifiers and traceability (Medium)

**File:** `event_filter.requirements.yaml`

**Explanation:** Requirements are listed as bare text with no IDs. This makes formal traceability (requirement → test, requirement → code) impossible to verify from the YAML alone. Each requirement should have a unique identifier (e.g., `EF-001`).

**Severity:** Medium

---

## 3. Component Implementation Review

### IMP-01 — Returning a `Byte_Array_Access` from a protected object leaks unsynchronized mutable state (High)

**File:** `component-event_filter-implementation.ads` / `.adb`, `Protected_Event_Filter_Entries.Get_Entry_Array` and its use in `Tick_T_Recv_Sync`

**Original (spec):**
```ada
function Get_Entry_Array return Basic_Types.Byte_Array_Access;
```

**Original (usage in Tick_T_Recv_Sync):**
```ada
Packet_Bytes := Self.Event_Entries.Get_Entry_Array;
State_Packet_Status := Self.Packets.Event_Filter_State_Packet (Timestamp, Packet_Bytes.all, State_Packet);
```

**Explanation:** `Get_Entry_Array` returns an access (pointer) to the internal byte array of `Event_Filter_Package`. After the protected function call returns, the lock is released, but the caller still holds a raw pointer to internal protected state. Any concurrent call to a protected *procedure* (e.g., `Set_Filter_State` from `Command_T_Recv_Sync`) could mutate the array while `Tick_T_Recv_Sync` is reading through the pointer.

In the current component model (`execution: passive`, all `recv_sync`), calls are serialized by the caller's task, so the race cannot occur **as long as** all three connectors (tick, event, command) are invoked from the same task. However, if the assembly ever routes tick and command from different tasks, this becomes a data race. The design relies on an undocumented assembly-level invariant.

**Corrected approach:** Copy the data inside the protected object:
```ada
procedure Get_Entry_Array_Copy (Dest : out Basic_Types.Byte_Array; Length : out Natural);
```
Or document the single-task constraint as a formal assumption.

**Severity:** High

### IMP-02 — `pragma Assert` used for runtime validation of command arguments in range commands (High)

**File:** `component-event_filter-implementation.adb`, `Filter_Event_Range` and `Unfilter_Event_Range`

**Original:**
```ada
when Invalid_Id =>
   pragma Assert (False, "Found Invalid_Id for the Event Filter when commanding enable range of events, which should have been caught in an earlier statement");
```

**Explanation:** `pragma Assert` is typically *disabled* in production builds (`-gnata` is needed to enable it). If for any reason the pre-check does not catch an invalid ID (e.g., due to a bug in `Event_Filter_Entry`, or TOCTOU if the design ever changes), the `Invalid_Id` branch would silently fall through to `null` with no error reporting. In safety-critical flight code, this should use a mechanism that is never compiled away, such as raising a specific exception or using `pragma Assert` with a project-wide policy that it is *never* suppressed, documented as such.

**Corrected:**
```ada
when Invalid_Id =>
   -- This should be unreachable given the range check above.
   -- Use a hard assertion that cannot be suppressed:
   raise Program_Error with "Unexpected Invalid_Id in Event Filter range command after pre-validation";
```

**Severity:** High

### IMP-03 — Counter overflow on `Unsigned_32` filtered/unfiltered counts (Medium)

**File:** `component-event_filter-implementation.adb`, `Tick_T_Recv_Sync`; also depends on `Event_Filter_Entry`

**Explanation:** `Total_Event_Filtered_Count` and `Total_Event_Unfiltered_Count` are `Unsigned_32`. Over a long mission, these counters will wrap around at 2³²−1. The data-product comparison `Num_Events_Filtered /= Self.Total_Event_Filtered_Count` will still work correctly after wrap (it will simply trigger a data-product update on every tick once the wrap happens and they transiently differ), but the telemetry value itself becomes misleading. If `Event_Filter_Entry` uses modular arithmetic, the wrap is silent. Consider either:
- Using `Unsigned_64` for lifetime counters, or
- Documenting the wrap behavior as accepted.

**Severity:** Medium

### IMP-04 — Duplicate Dump_Event_States call path may return misleading command status (Medium)

**File:** `component-event_filter-implementation.adb`, `Filter_Event` / `Unfilter_Event` / `Filter_Event_Range` / `Unfilter_Event_Range`

**Original:**
```ada
case Arg.Issue_State_Packet is
   when Issue_Packet_Type.Issue =>
      Ret := Self.Dump_Event_States;
   when Issue_Packet_Type.No_Issue =>
      null;
end case;
return Ret;
```

**Explanation:** `Dump_Event_States` currently always returns `Success`, so `Ret` is always `Success`. But if `Dump_Event_States` were ever modified to return `Failure` (e.g., due to resource constraints), the *original* command (Filter_Event) would report `Failure` even though the filter state change itself succeeded. The command status would be ambiguous — did the filter change fail, or just the packet dump? Consider either always returning the filter operation status and relying on the dump event for dump-status reporting, or sending a separate command response for the dump.

**Severity:** Medium

---

## 4. Unit Test Review

### TEST-01 — `Set_Up_Test` calls `Set_Up` before `Init` (High)

**File:** `test/event_filter_tests-implementation.adb`, `Set_Up_Test`

**Original:**
```ada
overriding procedure Set_Up_Test (Self : in out Instance) is
begin
   Self.Tester.Init_Base;
   Self.Tester.Connect;
   -- Self.Tester.Component_Instance.Init (Event_Id_Start_Range => TBD, Event_Id_End_Range => TBD, Event_Filter_List => TBD);
   Self.Tester.Component_Instance.Set_Up;
end Set_Up_Test;
```

**Explanation:** The `Init` call is *commented out* and each test body calls `Init` individually, but `Set_Up` is called *before* any `Init`. `Set_Up` calls `Self.Event_Entries.Get_Event_Filtered_Count` and other protected object functions on an uninitialized `Event_Filter_Package`. This works only because the protected object's default state happens to be benign (returning 0 / null access). In a stricter runtime or with different `Event_Filter_Entry` internals, this could cause undefined behavior or constraint errors.

**Corrected:** Either move `Set_Up` out of `Set_Up_Test` and call it in each test after `Init`, or provide a default `Init` in `Set_Up_Test`:
```ada
Self.Tester.Component_Instance.Init (Event_Id_Start_Range => 0, Event_Id_End_Range => 0);
Self.Tester.Component_Instance.Set_Up;
```

**Severity:** High

### TEST-02 — No test for counter wrap-around behavior (Low)

**File:** `test/event_filter_tests-implementation.adb`

**Explanation:** There is no test verifying behavior when the filtered/unfiltered counters approach or reach `Unsigned_32'Last`. Given IMP-03 above, a test confirming that wrap-around is handled gracefully (or documenting expected behavior) would be valuable.

**Severity:** Low

### TEST-03 — No test for `Event_Forward_T_Send_Dropped` and other `*_Dropped` handlers (Low)

**File:** `test/event_filter_tests-implementation.adb`

**Explanation:** The `*_Dropped` handlers are all `null` procedures, which is a valid design choice, but no test verifies that the component survives a dropped-message scenario (e.g., when a send connector is not connected). This is a minor gap.

**Severity:** Low

### TEST-04 — Hardcoded packet byte values make tests fragile (Low)

**File:** `test/event_filter_tests-implementation.adb`, `Test_Issue_State_Packet`, `Test_Command_Single_State_Change`, `Test_Command_Range_State_Change`

**Original (example):**
```ada
Packet_Assert.Eq (T.Event_Filter_State_Packet_History.Get (1),
   (Header => (..., Buffer_Length => 3),
    Buffer => [0 => 36, 1 => 64, 2 => 136, others => 0]));
```

**Explanation:** The raw byte values (36, 64, 136, etc.) encode the bit-packed filter states but are opaque magic numbers. If `Event_Filter_Entry`'s bit layout changes, these tests break silently with confusing assertion failures. Consider computing expected values programmatically or adding comments showing the bit breakdown.

**Severity:** Low

---

## 5. Summary — Top 5 Issues

| # | ID | Severity | Summary |
|---|-----|----------|---------|
| 1 | IMP-01 | **High** | `Get_Entry_Array` returns pointer to protected internal state, enabling potential data race if single-task assumption is violated. |
| 2 | IMP-02 | **High** | `pragma Assert(False)` in range command error paths may be compiled out in production, silently ignoring errors. |
| 3 | TEST-01 | **High** | `Set_Up` is called on uninitialized component (before `Init`) in test fixture — relies on benign default state. |
| 4 | IMP-03 | **Medium** | `Unsigned_32` lifetime counters will silently wrap on long missions with no documented mitigation. |
| 5 | IMP-04 | **Medium** | Combining filter-change and packet-dump into one command return status creates ambiguous failure reporting. |

## Resolution Notes

| # | Issue | Severity | Status | Commit | Notes |
|---|-------|----------|--------|--------|-------|
| 1 | Raw pointer leak from protected object | High | Fixed | - | Added safety rationale documenting single-task invariant |
| 2 | pragma Assert(False) in error branches | High | Fixed | - | Replaced with raise Program_Error |
| 3 | Test calls Set_Up before Init | High | Fixed | - | Added default Init call |
| 4 | Empty init description | Medium | Fixed | - | Co-fixed with IMP-01 |
| 5 | No requirement IDs | Medium | Fixed | - | Added EF-001 through EF-005 |
| 6 | Unsigned_32 counter wrap | Medium | Fixed | - | Documented as accepted |
| 7 | Piggybacked dump status | Medium | Fixed | - | Decoupled from filter response |
| 8 | Init description missing | Low | Fixed | - | Added to YAML |
| 9 | "decrement cycle" copy-paste | Low | Fixed | - | Corrected description |
| 10 | No event severities | Low | Fixed | - | Added to all 12 events |
| 11 | No wrap-around test | Low | Not Fixed | - | Needs counter injection |
| 12 | No dropped-message test | Low | Not Fixed | - | Needs tester framework |
| 13 | Magic packet bytes | Low | Fixed | - | Added bit-layout comments |

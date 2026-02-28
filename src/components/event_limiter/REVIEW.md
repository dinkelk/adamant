# Event Limiter Component — Code Review

**Reviewer:** Automated Review (Claude)
**Date:** 2026-02-28
**Branch:** `review/components-event-limiter`

---

## 1. Documentation Review

### Issue 1.1 — Init comment says "enabled" but means "disabled"

- **Location:** `component-event_limiter-implementation.adb`, line ~93 (Init procedure comment block)
- **Original Code:**
  ```ada
  -- Event_Disable_List : Two_Counter_Entry.Event_Id_List - A list of event IDs that are enabled by default
  ```
- **Explanation:** The Init comment says the `Event_Disable_List` parameter contains IDs "enabled by default," but the parameter name and the component.yaml both correctly state these are IDs **disabled** by default. This contradicts the YAML and the `.ads` file, creating confusion for integrators.
- **Corrected Code:**
  ```ada
  -- Event_Disable_List : Two_Counter_Entry.Event_Id_List - A list of event IDs that are disabled by default
  ```
- **Severity:** Medium

### Issue 1.2 — Tick connector description inconsistency ("every tick" vs. "every 10 ticks")

- **Location:** `component-event_limiter-implementation.ads`, `Tick_T_Recv_Sync` comment (line ~56)
- **Original Code:**
  ```ada
  -- This is the base tick for the component. Upon reception the component will decrement the count of each ID unless it is already 0. Every 10 ticks, an event of what is filtered will be sent.
  ```
- **Explanation:** The `.ads` says "Every 10 ticks" but the implementation sends the limited-events event **every tick** (when events were limited). The component.yaml correctly says "Every tick." The `.adb` `Tick_T_Recv_Sync` body repeats the same wrong "Every 10 ticks" comment. This is a stale comment from an earlier design.
- **Corrected Code:**
  ```ada
  -- This is the base tick for the component. Upon reception the component will decrement the count of each ID unless it is already 0. Every tick, an event of what has been filtered will be sent.
  ```
- **Severity:** Medium

### Issue 1.3 — Tester spec says "pid controller" in data product description

- **Location:** `test/component-event_limiter-implementation-tester.ads`, data product handler section comment
- **Original Code:**
  ```ada
  --    Data products for the pid controller component.
  ```
- **Explanation:** Copy-paste artifact from another component. Should reference the event limiter.
- **Corrected Code:**
  ```ada
  --    Data products for the event limiter component.
  ```
- **Severity:** Low

### Issue 1.4 — Command description says "Change" but YAML header says "Set"

- **Location:** `component-event_limiter-implementation.ads`, `Set_Event_Limit_Persistence` comment (line ~82)
- **Original Code:**
  ```ada
  -- Set the persistence of the event limiter for all events that are limited. Value must be between 0 and 7.
  ```
- **Explanation:** Says "between 0 and 7" but the commands.yaml and component description both say "between 1 and 7." A persistence of 0 would mean no events pass through at all, which contradicts requirement 3 ("shall allow one event through each tick"). The `Persistence_Type` range should be verified in `Two_Counter_Entry` — if it allows 0, this is a design gap; if it doesn't, the comment is simply wrong.
- **Corrected Code:**
  ```ada
  -- Set the persistence of the event limiter for all events that are limited. Value must be between 1 and 7.
  ```
- **Severity:** Medium

### Issue 1.5 — `event_enable_state_type.record.yaml` description is wrong

- **Location:** `types/event_enable_state_type.record.yaml`
- **Original Code:**
  ```yaml
  description: This record contains the definition for a two event ID type for ranges in the event limiter commands as well as an issue packet type for issuing packets
  ```
- **Explanation:** This description was clearly copied from `event_limiter_id_range.record.yaml`. It describes a range record, not an enable-state record. The type only contains a single `Component_Enable_State` field.
- **Corrected Code:**
  ```yaml
  description: This record contains the enable/disable state of the event limiter component master switch.
  ```
- **Severity:** Low

### Issue 1.6 — `event_single_state_cmd_type.record.yaml` description is wrong

- **Location:** `types/event_single_state_cmd_type.record.yaml`
- **Original Code:**
  ```yaml
  description: This record contains the definition for a two event ID type for ranges in the event limiter commands as well as an issue packet type for issuing packets
  ```
- **Explanation:** Same copy-paste issue. This type is for a *single* event ID command, not a range. The `Start_Event_Id` field description also says "starting event ID to begin the range" — it should say the single event to update.
- **Corrected Code:**
  ```yaml
  description: This record contains the definition for a single event ID and an issue packet flag for the event limiter enable/disable commands.
  fields:
    - name: Event_To_Update
      description: The event ID to update
  ```
- **Severity:** Low

---

## 2. Model Review

### Issue 2.1 — No issues found

The `component.yaml` connectors, init parameters, and `with` declarations are consistent and well-structured. The YAML models for commands, events, data products, and packets are correct and match the implementation.

---

## 3. Component Implementation Review

### Issue 3.1 — Off-by-one in `Num_Event_Ids` array fill (potential buffer overrun)

- **Location:** `component-event_limiter-implementation.adb`, `Tick_T_Recv_Sync`, Event_Max_Limit branch (~line 120)
- **Original Code:**
  ```ada
  when Event_Max_Limit =>
     if Num_Event_Limited_Event.Num_Event_Ids <= Num_Event_Limited_Event.Event_Id_Limited_Array'Length then
        Num_Event_Limited_Event.Event_Id_Limited_Array (Integer (Num_Event_Limited_Event.Num_Event_Ids)) := Dec_Event_Id;
        Num_Event_Limited_Event.Num_Event_Ids := @ + 1;
     end if;
  ```
- **Explanation:** The array is indexed starting at 0 (based on `Event_Id_Array` being a packed array type). `Num_Event_Ids` starts at 0 and is used as the index before incrementing. The guard condition uses `<=` against `'Length`. When `Num_Event_Ids` equals `'Length`, it indexes one past the last valid element (index `Length` in a 0-based array of size `Length` has valid indices 0..Length-1). This is an off-by-one that would write past the array bound. The Ada runtime range check would catch this, but in a safety-critical system with suppressed checks, this is a buffer overrun.
- **Corrected Code:**
  ```ada
  when Event_Max_Limit =>
     if Num_Event_Limited_Event.Num_Event_Ids < Num_Event_Limited_Event.Event_Id_Limited_Array'Length then
        Num_Event_Limited_Event.Event_Id_Limited_Array (Integer (Num_Event_Limited_Event.Num_Event_Ids)) := Dec_Event_Id;
        Num_Event_Limited_Event.Num_Event_Ids := @ + 1;
     end if;
  ```
- **Severity:** **Critical**

### Issue 3.2 — Assert placed after the call it is guarding in Init

- **Location:** `component-event_limiter-implementation.adb`, `Init` procedure (~line 97)
- **Original Code:**
  ```ada
  Self.Event_Array.Init (Event_Id_Start, Event_Id_Stop, Event_Disable_List, Event_Limit_Persistence);
  -- This is asserted in the package as well but added here for extra clarity
  pragma Assert (Event_Id_Stop >= Event_Id_Start, ...);
  ```
- **Explanation:** The assertion checking `Event_Id_Stop >= Event_Id_Start` is placed **after** `Event_Array.Init` has already been called with those values. If the precondition is violated, the inner package may have already performed invalid operations (e.g., computing a negative range for array allocation) before this assertion fires. The assert should precede the Init call.
- **Corrected Code:**
  ```ada
  pragma Assert (Event_Id_Stop >= Event_Id_Start, "Stop id must be equal to or greater than the start ID for the event limiter");
  Self.Event_Array.Init (Event_Id_Start, Event_Id_Stop, Event_Disable_List, Event_Limit_Persistence);
  ```
- **Severity:** High

### Issue 3.3 — Assert message in state packet says "decrementing" but context is "getting enable state"

- **Location:** `component-event_limiter-implementation.adb`, `Tick_T_Recv_Sync`, packet-building loop, `Invalid_Id` branch (~line 160)
- **Original Code:**
  ```ada
  when Invalid_Id =>
     pragma Assert (False, "Invalid_Id found when decrementing all event limiter counters which should not be possible: " & Natural'Image (Natural (Id)));
  ```
- **Explanation:** This assert is in the packet-building section, which calls `Get_Enable_State`, not `Decrement_Counter`. The message is copy-pasted from the decrement loop above.
- **Corrected Code:**
  ```ada
  when Invalid_Id =>
     pragma Assert (False, "Invalid_Id found when getting enable state for event limiter state packet which should not be possible: " & Natural'Image (Natural (Id)));
  ```
- **Severity:** Low

### Issue 3.4 — `Total_Event_Limited_Count` can silently wrap around

- **Location:** `component-event_limiter-implementation.adb`, `Tick_T_Recv_Sync` (~line 185)
- **Original Code:**
  ```ada
  Self.Total_Event_Limited_Count := @ + Unsigned_32 (Num_Events_Limited);
  ```
- **Explanation:** `Total_Event_Limited_Count` is `Unsigned_32` which wraps on overflow (modular arithmetic). For a long-duration mission, this counter could wrap from `2**32 - 1` back to 0 without any indication to the ground. The data product `Total_Events_Limited` would suddenly show a small number. Consider either saturating at `Unsigned_32'Last` or sending an event on wrap.
- **Corrected Code:**
  ```ada
  if Self.Total_Event_Limited_Count <= Unsigned_32'Last - Unsigned_32 (Num_Events_Limited) then
     Self.Total_Event_Limited_Count := @ + Unsigned_32 (Num_Events_Limited);
  else
     Self.Total_Event_Limited_Count := Unsigned_32'Last; -- Saturate
  end if;
  ```
- **Severity:** Medium

### Issue 3.5 — Tick decrement skipped when component disabled, but events limited count still reported

- **Location:** `component-event_limiter-implementation.adb`, `Tick_T_Recv_Sync`
- **Original Code:** The decrement loop is inside `if Component_State = Enabled`, but `Num_Events_Limited` is fetched **before** the if-block and the data product is sent unconditionally after.
- **Explanation:** When the component is disabled, `Increment_Counter` in `Event_T_Recv_Sync` still calls into the `Two_Counter_Entry` package (which handles the master state internally). However, the decrement loop is skipped entirely. If `Two_Counter_Entry.Increment_Counter` still counts events internally when the master is disabled (returning `Success` or `Invalid_Id` to let them through), the limited-count may accumulate without ever being decremented. The `Get_Events_Limited_Count` is called before checking state, and `Reset_Event_Limited_Count` only fires if `Num_Events_Limited > 0`. This design is intentional (the inner package handles master state), but the limited-events event and decrement-based ID listing are skipped, so ground never learns which IDs *would have been* limited. This is a design note rather than a bug, assuming the inner package correctly returns `Success` (not `Event_Max_Limit`) when master is disabled.
- **Severity:** Low (design observation)

---

## 4. Unit Test Review

### Issue 4.1 — No test for out-of-range event IDs

- **Location:** `test/event_limiter_tests-implementation.adb`
- **Explanation:** The requirements state "shall not limit and simply pass any events not initialized in the event ID range" (Requirement 6). While `Test_Received_Event` and `Test_Decrement_Event_Count` send events within the range, there is no explicit test that sends an event with an ID **outside** the configured range (e.g., ID 50 when range is 0..10) and verifies it is forwarded without limiting. The `Invalid_Id` path in `Event_T_Recv_Sync` is implicitly relied upon but not directly validated.
- **Corrected Code:** Add a test case or extend `Test_Received_Event`:
  ```ada
  -- Test out-of-range event passes through without limiting
  T.Event_Forward_T_Recv_Sync_History.Clear;
  Incoming_Event.Header.Id := 50; -- well outside 0..10
  for I in 1 .. 10 loop
     T.Event_T_Send (Incoming_Event);
     Natural_Assert.Eq (T.Event_Forward_T_Recv_Sync_History.Get_Count, I);
  end loop;
  ```
- **Severity:** Medium

### Issue 4.2 — No test for persistence value verification via event parameter

- **Location:** `test/event_limiter_tests-implementation.adb`, `Test_Persistence_Change`
- **Explanation:** The test sends `Set_Event_Limit_Persistence` and checks the command response and that the event was emitted, but does not verify the **actual persistence value** in the `Set_New_Persistence` event parameter. The test should assert that the returned persistence matches the commanded value.
- **Corrected Code:**
  ```ada
  Natural_Assert.Eq (T.Set_New_Persistence_History.Get_Count, 1);
  -- Verify the persistence value in the event
  Natural_Assert.Eq (Natural (T.Set_New_Persistence_History.Get (1).Persistence), 4);
  ```
- **Severity:** Low

### Issue 4.3 — Tests call `Init` after `Set_Up` without intervening teardown

- **Location:** `test/event_limiter_tests-implementation.adb`, multiple tests (e.g., `Test_Issue_State_Packet` calls `Init` three times)
- **Explanation:** `Set_Up_Test` calls `Set_Up` (which sends initial data products), then each test calls `Component_Instance.Init` again (sometimes multiple times). This re-initializes the protected object's internal state without calling `Destroy` first. If `Two_Counter_Entry.Init` allocates heap memory, this could leak. The tests clear history but rely on `Init` being idempotent. This is fragile — if the inner package changes, these tests silently leak or corrupt state.
- **Severity:** Low

### Issue 4.4 — `Events_Limited_Since_Last_Tick_History` count checked at 3 before first tick in `Test_Decrement_Event_Count`

- **Location:** `test/event_limiter_tests-implementation.adb`, `Test_Decrement_Event_Count` (~line near "Should have no limiting count, but will be listed")
- **Original Code:**
  ```ada
  Natural_Assert.Eq (T.Events_Limited_Since_Last_Tick_History.Get_Count, 3);
  ```
- **Explanation:** This assert appears partway through the test after only one tick has occurred (which would produce at most 1 event in that history since the previous tick produced 0 limited events). The value of 3 seems to include events dispatched through the `Event_Forward_T_Recv_Sync` handler which also dispatches events to the history. This is confusing to readers and suggests the test is coupling to the tester's event dispatch routing rather than directly checking the component behavior. Not a bug per se (the framework dispatches component events through the event handler), but makes the test hard to audit.
- **Severity:** Low

---

## 5. Summary — Top 5 Issues

| # | Severity | Location | Description |
|---|----------|----------|-------------|
| 1 | **Critical** | `implementation.adb`, `Tick_T_Recv_Sync`, Event_Max_Limit branch | Off-by-one: `<=` should be `<` when guarding array index, allowing write past array bounds |
| 2 | **High** | `implementation.adb`, `Init` | `pragma Assert` for start/stop range placed **after** `Event_Array.Init` call; precondition checked too late |
| 3 | **Medium** | `implementation.adb`, Init comment | Comment says `Event_Disable_List` contains IDs "enabled by default" — should say "disabled" |
| 4 | **Medium** | `implementation.ads` / `.adb`, Tick comment | Says "every 10 ticks" but implementation fires every tick; stale comment from prior design |
| 5 | **Medium** | `implementation.adb`, `Total_Event_Limited_Count` | Unsigned_32 lifetime counter silently wraps on overflow with no saturation or notification |

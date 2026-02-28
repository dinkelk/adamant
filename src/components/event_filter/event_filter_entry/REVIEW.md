# Code Review: Event_Filter_Entry Package

**Reviewer:** Ada Code Review (Automated)
**Date:** 2026-02-28
**Branch:** `review/components-event-filter-event-filter-entry`
**Verdict:** Several issues ranging from Critical to Low; see Summary.

---

## 1. Package Specification Review

**File:** `event_filter_entry.ads`

### Issue 1.1 — `Get_Entry_Array` Exposes Mutable Internal State

- **Location:** Line 39 (declaration of `Get_Entry_Array`)
- **Original Code:**
  ```ada
  function Get_Entry_Array (Self : in Instance) return Basic_Types.Byte_Array_Access;
  ```
- **Explanation:** This function returns the raw `Byte_Array_Access` pointer to the internal `Events` array. Any caller can modify the filter state arbitrarily without going through `Set_Filter_State`, bypassing all validation and potentially corrupting the data structure. In safety-critical code, exposing internal mutable state through an access type is a significant encapsulation violation. Ideally, a copy should be returned or a read-only access type used. However, the comment indicates this is intentional for performance ("quickly copy the whole thing into the state packet"). If this must remain for performance, it should be prominently documented as an unsafe accessor.
- **Suggested Change:**
  ```ada
  -- WARNING: Returns a direct pointer to internal state. Callers MUST treat as read-only.
  -- Used for efficient serialization into state packets by the owning component.
  function Get_Entry_Array (Self : in Instance) return Basic_Types.Byte_Array_Access;
  ```
  Or preferably, return a copy:
  ```ada
  function Get_Entry_Array (Self : in Instance) return Basic_Types.Byte_Array;
  ```
- **Severity:** Medium

### Issue 1.2 — Misleading Package-Level Comment

- **Location:** Line 1
- **Original Code:**
  ```ada
  -- This is a generic, unprotected statistics data structure.
  -- The user can instantiate this class with any type that they choose.
  ```
- **Explanation:** This package is not generic, nor does the user instantiate it with a chosen type. This comment appears to be copy-pasted boilerplate from another package and does not describe `Event_Filter_Entry` at all. Misleading comments in safety-critical code undermine understanding and review confidence.
- **Corrected Code:**
  ```ada
  -- This package provides a bit-packed event filter data structure.
  -- Each event ID within a configured range has an associated filter state
  -- (Filtered/Unfiltered) stored as a single bit. The structure also tracks
  -- filtered/unfiltered event counts and a global enable/disable switch.
  ```
- **Severity:** Low

### Issue 1.3 — `Event_Id_List_Access` Declared But Never Used

- **Location:** Line 17
- **Original Code:**
  ```ada
  type Event_Id_List_Access is access Event_Id_List;
  ```
- **Explanation:** This access type is never referenced anywhere in the package specification, body, or tests. Dead declarations add confusion and, for access types, imply potential heap usage patterns that don't exist.
- **Corrected Code:** Remove the line.
- **Severity:** Low

---

## 2. Package Implementation Review

**File:** `event_filter_entry.adb`

### Issue 2.1 — `Init` Silently Ignores Out-of-Range IDs in Filter List (Production Builds)

- **Location:** Lines 29–33 (`Init`, the filter-list loop)
- **Original Code:**
  ```ada
  for Event_Id_To_Filter of Event_Filter_List loop
     Status := Set_Filter_State (Self, Event_Id_To_Filter, Event_Filter_State.Filtered);
     -- Assert here on status
     pragma Assert (Status /= Invalid_Id, "Event ID in the filtered list is out of range");
  end loop;
  ```
- **Explanation:** `pragma Assert` is suppressed in production builds (with `-gnata` disabled or `Assertion_Policy(Ignore)`). When suppressed, an out-of-range event ID in `Event_Filter_List` is silently ignored—the filter the caller requested is never applied, and no error is reported. In a flight system, this means an event that should be filtered may pass through without any indication of misconfiguration. The check must use a runtime-active mechanism.
- **Corrected Code:**
  ```ada
  for Event_Id_To_Filter of Event_Filter_List loop
     Status := Set_Filter_State (Self, Event_Id_To_Filter, Event_Filter_State.Filtered);
     if Status = Invalid_Id then
        raise Constraint_Error with "Event ID in the filtered list is out of range: " & Event_Types.Event_Id'Image (Event_Id_To_Filter);
     end if;
  end loop;
  ```
  Alternatively, if exceptions are not permitted, propagate the error status to the caller by changing `Init` to a function returning a status.
- **Severity:** Critical

### Issue 2.2 — `Init` Does Not Deallocate Pre-existing `Events` Array (Memory Leak)

- **Location:** Line 15 (`Init`, allocation)
- **Original Code:**
  ```ada
  Self.Events := new Basic_Types.Byte_Array (0 .. Num_Event_Bytes - 1);
  ```
- **Explanation:** If `Init` is called on an already-initialized `Instance` (without a preceding `Destroy`), the previously allocated `Events` array is leaked. In a long-running flight system, even a single leak in a re-initialization path is unacceptable.
- **Corrected Code:**
  ```ada
  -- Deallocate any prior allocation to prevent memory leaks on re-init
  if Self.Events /= null then
     -- (use the same deallocation strategy as Destroy)
     Destroy (Self);
  end if;
  Self.Events := new Basic_Types.Byte_Array (0 .. Num_Event_Bytes - 1);
  ```
- **Severity:** High

### Issue 2.3 — `Destroy` Does Not Reset `Global_Enable_State`

- **Location:** Lines 40–50 (`Destroy` procedure)
- **Original Code:**
  ```ada
  Self.Start_Id := Event_Id'First;
  Self.End_Id := Event_Id'First;
  Self.Num_Events_Filtered := Interfaces.Unsigned_32'First;
  Self.Num_Events_Unfiltered := Interfaces.Unsigned_32'First;
  ```
- **Explanation:** All record fields are reset to defaults except `Global_Enable_State`. If a `Destroy`/`Init` cycle occurs, the global state from the prior lifetime carries over. If the previous lifetime ended with the filter globally disabled, the new lifetime silently starts disabled, which could allow events that should be filtered to pass through.
- **Corrected Code:**
  ```ada
  Self.Start_Id := Event_Id'First;
  Self.End_Id := Event_Id'First;
  Self.Num_Events_Filtered := Interfaces.Unsigned_32'First;
  Self.Num_Events_Unfiltered := Interfaces.Unsigned_32'First;
  Self.Global_Enable_State := Global_Filter_State.Enabled;
  ```
- **Severity:** High

### Issue 2.4 — `Filter_Event` Does Not Count When Globally Disabled

- **Location:** Lines 80–83 (`Filter_Event`, global disable check)
- **Original Code:**
  ```ada
  if Self.Global_Enable_State = Global_Filter_State.Disabled then
     return Unfiltered;
  end if;
  ```
- **Explanation:** When the global filter is disabled, `Filter_Event` returns `Unfiltered` but does not increment `Num_Events_Unfiltered`. This creates an inconsistency: the counter does not reflect the true number of events that passed through as unfiltered. Telemetry consumers tracking event throughput via these counters will see an unexplained gap during disabled periods. If this is intentional (counters only track decisions made by the per-event filter logic), it should be clearly documented.
- **Corrected Code (if counting is desired):**
  ```ada
  if Self.Global_Enable_State = Global_Filter_State.Disabled then
     Self.Num_Events_Unfiltered := @ + 1;
     return Unfiltered;
  end if;
  ```
  Or add a comment:
  ```ada
  -- Note: When globally disabled, bypass counters intentionally.
  -- Counters reflect only per-event filter decisions.
  ```
- **Severity:** Medium

### Issue 2.5 — Counter Wraparound Without Notification

- **Location:** Lines 104, 107 (`Filter_Event`, counter increments)
- **Original Code:**
  ```ada
  Self.Num_Events_Filtered := @ + 1;
  ...
  Self.Num_Events_Unfiltered := @ + 1;
  ```
- **Explanation:** `Unsigned_32` silently wraps around at `2**32 - 1`. The unit tests explicitly validate this wraparound behavior, confirming it is by design. However, in flight telemetry, a counter that wraps from `Unsigned_32'Last` to `0` could be misinterpreted as a reset or as zero events filtered. There is no saturation, no flag, and no event generated on overflow. For safety-critical systems, saturating arithmetic or an overflow indicator is preferred.
- **Corrected Code (saturating):**
  ```ada
  if Self.Num_Events_Filtered < Interfaces.Unsigned_32'Last then
     Self.Num_Events_Filtered := @ + 1;
  end if;
  ```
- **Severity:** Medium

---

## 3. Model Review

**Files:** `event_filter_entry_enums.enums.yaml`, `event_filter_entry_type.record.yaml`

### Issue 3.1 — No Issues Found

The enum and record models are clean and well-structured. Each `Event_Filter_State` field uses `E1` (1-bit) format, correctly packing 8 filter states into a single byte. The enum values (0/1) align with the bit representation. The `Global_Filter_State` enum correctly separates the global enable concept from per-event state while reusing the same binary width.

No issues identified.

---

## 4. Unit Test Review

**Files:** `test/event_filter_entry_tests-implementation.adb`, `test/event_filter_entry-tester.ads`, `test/event_filter_entry-tester.adb`

### Issue 4.1 — `Invalid_Init_Range` Test Is Ineffective (Always Passes)

- **Location:** `Test_Init_List`, nested procedure `Invalid_Init_Range` (approx. lines 37–44)
- **Original Code:**
  ```ada
  procedure Invalid_Init_Range is
     Start_List : constant Event_Id_List := [2, 5];
  begin
     Event_Filter.Init (Event_Id_Start => 7, Event_Id_Stop => 2, Event_Filter_List => Start_List);
  exception
     when others =>
        Assert (True, "Invalid Event ID Range assert failed!");
  end Invalid_Init_Range;
  ```
- **Explanation:** This test intends to verify that an invalid range raises an exception. However:
  1. If the exception IS raised, `Assert(True, ...)` is a no-op—it always passes.
  2. If the exception is NOT raised (e.g., assertions disabled in build), execution falls through the `begin` block normally with no failure assertion. The test silently passes.

  The correct pattern is to place `Assert(False, "Should have raised")` after the call, and let the exception handler be the success path.
- **Corrected Code:**
  ```ada
  procedure Invalid_Init_Range is
     Start_List : constant Event_Id_List := [2, 5];
  begin
     Event_Filter.Init (Event_Id_Start => 7, Event_Id_Stop => 2, Event_Filter_List => Start_List);
     -- If we reach here, the expected assertion was not raised
     Assert (False, "Expected assertion failure for invalid Event ID range, but Init succeeded");
  exception
     when others =>
        null; -- Expected: assertion fired for invalid range
  end Invalid_Init_Range;
  ```
- **Severity:** High

### Issue 4.2 — `Event_Id_List_To_Byte_Array` Leaks Memory

- **Location:** `Test_Get_Entry_Array`, the helper function `Event_Id_List_To_Byte_Array` and its usage (~lines 44–80 of tests, and lines 340–360)
- **Original Code:**
  ```ada
  Expected_Array := Event_Id_List_To_Byte_Array (Start_Id, Stop_Id, Event_Start_List);
  ...
  Expected_Array := Event_Id_List_To_Byte_Array (Start_Id, Stop_Id, Event_End_List);
  ```
- **Explanation:** `Event_Id_List_To_Byte_Array` allocates a new `Byte_Array` on the heap each call. The first allocation pointed to by `Expected_Array` is overwritten by the second call without deallocation. In a test context this is benign (process exits), but it sets a poor precedent and may trigger leak-detection tooling. For test code this is Low severity.
- **Severity:** Low

### Issue 4.3 — No Test for `Destroy`/`Init` Cycle

- **Explanation:** There is no test that verifies correct behavior when `Destroy` is called followed by a new `Init` on the same instance—particularly whether `Global_Enable_State` is properly reset (it isn't; see Issue 2.3). Given that the component lifecycle may involve reconfiguration, this is a gap.
- **Severity:** Medium

### Issue 4.4 — No Test for `Filter_Event` Behavior When Globally Disabled

- **Explanation:** `Test_Global_Enable_Switch` verifies that a filtered event returns `Unfiltered` when globally disabled, but does not check whether the counters are affected. Given the ambiguity in Issue 2.4, a test should explicitly validate the counter behavior during the disabled state.
- **Severity:** Low

---

## 5. Summary — Top 5 Issues

| # | Issue | Location | Severity | Description |
|---|-------|----------|----------|-------------|
| 1 | **2.1** | `Init`, filter-list loop | **Critical** | Out-of-range IDs in the init filter list are silently ignored in production builds due to reliance on `pragma Assert`. A misconfigured filter list could allow safety-relevant events to pass through unfiltered with no error indication. |
| 2 | **4.1** | `Test_Init_List`, `Invalid_Init_Range` | **High** | The negative test for invalid ID range always passes regardless of whether the expected exception is raised. The test provides false confidence. |
| 3 | **2.2** | `Init`, allocation | **High** | Calling `Init` without `Destroy` leaks the prior `Events` allocation. No guard against double-init. |
| 4 | **2.3** | `Destroy` | **High** | `Global_Enable_State` is not reset during `Destroy`, causing stale state to persist across `Destroy`/`Init` cycles. A previously-disabled filter could silently remain disabled after re-initialization. |
| 5 | **2.4** | `Filter_Event`, global disable path | **Medium** | Events processed while globally disabled are not counted in either counter, creating telemetry blind spots. At minimum, the behavior should be documented. |

## Resolution Notes

| # | Issue | Severity | Status | Commit | Notes |
|---|-------|----------|--------|--------|-------|
| 1 | Silent filter misconfiguration in prod | Critical | Fixed | - | Runtime raise replaces pragma Assert |
| 2 | Broken negative test | High | Fixed | - | Added Assert(False) after Init |
| 3 | Memory leak on double-init | High | Fixed | - | Null check + Destroy before alloc |
| 4 | Destroy doesn't reset Global_Enable | High | Fixed | - | Reset to Enabled in Destroy |
| 5 | No counting when globally disabled | Medium | Fixed | - | Increment unfiltered counter |
| 6 | Counter wraparound | Medium | Fixed | - | Saturating arithmetic |
| 7 | Get_Entry_Array exposes mutable state | Medium | Fixed | - | Added safety warning comment |
| 8 | No Destroy/Init cycle test | Medium | Fixed | - | Added cycle test |
| 9 | Misleading package comment | Low | Fixed | - | Replaced |
| 10 | Unused Event_Id_List_Access | Low | Fixed | - | Removed |
| 11 | Test memory leaks | Low | Fixed | - | Added Free_Byte_Array |
| 12 | No disabled counter test | Low | Fixed | - | Added assertions |

# Two_Counter_Entry Code Review

**Package:** `Two_Counter_Entry`
**Reviewer:** Automated Ada Code Review (Safety-Critical)
**Date:** 2026-02-28
**Branch:** `review/components-event-limiter-two-counter-entry`

---

## 1. Package Specification Review

### Issue 1.1 — Unused Access Type Declaration

- **Location:** `two_counter_entry.ads`, line ~20
- **Original Code:**
  ```ada
  type Event_Id_List_Access is access Event_Id_List;
  ```
- **Explanation:** `Event_Id_List_Access` is declared but never referenced anywhere in the specification, body, or tests. In safety-critical code, unused access types create unnecessary heap-related complexity and dead code. This should be removed to keep the interface minimal and auditable.
- **Corrected Code:** Remove the line entirely.
- **Severity:** Low

### Issue 1.2 — `Get_Event_Start_Stop_Range` Awkward API Design

- **Location:** `two_counter_entry.ads`, line ~44
- **Original Code:**
  ```ada
  function Get_Event_Start_Stop_Range (Self : in Instance; Event_Stop_Id : out Event_Id) return Event_Id;
  ```
- **Explanation:** Returning Start via the function return value and Stop via an `out` parameter is asymmetric and error-prone for callers. A procedure with two `out` parameters, or returning a record, would be clearer and harder to misuse. This is a design concern, not a defect.
- **Corrected Code:**
  ```ada
  procedure Get_Event_Start_Stop_Range (Self : in Instance; Event_Start_Id : out Event_Id; Event_Stop_Id : out Event_Id);
  ```
- **Severity:** Low

---

## 2. Package Implementation Review

### Issue 2.1 — Memory Leak on Double Init

- **Location:** `two_counter_entry.adb`, `Init` procedure, line ~10
- **Original Code:**
  ```ada
  Self.Bytes := new Basic_Types.Byte_Array (0 .. Num_Event_Bytes - 1);
  ```
- **Explanation:** If `Init` is called on an already-initialized `Instance` (where `Self.Bytes /= null`), the previous heap allocation is leaked. There is no guard or `Destroy` call before the new allocation. In a long-running flight system, this is a memory leak that grows silently. `Init` should either assert `Self.Bytes = null` or call `Destroy` first.
- **Corrected Code:**
  ```ada
  pragma Assert (Self.Bytes = null, "Init called on already-initialized instance; call Destroy first");
  Self.Bytes := new Basic_Types.Byte_Array (0 .. Num_Event_Bytes - 1);
  ```
- **Severity:** High

### Issue 2.2 — `Num_Events_Limited` Unsigned_16 Overflow (Silent Wraparound)

- **Location:** `two_counter_entry.adb`, `Increment_Counter`, lines ~50 and ~70
- **Original Code:**
  ```ada
  Self.Num_Events_Limited := @ + 1;
  ```
- **Explanation:** `Num_Events_Limited` is `Interfaces.Unsigned_16`, which wraps around silently at 65535 (modular arithmetic — no `Constraint_Error`). In a long-running flight system with high event rates, this counter can wrap to zero, producing incorrect telemetry that understates the number of limited events. Either use a saturating increment or switch to a non-modular type with overflow checking.
- **Corrected Code:**
  ```ada
  if Self.Num_Events_Limited < Interfaces.Unsigned_16'Last then
     Self.Num_Events_Limited := @ + 1;
  end if;
  ```
- **Severity:** Critical

### Issue 2.3 — `Destroy` Does Not Reset `Master_Enable_State`

- **Location:** `two_counter_entry.adb`, `Destroy` procedure, lines ~28–35
- **Original Code:**
  ```ada
  procedure Destroy (Self : in out Instance) is
     ...
  begin
     if Self.Bytes /= null then
        Free_If_Testing (Self.Bytes);
        Self.Bytes := null;
     end if;
     Self.Start_Id := Event_Id'First;
     Self.End_Id := Event_Id'First;
     Self.Persistence := Persistence_Type'Last;
     Self.Num_Events_Limited := Interfaces.Unsigned_16'First;
  end Destroy;
  ```
- **Explanation:** `Master_Enable_State` is not reset to its default (`Enabled`) in `Destroy`. If an instance is destroyed while in `Disabled` state and then re-initialized, the `Init` procedure *does* reset it to `Enabled`, so this is not a functional defect today. However, `Destroy` should fully restore the record to its default state for defensive correctness. If `Init` is ever refactored and the reset is removed, this would become a latent defect.
- **Corrected Code:** Add after the `Num_Events_Limited` reset:
  ```ada
  Self.Master_Enable_State := Event_State_Type.Enabled;
  ```
- **Severity:** Low

### Issue 2.4 — `Init` Relies on `pragma Assert` for Disable-List Validation

- **Location:** `two_counter_entry.adb`, `Init`, lines ~20–22
- **Original Code:**
  ```ada
  Status := Set_Enable_State (Self, Event_Id_To_Disable, Event_State_Type.Disabled);
  pragma Assert (Status /= Invalid_Id, "Event ID in the disable list is out of range");
  ```
- **Explanation:** In production builds, `pragma Assert` is typically suppressed (via `pragma Suppress(All_Checks)` or `-gnatp`). If a caller passes an out-of-range ID in the disable list, `Set_Enable_State` returns `Invalid_Id` and the error is silently ignored. For safety-critical code, runtime validation must not rely solely on assertions. Use an explicit `if` check that always executes.
- **Corrected Code:**
  ```ada
  Status := Set_Enable_State (Self, Event_Id_To_Disable, Event_State_Type.Disabled);
  if Status = Invalid_Id then
     -- Handle error: raise, log, or use a dedicated error mechanism
     pragma Assert (False, "Event ID in the disable list is out of range");
  end if;
  ```
  Or better, use the project's runtime error-handling pattern instead of relying on assertion alone.
- **Severity:** High

### Issue 2.5 — `Set_Persistence` Uses Direct Address Overlay Inconsistently

- **Location:** `two_counter_entry.adb`, `Set_Persistence`, lines ~150–165
- **Original Code:**
  ```ada
  for Idx in Self.Bytes'Range loop
     declare
        Event_Info : Two_Counter_Entry_Type.T with
           Import, Convention => Ada, Address => Self.Bytes (Idx)'Address;
     begin
        if Event_Info.Top_Event_Count > New_Persistence then
           Event_Info.Top_Event_Count := New_Persistence;
        end if;
        if Event_Info.Bottom_Event_Count > New_Persistence then
           Event_Info.Bottom_Event_Count := New_Persistence;
        end if;
     end;
  end loop;
  ```
- **Explanation:** The rest of the package accesses the byte array via `Get_Entry`/`Set_Entry`, which properly abstract the address overlay. `Set_Persistence` bypasses these helpers and performs its own direct overlay. This creates a maintenance hazard: if the byte layout or overlay mechanism changes, this loop must be updated separately. It also modifies *both* halves of every byte — including the unused "phantom" half of the last byte when the event count is odd — which could set a counter on a non-existent event slot.
- **Corrected Code:** Iterate using `Get_Entry`/`Set_Entry` for each valid event ID from `Self.Start_Id` to `Self.End_Id`, or at minimum add a comment documenting why the direct overlay is used and noting the phantom-slot behavior is benign.
- **Severity:** Medium

### Issue 2.6 — `Set_Entry` Has No Bounds Validation

- **Location:** `two_counter_entry.adb`, `Set_Entry`, lines ~200–208
- **Original Code:**
  ```ada
  procedure Set_Entry (Self : in out Instance; Id : in Event_Id; Event_New_Info : in Two_Counter_Entry_Type.T) is
     Event_Id_In : constant Natural := Natural (Id - Self.Start_Id) / 2;
     Event_Info : Two_Counter_Entry_Type.T with
        Import, Convention => Ada, Address => Self.Bytes (Event_Id_In)'Address;
  begin
     Event_Info := Event_New_Info;
  end Set_Entry;
  ```
- **Explanation:** The comment "No range checking here since we always call get then set" is a fragile assumption. If a future code change calls `Set_Entry` without a prior `Get_Entry` range check, an out-of-bounds memory write occurs — a critical safety violation. A defensive `pragma Assert` at minimum (or a full range check) would prevent this class of error.
- **Corrected Code:**
  ```ada
  procedure Set_Entry (Self : in out Instance; Id : in Event_Id; Event_New_Info : in Two_Counter_Entry_Type.T) is
     pragma Assert (Id >= Self.Start_Id and then Id <= Self.End_Id, "Set_Entry called with out-of-range ID");
     Event_Id_In : constant Natural := Natural (Id - Self.Start_Id) / 2;
     ...
  ```
- **Severity:** Medium

### Issue 2.7 — Unnecessary `Set_Entry` Calls on Disabled/No-Op Paths

- **Location:** `two_counter_entry.adb`, `Increment_Counter` and `Decrement_Counter`
- **Original Code (Increment_Counter):**
  ```ada
  end case;
  -- Write the new values back into our structure
  Set_Entry (Self, Id, Event_Info);
  ```
- **Explanation:** When an event is disabled, neither `Increment_Counter` nor `Decrement_Counter` modifies `Event_Info`, yet both unconditionally call `Set_Entry` to write back the unchanged data. This is a minor performance concern — an unnecessary memory write per disabled event per tick in a system that may process thousands of events.
- **Corrected Code:** Move `Set_Entry` inside the `Enabled` branches, or add a `Modified` flag.
- **Severity:** Low

---

## 3. Model Review

### Issue 3.1 — No Issues Found in Enum Model

- **File:** `two_counter_entry_enums.enums.yaml`
- The `Event_State_Type` enum is well-defined with explicit values (0=Disabled, 1=Enabled) matching the 1-bit format field. No issues.

### Issue 3.2 — No Issues Found in Record Model

- **File:** `two_counter_entry_type.record.yaml`
- The bit layout (E1+U3+E1+U3 = 8 bits) correctly packs two counter entries into a single byte. `Event_Count_Type` range `0..7` matches the 3-bit unsigned field. No issues.

---

## 4. Unit Test Review

### Issue 4.1 — No Test for Double-Init Memory Leak

- **Location:** `test/two_counter_entry_tests-implementation.adb`
- **Explanation:** There is no test case that calls `Init` twice on the same instance without an intervening `Destroy`. Given Issue 2.1 (memory leak on double init), a test should verify this is either caught (assertion) or handled gracefully.
- **Severity:** Medium

### Issue 4.2 — No Test for `Num_Events_Limited` Overflow/Saturation Behavior

- **Location:** `test/two_counter_entry_tests-implementation.adb`
- **Explanation:** `Test_Event_Limited_Count` only checks counts up to 7. There is no test verifying behavior near `Unsigned_16'Last` (65535). Given Issue 2.2, this is an untested edge case in a safety counter.
- **Severity:** Medium

### Issue 4.3 — No Test for Master-Disable Effect on Increment/Decrement

- **Location:** `test/two_counter_entry_tests-implementation.adb`, `Test_Master_Enable_Switch`
- **Explanation:** `Test_Master_Enable_Switch` only verifies get/set of the master state. It never tests that `Increment_Counter` and `Decrement_Counter` correctly bypass counting logic when master is disabled. This is a major behavioral contract that is untested.
- **Corrected Test Sketch:**
  ```ada
  My_Counter.Set_Master_Enable_State (Event_State_Type.Disabled);
  Return_Status := My_Counter.Increment_Counter (0);
  Count_Status_Assert.Eq (Return_Status, Two_Counter_Entry.Success);
  -- Verify counter did not actually increment (enable master, check count is still 0)
  ```
- **Severity:** High

### Issue 4.4 — No Test for Odd Event Count Ranges

- **Location:** `test/two_counter_entry_tests-implementation.adb`
- **Explanation:** All test `Init` calls use even-count ranges (e.g., 0–5 = 6 events, 1–7 = 7 events... wait, 1–7 is 7 events which is odd). Actually, `Test_Increment_Count` uses Start=1, Stop=7 (7 events, odd). However, no test explicitly verifies that the phantom half of the last byte (the unused Top or Bottom slot) does not interfere with valid event operations. This is particularly relevant given Issue 2.5.
- **Severity:** Low

---

## 5. Summary — Top 5 Issues

| # | Severity | Issue | Location |
|---|----------|-------|----------|
| 1 | **Critical** | `Num_Events_Limited` (`Unsigned_16`) silently wraps at 65535 — safety counter produces incorrect telemetry in long-running systems | `Increment_Counter`, adb ~50,70 |
| 2 | **High** | `Init` relies on `pragma Assert` for disable-list validation — silently ignored in production builds | `Init`, adb ~20–22 |
| 3 | **High** | Memory leak if `Init` called twice without `Destroy` — no guard on existing allocation | `Init`, adb ~10 |
| 4 | **High** | No test for master-disable effect on `Increment_Counter`/`Decrement_Counter` — major behavioral contract untested | Test suite |
| 5 | **Medium** | `Set_Persistence` bypasses `Get_Entry`/`Set_Entry` abstraction and modifies phantom slots on odd-count ranges | `Set_Persistence`, adb ~150–165 |

## Resolution Notes

| # | Issue | Severity | Status | Commit | Notes |
|---|-------|----------|--------|--------|-------|
| 1 | Num_Events_Limited wraparound | Critical | Fixed | - | Saturating increment |
| 2 | Memory leak on double Init | High | Fixed | - | Added pragma Assert guard |
| 3 | Disable-list validation via assert only | High | Fixed | - | Explicit status check |
| 4 | No master-disable behavioral test | High | Fixed | - | Extended test |
| 5 | Set_Persistence bypasses abstraction | Medium | Fixed | - | Refactored to use Get/Set_Entry |
| 6 | Set_Entry no bounds validation | Medium | Fixed | - | Added pragma Assert |
| 7 | Missing double-init and saturation tests | Medium | Fixed | - | Added 2 tests |
| 8 | Unused Event_Id_List_Access | Low | Fixed | - | Removed |
| 9 | Awkward API | Low | Not Fixed | - | Cross-component, deferred |
| 10 | Destroy doesn't reset Master_Enable | Low | Fixed | - | Added reset |
| 11 | Unnecessary Set_Entry on no-op | Low | Fixed | - | Added Modified flag |
| 12 | No odd-count range test | Low | Not Fixed | - | Existing coverage sufficient |

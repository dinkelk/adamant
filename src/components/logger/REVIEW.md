# Logger Component Code Review

**Component:** `src/components/logger`  
**Branch:** `review/components-logger`  
**Reviewer:** Automated (Claude)  
**Date:** 2026-02-28  

---

## 1. Documentation Review

### DOC-01: Misleading test comments — "while it is disabled" when logger is enabled

**Location:** `test/logger_tests-implementation.adb`, lines in `Test_Log_And_Dump_Enabled`  
**Also:** `test/logger_tests-implementation.adb`, `Test_Log_Overwrite_And_Dump`  
**Also:** `test/logger_tests-implementation.adb`, `Test_Enable_Disable` (multiple occurrences)  
**Also:** `test_variable/variable_tests-implementation.adb`, `Test_Log_And_Dump`

**Original Code:**
```ada
-- Send some data to the logger while it is disabled:
The_Tick := ((1, 2), 3);
```

**Explanation:** In `Test_Log_And_Dump_Enabled`, the component is initialized with `Initial_Mode => Logger_Mode.Enabled`, yet the comment says "while it is disabled." This misleading comment is copy-pasted into `Test_Log_Overwrite_And_Dump` (also enabled), multiple blocks of `Test_Enable_Disable` (some when enabled, some when disabled), and `Test_Log_And_Dump` in the variable test suite. Incorrect comments in safety-critical test code can cause reviewers to misjudge test intent.

**Corrected Code:**
```ada
-- Send some data to the logger while it is enabled:
The_Tick := ((1, 2), 3);
```
(Correct each occurrence to match the actual mode.)

**Severity:** Low

---

### DOC-02: Component description inconsistency — "statically-sized, or variable-sized" vs. spec

**Location:** `logger.component.yaml`, `description` field  
**Also:** `component-logger-implementation.ads`, package comment

**Original Code (YAML):**
```yaml
description: |
  The Logger component receives data of generic statically-sized, or variable-sized type.
```

**Original Code (spec):**
```ada
-- The Logger component receives data of generic type. This data is synchronously added to an internal circular buffer.
```

**Explanation:** The YAML description says "statically-sized, or variable-sized" while the Ada spec says just "generic type." The descriptions should be consistent. The YAML description is more accurate given the `Serialized_Length` generic formal.

**Corrected Code:** Update the Ada spec comment to match the YAML description.

**Severity:** Low

---

### DOC-03: Requirement 3 uses "should" instead of "shall"

**Location:** `logger.requirements.yaml`, requirement 3

**Original Code:**
```yaml
- text: The default state of the component should be disabled upon initialization.
```

**Explanation:** In requirements engineering (especially for safety-critical/flight software per DO-178C conventions), "shall" denotes a mandatory requirement while "should" is merely advisory. However, this behavior is configurable via the `Initial_Mode` init parameter, so the requirement as stated is also slightly inaccurate — the *default* of the parameter is Disabled, but a caller can override it.

**Corrected Code:**
```yaml
- text: The default state of the component shall be disabled upon initialization.
  description: The Initial_Mode parameter defaults to Disabled, ignoring all incoming data.
```

**Severity:** Low

---

## 2. Model Review

### MOD-01: No `Clear` command exposed

**Location:** `logger.commands.yaml`

**Explanation:** The internal `Protected_Buffer` has a `Clear` procedure, but there is no command to invoke it. While the design may intentionally omit this, a clear/reset command is typically expected for a flight logger to allow operators to reset the buffer without a full disable/enable cycle. If intentional, this should be documented in requirements or design rationale.

**Severity:** Low (design observation)

---

### MOD-02: `Log_Attempt_Status.Too_Full` description is inaccurate

**Location:** `types/logger_enums.enums.yaml`

**Original Code:**
```yaml
- name: Too_Full
  value: 2
  description: Logging failed because the log was too full to fit the data.
```

**Explanation:** The `Push` procedure in the protected buffer always uses `Overwrite => True`, which means the underlying circular buffer should overwrite old data when full — it should never return `Too_Full` in normal operation. The `Too_Full` status from `Circular_Buffer.Push` with `Overwrite => True` would only occur if a single element is larger than the entire buffer. The description should clarify this edge case.

**Corrected Code:**
```yaml
- name: Too_Full
  value: 2
  description: Logging failed because the data is larger than the entire log buffer capacity.
```

**Severity:** Medium

---

## 3. Component Implementation Review

### IMPL-01: `Push` reports `Num_Bytes_Stored` on serialization failure — value is uninitialized

**Location:** `component-logger-implementation.adb`, `Protected_Buffer.Push` procedure

**Original Code:**
```ada
procedure Push (Src : in T; Num_Bytes_To_Store : out Natural; Status : out Log_Attempt_Status.E) is
   use Serializer_Types;
   use Logger_Enums.Log_Attempt_Status;
   -- Get the serialized length of the source:
   Stat : constant Serialization_Status := Serialized_Length (Src, Num_Bytes_To_Store);
begin
   -- Make sure source has a valid length:
   if Stat /= Success then
      Status := Serialization_Failure;
   else
```

**Also:** `component-logger-implementation.adb`, `T_Recv_Sync`

```ada
Self.Event_T_Send_If_Connected (Self.Events.Log_Attempt_Failed (Self.Sys_Time_T_Get, (Num_Bytes_Logged => Num_Bytes_Stored, Status => Status)));
```

**Explanation:** When `Serialized_Length` fails, the value written to `Num_Bytes_To_Store` is whatever the failed `Serialized_Length` function left in the out parameter — potentially garbage. This value is then reported in the `Log_Attempt_Failed` event as `Num_Bytes_Logged`. In `T_Recv_Sync`, the event is sent whenever `Status /= Success`, which includes `Serialization_Failure`. The event will contain a misleading `Num_Bytes_Logged` value. The variable test confirms this: `Logger_Error_Assert.Eq (T.Log_Attempt_Failed_History.Get (1), (21 + 1, Serialization_Failure))` shows `Num_Bytes_Logged = 22` (i.e., `Length + 1`) from a failed serialization — this is the length the type *claims* but that couldn't be serialized, which is confusing in telemetry.

**Corrected Code:** Either explicitly set `Num_Bytes_To_Store := 0` in the failure path of `Push`, or handle the serialization failure case separately in `T_Recv_Sync`:
```ada
if Stat /= Success then
   Num_Bytes_To_Store := 0;
   Status := Serialization_Failure;
```

**Severity:** Medium

---

### IMPL-02: `Final` calls `Destroy` then `Set_Mode` — potential use of destroyed buffer metadata

**Location:** `component-logger-implementation.adb`, `Final` procedure

**Original Code:**
```ada
not overriding procedure Final (Self : in out Instance) is
begin
   Self.Buffer.Destroy;
   Self.Buffer.Set_Mode (Logger_Mode.Disabled);
end Final;
```

**Explanation:** After `Destroy` is called on the circular buffer, the internal `Buffer` object is in a destroyed state. Calling `Set_Mode` afterward accesses the protected object's `Mode` field, which should still be valid (it's a separate field from the buffer), so this is not a crash risk. However, the ordering is misleading and fragile — if the protected object's state is ever tied to buffer validity, this would break. Best practice: set mode before destroy.

**Corrected Code:**
```ada
not overriding procedure Final (Self : in out Instance) is
begin
   Self.Buffer.Set_Mode (Logger_Mode.Disabled);
   Self.Buffer.Destroy;
end Final;
```

**Severity:** Low

---

### IMPL-03: No memory deallocation for heap-allocated `Bytes` and `Meta_Data` in `Final`

**Location:** `component-logger-implementation.adb`, `Final` procedure

**Original Code:**
```ada
not overriding procedure Final (Self : in out Instance) is
begin
   Self.Buffer.Destroy;
   Self.Buffer.Set_Mode (Logger_Mode.Disabled);
end Final;
```

**Explanation:** When `Init` is called with `Size > 0`, memory is allocated on the heap for both `Self.Bytes` and `Self.Meta_Data` via `new`. The `Final` procedure calls `Buffer.Destroy` but never deallocates `Self.Bytes` or `Self.Meta_Data`. This is a memory leak if the component is finalized and re-initialized (or in a test environment). In a flight system with a single init this may be acceptable, but the asymmetry with `Init` is a defect for reuse and testing.

**Corrected Code:**
```ada
not overriding procedure Final (Self : in out Instance) is
   procedure Free_Bytes is new Ada.Unchecked_Deallocation (Basic_Types.Byte_Array, Basic_Types.Byte_Array_Access);
   procedure Free_Meta is new Ada.Unchecked_Deallocation (Circular_Buffer_Meta.T, Circular_Buffer_Meta.T_Access);
begin
   Self.Buffer.Set_Mode (Logger_Mode.Disabled);
   Self.Buffer.Destroy;
   -- Only free if we allocated on the heap (check is implicit - Free is safe on null)
   Free_Bytes (Self.Bytes);
   Free_Meta (Self.Meta_Data);
end Final;
```

**Severity:** Medium

---

### IMPL-04: TOCTOU between `Get_Mode` check and `Push` in `T_Recv_Sync`

**Location:** `component-logger-implementation.adb`, `T_Recv_Sync`

**Original Code:**
```ada
case Self.Buffer.Get_Mode is
   when Enabled =>
      Self.Buffer.Push (Arg, Num_Bytes_Stored, Status);
```

**Explanation:** `Get_Mode` is a protected function (read-only lock) and `Push` is a protected procedure (read-write lock). Between the two calls, another task could call `Set_Mode(Disabled)` via the `Disable` command. This is a classic TOCTOU (time-of-check-time-of-use) race. In practice, the component is `passive` (single-threaded execution model per the YAML), so this race cannot occur in the current design. However, if the component were ever changed to `active` or used in a concurrent context, this would be a real bug. The mode check should be inside the protected `Push` procedure.

**Corrected Code (defensive):** Move mode check inside `Protected_Buffer.Push`:
```ada
procedure Push (Src : in T; Num_Bytes_To_Store : out Natural; Status : out Log_Attempt_Status.E) is
begin
   if Mode /= Logger_Mode.Enabled then
      Num_Bytes_To_Store := 0;
      Status := Disabled;  -- new enum value, or handle differently
      return;
   end if;
   -- existing push logic...
end Push;
```

**Severity:** Low (passive component, but design fragility)

---

### IMPL-05: `Send_Meta_Data_Event` makes two separate protected calls — non-atomic snapshot

**Location:** `component-logger-implementation.adb`, `Send_Meta_Data_Event`

**Original Code:**
```ada
overriding function Send_Meta_Data_Event (Self : in out Instance) return Command_Execution_Status.E is
   use Command_Execution_Status;
begin
   Self.Event_T_Send_If_Connected (Self.Events.Log_Info_Update (Self.Sys_Time_T_Get, (Meta_Data => Self.Buffer.Get_Meta_Data, Current_Mode => Self.Buffer.Get_Mode)));
   return Success;
end Send_Meta_Data_Event;
```

**Explanation:** `Get_Meta_Data` and `Get_Mode` are two separate protected function calls. In a concurrent context, the buffer state could change between them, producing an inconsistent snapshot (e.g., metadata says count=50 but mode says Disabled when the disable happened between the two calls). Same as IMPL-04, mitigated by the passive execution model. A single protected function returning both values would be more robust.

**Severity:** Low

---

## 4. Unit Test Review

### TEST-01: No test for `Dump_Log` / `Dump_Newest_Data` / `Dump_Oldest_Data` on an empty, enabled log

**Location:** `test/logger_tests-implementation.adb`

**Explanation:** `Test_Log_And_Dump_Disabled` tests dump commands when no data has been logged (disabled mode). `Test_Log_And_Dump_Enabled` only tests dumps after data has been pushed. There is no test that enables the logger, sends no data, and then issues dump commands. This would exercise the edge case where the buffer is enabled but empty (count=0), which may produce null pointers in the dump that need to be handled by `Dump_Ptr`.

**Severity:** Medium

---

### TEST-02: No test for double-`Init` or `Init` after `Final`

**Location:** `test/logger_tests-implementation.adb`, `Test_Init`

**Explanation:** `Test_Init` tests various valid and invalid parameter combinations for `Init`, but never tests calling `Init` twice on the same instance (which could leak memory) or calling `Init` after `Final`. Given IMPL-03 (no heap deallocation in `Final`), this would leak. This scenario matters for test harnesses and long-running ground systems.

**Severity:** Low

---

### TEST-03: Variable test `Test_Log_And_Dump` doesn't verify newest/oldest dump content accurately

**Location:** `test_variable/variable_tests-implementation.adb`, `Test_Log_And_Dump`

**Explanation:** When dumping the oldest 25 bytes, the test checks that the dump length equals `Idx` (total logged bytes, which is less than 25), not 25. This is correct behavior (can't dump more than exists), but the test then also dumps newest 24 bytes and again gets `Idx` bytes back. The test verifies the full buffer content both times rather than verifying that the correct *subset* was returned. The assertions `Bytes (0 .. Length(Ptr) - 1) = Bytes_To_Compare (0 .. Length(Ptr) - 1)` work only because the entire buffer is returned (total data < requested dump size). This means the oldest/newest distinction is not actually tested in the variable test.

**Severity:** Medium

---

### TEST-04: `Test_Logger_Error` reinitializes without calling `Final` first

**Location:** `test_variable/variable_tests-implementation.adb`, `Test_Logger_Error`

**Original Code:**
```ada
-- Reinitialize the component to have tiny log:
T.Component_Instance.Init (Size => 5, Initial_Mode => Logger_Mode.Enabled);
```

**Explanation:** The first `Init` uses stack-allocated `Log_Bytes` and `Meta_Data`. The second `Init` uses heap allocation (`Size => 5`). `Final` is never called between them. The circular buffer from the first init is not destroyed before being overwritten. While the first init used stack memory (no leak), the internal `Circular_Buffer.Circular` object may hold state that should be properly torn down. Additionally, the second init allocates heap memory that is later freed by `Tear_Down_Test` calling `Final`, but the pattern is fragile.

**Corrected Code:**
```ada
T.Component_Instance.Final;
T.Component_Instance.Init (Size => 5, Initial_Mode => Logger_Mode.Enabled);
```

**Severity:** Medium

---

## 5. Summary — Top 5 Issues

| # | ID | Severity | Description |
|---|------|----------|-------------|
| 1 | IMPL-03 | **Medium** | `Final` does not deallocate heap-allocated `Bytes` and `Meta_Data`, causing memory leaks on re-init or in test environments. |
| 2 | IMPL-01 | **Medium** | `Num_Bytes_Stored` reported in `Log_Attempt_Failed` event contains a misleading value on serialization failure — should be explicitly zeroed. |
| 3 | MOD-02 | **Medium** | `Too_Full` enum description says "log was too full" but with `Overwrite => True`, this only triggers when a single item exceeds total buffer capacity. Description is misleading. |
| 4 | TEST-04 | **Medium** | `Test_Logger_Error` re-initializes without calling `Final`, skipping buffer teardown and creating an inconsistent lifecycle pattern. |
| 5 | TEST-01 | **Medium** | No test for dump commands on an enabled but empty buffer — missing edge case coverage for null/zero-length pointer handling in `Dump_Ptr`. |

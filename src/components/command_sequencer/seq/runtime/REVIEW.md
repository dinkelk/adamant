# Code Review: Seq_Runtime Package

**Package:** `Seq_Runtime`
**Reviewer:** Automated Ada Code Review
**Date:** 2026-02-28
**Branch:** `review/components-command-sequencer-seq-runtime`

---

## 1. Package Specification Review

### 1.1 — Missing Precondition on `Execute_Sequence`

- **File:** `seq_runtime.ads`, line ~36
- **Original Code:**
```ada
function Execute_Sequence (Self : in out Instance; Instruction_Limit : in Positive; Timestamp : in Sys_Time.T) return Seq_Runtime_State.E;
```
- **Explanation:** The body of `Execute_Sequence` explicitly rejects execution in certain states (`Unloaded`, `Wait_Relative`, `Wait_Absolute`, `Wait_Telemetry_Set`, `Wait_Telemetry_Relative`, `Done`) by returning early with no action. A precondition should document which states are valid for callers, matching the body's `case` statement. Without it, callers have no contract guidance and may invoke execution in nonsensical states (e.g., `Done`), silently getting a no-op return.
- **Corrected Code:**
```ada
function Execute_Sequence (Self : in out Instance; Instruction_Limit : in Positive; Timestamp : in Sys_Time.T) return Seq_Runtime_State.E
   with Pre => Self.Get_State /= Unloaded and then
               Self.Get_State /= Wait_Relative and then
               Self.Get_State /= Wait_Absolute and then
               Self.Get_State /= Wait_Telemetry_Set and then
               Self.Get_State /= Wait_Telemetry_Relative and then
               Self.Get_State /= Done;
```
- **Severity:** Medium

### 1.2 — Missing Preconditions on Telemetry-Related Getters

- **File:** `seq_runtime.ads`, lines ~77, ~86, ~89
- **Original Code:**
```ada
function Get_Telemetry_Request (Self : in Instance) return Telemetry_Record.T;
function Get_Telemetry_Timeout (Self : in Instance) return Sys_Time.T;
function Get_Telemetry_Wait_Start_Time (Self : in Instance) return Sys_Time.T;
```
- **Explanation:** These functions return telemetry-related fields that are only meaningful when the runtime is in a telemetry wait state. Other getters like `Get_Command` properly have preconditions. Callers could read stale/uninitialized telemetry metadata in unrelated states with no indication of misuse.
- **Corrected Code:** Add appropriate preconditions, e.g.:
```ada
function Get_Telemetry_Request (Self : in Instance) return Telemetry_Record.T
   with Pre => Self.Get_State = Wait_Telemetry_Set or else
               Self.Get_State = Wait_Telemetry_Value or else
               Self.Get_State = Wait_Telemetry_Relative;
```
- **Severity:** Medium

### 1.3 — Missing Precondition on `Get_Seq_Id_To_Load`

- **File:** `seq_runtime.ads`, line ~82
- **Original Code:**
```ada
function Get_Seq_Id_To_Load (Self : in Instance) return Sequence_Types.Sequence_Id;
```
- **Explanation:** This is only meaningful in `Wait_Load_New_*` states (similar to `Get_Spawn_Destination` which has a precondition). Inconsistency with the rest of the API.
- **Corrected Code:**
```ada
function Get_Seq_Id_To_Load (Self : in Instance) return Sequence_Types.Sequence_Id
   with Pre => Self.Get_State = Wait_Load_New_Seq_Overwrite or else
               Self.Get_State = Wait_Load_New_Sub_Seq or else
               Self.Get_State = Wait_Load_New_Seq_Elsewhere;
```
- **Severity:** Low

### 1.4 — Comment Typo: "subpograms"

- **File:** `seq_runtime.ads`, line ~55
- **Original Code:**
```ada
-- ...which requires one of the next two subpograms to be called
```
- **Corrected Code:**
```ada
-- ...which requires one of the next two subprograms to be called
```
- **Severity:** Low

### 1.5 — Comment Typo: "produces"

- **File:** `seq_runtime.ads`, line ~22
- **Original Code:**
```ada
-- ...depends on the byte code produces from the LASP SEQ
```
- **Corrected Code:**
```ada
-- ...depends on the byte code produced by the LASP SEQ
```
- **Severity:** Low

---

## 2. Package Implementation Review

### 2.1 — `Change_Relative_Wait_To_Absolute`: Integer Overflow on Time Addition (Critical)

- **File:** `seq_runtime.adb`, line ~190
- **Original Code:**
```ada
procedure Change_Relative_Wait_To_Absolute (Self : in out Instance; Current_Time : in Sys_Time.T) is
begin
   Self.Wake_Time.Seconds := @ + Current_Time.Seconds;
   Self.Set_State_Blocking (Wait_Absolute);
end Change_Relative_Wait_To_Absolute;
```
- **Explanation:** `Wake_Time.Seconds` was previously set to a relative duration. Adding `Current_Time.Seconds` to it could overflow the underlying integer type if the sum exceeds the type's range. In a safety-critical system, this could cause a Constraint_Error at runtime, crashing the sequencer. The same issue exists in `Change_Relative_Timeout_To_Absolute`.
- **Corrected Code:**
```ada
procedure Change_Relative_Wait_To_Absolute (Self : in out Instance; Current_Time : in Sys_Time.T) is
   use type Interfaces.Unsigned_32; -- or whatever the Seconds type is
begin
   -- Saturate to prevent overflow
   if Self.Wake_Time.Seconds > Sys_Time.Seconds_Type'Last - Current_Time.Seconds then
      Self.Wake_Time.Seconds := Sys_Time.Seconds_Type'Last;
   else
      Self.Wake_Time.Seconds := @ + Current_Time.Seconds;
   end if;
   Self.Set_State_Blocking (Wait_Absolute);
end Change_Relative_Wait_To_Absolute;
```
- **Severity:** Critical

### 2.2 — `Check_Wake` Ignores Sub-Second Precision

- **File:** `seq_runtime.adb`, line ~202
- **Original Code:**
```ada
if Current_Time.Seconds >= Self.Wake_Time.Seconds then
```
- **Explanation:** `Sys_Time.T` appears to have at least two fields (the record literal `(0, 0)` is used throughout). Only `.Seconds` is compared, meaning the sub-second field is entirely ignored. A wake time of `(5, 999999)` would be considered satisfied by `(5, 0)`. For safety-critical timing, this could cause premature wake-ups. The same pattern occurs in `Wait_On_Helper` for telemetry timeout comparison.
- **Corrected Code:**
```ada
if Current_Time.Seconds > Self.Wake_Time.Seconds
   or else (Current_Time.Seconds = Self.Wake_Time.Seconds
            and then Current_Time.Subseconds >= Self.Wake_Time.Subseconds)
then
```
- **Severity:** High

### 2.3 — `Cmd_Set_Bit_Pattern`: Instruction Parsed Before Validation, Fields Used Before Status Check

- **File:** `seq_runtime.adb`, lines ~476–480
- **Original Code:**
```ada
function Cmd_Set_Bit_Pattern (Self : in out Instance) return Seq_Position is
   Instruction : Set_Bit_Record.T;
   Status : constant Seq_Status := Get_Set_Bit_Pattern (Self, Instruction);

   use System.Storage_Elements;
   Bytes : Basic_Types.Byte_Array (0 .. Natural (Instruction.Length) - 1)
      with Import, Convention => Ada, Address => Self.Sequence_Region.Address + Storage_Offset (Self.Next_Position);
   Bytes_Serialized : Natural;
   Command_Serialization_Status : constant Serialization_Status := Command.Serialization.From_Byte_Array (Self.Bit_Pattern, Bytes, Bytes_Serialized);
begin
   pragma Assert (Status = Success);
```
- **Explanation:** `Instruction.Length` is used in the declarative region to size the `Bytes` array *before* `Status` is checked. If parsing failed, `Instruction.Length` could contain garbage, potentially creating an enormous or zero-length array and causing a Constraint_Error or reading arbitrary memory. Additionally, `Command.Serialization.From_Byte_Array` is called with this potentially-invalid array.
- **Corrected Code:** Move the `Bytes` declaration and serialization into the `begin` block after asserting `Status = Success`:
```ada
function Cmd_Set_Bit_Pattern (Self : in out Instance) return Seq_Position is
   Instruction : Set_Bit_Record.T;
   Status : constant Seq_Status := Get_Set_Bit_Pattern (Self, Instruction);
   use System.Storage_Elements;
begin
   pragma Assert (Status = Success);

   declare
      Bytes : Basic_Types.Byte_Array (0 .. Natural (Instruction.Length) - 1)
         with Import, Convention => Ada, Address => Self.Sequence_Region.Address + Storage_Offset (Self.Next_Position);
      Bytes_Serialized : Natural;
      Command_Serialization_Status : constant Serialization_Status :=
         Command.Serialization.From_Byte_Array (Self.Bit_Pattern, Bytes, Bytes_Serialized);
   begin
      if Command_Serialization_Status /= Success or else Bytes_Serialized /= Natural (Instruction.Length) then
         return Self.Process_Error (Command_Parse);
      end if;
      -- ...
   end;
end Cmd_Set_Bit_Pattern;
```
- **Severity:** High

### 2.4 — `Cmd_Fetch_Tlm`: Missing State Transition for Non-WaitOn Case

- **File:** `seq_runtime.adb`, line ~621
- **Original Code:**
```ada
if Instruction.Waiton = False then
   Self.Telemetry_Request.New_Value_Required := False;
   Self.Set_State_Blocking (Wait_Telemetry_Set);
end if;

return Self.Next_Position;
```
- **Explanation:** When `Instruction.Waiton = True`, no state transition occurs—the function returns `Next_Position` in the `Ready` state. The caller (component) has no indication that telemetry needs to be fetched. This appears to be a missing `else` branch that should set the state to `Wait_Telemetry_Value` or `Wait_Telemetry_Relative` depending on context, or at minimum `Wait_Telemetry_Set`.
- **Corrected Code:**
```ada
if Instruction.Waiton = False then
   Self.Telemetry_Request.New_Value_Required := False;
   Self.Set_State_Blocking (Wait_Telemetry_Set);
else
   Self.Set_State_Blocking (Wait_Telemetry_Set);
end if;

return Self.Next_Position;
```
- **Severity:** High

### 2.5 — `Get_Instruction`: No Bounds Check Before Memory Overlay

- **File:** `seq_runtime.adb`, lines ~274–280
- **Original Code:**
```ada
function Get_Instruction (Inst : in out Instance; Instruction : out T) return Seq_Status is
   use System.Storage_Elements;
   Offset : constant Storage_Offset := Storage_Offset (Inst.Position);
   To_Return : T with Import, Convention => Ada, Address => Inst.Sequence_Region.Address + Offset;
begin
   Instruction := To_Return;
```
- **Explanation:** The overlay reads `T'Object_Size / 8` bytes starting at `Position` within the sequence memory region. There is no check that `Position + T'Size/8 <= Sequence_Region.Length`. If the sequence is truncated or corrupted, this reads past the end of the allocated memory region, which is undefined behavior and a potential security/safety vulnerability.
- **Corrected Code:**
```ada
function Get_Instruction (Inst : in out Instance; Instruction : out T) return Seq_Status is
   use System.Storage_Elements;
   Inst_Size : constant Natural := T'Object_Size / Basic_Types.Byte'Object_Size;
   Offset : constant Storage_Offset := Storage_Offset (Inst.Position);
begin
   -- Bounds check: ensure instruction fits within sequence region
   if Natural (Inst.Position) + Inst_Size > Inst.Sequence_Region.Length then
      Inst.Errant_Field := 0;
      return Failure;
   end if;

   declare
      To_Return : T with Import, Convention => Ada, Address => Inst.Sequence_Region.Address + Offset;
      Errant : Interfaces.Unsigned_32 := 0;
   begin
      Instruction := To_Return;
      if Valid (Instruction, Errant) then
         Inst.Next_Position := Seq_Position (Inst_Size) + Inst.Position;
         return Success;
      else
         Inst.Errant_Field := Errant;
         return Failure;
      end if;
   end;
end Get_Instruction;
```
- **Severity:** Critical

### 2.6 — `Get_Opcode_From_Memory`: No Bounds Check Before Memory Read

- **File:** `seq_runtime.adb`, line ~246
- **Original Code:**
```ada
function Get_Opcode_From_Memory (Self : in Instance) return Seq_Opcode.E is
   use System.Storage_Elements;
   Offset : constant Storage_Offset := Storage_Offset (Self.Position);
   This_Opcode : Packed_Seq_Opcode.T with Import, Convention => Ada, Address => Self.Sequence_Region.Address + Offset;
```
- **Explanation:** Same class of issue as 2.5—reads memory at `Position` without verifying it's within bounds. If `Position >= Sequence_Region.Length`, this reads arbitrary memory.
- **Corrected Code:** Add a bounds check before the overlay:
```ada
if Natural (Self.Position) >= Self.Sequence_Region.Length then
   return Invalid;
end if;
```
- **Severity:** Critical

### 2.7 — `Set_Telemetry`: Silently Ignores Telemetry in Wrong State

- **File:** `seq_runtime.adb`, line ~228
- **Original Code:**
```ada
procedure Set_Telemetry (Self : in out Instance; Telemetry : in Poly_32_Type) is
   ...
begin
   if Self.State = Wait_Telemetry_Value or else Self.State = Wait_Telemetry_Set then
      Ignore := Set_Internal_Poly_32 (Self, Self.Telemetry_Destination, Telemetry);
      Self.Set_State_Blocking (Telemetry_Set);
      pragma Assert (Ignore = Success);
   end if;
end Set_Telemetry;
```
- **Explanation:** If called in the wrong state, telemetry data is silently dropped with no error indication. In safety-critical code, silent data loss is dangerous. At minimum this should be documented; ideally it should have a precondition or raise an error.
- **Severity:** Medium

### 2.8 — `Unload` Does Not Reset `String_To_Print`

- **File:** `seq_runtime.adb`, `Unload` procedure
- **Original Code:** The `Unload` procedure resets most fields but does not reset `String_To_Print`.
- **Explanation:** After unload, stale print data from a previous sequence remains in the instance. If queried, it would return data from the prior sequence. Minor since `Get_String_To_Print` should only be called in `Print` state, but defensively this field should be cleared.
- **Corrected Code:** Add to `Unload`:
```ada
Self.String_To_Print := (Print_Type => Seq_Print_Type.Debug, Encoded_String => [others => 0]);
```
- **Severity:** Low

### 2.9 — `Execute_Sequence` Allows Execution in `Error` State

- **File:** `seq_runtime.adb`, line ~115
- **Original Code:**
```ada
when Ready | Wait_Command | Wait_Telemetry_Value | Telemetry_Set | Timeout | Wait_Load_New_Seq_Overwrite | Wait_Load_New_Sub_Seq | Wait_Load_New_Seq_Elsewhere | Kill_Engine | Print | Error =>
   null;
```
- **Explanation:** The spec comment says "If the runtime is in an error state, then it must be cleared before calling this function." However, the implementation allows `Error` state to pass through and continue executing. This contradicts the documented contract and could cause execution on a corrupted runtime.
- **Corrected Code:** Move `Error` to the rejected states:
```ada
when Ready | Wait_Command | Wait_Telemetry_Value | Telemetry_Set | Timeout | Wait_Load_New_Seq_Overwrite | Wait_Load_New_Sub_Seq | Wait_Load_New_Seq_Elsewhere | Kill_Engine | Print =>
   null;
when Unloaded | Wait_Relative | Wait_Absolute | Wait_Telemetry_Set | Wait_Telemetry_Relative | Done | Error =>
   return Self.State;
```
- **Severity:** High

### 2.10 — `Cmd_Eval` / `Cmd_Eval_S`: Catch-All Exception Handler Masks Bugs

- **File:** `seq_runtime.adb`, `Cmd_Eval`, `Cmd_Eval_Flt`, `Cmd_Eval_S`
- **Original Code:**
```ada
exception
   when others =>
      return Self.Process_Error (Eval);
```
- **Explanation:** Catching all exceptions is intentional for division-by-zero and overflow, but it also catches Storage_Error, Program_Error, and any other unanticipated exception. In safety-critical code, masking unexpected failures (e.g., stack overflow) prevents proper fault detection. Consider catching only `Constraint_Error`.
- **Corrected Code:**
```ada
exception
   when Constraint_Error =>
      return Self.Process_Error (Eval);
```
- **Severity:** Medium

---

## 3. Model Review

No model files (`.yaml`, `.json`, `.py`, or other configuration/generation files) were found in the `runtime/` directory. No model-level issues to report.

---

## 4. Unit Test Review

No unit test files were found in the `runtime/` directory. Unit tests for this package likely reside elsewhere in the component tree. No test-level issues to report for this directory scope.

---

## 5. Summary — Top 5 Issues

| # | Severity | Location | Issue |
|---|----------|----------|-------|
| 1 | **Critical** | `seq_runtime.adb` — `Get_Instruction` | No bounds check before overlaying instruction type onto sequence memory. Out-of-bounds read on truncated/corrupted sequences. |
| 2 | **Critical** | `seq_runtime.adb` — `Get_Opcode_From_Memory` | No bounds check before reading opcode byte from sequence memory. |
| 3 | **Critical** | `seq_runtime.adb` — `Change_Relative_Wait_To_Absolute` | Integer overflow possible when adding relative wait time to current time. |
| 4 | **High** | `seq_runtime.adb` — `Execute_Sequence` | `Error` state is allowed to proceed with execution despite spec stating it must be cleared first. |
| 5 | **High** | `seq_runtime.adb` — `Check_Wake` / `Wait_On_Helper` | Sub-second time field ignored in all time comparisons, causing premature wake-ups. |

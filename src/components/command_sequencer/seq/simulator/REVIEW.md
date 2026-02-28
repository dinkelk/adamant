# Code Review: `Seq_Simulator` Package

**Reviewer:** Ada Code Review (Automated)
**Date:** 2026-02-28
**Branch:** `review/components-command-sequencer-seq-simulator`
**Scope:** `src/components/command_sequencer/seq/simulator/`

---

## 1. Package Specification Review (`seq_simulator.ads`)

### Issue 1.1 — Missing `Finalize` or cleanup primitive for heap-allocated engines

- **Location:** `seq_simulator.ads:10-11` (type `Instance`)
- **Original Code:**
  ```ada
  type Instance is tagged record
     Seq_Engines : Seq_Engine_Array_Access := null;
  end record;
  ```
- **Explanation:** `Instance` holds a heap-allocated array (`Seq_Engine_Array_Access`) but provides no `Finalize` or explicit `Destroy` procedure. Every call to `Initialize` overwrites `Seq_Engines` without freeing any prior allocation, and there is no way for a caller to release the memory. In a long-running or repeatedly-initialized simulator this is a memory leak. For safety-critical patterns, the type should either be `Controlled` with a `Finalize` override or expose an explicit `Destroy` procedure.
- **Corrected Code (option — explicit destroy):**
  ```ada
  procedure Destroy (Self : in out Instance);
  ```
  And in the body, free `Self.Seq_Engines` via `Ada.Unchecked_Deallocation`.
- **Severity:** Medium

### Issue 1.2 — `Initialize` returns `Boolean` instead of raising or using a status type

- **Location:** `seq_simulator.ads:8`
- **Original Code:**
  ```ada
  function Initialize (Self : in out Instance; Num_Engines : in Sequence_Engine_Id; ...) return Boolean;
  ```
- **Explanation:** Returning a bare `Boolean` from `Initialize` discards all diagnostic information about failures. The caller cannot distinguish between allocation failure, constraint error, or any other exception swallowed by the blanket `when others` handler. An enumeration status type or propagating a specific exception would be more informative and is the preferred Adamant pattern for initialization routines.
- **Corrected Code (suggestion):**
  ```ada
  type Init_Status is (Success, Allocation_Error, Configuration_Error);
  function Initialize (...) return Init_Status;
  ```
- **Severity:** Low

---

## 2. Package Implementation Review (`seq_simulator.adb`)

### Issue 2.1 — Buffer overflow in `Load_Sequence_In_Memory`

- **Location:** `seq_simulator.adb:36-41`
- **Original Code:**
  ```ada
  while not End_Of_File (File) loop
     Read (File, Data);
     Buffer (Sequence_Size) := Data;
     Sequence_Size := @ + 1;
  end loop;
  ```
- **Explanation:** The loop reads bytes into `Buffer` indexed by `Sequence_Size`, but never checks that `Sequence_Size` remains within `Buffer'Range`. If the file on disk exceeds `Max_Sequence_Size` (524,288 bytes), the index will go past `Buffer'Last`, raising a `Constraint_Error` at runtime. This exception is **not** caught by the `Name_Error`-only handler, so it propagates unhandled. In a simulator this crashes the process; in a pattern reused for flight code this would be a safety-critical defect. The loop must guard against exceeding the buffer bounds.
- **Corrected Code:**
  ```ada
  while not End_Of_File (File) loop
     if Sequence_Size > Buffer'Last then
        Close (File);
        Put_Line ("Error: Sequence file exceeds maximum size of"
                   & Natural'Image (Max_Sequence_Size) & " bytes.");
        return False;
     end if;
     Read (File, Data);
     Buffer (Sequence_Size) := Data;
     Sequence_Size := @ + 1;
  end loop;
  ```
- **Severity:** **Critical**

### Issue 2.2 — Insufficient exception handling in `Load_Sequence_In_Memory`

- **Location:** `seq_simulator.adb:46-47`
- **Original Code:**
  ```ada
  exception
     when Ada.IO_Exceptions.Name_Error =>
        return False;
  ```
- **Explanation:** Only `Name_Error` (file not found) is caught. Other I/O failures — `Use_Error` (permissions), `Device_Error` (disk fault), `Data_Error`, or the `Constraint_Error` from Issue 2.1 — all propagate unhandled, crashing the simulator without closing the file. At minimum, a broader handler should close the file and return `False` (or a descriptive status).
- **Corrected Code:**
  ```ada
  exception
     when Ada.IO_Exceptions.Name_Error =>
        return False;
     when others =>
        if Is_Open (File) then
           Close (File);
        end if;
        return False;
  ```
- **Severity:** **High**

### Issue 2.3 — Memory leak of `Buffer` in `Simulate`

- **Location:** `seq_simulator.adb:53, and throughout `Simulate``
- **Original Code:**
  ```ada
  Buffer := new Basic_Types.Byte_Array (0 .. Max_Sequence_Size - 1);
  ```
- **Explanation:** A 512 KB buffer is heap-allocated on every call to `Simulate` but is never freed on any exit path (normal return, early error return, or exception). Additionally, the self-recursive call for `Wait_Load_Seq` allocates another `New_Buffer` (line ~130) that is also never freed. In a simulator session exercising many sequences, this leaks memory unboundedly.
- **Corrected Code:** Use `Ada.Unchecked_Deallocation` to free `Buffer` before every `return`, or preferably declare the buffer on the stack:
  ```ada
  Buffer : Basic_Types.Byte_Array (0 .. Max_Sequence_Size - 1);
  ```
  (Stack allocation avoids the leak entirely, though 512 KB per stack frame requires adequate stack size.)
- **Severity:** **High**

### Issue 2.4 — Magic number 255 for "any engine" sentinel

- **Location:** `seq_simulator.adb:107`
- **Original Code:**
  ```ada
  if Self.Seq_Engines (To_Load).Get_Load_Destination /= To_Load then
     if Self.Seq_Engines (To_Load).Get_Load_Destination = 255 then
  ```
- **Explanation:** The literal `255` is used as a sentinel meaning "any engine." This is fragile and undocumented. If the underlying type `Sequence_Engine_Id` changes range, or if the engine API changes, this breaks silently. A named constant or a function from the `Seq` package should be used.
- **Corrected Code:**
  ```ada
  Any_Engine : constant Sequence_Engine_Id := Sequence_Engine_Id'Last;
  ...
  if Self.Seq_Engines (To_Load).Get_Load_Destination = Any_Engine then
  ```
- **Severity:** Medium

### Issue 2.5 — No bounds check on `To_Load` against allocated engine array

- **Location:** `seq_simulator.adb:60` (and throughout `Simulate`)
- **Original Code:**
  ```ada
  Load_State := Self.Seq_Engines (To_Load).Load (Sequence);
  ```
- **Explanation:** `Simulate` indexes `Self.Seq_Engines` by `To_Load` without verifying that `To_Load` is within the allocated range. While Ada will raise `Constraint_Error` at runtime, the simulator should validate this up front and provide a meaningful error message rather than a raw exception, especially since `To_Load` comes from user input (command-line argument or interactive prompt at line ~113).
- **Corrected Code:**
  ```ada
  if To_Load not in Self.Seq_Engines.all'Range then
     Put_Line ("Error: Engine ID" & To_Load'Image
                & " is out of range. Valid range:"
                & Self.Seq_Engines.all'First'Image & " .."
                & Self.Seq_Engines.all'Last'Image);
     return;
  end if;
  ```
- **Severity:** Medium

### Issue 2.6 — Unhandled `Constraint_Error` from interactive `Get_Line` / `'Value` conversions

- **Location:** `seq_simulator.adb:78`, `93`, `113`, etc.
- **Original Code (example):**
  ```ada
  New_Time : constant Sys_Time.T := (Interfaces.Unsigned_32'Value (Get_Line), 0);
  ```
- **Explanation:** Several places read user input via `Get_Line` and immediately convert with `'Value`. If the user types non-numeric text, `Constraint_Error` propagates unhandled, crashing the simulator. Each interactive input should be validated in a loop or wrapped in an exception handler.
- **Corrected Code (example):**
  ```ada
  declare
     Line : constant String := Get_Line;
  begin
     New_Time := (Interfaces.Unsigned_32'Value (Line), 0);
  exception
     when Constraint_Error =>
        Put_Line ("Invalid input: " & Line & ". Please enter a numeric value.");
        -- retry or return
  end;
  ```
- **Severity:** Medium

### Issue 2.7 — Blanket `when others` swallows all exceptions in `Initialize`

- **Location:** `seq_simulator.adb:26-27`
- **Original Code:**
  ```ada
  exception
     when others =>
        return False;
  ```
- **Explanation:** This handler catches every exception (including `Program_Error`, `Storage_Error`, logic bugs) and silently returns `False`. The caller has no way to distinguish a benign configuration issue from a fundamental runtime failure. At minimum, the exception information should be logged before returning.
- **Corrected Code:**
  ```ada
  exception
     when E : others =>
        Put_Line ("Initialize failed: "
                   & Ada.Exceptions.Exception_Information (E));
        return False;
  ```
- **Severity:** Medium

### Issue 2.8 — `Load_State` not checked after `Self.Seq_Engines (To_Load).Load`

- **Location:** `seq_simulator.adb:60-61`
- **Original Code:**
  ```ada
  Load_State := Self.Seq_Engines (To_Load).Load (Sequence);
  Put_Line ("Engine loaded with state: " & Load_State'Image);
  ```
- **Explanation:** The return value of `Load` is printed but never checked. If loading fails, execution proceeds into the `while True` loop, which will operate on an engine in a failed state, producing undefined or misleading simulation results. The procedure should exit or retry on a failed load.
- **Corrected Code:**
  ```ada
  Load_State := Self.Seq_Engines (To_Load).Load (Sequence);
  Put_Line ("Engine loaded with state: " & Load_State'Image);
  if Load_State /= Success then
     Put_Line ("Failed to load sequence into engine. Aborting.");
     return;
  end if;
  ```
- **Severity:** **High**

---

## 3. Model Review

No model files (`.record_model.yaml`, `.enum_model.yaml`, or similar Adamant model definitions) are present in this package directory. The package relies on types defined in external packages (`Seq_Types`, `Seq_Enums`, `Command_Types`). No issues found specific to models.

---

## 4. Unit Test Review

**No unit tests exist for this package.** The `simulator/` directory contains no `test/` subdirectory and no test files.

While this is a development/ground tool (not flight code), the core logic — particularly `Load_Sequence_In_Memory` and `Initialize` — contains non-trivial error handling paths that would benefit from automated testing:

- Loading a file that exceeds `Max_Sequence_Size`
- Loading a nonexistent file
- Initializing with boundary values for `Num_Engines`, `Stack_Size`
- Providing invalid interactive input

**Severity:** Low (ground tool, but good practice)

---

## 5. Summary — Top 5 Issues

| # | Issue | Location | Severity | Description |
|---|-------|----------|----------|-------------|
| 1 | **Buffer overflow in file read loop** | `seq_simulator.adb:36-41` | **Critical** | No bounds check on `Sequence_Size` vs. `Buffer'Last`; oversized file causes unhandled `Constraint_Error`. |
| 2 | **`Load_State` not checked after `Load`** | `seq_simulator.adb:60-61` | **High** | Failed load proceeds into execution loop, producing undefined behavior. |
| 3 | **Memory leak of `Buffer` allocations** | `seq_simulator.adb:53,130` | **High** | Heap-allocated 512 KB buffers never freed on any exit path; unbounded leak in recursive calls. |
| 4 | **Insufficient exception handling in file I/O** | `seq_simulator.adb:46-47` | **High** | Only `Name_Error` caught; other I/O exceptions leave file handle open and crash simulator. |
| 5 | **Magic number 255 for any-engine sentinel** | `seq_simulator.adb:107` | **Medium** | Undocumented magic literal; fragile if `Sequence_Engine_Id` range changes. |

## Resolution Notes

| # | Issue | Severity | Status | Commit | Notes |
|---|-------|----------|--------|--------|-------|
| 1 | Buffer overflow in Load_Sequence_In_Memory | Critical | Fixed | 96a9b6d | Added bounds check |
| 2 | Insufficient exception handling | High | Fixed | - | Broadened catch |
| 3 | Memory leak of Buffer allocations | High | Fixed | - | Added Unchecked_Deallocation |
| 4 | Load_State not checked | High | Fixed | - | Added check after Load |
| 5 | Missing Destroy procedure | Medium | Fixed | - | Added to spec/body |
| 6 | Magic number 255 sentinel | Medium | Fixed | - | Named constant |
| 7 | No bounds check on To_Load | Medium | Fixed | - | Added guard |
| 8 | Unhandled Constraint_Error from Get_Line | Medium | Fixed | - | Added handler |
| 9 | Blanket when others in Initialize | Medium | Fixed | - | Narrowed |
| 10 | Boolean return type | Low | Not Fixed | - | API change deferred |
| 11 | No unit tests | Low | Not Fixed | - | Out of scope |

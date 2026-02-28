# Code Review: `seq/decode` Package

**Reviewer:** Automated Ada Code Review  
**Date:** 2026-02-28  
**Branch:** `review/components-command-sequencer-seq-decode`  
**Scope:** `src/components/command_sequencer/seq/decode/` (non-component, ground tool)

---

## 1. Package Specification Review

### 1.1 `seq_config.ads`

**No critical issues.** The specification is straightforward. Minor observations:

#### Issue SC-1: `Seq_String` fixed at 1024 characters is wasteful for map storage

- **File:** `seq_config.ads`, line 14
- **Original:** `subtype Seq_String is String (1 .. 1024);`
- **Explanation:** Every `Seq_Cmd_Def` and `Seq_Tlm_Def` record embeds a 1024-byte `Seq_String` for the name. With potentially hundreds of commands/telemetry items stored in ordered maps, this results in significant memory waste. For a ground tool this is tolerable but poor practice.
- **Suggested:** Use `Ada.Strings.Unbounded.Unbounded_String` or a bounded string with a smaller limit.
- **Severity:** Low

#### Issue SC-2: `Seq_Cmd_Param_Array_Access` is a general access type with no deallocation strategy

- **File:** `seq_config.ads`, line 22
- **Original:** `type Seq_Cmd_Param_Array_Access is access all Seq_Cmd_Param_Array;`
- **Explanation:** This heap-allocated access type has no corresponding `Unchecked_Deallocation` or storage pool. The `Parameters` field is always set to `null` (see `TODO` in body), so this is dead code. If ever used, it would leak memory.
- **Suggested:** Remove or implement with proper lifetime management.
- **Severity:** Low

### 1.2 `seq_runtime-decoder.ads`

#### Issue SD-1: `with Ada.Text_IO; use Ada.Text_IO;` in specification

- **File:** `seq_runtime-decoder.ads`, line 2
- **Original:** `with Ada.Text_IO; use Ada.Text_IO;`
- **Explanation:** Pulling `use Ada.Text_IO` into the package spec pollutes the namespace for any client that withs `Seq_Runtime.Decoder`. The `File_Type` reference in procedure signatures could use the fully qualified name or a `use type` clause instead.
- **Suggested:** Remove `use Ada.Text_IO;` from the spec; qualify as `Ada.Text_IO.File_Type` in parameter declarations.
- **Severity:** Low

#### Issue SD-2: All `Decode_*` functions are in the private part but could be body-only

- **File:** `seq_runtime-decoder.ads`, lines 18–56
- **Explanation:** Every `Decode_*` function is declared in the private part of the spec. Since none of these are called by child packages or clients, they should be declared only in the package body. Placing them in the spec unnecessarily exposes implementation details and increases recompilation dependencies.
- **Suggested:** Move all `Decode_*` declarations and `Load_Sequence_In_Memory` / `Print_Decode_String` into the package body.
- **Severity:** Low

---

## 2. Package Implementation Review

### 2.1 `seq_config.adb`

#### Issue CI-1: `Parse_Line` can return tokens past `End_Idx` (comment boundary)

- **File:** `seq_config.adb`, lines 32–56 (`Parse_Line`)
- **Original:**
  ```ada
  Find_Token (
     Source   => S,         -- Full string S, not truncated
     Set       => Whitespace,
     From      => I,
     Test      => Outside,
     First    => F,
     Last      => L
  );
  ```
- **Explanation:** `Find_Token` is called with the full `Source => S`, but the comment-truncation logic only sets `End_Idx`. If a token starts before `End_Idx` but extends past it, `Find_Token` will return `L > End_Idx`, causing comment text to be included in a parsed token. The `while I in S'First .. End_Idx` guard only checks the *start* position, not the token's end.
- **Suggested:**
  ```ada
  Find_Token (
     Source   => S (S'First .. End_Idx),
     Set       => Whitespace,
     From      => I,
     Test      => Outside,
     First    => F,
     Last      => L
  );
  ```
  Or clamp: `L := Natural'Min (L, End_Idx);`
- **Severity:** **High** — could misparse config lines containing comments, leading to incorrect command/telemetry definitions.

#### Issue CI-2: `Init` uses `exit` instead of `null` on duplicate command, silently stops parsing

- **File:** `seq_config.adb`, line 95
- **Original:**
  ```ada
  if Self.Commands.Contains (The_Command.Header.Id) then
     exit;
  else
  ```
- **Explanation:** When a duplicate command ID is found, the code executes `exit`, which exits the **outer** `while not End_Of_File` loop, silently stopping all further config file parsing. This means any commands or telemetry defined after the first duplicate are silently dropped. The commented-out code suggests the original intent was to raise `Program_Error` (as the telemetry branch does). At minimum it should `null` to skip and continue, or log and continue.
- **Suggested:**
  ```ada
  if Self.Commands.Contains (The_Command.Header.Id) then
     Put_Line (Standard_Error, "Duplicate command found with ID: '"
        & Command_Types.Command_Id'Image (The_Command.Header.Id) & "', skipping.");
  else
  ```
- **Severity:** **Critical** — silently drops all remaining config entries after first duplicate command ID. In a flight operations ground tool, this means commands and telemetry could be missing from the decode output with no indication.

#### Issue CI-3: Telemetry parsing accesses `Parsed_Line (5)` without bounds check

- **File:** `seq_config.adb`, line 114
- **Original:**
  ```ada
  Offset : constant Interfaces.Unsigned_16 := Interfaces.Unsigned_16'Value (Strip_Nul (Parsed_Line (5)));
  ```
- **Explanation:** The guard only checks `Words_Parsed < 4` (i.e., requires at least 4 words), but the code accesses index 5 (the 6th word). If the config line has exactly 4 or 5 words, this accesses an NUL-filled entry, and `Unsigned_16'Value` of an empty or NUL string will raise `Constraint_Error` at runtime with no helpful diagnostic. The bounds check should require `Words_Parsed >= 6`.
- **Suggested:**
  ```ada
  if Words_Parsed < 6 then
     Put_Line (Standard_Error, "Malformed telem (need 6 fields): '" & A_Line & "'");
     raise Program_Error;
  end if;
  ```
- **Severity:** **High** — runtime crash with unhelpful error on malformed telemetry config lines.

#### Issue CI-4: Telemetry ID parsing uses hard-coded offset `Id_Str'First + 3` without validation

- **File:** `seq_config.adb`, line 113
- **Original:**
  ```ada
  Id : constant Data_Product_Types.Data_Product_Id := Data_Product_Types.Data_Product_Id'Value ("16#" & Strip_Nul (Id_Str (Id_Str'First + 3 .. Id_Str'Last)) & "#");
  ```
- **Explanation:** This assumes the ID string starts with a 3-character prefix (e.g., `"0x_"`). If the format differs (shorter prefix, no prefix), this silently computes the wrong ID or raises `Constraint_Error`. No validation of the prefix is performed.
- **Suggested:** Add format validation or use a more robust hex-parsing approach.
- **Severity:** Medium

#### Issue CI-5: `Seq_Str_Cmp` does not guard against `R'Length > L'Length`

- **File:** `seq_config.adb`, line 62
- **Original:**
  ```ada
  function Seq_Str_Cmp (L : in Seq_String; R : in String) return Boolean is
  begin
     return L (1 .. R'Length) = R;
  end Seq_Str_Cmp;
  ```
- **Explanation:** If `R'Length > 1024` (the length of `Seq_String`), this raises `Constraint_Error`. While unlikely with current callers, this is a latent defect in a utility function.
- **Severity:** Low

### 2.2 `seq_runtime-decoder.adb`

#### Issue DI-1: Memory leak — `Buffer` is allocated but never freed

- **File:** `seq_runtime-decoder.adb`, `Decode` procedure, line 58
- **Original:**
  ```ada
  Buffer := new Basic_Types.Byte_Array (0 .. Max_Sequence_Size - 1);
  ```
- **Explanation:** A 512 KB buffer is heap-allocated on every call to `Decode` and never deallocated. For a single-invocation CLI tool this is cosmetic, but if `Decode` were ever called multiple times (e.g., batch processing), each call leaks 512 KB.
- **Suggested:** Use `Ada.Unchecked_Deallocation` at end of `Decode`, or declare the buffer on the stack.
- **Severity:** Medium

#### Issue DI-2: `Decode_Str_Set` writes to `Standard_Output` instead of `Output` parameter

- **File:** `seq_runtime-decoder.adb`, `Decode_Str_Set`, near end
- **Original:**
  ```ada
  Put (Output, """");
  New_Line;
  ```
- **Explanation:** `New_Line` without a file parameter writes to `Standard_Output`, not the `Output` parameter. This breaks output redirection. Should be `New_Line (Output)`.
- **Suggested:**
  ```ada
  Put_Line (Output, """");
  ```
- **Severity:** Medium

#### Issue DI-3: `Decode_Str_Set` is defined but never called (dead code, commented out in dispatch)

- **File:** `seq_runtime-decoder.adb`, function body exists; `Decode_Instruction` case has it commented out (lines ~108-109 of the case statement)
- **Explanation:** The `Str_Set` opcode handling is commented out in `Decode_Instruction`, so `Decode_Str_Set` is dead code. If the opcode is encountered at runtime, it falls through to the `others` branch and raises `Program_Error`. This is either an incomplete feature or a regression.
- **Severity:** Medium — could cause unexpected crashes if `Str_Set` opcodes exist in sequences.

#### Issue DI-4: `Subscribe`/`Unsubscribe` advance position by hard-coded `4` bytes

- **File:** `seq_runtime-decoder.adb`, lines ~107-110
- **Original:**
  ```ada
  when Subscribe =>
     Put_Line (Output, "Ignore");
     return Self.Position + 4;
  when Unsubscribe =>
     Put_Line (Output, "Ignore");
     return Self.Position + 4;
  ```
- **Explanation:** The position advance of 4 bytes is a magic number. If the instruction size differs from 4 bytes, the decoder will become misaligned and all subsequent instructions will be garbage. Same concern applies to `Decode_Return` which also uses `Self.Position + 4`.
- **Severity:** Medium — hard to verify correctness without knowing the instruction encoding; fragile.

#### Issue DI-5: `Decode_Cast_F_To_U` and `Decode_Cast_U_To_F` output is ambiguous

- **File:** `seq_runtime-decoder.adb`, `Decode_Cast_F_To_U` and `Decode_Cast_U_To_F`
- **Original:**
  ```ada
  Put_Line (Output, "Casting internal " & Instruction.Id'Image);
  ```
- **Explanation:** Unlike `Decode_Cast_S_To_U` etc. which print `"Cast INTERNAL.X from TYPE_A to TYPE_B"`, these two functions just print `"Casting internal"` with no indication of the source/destination types. Inconsistent and less useful output.
- **Suggested:**
  ```ada
  Put_Line (Output, "Cast INTERNAL." & Instruction.Id'Image & " from FLOAT to UNSIGNED");
  ```
- **Severity:** Low

#### Issue DI-6: `Load_Sequence_In_Memory` has no bounds check on `Buffer` size

- **File:** `seq_runtime-decoder.adb`, `Load_Sequence_In_Memory`
- **Original:**
  ```ada
  while not End_Of_File (File) loop
     Read (File, Data);
     Buffer (Sequence_Size) := Data;
     Sequence_Size := @ + 1;
  end loop;
  ```
- **Explanation:** If the file is larger than `Max_Sequence_Size` (512 KB), `Buffer (Sequence_Size)` will raise `Constraint_Error` with an unhelpful index-out-of-range message. Should check `Sequence_Size < Buffer'Length` and provide a clear error.
- **Suggested:**
  ```ada
  while not End_Of_File (File) loop
     if Sequence_Size >= Buffer'Length then
        Close (File);
        Put_Line (Standard_Error, "Sequence file exceeds maximum size of" & Max_Sequence_Size'Image & " bytes");
        return False;
     end if;
     Read (File, Data);
     Buffer (Sequence_Size) := Data;
     Sequence_Size := @ + 1;
  end loop;
  ```
- **Severity:** **High** — unbounded file read into fixed buffer.

#### Issue DI-7: `Print_Decode_String` uses `Address` overlay on `Byte` to get `Character`

- **File:** `seq_runtime-decoder.adb`, `Print_Decode_String`
- **Original:**
  ```ada
  declare
     Char : Character with Import, Convention => Ada, Address => A_Byte'Address;
  begin
     Put (Output, Char);
  end;
  ```
- **Explanation:** Using an address overlay to convert a `Byte` (presumably `Interfaces.Unsigned_8`) to `Character` works but is unnecessarily unsafe. `Character'Val (Natural (A_Byte))` is the idiomatic, safe approach.
- **Suggested:**
  ```ada
  Put (Output, Character'Val (Natural (A_Byte)));
  ```
- **Severity:** Low

### 2.3 `main.adb`

#### Issue MI-1: No error handling for missing sequence filename argument

- **File:** `main.adb`, line 17
- **Original:**
  ```ada
  Seq_Filename : constant String := Get_Argument;
  ```
- **Explanation:** If no positional argument is provided, `Get_Argument` returns `""`, and `Decode` will try to open an empty filename, resulting in an unhelpful `Name_Error` exception. Should check for empty string and print usage.
- **Severity:** Low (ground tool, but poor UX)

---

## 3. Model Review

**No model files found** in this package directory. This is a standalone ground tool (CLI decoder), not an Adamant component, so the absence of `.component_model.yaml` or `.record_model.yaml` files is expected and acceptable.

No issues to report.

---

## 4. Unit Test Review

**No unit test files found** in this package directory.

#### Issue UT-1: No unit tests exist for `seq_config` or `seq_runtime-decoder`

- **Explanation:** The config parser (`seq_config`) contains non-trivial parsing logic with multiple edge cases (comments, duplicate entries, hex parsing, field counts). The decoder has ~30 instruction decode functions. Neither has any automated tests. For a ground tool used in flight operations to decode command sequences, this is a significant gap in verification.
- **Severity:** **High** — safety-critical ground support tool with zero automated test coverage.

---

## 5. Summary (Top 5 Issues)

| # | ID | Severity | Location | Description |
|---|-----|----------|----------|-------------|
| 1 | CI-2 | **Critical** | `seq_config.adb:95` | Duplicate command `exit` silently aborts all remaining config parsing — commands and telemetry after the first duplicate are lost with no warning |
| 2 | CI-1 | **High** | `seq_config.adb:38` | `Parse_Line` passes full string to `Find_Token` but comment truncation only limits start position — tokens can include comment text |
| 3 | CI-3 | **High** | `seq_config.adb:114` | Telemetry parsing accesses `Parsed_Line(5)` but only validates `Words_Parsed >= 4` — crashes on 4- or 5-word lines |
| 4 | DI-6 | **High** | `seq_runtime-decoder.adb` (`Load_Sequence_In_Memory`) | No bounds check when reading file into fixed 512 KB buffer — oversized file causes unhandled `Constraint_Error` |
| 5 | UT-1 | **High** | Package-wide | Zero automated test coverage for a ground tool used in flight operations sequence decoding |

## Resolution Notes

| # | Issue | Severity | Status | Commit | Notes |
|---|-------|----------|--------|--------|-------|
| 1 | Duplicate command exit aborts parsing | Critical | Fixed | ff1b52e | Log & skip, continue parsing |
| 2 | Comment truncation bug | High | Fixed | a92357c | Truncated string before Find_Token |
| 3 | Telemetry bounds check | High | Fixed | eb7a491 | Changed < 4 to < 6 |
| 4 | Buffer bounds check | High | Fixed | dd71c27 | Added bounds check |
| 5 | No unit tests | High | Not Fixed | - | Needs test framework setup |
| 6 | Hex prefix validation | Medium | Fixed | - | Added validation |
| 7 | Memory leak in Decode | Medium | Fixed | - | Added Unchecked_Deallocation |
| 8 | New_Line output param | Medium | Fixed | - | Uses Put_Line(Output) |
| 9 | Str_Set dispatch | Medium | Fixed | - | Uncommented |
| 10 | Magic numbers | Medium | Not Fixed | - | Needs instruction record defs |
| 11-18 | Low items | Low | Mixed | - | Various fixes, 2 deferred |

# Code Review: `seq/types` Package

**Reviewer:** Automated Ada/Adamant Code Review  
**Date:** 2026-02-28  
**Branch:** `review/components-command-sequencer-seq-types`  
**Scope:** `src/components/command_sequencer/seq/types/` — all specification, model (YAML), and test files (excluding `build/`)

---

## 1. Package Specification Review (`seq_types.ads`)

### 1.1 — `Seq_Num_Internals` range inconsistent with `Seq_Internal` enum

- **Location:** `seq_types.ads`, line defining `Seq_Num_Internals`
- **Original Code:**
  ```ada
  type Seq_Num_Internals is range 0 .. 3;
  ```
- **Explanation:** The comment says "Seq has two internal variables," but the type range is `0 .. 3` (four values), and the `Seq_Internal` enum defines four literals (`Timeout`, `Seq_Return`, `A`, `B`). The comment is misleading and could cause a maintainer to incorrectly restrict the range or misunderstand the design.
- **Corrected Code:**
  ```ada
  -- Seq has four internal variables (Timeout, Seq_Return, A, B):
  type Seq_Num_Internals is range 0 .. 3;
  ```
- **Severity:** Medium

### 1.2 — `Max_Seq_Size` allows sequences larger than stated 65535 limit

- **Location:** `seq_types.ads`, constant `Max_Seq_Size`
- **Original Code:**
  ```ada
  Max_Seq_Size : constant Natural := 2**16;
  ```
- **Explanation:** The comment states "The command sequencer itself can handle sequences up to 65535 bytes in length." However, `2**16 = 65536`, and `Seq_Position` ranges `0 .. 65535`, which means 65536 addressable positions. This is internally consistent for a zero-based index, but the comment is off by one relative to the constant value. More critically, multiple record types use `Interfaces.Unsigned_16` for position fields (e.g., `goto_record`, `jump_zero_record`). An `Unsigned_16` maxes at 65535, so position 65535 is reachable, but the buffer size is 65536 — this is fine. However, if the constant were ever changed independently of the position fields (which are hard-coded to `U16`), the system would silently break. Consider deriving the constant from the position type or adding a static assertion.
- **Corrected Code (defensive):**
  ```ada
  Max_Seq_Size : constant Natural := Natural (Interfaces.Unsigned_16'Last) + 1;
  -- Or add a compile-time check that Max_Seq_Size <= 2**16
  ```
- **Severity:** Low

### 1.3 — `Sequence_Engine_Id` upper bound coupled to `Basic_Types.Byte'Last` without rationale

- **Location:** `seq_types.ads`, type `Sequence_Engine_Id`
- **Original Code:**
  ```ada
  type Sequence_Engine_Id is range 0 .. Basic_Types.Byte'Last;
  ```
- **Explanation:** The mission parameter `SEQ_NUM_ENGINES` is 16, yet the engine ID type allows values up to 255. While this gives headroom, `kill_eng_record` uses this type for both `Engine_Start` and `Num_To_Kill`. If `Engine_Start = 200` and `Num_To_Kill = 200`, the sum overflows the byte range with no protection at the type level. This is a runtime concern, not a type-safety concern, but in safety-critical code, tighter typing is preferred when the actual mission limit is known.
- **Corrected Code:** Consider a discriminated or constrained subtype based on actual engine count at initialization, or document why the wide range is intentional.
- **Severity:** Low

### 1.4 — No body for `Seq_Types` — Package is pure specification

- **Location:** `seq_types.ads` (no `.adb` exists)
- **Explanation:** This is correct for a types-only package. No issue — noted for completeness.
- **Severity:** N/A

---

## 2. Package Implementation Review

No implementation body (`seq_types.adb`) exists. This package consists solely of type declarations and constants, which is appropriate. All logic lives in consuming packages.

**No issues.**

---

## 3. Model Review (YAML Record & Enum Definitions)

### 3.1 — `Seq_Error` enum: Inconsistent casing of literal names

- **Location:** `seq_enums.enums.yaml`, enum `Seq_Error`
- **Original Code (excerpts):**
  ```yaml
  - name: NONE
  - name: PARSE
  - name: Update_Bit_Pattern    # Mixed_Case
  - name: Command_Argument      # Mixed_Case
  - name: TELEMETRY_FAIL        # ALL_CAPS
  - name: Recursion             # Mixed_Case
  - name: Command_Timeout       # Mixed_Case
  - name: Unimplemented         # Mixed_Case
  ```
- **Explanation:** Most literals use `ALL_CAPS` (e.g., `NONE`, `PARSE`, `OPCODE`, `COMMAND_FAIL`), but several use `Mixed_Case` (`Update_Bit_Pattern`, `Command_Argument`, `Recursion`, `Command_Timeout`, `Load_Timeout`, `Telemetry_Timeout`, `Unimplemented`). In safety-critical code, inconsistent naming conventions increase the risk of typos and pattern-matching errors in consuming code. The generated Ada enums will preserve this casing.
- **Corrected Code:** Adopt a single convention. Since the majority are `ALL_CAPS`:
  ```yaml
  - name: UPDATE_BIT_PATTERN
  - name: COMMAND_ARGUMENT
  - name: RECURSION
  - name: COMMAND_TIMEOUT
  - name: LOAD_TIMEOUT
  - name: TELEMETRY_TIMEOUT
  - name: UNIMPLEMENTED
  ```
- **Severity:** Medium

### 3.2 — `Seq_Internal` enum comment says "two" registers, but there are four

- **Location:** `seq_enums.enums.yaml`, enum `Seq_Internal`
- **Original Code:**
  ```yaml
  description: Represents one of the two seq registers.
  ```
- **Explanation:** The enum defines four literals: `Timeout`, `Seq_Return`, `A`, `B`. The description saying "two" is incorrect. This mirrors Issue 1.1 and both should be corrected together.
- **Corrected Code:**
  ```yaml
  description: Represents one of the four seq internal registers.
  ```
- **Severity:** Medium

### 3.3 — `var_record`: `Id` field is `Unsigned_32` but most variable indices are small

- **Location:** `var_record.record.yaml`, field `Id`
- **Original Code:**
  ```yaml
  - name: Id
    description: "If type is 0, this is a literal, if type is 1, this is an index in a local variable array, if the type is 2 this is an index into the internal variable array..."
    type: Interfaces.Unsigned_32
    format: U32
  ```
- **Explanation:** When `Var_Type` is `Local` (1), valid indices are 0–15 (`Seq_Local_Id`). When `Internal` (2), valid indices are 0–3. The field is 32 bits because when `Var_Type` is `In_Sequence` (0), the value is a literal constant occupying all 32 bits. This dual-use (index vs. literal value) in the same field is a known pattern in bytecode interpreters, but it means the consuming code **must** range-check the `Id` when interpreting it as an index. This is not enforceable at the type/model level, so consuming code must be reviewed for proper bounds checking. Not a defect in this package, but a design risk to document.
- **Corrected Code:** Add a comment to the description:
  ```yaml
  description: "... NOTE: When used as an index (Local or Internal), consuming code MUST validate Id is within the valid range before use."
  ```
- **Severity:** High (design risk — bounds-check responsibility is implicit)

### 3.4 — `telemetry_record`: `Size` field uses `Basic_Types.Positive_16` but minimum telemetry size of 1 bit may be too permissive

- **Location:** `telemetry_record.record.yaml`, field `Size`
- **Original Code:**
  ```yaml
  - name: Size
    description: Size of the telemetry item (in bits).
    type: Basic_Types.Positive_16
    format: U16
  ```
- **Explanation:** `Positive_16` presumably ranges from 1 to 65535. A telemetry item of 65535 bits (≈8 KB) seems excessively large for a value that will be stored into a 32-bit `Packed_Poly_32_Type`. If the runtime fetches a telemetry item larger than 32 bits and attempts to store it in an internal variable, it would overflow. The type-level constraint here does not prevent this.
- **Corrected Code:** Consider constraining to 32 bits max:
  ```yaml
  type: Interfaces.Unsigned_16  # with runtime check: Size <= 32
  ```
  Or define a subtype: `subtype Tlm_Bit_Size is Positive range 1 .. 32;`
- **Severity:** High (potential runtime overflow if unchecked in consuming code)

### 3.5 — `Seq_Opcode` enum: value collision between `Str_Alloc` (37) and `Seq_Operation.Modulus` (37)

- **Location:** `seq_enums.enums.yaml`, enums `Seq_Opcode` and `Seq_Operation`
- **Explanation:** These are separate enums used in different contexts (`Opcode` field vs. `Operation` field), so this is not a true collision at the Ada type level. However, the `packed_seq_opcode` record stores the opcode as `Seq_Opcode.E` with format `U8`, and opcodes 37–45 overlap in numeric value space with some `Seq_Operation` values (also `U8`). Since they occupy different record fields, this is safe — but worth noting for anyone debugging raw binary sequences.
- **Severity:** Low (informational)

### 3.6 — `Seq_Data_Type` description says "two" but has note about chars being "random"

- **Location:** `seq_enums.enums.yaml`, enum `Seq_Data_Type`
- **Original Code:**
  ```yaml
  description: "...the values my seem random, they are not."
  ```
- **Explanation:** Typo: "my" should be "may."
- **Corrected Code:**
  ```yaml
  description: "...the values may seem random, they are not."
  ```
- **Severity:** Low

### 3.7 — `kill_eng_record`: `Num_To_Kill` overflow risk

- **Location:** `kill_eng_record.record.yaml`
- **Original Code:**
  ```yaml
  - name: Engine_Start
    type: Seq_Types.Sequence_Engine_Id
    format: U8
  - name: Num_To_Kill
    type: Seq_Types.Sequence_Engine_Id
    format: U8
  ```
- **Explanation:** `Num_To_Kill` uses the type `Sequence_Engine_Id` (range 0..255), but semantically it represents a count, not an engine identifier. If `Engine_Start + Num_To_Kill - 1` exceeds the actual number of engines, the runtime must handle it. Using the engine ID type for a count is semantically misleading. A dedicated count type would be clearer and safer.
- **Corrected Code:**
  ```yaml
  - name: Num_To_Kill
    description: The number of engines to kill from Engine_Start (including Engine_Start).
    type: Basic_Types.Byte  # or a dedicated Num_Engines count type
    format: U8
  ```
- **Severity:** Medium

### 3.8 — `Seq_Runtime_State`: Typo in description

- **Location:** `seq_enums.enums.yaml`, enum `Seq_Runtime_State`, literal `TELEMETRY_SET`
- **Original Code:**
  ```yaml
  description: "The sequence has received valid telemetry and should check act upon it's value."
  ```
- **Explanation:** Two issues: "check act upon" should be "check and act upon" (or just "act upon"), and "it's" should be "its" (possessive, not contraction).
- **Corrected Code:**
  ```yaml
  description: "The sequence has received valid telemetry and should act upon its value."
  ```
- **Severity:** Low

---

## 4. Unit Test Review

**No unit test files found** in this directory or subdirectories (excluding `build/`).

This is acceptable for a pure types/constants package — the types are exercised by consuming packages' tests. However, for a safety-critical system, consider adding a minimal test package that verifies:

1. **Constants match assumptions:** `Max_Seq_Size = 65536`, `Num_Seq_Variables = 16`, `Max_Seq_String_Size = 64`.
2. **Type ranges are as expected:** `Seq_Position'Last = 65535`, `Seq_Local_Id'Last = 15`.
3. **Generated record sizes match expected wire format sizes** (e.g., `Goto_Record.Size_In_Bytes = 4`).

**Severity:** Medium (no tests for a foundational types package in safety-critical code)

---

## 5. Summary — Top 5 Issues

| # | Severity | Location | Issue |
|---|----------|----------|-------|
| 1 | **High** | `var_record.record.yaml` : `Id` field | Dual-use 32-bit field (literal vs. index) with no documented bounds-check requirement. Consuming code must validate index values against `Seq_Local_Id` (0–15) or `Seq_Num_Internals` (0–3) — failure to do so is a potential out-of-bounds access. |
| 2 | **High** | `telemetry_record.record.yaml` : `Size` field | Allows telemetry sizes up to 65535 bits, but values are stored in 32-bit internals. No type-level constraint prevents overflow; consuming code must enforce `Size <= 32`. |
| 3 | **Medium** | `seq_enums.enums.yaml` : `Seq_Error` | Inconsistent literal naming convention (mix of `ALL_CAPS` and `Mixed_Case`) increases risk of typos and maintenance errors in safety-critical pattern matching. |
| 4 | **Medium** | `seq_enums.enums.yaml` / `seq_types.ads` | Comments and descriptions incorrectly state "two" internal variables when there are four (`Timeout`, `Seq_Return`, `A`, `B`). Misleading documentation in flight code. |
| 5 | **Medium** | `kill_eng_record.record.yaml` : `Num_To_Kill` | Uses `Sequence_Engine_Id` type for a count field — semantically incorrect and could mislead maintainers about valid values and overflow behavior. |

## Resolution Notes

| # | Issue | Severity | Status | Commit | Notes |
|---|-------|----------|--------|--------|-------|
| 1 | var_record.Id bounds-check docs | High | Fixed | 172e3c7 | Added documentation |
| 2 | telemetry_record.Size constraint | High | Fixed | cf584f9 | Documented 32-bit limit |
| 3 | Inconsistent Seq_Error casing | Medium | Fixed | 11d2020 | Standardized to ALL_CAPS |
| 4 | Misleading "two internals" comment | Medium | Fixed | 43c5c35 | Corrected to four |
| 5 | Num_To_Kill type misuse | Medium | Fixed | dc8f1f6 | Changed to Basic_Types.Byte |
| 6 | No unit tests | Medium | Not Fixed | b4108a2 | Deferred |
| 7 | Max_Seq_Size derivation | Low | Fixed | 9b85e35 | Derived from Unsigned_16'Last |
| 8 | Wide Engine_Id range | Low | Fixed | 88f00ad | Added rationale comment |
| 9 | Opcode overlap | Low | Not Fixed | 0abda7e | By design |
| 10 | Typo "my" → "may" | Low | Fixed | 4fd2a2c | Fixed |
| 11 | Grammar in TELEMETRY_SET | Low | Fixed | 87ae1b5 | Fixed |

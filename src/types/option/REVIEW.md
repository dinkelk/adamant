# Types Package Review

Review of `src/types/{option, packet, parameter, sequence, sys_time, tick}`.

---

## 1. Option (`option/`)

**Purpose:** Generic Ada discriminated record implementing a Rust-style `Option<T>` pattern — either holds an element or is empty.

**Assessment: Clean and well-designed.**

- Elegant use of Ada's discriminated records to create a type-safe optional. The discriminant `Has_Element` controls field presence at the type level, preventing access to undefined data (unlike the `out` parameter + status Boolean pattern demonstrated in the test).
- Generic over any constrained, non-limited type — good composability.
- Test file (`test/test.adb`) is excellent pedagogical code showing exactly why this pattern is superior to the `Return_Status` pattern (variable `G` is used uninitialized if status isn't checked).

**Issues:** None significant.

**Nit:** The test uses `pragma Profile (Ravenscar)` but then uses `Ada.Text_IO` — this wouldn't fly on a real Ravenscar target. Fine for a demo/test though.

---

## 2. Packet (`packet/`)

**Purpose:** Defines the telemetry/data packet type system — IDs, headers, buffers, and rate-limiting.

**Assessment: Solid, well-structured.**

- `Packet_Types.ads`: Clean type declarations. Using `new Natural range` for `Packet_Id` gives type safety. `Sequence_Count_Mod_Type` as `mod 2**14` is a good fit for a wrapping counter.
- `packet_header.record.yaml`: Good inclusion of timestamp, ID, sequence count, and buffer length in the header.
- `packet.record.yaml`: Variable-length buffer via `variable_length: Header.Buffer_Length` — clean pattern.
- `packets_per_period.record.yaml`: Simple rate-limiting config with sensible defaults (5 packets/second).

**Issues:**

- **Buffer size coupling:** `Packet_Buffer_Length_Type` and buffer size come from `Configuration.Packet_Buffer_Size`. This is a project-wide constant — appropriate for embedded, but worth noting the tight coupling.
- **Index off-by-one pattern:** `Packet_Buffer_Index_Type` ranges `0 .. Last - 1` while `Packet_Buffer_Length_Type` ranges `0 .. Last`. This is correct (length vs. index) but could trip up maintainers. A comment would help.

---

## 3. Parameter (`parameter/`)

**Purpose:** Full parameter management system — IDs, headers, buffers, operations, status reporting, table management with CRC and versioning.

**Assessment: Comprehensive and production-quality.**

- Rich enumeration set in `parameter_enums.enums.yaml` covering operations (Stage/Update/Fetch/Validate), statuses, table operations, and validation states. Well-thought-out state machine.
- `parameter_update.record.yaml` bundles table ID, operation, status, and the parameter itself — good for a connector/message-passing type.
- `parameter_table_header.record.yaml` includes CRC and version with a preamble computing section lengths — clean.
- `Invalid_Parameter_Info` with `Errant_Field_Number` (0=unknown, 2^32=length field) is a practical diagnostic type.

**Issues:**

- **`Parameter_Buffer_Length` format is U16 but `Parameter_Header.Buffer_Length` format is U8.** The header constrains buffer length to 255 bytes max (U8), while `Parameter_Buffer_Length_Type` allows up to `Configuration.Parameter_Buffer_Size` which could exceed 255. If `Parameter_Buffer_Size > 255`, the U8 format in the header would silently truncate. **This is a potential bug** — verify that `Parameter_Buffer_Size` is always ≤ 255, or change the header format to U16.
- `Parameter_Types.ads` mixes record-style declarations (`Parameter_Status`) with the package's primary role as a types-only package. Not wrong, but slightly inconsistent with the YAML-driven record generation pattern used elsewhere.
- `Parameter_Table_Update_Status` has 7 values (0–6) which is fine for an E8, but the `Individual_Parameter_Modified` status (value 6) has a very long description that doubles as documentation — consider moving the detailed explanation to a separate doc.

---

## 4. Sequence (`sequence/`)

**Purpose:** Command sequence types and a CRC validation utility.

**Assessment: Well-implemented with careful defensive coding.**

- `Sequence_Util.Crc_Sequence_Memory_Region` is excellent:
  - Validates region length ≥ header size before overlay.
  - Validates header's stated length against region length AND minimum header size.
  - CRCs only after both length checks pass.
  - Returns structured status (`Valid | Length_Error | Crc_Error`) — no silent failures.
- CRC excludes the first 2 bytes (the CRC field itself) — standard pattern, correctly implemented.
- Uses `with Import, Convention => Ada, Address => ...` for memory overlays — correct and idiomatic for this kind of work.

**Issues:**

- **`Sequence_Header.Category` is described as "currently unused by Adamant."** Dead fields in wire-format headers are tech debt. If truly unused, consider marking it reserved or documenting when it might be used.
- `Sequence_Length_Type` is `Natural range 0 .. 65_535` — this is a U16 on the wire but `Natural` in Ada (which is typically 32-bit). The YAML format is U16, so this is fine for serialization, just noting the in-memory vs. wire distinction.
- The initialization of `Seq_Header` in the error path uses an aggregate with hardcoded zeros. This is fine but could use a named constant (e.g., `Null_Header`).

---

## 5. Sys_Time (`sys_time/` + sub-packages)

**Purpose:** GPS-epoch timestamp system with 32-bit seconds + 32-bit subseconds (1/(2^32) resolution), arithmetic, pretty-printing, assertions, and an alternative 16-bit subseconds variant.

**Assessment: The most complex package in this set. Thoroughly engineered and well-tested.**

### Core (`sys_time/`)
- `sys_time.record.yaml`: 32-bit seconds + 32-bit subseconds since GPS epoch (Jan 6, 1980). ~0.23 nanosecond resolution. Good for spacecraft/embedded.
- `delta_time.record.yaml` / `signed_delta_time.record.yaml`: Unsigned and signed time differences. The signed variant adds a `Sign` discriminator enum rather than using two's complement — appropriate for a wire format.

### Arithmetic (`arithmetic/`)
- `Sys_Time.Arithmetic`: Full operator set (+, -, <, <=, >, >=) with overflow/underflow detection via `Sys_Time_Status`. Excellent.
- `To_Sys_Time`: Handles negative times (underflow), oversized times (overflow), and the subtle fixed-point rounding edge case where subseconds can round to `2^32` (rolls to next second). **This is a known hard bug in time conversion code and they got it right.**
- `To_Time`: Uses scaled integer math (`Scale_64 = 10^10`) to avoid floating point in the subsecond conversion. Includes a `Compile_Time_Error` pragma to catch overflow at compile time. Very good.
- `Delta_Time.Arithmetic` / `Signed_Delta_Time.Arithmetic`: Reuse `Sys_Time.Arithmetic` via `Unchecked_Conversion` (same binary representation). Clean code reuse. Handles `Time_Span_First` edge case (would overflow `abs`).

### Pretty (`pretty/`)
- Simple `seconds.nanoseconds` string formatting with optional zero-padding. `Delta_Time.Pretty` delegates to `Sys_Time.Pretty` via unchecked conversion — consistent reuse pattern.

### Assertion (`sys_time/` + `subseconds_16/`)
- Epsilon-based equality (default 300ns tolerance) for test assertions. Diagnostic messages include difference in nanoseconds and epsilon details — very helpful for debugging.
- Duplicate code between `sys_time/` and `subseconds_16/` assertion packages — these are identical. This appears intentional (different compilation units for different subsecond widths) but worth noting.

### Subseconds_16 (`subseconds_16/`)
- Alternative 16-bit subsecond representation (1/(2^16) ≈ 15.3μs resolution) described as "EMA VTC format."
- `env.py` swaps build paths to substitute the 16-bit variant. Clean build-system integration.
- `README.md` documents the swap mechanism.

### Tests (`test/`)
- 20,000 random iterations each for add, subtract-time, and subtract-timespan operations. Statistical reporting (max/average error in nanoseconds). Tolerance of 32μs for floating-point comparison paths.
- `Test_Subtract_Problematic`: Regression test for the fixed-point rounding overflow bug. Excellent.
- `duration_info.txt` documents the platform's `Duration` characteristics — useful reference.

**Issues:**

- **Commented-out debug code** in `Sys_Time.Arithmetic.To_Time` (7 `Put_Line` calls). Should be removed or moved to a debug build flag.
- **`Ignore` variable pattern** in `Sys_Time.Assertion.Eq`/`Neq`: `Ignore : Sys_Time_Status := To_Delta_Time(...)` — calling a function for its side effect and ignoring the status. If `To_Delta_Time` fails (e.g., epsilon overflows), the diagnostic message will contain garbage. Low risk since epsilon values are small, but not ideal.
- **Test comments say "5000" but code runs 20,000** iterations — stale comments in `Add_Time` and `Subtract_Time`.
- The comparison operators (`<`, `<=`, `>`, `>=`) convert to `Ada.Real_Time.Time` and back. This works but introduces unnecessary conversion overhead. A direct comparison of `(Seconds, Subseconds)` tuples would be trivial and faster:
  ```ada
  function "<" (Left, Right : Sys_Time.T) return Boolean is
  begin
     return Left.Seconds < Right.Seconds or else
            (Left.Seconds = Right.Seconds and Left.Subseconds < Right.Subseconds);
  end "<";
  ```
  This would also avoid any potential precision loss from round-tripping through `Duration`.

---

## 6. Tick (`tick/`)

**Purpose:** Periodic scheduling tick type — a timestamp plus a monotonic counter.

**Assessment: Simple, correct, focused.**

- `tick.record.yaml`: Just `Sys_Time.T` + `Unsigned_32` count. Minimal and sufficient.
- `Tick_Interrupt_Handler`: Two procedures — `Handler` increments the count, `Set_Tick_Time` sets the timestamp. Designed for use as formal parameters to generic interrupt handler components.
- Uses `@ + 1` syntax (Ada 2022 target renaming) for the increment — modern.

**Issues:** None. This is about as simple as a type package can be.

---

## Summary

| Package | Quality | Issues |
|---------|---------|--------|
| Option | ★★★★★ | None |
| Packet | ★★★★☆ | Minor: index range documentation |
| Parameter | ★★★★☆ | **Potential bug: Header.Buffer_Length U8 vs Parameter_Buffer_Size** |
| Sequence | ★★★★½ | Minor: unused Category field |
| Sys_Time | ★★★★½ | Comparison operators should be direct; stale comments; dead debug code |
| Tick | ★★★★★ | None |

### Top Priority
**Verify `Parameter_Header.Buffer_Length` (U8) can hold `Configuration.Parameter_Buffer_Size`.** If the config value can exceed 255, this is a silent truncation bug in serialized parameters.

### Recurring Patterns (Positive)
- Consistent use of `new Natural range` for ID types — type safety without runtime cost
- YAML-driven record generation with explicit wire formats — good for cross-language interop
- Defensive overflow/underflow handling throughout arithmetic code
- `Unchecked_Conversion` reuse between structurally identical types (Delta_Time ↔ Sys_Time)

### Recurring Patterns (To Improve)
- Stale/commented-out debug code (sys_time arithmetic)
- Some comments reference different numbers than the code (test iteration counts)
- Duplicate assertion packages across subseconds variants (unavoidable given build-path swapping, but worth noting)

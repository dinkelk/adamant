# Code Review — `src/util/crc`

## 1. Package Specification Review

### 1.1 — Crc_16 Spec: Well-Designed API
**Severity:** None  
The specification is clean. The `Crc_16_Type` as a 2-byte array with explicit `Object_Size` is a sound design choice for endianness safety. Both overloads (Byte_Array and Byte_Array_Pointer) with a seeded default are appropriate for incremental CRC computation. Comments are accurate and thorough.

### 1.2 — Checksum_16 Spec: Missing Object_Size on Subtype
**Severity:** Low  
**Location:** `checksum_16.ads:7`  
**Original Code:**
```ada
subtype Checksum_16_Type is Basic_Types.Byte_Array (0 .. 1);
```
**Issue:** Unlike `Crc_16_Type`, this subtype does not have an `Object_Size` aspect. While the parent type likely constrains it, the CRC-16 package explicitly sets it — the inconsistency suggests an oversight.  
**Proposed Fix:**
```ada
subtype Checksum_16_Type is Basic_Types.Byte_Array (0 .. 1)
   with Object_Size => 2 * 8;
```

### 1.3 — Xor_8 Spec: Default Seed of 0xFF May Surprise Callers
**Severity:** Low  
**Location:** `xor_8.ads:13`  
**Original Code:**
```ada
Seed : in Xor_8_Type := 16#FF#
```
**Issue:** The conventional initial value for an 8-bit XOR/LRC calculation is `0x00` (identity element for XOR). A default of `0xFF` effectively inverts the result. The comment says "Including this parity byte in the byte array to be checked will result in a result of zero" — this is only true if the original computation also used `0xFF`, which is non-standard. If this is intentional for the project's protocol, it should be documented *why* `0xFF` was chosen rather than `0x00`.  
**Proposed Fix:** Add a comment explaining the rationale, e.g., `-- Seed of 0xFF chosen to match [protocol X] convention.`

## 2. Package Implementation Review

### 2.1 — Crc_16 Body (Byte_Array_Pointer overload): Unsafe on Zero-Length Input
**Severity:** High  
**Location:** `crc_16.adb` (Byte_Array_Pointer overload)  
**Original Code:**
```ada
subtype Safe_Byte_Array_Type is Basic_Types.Byte_Array (0 .. Length (Byte_Ptr) - 1);
Safe_Byte_Array : Safe_Byte_Array_Type with Import, Convention => Ada, Address => Address (Byte_Ptr);
```
**Issue:** If `Length(Byte_Ptr)` returns 0, the subtype range becomes `0 .. -1` (a null range), and the overlay is created at whatever `Address(Byte_Ptr)` returns. The subsequent call to `Compute_Crc_16(Safe_Byte_Array, Seed)` should be safe because the loop over a null range is a no-op, BUT the `Import` overlay at a potentially null/invalid address is undefined behavior even if never accessed. On some runtimes/targets, elaborating an `Import`ed object at address 0 with a null range could raise `Storage_Error` or cause other issues. A defensive guard would be safer.  
**Proposed Fix:**
```ada
if Length (Byte_Ptr) = 0 then
   return Seed;
end if;
-- ... existing overlay code ...
```

### 2.2 — Crc_16 Body: Lookup Tables Declared Inside Function (Performance)
**Severity:** Low  
**Location:** `crc_16.adb:6-47` (inside `Compute_Crc_16`)  
**Original Code:** `Low_Crc` and `High_Crc` constants declared as local variables inside the function body.  
**Issue:** On targets without link-time optimization, the compiler may place these 256-byte tables on the stack or re-initialize them on each call. For a safety-critical embedded system, stack usage should be predictable and minimal. Moving them to package-level would guarantee static allocation.  
**Proposed Fix:** Move `Low_Crc`, `High_Crc`, and the `Byte_Array_Byte_Index` type to the package body declarative region (outside the function).

### 2.3 — Checksum_16 Body: Unsigned_16 Wraparound Is Intentional but Undocumented
**Severity:** Medium  
**Location:** `checksum_16.adb:9-10`  
**Original Code:**
```ada
To_Return := @ + Unsigned_16 (Bytes (Idx)) * 16#100#;
...
To_Return := @ + Unsigned_16 (Bytes (Idx));
```
**Issue:** `Unsigned_16` arithmetic wraps modularly, so this is a modular 16-bit checksum. This is standard behavior for a Fletcher/simple checksum, but the specification says "adds all the 16-bit words" without stating that overflow wraps (mod 2^16). In safety-critical code, reliance on modular wraparound should be explicitly documented.  
**Proposed Fix:** Add a comment: `-- Note: Unsigned_16 addition wraps mod 2**16 per the checksum algorithm.`

## 3. Model Review

### 3.1 — crc_16.tests.yaml
**Severity:** None  
The YAML test model is minimal and correct. It declares two tests matching the implementation. No issues.

No other YAML models to review.

## 4. Unit Test Review

### 4.1 — CRC-16 Tests: Only One Input Pattern Tested
**Severity:** Medium  
**Location:** `test/crc_16_tests-implementation.adb`  
**Issue:** Both `Test_Crc` and `Test_Crc_Seeded` use the exact same 15-byte input and expected output (`75 FB`). The seeded test verifies incremental CRC (splitting the input into chunks), which is valuable, but there is no variation in test data. Missing coverage includes:
- Empty byte array (0 bytes) — tests the seed-passthrough behavior
- Single byte
- All-zeros / all-ones patterns
- Known CCITT test vector: "123456789" → `0x29B1` (with seed `0xFFFF`)
- Maximum-length arrays (stress/boundary)

**Proposed Fix:** Add at least the standard CCITT verification vector and an empty-input test case.

### 4.2 — CRC-16 Tests: Byte_Array_Pointer Overload Not Tested
**Severity:** Medium  
**Location:** `test/crc_16_tests-implementation.adb`  
**Issue:** The `Compute_Crc_16(Byte_Array_Pointer.Instance, ...)` overload is never exercised by any unit test. This is the overload with the `Import`/`Address` overlay (see finding 2.1), which is the most safety-critical code path to validate.  
**Proposed Fix:** Add a test case that constructs a `Byte_Array_Pointer.Instance` and verifies the CRC matches the Byte_Array overload for the same data.

### 4.3 — Xor_8: No Unit Tests
**Severity:** Medium  
**Location:** `xor_8.ads` / `xor_8.adb`  
**Issue:** There is no test directory or test file for `Xor_8`. The package is trivial but untested. For safety-critical code, even trivial functions should have at least basic verification (identity: XOR of nothing returns seed; known pattern; self-check property).  
**Proposed Fix:** Add a test harness for `Xor_8` with basic vectors.

### 4.4 — Checksum_16 Tests: pragma Assert Instead of AUnit
**Severity:** Low  
**Location:** `test_checksum/test.adb`  
**Issue:** The checksum tests use `pragma Assert` in a standalone procedure rather than the AUnit framework used by CRC-16 tests. If assertions are disabled at compile time (`-gnata` not set), these tests silently pass without checking anything. The test also has good coverage (even/odd lengths, non-zero-based arrays, seeds, large input), so the *content* is solid — only the mechanism is fragile.  
**Proposed Fix:** Either ensure the build system always compiles this test with `-gnata`, or migrate to AUnit for consistency.

## 5. Summary — Top 5 Highest-Severity Findings

| # | Severity | Finding | Location |
|---|----------|---------|----------|
| 1 | **High** | `Byte_Array_Pointer` CRC overload creates an `Import` overlay that is unsafe for zero-length input (null range at potentially invalid address) | `crc_16.adb` (pointer overload) |
| 2 | **Medium** | `Byte_Array_Pointer` CRC overload has no unit test coverage | `test/crc_16_tests-implementation.adb` |
| 3 | **Medium** | CRC-16 tests use only one input pattern; missing standard CCITT test vector and edge cases | `test/crc_16_tests-implementation.adb` |
| 4 | **Medium** | `Xor_8` package has no unit tests at all | (missing) |
| 5 | **Medium** | Checksum_16 modular wraparound behavior is undocumented; relies on `Unsigned_16` semantics without comment | `checksum_16.adb` |

# Code Review: src/util/crc

**Reviewer:** Automated Ada Code Review
**Date:** 2026-02-28
**Packages:** `Crc_16`, `Checksum_16`, `Xor_8`

---

## 1. Package Specification Review

> _No issues found in Package Specifications. All three specs (`crc_16.ads`, `checksum_16.ads`, `xor_8.ads`) have clear documentation, appropriate type definitions using byte arrays to avoid endianness issues, and well-defined interfaces with sensible default seeds._

---

## 2. Package Implementation Review

### Implementation — Unsafe Address Overlay With Zero-Length Pointer
**Severity:** Medium
**Location:** `crc_16.adb:56-59`
**Original Code:**
```ada
56:   subtype Safe_Byte_Array_Type is Basic_Types.Byte_Array (0 .. Length (Byte_Ptr) - 1);
57:   -- Perform overlay manually instead of using Byte_Array_Pointer.Pointer to avoid Byte_Array_Access range checking.
58:   -- A null (address 0x0) Byte_Array_Access is not allowed in Ada, but we want to be able to CRC at address zero.
59:   Safe_Byte_Array : Safe_Byte_Array_Type with Import, Convention => Ada, Address => Address (Byte_Ptr);
```
**Issue:** If `Length(Byte_Ptr)` is 0, the subtype becomes `Byte_Array(0 .. -1)` (empty), which is valid Ada. However, the `Address` overlay is still applied to whatever address is in the pointer (potentially invalid/null). While Ada should never access memory for an empty array, the overlay itself with `Import` on an invalid address is implementation-defined behavior. A guard clause would make the intent explicit and protect against compiler-specific behavior.
**Proposed Fix:**
```ada
function Compute_Crc_16 (Byte_Ptr : in Byte_Array_Pointer.Instance; Seed : in Crc_16_Type := [0 => 16#FF#, 1 => 16#FF#]) return Crc_16_Type is
   use Byte_Array_Pointer;
begin
   if Length (Byte_Ptr) = 0 then
      return Seed;
   end if;
   declare
      subtype Safe_Byte_Array_Type is Basic_Types.Byte_Array (0 .. Length (Byte_Ptr) - 1);
      Safe_Byte_Array : Safe_Byte_Array_Type with Import, Convention => Ada, Address => Address (Byte_Ptr);
   begin
      return Compute_Crc_16 (Safe_Byte_Array, Seed);
   end;
end Compute_Crc_16;
```

### Implementation — Checksum_16 Wrapping Arithmetic Is Intentional But Undocumented
**Severity:** Low
**Location:** `checksum_16.adb:9`
**Original Code:**
```ada
 9:   function Compute_Checksum_16 (Bytes : in Basic_Types.Byte_Array; Seed : in Unsigned_16 := 16#0000#) return Unsigned_16 is
10:      To_Return : Unsigned_16 := Seed;
```
**Issue:** `Unsigned_16` is a modular type so addition wraps silently. This is standard for checksum algorithms but a brief comment noting the intentional wrapping behavior would aid maintainability, especially in a safety-critical codebase where overflow is normally a concern.
**Proposed Fix:** Add a comment:
```ada
-- Note: Unsigned_16 is modular; addition wraps by design (standard checksum behavior).
To_Return : Unsigned_16 := Seed;
```

> _No other issues found in implementations. The CRC-16 lookup tables, XOR-8 logic, and checksum computation are straightforward and correct._

---

## 3. Model Review

> _No YAML models to review._

---

## 4. Unit Test Review

### Unit Tests — No Tests for Xor_8 Package
**Severity:** High
**Location:** (missing test directory for `xor_8`)
**Issue:** The `Xor_8` package has no unit tests anywhere in this directory tree. While the implementation is simple, any package in a safety-critical system should have tests verifying at minimum: known-good values, empty array input, single-byte input, and the seed mechanism. Without tests, regressions or integration errors would go undetected.
**Proposed Fix:** Create a `test_xor/` directory with tests covering:
- Known XOR result for a multi-byte array
- Empty array returns seed unchanged
- Single byte XOR with default seed (0xFF)
- Seed override behavior
- Round-trip: XOR of (data ++ xor_result) == 0x00

### Unit Tests — CRC-16 Tests Lack Edge Cases and Diversity
**Severity:** Medium
**Location:** `test/crc_16_tests-implementation.adb`
**Issue:** Only one input pattern is tested (the same 15-byte array in both `Test_Crc` and `Test_Crc_Seeded`). Missing test cases include:
- Empty byte array (should return seed)
- Single-byte input
- All-zeros input
- All-0xFF input
- Large input to exercise more table entries
- The `Byte_Array_Pointer` overload is entirely untested
**Proposed Fix:** Add additional test procedures covering the above cases, and add at least one test exercising `Compute_Crc_16` via `Byte_Array_Pointer`.

### Unit Tests — Checksum_16 Tests Lack Empty Array Case
**Severity:** Low
**Location:** `test_checksum/test.adb`
**Issue:** The checksum tests cover even-length, odd-length, seeded, and large arrays well, but do not test the empty array edge case (`Compute_Checksum_16([])` should return the seed).
**Proposed Fix:** Add:
```ada
Checksum := Compute_Checksum_16 (Basic_Types.Byte_Array'(1 .. 0 => 0));
pragma Assert (Checksum = [16#00#, 16#00#], "Empty array should return default seed");
```

### Unit Tests — Checksum Test Uses pragma Assert Instead of Test Framework
**Severity:** Low
**Location:** `test_checksum/test.adb`
**Issue:** The checksum tests use `pragma Assert` in a standalone procedure rather than the AUnit framework used by the CRC-16 tests. This means test failures may manifest as unhandled exceptions rather than structured test reports, and individual test case identification is lost. This is a consistency and maintainability issue.
**Proposed Fix:** Consider migrating to AUnit for consistency, or document why the simpler approach is used here.

---

## 5. Summary — Top 5 Findings

| # | Severity | Description | Location | Why It Matters |
|---|----------|-------------|----------|----------------|
| 1 | **High** | No unit tests exist for the `Xor_8` package | (missing) | Zero test coverage for a safety-critical utility; regressions undetectable |
| 2 | **Medium** | Address overlay on potentially invalid pointer when length is zero | `crc_16.adb:56-59` | Implementation-defined behavior; could cause issues on some targets |
| 3 | **Medium** | CRC-16 tests lack edge cases and input diversity | `test/crc_16_tests-implementation.adb` | Single test vector insufficient to validate lookup table correctness |
| 4 | **Low** | Checksum wrapping arithmetic undocumented | `checksum_16.adb:9-10` | In safety-critical code, intentional wrapping should be explicitly noted |
| 5 | **Low** | Checksum tests missing empty array case | `test_checksum/test.adb` | Edge case boundary not validated |

---

## Resolution Notes

| # | Issue | Severity | Status | Commit | Notes |
|---|-------|----------|--------|--------|-------|
| 1 | No Unit Tests for Xor_8 Package | High | Fixed | 76d71eb | Added test directory and tests for Xor_8 package |
| 2 | Unsafe Address Overlay With Zero-Length Pointer | Medium | Fixed | ba02baf | Added early return guard clause when length is zero |
| 3 | CRC-16 Tests Lack Edge Cases and Diversity | Medium | Fixed | e935e62 | Added edge case and diverse input test vectors |
| 4 | Checksum_16 Wrapping Arithmetic Undocumented | Low | Fixed | 7c4488f | Added comment documenting intentional modular wrapping |
| 5 | Checksum_16 Tests Lack Empty Array Case | Low | Fixed | 80787dc | Added empty array test case |
| 6 | Checksum Test Uses pragma Assert Instead of Test Framework | Low | Fixed | aad356b | Migrated checksum tests to use AUnit framework |

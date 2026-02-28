# Code Review — `Diagnostic_Uart` Package

**Reviewer:** Automated (Claude)  
**Date:** 2026-02-28  
**Scope:** `src/components/ccsds_serial_interface/uart/` (excluding `build/`)

---

## 1. Package Specification Review

### 1.1 — Specification is Clean and Well-Documented
**Severity:** None  
**Location:** `diagnostic_uart.ads`

The specification is straightforward. The API is minimal (Get/Put for single bytes and arrays), comments clearly document blocking behavior and the Text_IO conflict hazard. No issues found in the specification.

---

## 2. Package Implementation Review

### 2.1 — Address Overlay in `Get` May Read Uninitialized Memory on Mismatched Sizes
**Severity:** Low  
**Location:** `diagnostic_uart.adb:6-8`  
**Original Code:**
```ada
Val : Character;
A_Byte : Basic_Types.Byte with Import, Convention => Ada, Address => Val'Address;
```
**Issue:** The overlay of `Character` and `Basic_Types.Byte` (presumably `Interfaces.Unsigned_8`) relies on both being exactly 1 byte. This is safe on all realistic GNAT targets (Character is always 8 bits), but the assumption is implicit. If `Basic_Types.Byte` were ever wider than `Character'Size`, this overlay would read beyond `Val`'s storage. The same pattern appears in `Put` (line 18-19) in reverse.  
**Proposed Fix:** No change required for current targets. For defense-in-depth, add a compile-time assertion:
```ada
pragma Compile_Time_Error
  (Character'Size /= Basic_Types.Byte'Size,
   "Character and Byte must be the same size for overlay");
```

### 2.2 — `Put` Overlay Aliases an `in`-Mode Parameter
**Severity:** Medium  
**Location:** `diagnostic_uart.adb:18-19`  
**Original Code:**
```ada
procedure Put (B : in Basic_Types.Byte) is
   Val : Character with Import, Convention => Ada, Address => B'Address;
```
**Issue:** `B` is an `in`-mode formal parameter. On some calling conventions (especially when the parameter is passed by copy in a register), taking `'Address` of a by-copy `in` parameter and overlaying it is technically erroneous per Ada RM 13.3(16) — the address may not be meaningful or stable. GNAT on most targets handles this correctly because `Byte` is small and `'Address` forces it to memory, but this is a portability and correctness concern. The `Get` function's overlay on a local `Val` variable does not have this issue.  
**Proposed Fix:** Copy to a local variable first, then overlay:
```ada
procedure Put (B : in Basic_Types.Byte) is
   Local : constant Basic_Types.Byte := B;
   Val : Character with Import, Convention => Ada, Address => Local'Address;
begin
   Ada.Text_IO.Put (Val);
end Put;
```

### 2.3 — No Concurrency Protection Despite Documented Hazard
**Severity:** Low  
**Location:** `diagnostic_uart.adb` (entire body)  
**Original Code:** N/A (absence of code)  
**Issue:** The spec comments warn "DO NOT use Text_IO and this package concurrently." However, even calls to `Diagnostic_Uart` itself from multiple tasks would interleave bytes, corrupting both Tx and Rx streams. For a non-flight diagnostic utility this may be acceptable, but there is no protected object, lock, or even a comment acknowledging task-safety within the body.  
**Proposed Fix:** Either (a) document in the spec that the package is **not task-safe** (single-task use only), or (b) wrap `Put (Bytes)` and `Get (Bytes)` in a protected object or use `Ada.Text_IO` locking if available.

---

## 3. Model Review

No YAML models to review.

---

## 4. Unit Test Review

### 4.1 — Test is a Smoke-Test Only; No Assertions or Rx Coverage
**Severity:** High  
**Location:** `test/test.adb`  
**Original Code:**
```ada
procedure Test is
begin
   Diagnostic_Uart.Put ([72, 101, 108, 108, 111, 44, 32, 119, 111, 114, 108, 100, 33]);
end Test;
```
**Issue:** The test sends "Hello, world!" and exits. There are no assertions, no verification of output, no exercise of `Get` (single or array), and no exercise of `Put` for a single byte. This provides no regression protection — any implementation that compiles will pass. On a host this may just print to stdout with no way to capture/verify, but even so, a loopback test or mocked Text_IO would add value.  
**Proposed Fix:** At minimum, test all four API entry points. Ideally, redirect or mock `Ada.Text_IO` to verify round-trip correctness:
```ada
-- Test single-byte Put
Diagnostic_Uart.Put (65);

-- Test single-byte Get (requires loopback or mock)
-- Test array Get (requires loopback or mock)

-- If mocking isn't feasible, at least call all subprograms
-- and document that this is a build-verification test only.
```

### 4.2 — Magic Numbers Without Comment
**Severity:** Low  
**Location:** `test/test.adb:7`  
**Original Code:**
```ada
Diagnostic_Uart.Put ([72, 101, 108, 108, 111, 44, 32, 119, 111, 114, 108, 100, 33]);
```
**Issue:** The byte literal array is the ASCII encoding of "Hello, world!" but this is not immediately obvious. The comment above helps, but the values themselves are opaque.  
**Proposed Fix:** Use `Character'Pos` conversions or a named constant:
```ada
Hello : constant Basic_Types.Byte_Array := [Character'Pos ('H'), Character'Pos ('e'), ...];
```
Or simply add a clear inline comment mapping the values.

---

## 5. Summary — Top 5 Highest-Severity Findings

| # | Severity | Section | Title | Location |
|---|----------|---------|-------|----------|
| 1 | **High** | 4.1 | Test is smoke-test only; no assertions, no `Get` coverage | `test/test.adb` |
| 2 | **Medium** | 2.2 | `Put` overlay aliases an `in`-mode parameter (`'Address` on by-copy formal) | `diagnostic_uart.adb:18-19` |
| 3 | **Low** | 2.3 | No concurrency protection despite documented multi-use hazard | `diagnostic_uart.adb` |
| 4 | **Low** | 2.1 | Address overlay assumes `Character'Size = Byte'Size` without compile-time check | `diagnostic_uart.adb:6-8` |
| 5 | **Low** | 4.2 | Magic numbers in test without clear mapping | `test/test.adb:7` |

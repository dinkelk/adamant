# Code Review: ccsds_subpacket_extractor

**Reviewer:** Automated Code Review Agent
**Date:** 2026-02-28
**Branch:** review/components-ccsds-subpacket-extractor

---

## 1. Documentation Review

Documentation is present at `doc/ccsds_subpacket_extractor.pdf` with supporting LaTeX source and assembly context examples.

> _No issues found in Documentation Review. All checks passed._

---

## 2. Model Review

Files reviewed:
- `ccsds_subpacket_extractor.component.yaml`
- `ccsds_subpacket_extractor.events.yaml`
- `ccsds_subpacket_extractor.packets.yaml`
- `ccsds_subpacket_extractor.requirements.yaml`

> _No issues found in Model Review. All checks passed._

---

## 3. Component Implementation Review

Files reviewed:
- `component-ccsds_subpacket_extractor-implementation.ads`
- `component-ccsds_subpacket_extractor-implementation.adb`

### Impl-1 — Silent packet loss on downstream send connector overflow
**Severity:** Medium
**Location:** `component-ccsds_subpacket_extractor-implementation.ads:46-50`
**Original Code:**
```ada
46:   overriding procedure Ccsds_Space_Packet_T_Send_Dropped (Self : in out Instance; Arg : in Ccsds_Space_Packet.T) is null;
47:   overriding procedure Event_T_Send_Dropped (Self : in out Instance; Arg : in Event.T) is null;
48:   overriding procedure Packet_T_Send_Dropped (Self : in out Instance; Arg : in Packet.T) is null;
```
**Issue:** All three downstream send-dropped handlers are `is null`. If the downstream consumer's queue is full, successfully extracted subpackets are silently lost with no event, counter, or log. In a safety-critical system, silent data loss can mask failures. The `Event_T_Send_Dropped` and `Packet_T_Send_Dropped` being null is especially concerning since error-reporting paths themselves would be silently dropped.

**Proposed Fix:**
At minimum, add a counter or event for `Ccsds_Space_Packet_T_Send_Dropped`. For `Event_T_Send_Dropped` and `Packet_T_Send_Dropped`, a counter is the only safe option (sending an event about a dropped event would recurse).

---

### Impl-2 — No validation of Init parameters
**Severity:** Medium
**Location:** `component-ccsds_subpacket_extractor-implementation.adb:22-26`
**Original Code:**
```ada
22:   overriding procedure Init (Self : in out Instance; Start_Offset : in Natural := 0; Stop_Offset : in Natural := 0; Max_Subpackets_To_Extract : in Integer := -1) is
23:   begin
24:      Self.Start_Offset := Start_Offset;
25:      Self.Stop_Offset := Stop_Offset;
26:      Self.Max_Subpackets_To_Extract := Max_Subpackets_To_Extract;
27:   end Init;
```
**Issue:** There is no validation that `Start_Offset + Stop_Offset` is reasonable (e.g., less than the maximum CCSDS data section length). Misconfiguration could lead to `Corrected_Packet_Data_Length` always being negative, causing every packet to be rejected. While the runtime code handles this safely, a defensive assertion at init time would catch configuration errors early.

**Proposed Fix:**
```ada
overriding procedure Init (Self : in out Instance; Start_Offset : in Natural := 0; Stop_Offset : in Natural := 0; Max_Subpackets_To_Extract : in Integer := -1) is
begin
   pragma Assert (Start_Offset + Stop_Offset < Ccsds_Space_Packet.Ccsds_Data_Type'Length,
      "Start_Offset + Stop_Offset exceeds maximum CCSDS data section size");
   Self.Start_Offset := Start_Offset;
   Self.Stop_Offset := Stop_Offset;
   Self.Max_Subpackets_To_Extract := Max_Subpackets_To_Extract;
end Init;
```

---

### Impl-3 — Loop termination depends on external deserialization contract
**Severity:** Low
**Location:** `component-ccsds_subpacket_extractor-implementation.adb:61-73`
**Original Code:**
```ada
61:            while Idx <= Packet_End_Index loop
62:               Stat := Ccsds_Space_Packet.Serialization.From_Byte_Array (Subpacket, Arg.Data (Idx .. Packet_End_Index), Num_Bytes_Deserialized);
63:               if Stat = Success then
64:                  -- Send out subpacket:
65:                  Self.Ccsds_Space_Packet_T_Send (Subpacket);
66:                  Idx := @ + Num_Bytes_Deserialized;
```
**Issue:** Loop termination relies on `Num_Bytes_Deserialized > 0` when `Stat = Success`. If the deserialization function ever returned `Success` with `Num_Bytes_Deserialized = 0` (a contract violation), this would be an infinite loop. In practice, CCSDS minimum serialized length is 7 bytes, making this extremely unlikely, but a defensive assertion would provide a guarantee.

**Proposed Fix:**
```ada
               if Stat = Success then
                  pragma Assert (Num_Bytes_Deserialized > 0, "Deserialization returned success with zero bytes");
                  Self.Ccsds_Space_Packet_T_Send (Subpacket);
                  Idx := @ + Num_Bytes_Deserialized;
```

---

## 4. Unit Test Review

Files reviewed:
- `test/ccsds_subpacket_extractor.tests.yaml`
- `test/ccsds_subpacket_extractor_tests-implementation.ads`
- `test/ccsds_subpacket_extractor_tests-implementation.adb`
- `test/component-ccsds_subpacket_extractor-implementation-tester.ads`
- `test/component-ccsds_subpacket_extractor-implementation-tester.adb`
- `test/test.adb`

Test coverage is thorough with 7 tests covering:
- Nominal extraction (single/multiple subpackets, sync/async)
- Invalid received packet length (too small, too large)
- Invalid extracted subpacket length
- Remaining/trailing bytes
- Queue overflow (dropped packet)
- Start/stop offsets
- Max subpackets to extract (0, 1, 2, 3, 18)

### Test-1 — No test for negative Max_Subpackets_To_Extract (unlimited extraction)
**Severity:** Low
**Location:** `test/ccsds_subpacket_extractor_tests-implementation.adb` (Test_Max_Subpackets_To_Extract)
**Issue:** The `Test_Max_Subpackets_To_Extract` test covers `Max_Subpackets_To_Extract` values of 0, 1, 2, 3, and 18, but never explicitly tests the default negative value (-1) which enables unlimited extraction. While the `Nominal_Extraction` test implicitly exercises this path (the component defaults to -1), an explicit test in `Test_Max_Subpackets_To_Extract` with a comment noting this would improve clarity and coverage intent.

**Proposed Fix:** Add a test case with `Init(Max_Subpackets_To_Extract => -1)` and a packet containing multiple subpackets, verifying all are extracted.

---

### Test-2 — No test for combined offsets with Max_Subpackets_To_Extract
**Severity:** Low
**Location:** `test/ccsds_subpacket_extractor_tests-implementation.adb`
**Issue:** `Test_Offsets` and `Test_Max_Subpackets_To_Extract` are tested independently but never in combination. If an interaction between offset calculation and subpacket counting existed, it would not be caught.

**Proposed Fix:** Add a test case that initializes with both non-zero offsets and a positive `Max_Subpackets_To_Extract`, verifying correct behavior under both constraints simultaneously.

---

## 5. Summary — Top 5 Findings

| # | Severity | Finding | Location | Why It Matters |
|---|----------|---------|----------|----------------|
| 1 | **Medium** | Silent packet loss on downstream send connector overflow — no event or counter when extracted subpackets or error reports are dropped | `implementation.ads:46-50` | In safety-critical systems, silent data loss masks failures and violates observability requirements |
| 2 | **Medium** | No validation of Init parameters — `Start_Offset + Stop_Offset` never checked against maximum data size | `implementation.adb:22-27` | Misconfiguration silently rejected at runtime instead of caught at initialization |
| 3 | **Low** | Loop termination depends on external deserialization returning `Num_Bytes_Deserialized > 0` on success | `implementation.adb:61-66` | Defensive assertion would guard against infinite loop from upstream contract violation |
| 4 | **Low** | No explicit test for negative (unlimited) `Max_Subpackets_To_Extract` value | `test/..._tests-implementation.adb` | Default configuration path deserves explicit test coverage |
| 5 | **Low** | No combined test for offsets + max subpackets | `test/..._tests-implementation.adb` | Feature interaction testing gap |

---

**Overall Assessment:** This is a well-structured, cleanly implemented component. The extraction logic correctly handles boundary conditions, and the test suite is comprehensive. The main concerns are around observability of silent failures on downstream send drops, and a minor defensive programming improvement for the extraction loop. No critical or high severity issues were found.

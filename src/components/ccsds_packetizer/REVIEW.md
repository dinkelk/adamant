# CCSDS Packetizer — Code Review

**Reviewer:** Automated  
**Date:** 2026-02-28  
**Component:** `src/components/ccsds_packetizer`

---

## 1. Documentation Review

**Files:** `ccsds_packetizer.component.yaml`, `ccsds_packetizer.requirements.yaml`, `doc/ccsds_packetizer.tex`

| # | Finding | Severity |
|---|---------|----------|
| D-1 | The component description and requirements are clear, accurate, and consistent with the implementation. | — |
| D-2 | Requirements are well-specified (secondary header with 8-byte timestamp, CRC-CCITT). The CRC polynomial is explicitly documented in LaTeX. | — |
| D-3 | No requirement addresses behavior when `Buffer_Length` is invalid (e.g., exceeds buffer capacity). This is an implicit precondition that is never documented. | Low |
| D-4 | The `.tex` document relies entirely on generated `build/tex/` includes and adds no design rationale or discussion of the conversion algorithm, CRC computation strategy, or memory overlay technique. | Low |

**Assessment:** Documentation is adequate for a simple component. Minor gap in precondition documentation.

---

## 2. Model Review

**File:** `ccsds_packetizer.component.yaml`

| # | Finding | Severity |
|---|---------|----------|
| M-1 | Model is minimal and correct: one `recv_sync` input, one `send` output. Passive execution is appropriate since the conversion is synchronous and stateless. | — |
| M-2 | The send connector is not `recv_sync` on the tester side — it is a standard `send`, meaning dropped packets are silently handled by the null `Ccsds_Space_Packet_T_Send_Dropped` override. This is a design choice but worth noting: **if the downstream queue is full, CCSDS packets are silently dropped with no event, data product, or fault raised.** | Medium |

**Assessment:** Model is sound. Silent drop behavior (M-2) is the most significant design-level observation.

---

## 3. Component Implementation Review

**Files:** `component-ccsds_packetizer-implementation.ads`, `component-ccsds_packetizer-implementation.adb`

| # | Finding | Severity |
|---|---------|----------|
| I-1 | **No validation of `P.Header.Buffer_Length`.** The `To_Ccsds` function trusts `Buffer_Length` from the incoming packet. If `Buffer_Length` exceeds `Packet_Buffer_Type'Length`, the slicing operations on `P.Buffer` and `To_Return.Data` will raise `Constraint_Error` at runtime. While the compile-time check ensures the CCSDS buffer can hold a max-size Adamant packet, there is no runtime guard against a corrupted or malformed `Buffer_Length` field. In a flight system, a single corrupted header could crash the task hosting this component. | **High** |
| I-2 | **Memory overlay for CRC computation assumes contiguous layout.** The `Overlay` byte array is placed at `To_Return'Address` with a computed length. This relies on the record `Ccsds_Space_Packet.T` having no padding between `Header` and `Data`, and that the representation is exactly as expected. While this likely holds given the CCSDS type definitions, it is a fragile assumption — any change to `Ccsds_Space_Packet.T`'s representation clause could silently produce incorrect CRCs. | Medium |
| I-3 | **`Ccsds_Space_Packet_T_Send_Dropped` is `is null`.** As noted in M-2, dropped packets are silently lost. For a telemetry packetizer, this means data loss with no observability. Consider at minimum incrementing a counter or emitting an event. | Medium |
| I-4 | The compile-time size check (`pragma Compile_Time_Error`) is good defensive practice. | — |
| I-5 | The `Packet_Length` field computation (`Sys_Time.Serialization.Serialized_Length + P.Header.Buffer_Length + Crc_16_Type'Length - 1`) correctly follows CCSDS convention (packet length = number of octets in data field − 1). This is correct. | — |

**Assessment:** The implementation is concise and correct for well-formed inputs. The primary concern is the absence of any `Buffer_Length` validation (I-1), which could turn a corrupted packet header into a runtime exception.

---

## 4. Unit Test Review

**Files:** `test/ccsds_packetizer_tests-implementation.adb`, `test/ccsds_packetizer.tests.yaml`, tester files

| # | Finding | Severity |
|---|---------|----------|
| T-1 | **No test for invalid/out-of-range `Buffer_Length`.** Since the implementation does not validate `Buffer_Length`, a test demonstrating what happens with `Buffer_Length > Packet_Buffer_Type'Length` (or a very large value) would reveal the runtime exception vulnerability identified in I-1. | **High** |
| T-2 | **No test for dropped send behavior.** The `Ccsds_Space_Packet_T_Send_Dropped` handler is `is null`. There is no test verifying what happens when the downstream is full. | Medium |
| T-3 | **All three tests are structurally identical** — send 5 packets, check all 5. They only vary in `Buffer_Length` (5, max, 0). The `Check_Packet` helper is thorough (verifies header, timestamp, data, and CRC), which is good. | Low |
| T-4 | **Limited APID/ID diversity.** Tests use only 2 distinct `Id` values (77 and 13). Testing with boundary APID values (0, max APID) would improve coverage of the `Ccsds_Apid_Type` conversion. | Low |
| T-5 | **No test with non-trivial timestamp values.** All tests use `(10, 55)`. Testing with boundary time values (0,0) or max values would verify the timestamp serialization path more thoroughly. | Low |
| T-6 | The `Check_Packet` helper correctly re-computes the CRC over the overlay independently, which is good verification that the CRC in the implementation is correct. | — |
| T-7 | **CRC overlay in test uses `Ccsds_Packet'Address`** — this has the same fragility concern as I-2, and since the test mirrors the implementation technique, it cannot catch overlay-related bugs (it would produce the same wrong answer). | Medium |

**Assessment:** Tests cover the happy path well (nominal, min, max sizes) with thorough output validation. The main gaps are negative/robustness testing and the lack of independence between the test's CRC verification and the implementation's CRC computation technique.

---

## 5. Summary — Top 5 Highest-Severity Findings

| Rank | ID | Severity | Finding |
|------|----|----------|---------|
| 1 | I-1 | **High** | No runtime validation of `Buffer_Length` — a corrupted or out-of-range value will cause `Constraint_Error`, potentially crashing the host task. |
| 2 | T-1 | **High** | No unit test for invalid `Buffer_Length`, leaving the I-1 vulnerability unexercised and undetected. |
| 3 | M-2 / I-3 | **Medium** | Silent packet drop on full downstream queue — no event, counter, or fault is raised, making data loss invisible to operators. |
| 4 | T-7 | **Medium** | Test CRC verification mirrors the implementation's overlay technique, so both would fail identically if the overlay assumption breaks — no independent CRC check. |
| 5 | I-2 | **Medium** | Memory overlay for CRC assumes contiguous, padding-free record layout of `Ccsds_Space_Packet.T`. Fragile under type representation changes. |

## Resolution Notes

| # | Issue | Severity | Status | Commit | Notes |
|---|-------|----------|--------|--------|-------|
| 1 | No Buffer_Length validation (I-1) | High | Fixed | 772eb5d | Added pragma Assert guard |
| 2 | No test for invalid Buffer_Length (T-1) | High | Fixed | 29c2b98 | Added Test_Invalid_Buffer_Length |
| 3 | Silent packet drop (M-2/I-3) | Medium | Not Fixed | ea53999 | Requires model architecture changes |
| 4 | Fragile CRC overlay (I-2) | Medium | Fixed | 0c1acf4 | Added compile-time size check |
| 5 | No drop test (T-2) | Medium | Not Fixed | e99a084 | Requires tester architecture changes |
| 6 | CRC test mirrors impl (T-7) | Medium | Fixed | b630e5a | Independent byte-array construction |
| 7 | Undocumented precondition (D-3) | Low | Fixed | c9d7a43 | Added requirement to YAML |
| 8 | No design rationale (D-4) | Low | Fixed | 6f7aa07 | Added Conversion Algorithm subsection |
| 9 | Identical test structure (T-3) | Low | N/A | 547dd8f | Intentional design, acknowledged |
| 10 | Limited APID diversity (T-4) | Low | Fixed | d739f0a | Added boundary APID tests |
| 11 | No boundary timestamps (T-5) | Low | Fixed | cf6ed1b | Added boundary timestamp tests |

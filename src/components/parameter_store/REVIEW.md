# Parameter Store Component — Code Review

**Reviewed:** 2026-03-01
**Reviewer:** Automated Expert Review
**Verdict:** Generally well-implemented with good test coverage. A few medium-severity issues noted.

---

## 1. Documentation Review

| Aspect | Assessment |
|--------|-----------|
| component.yaml description | Clear and accurate |
| Ada spec comments | Accurate, match model |
| LaTeX document | Well-structured, references build artifacts correctly |
| Requirements | Complete, traceable to implementation |

**Findings:**

- **(Low) Spec comment typo:** In `implementation.ads`, the comment on `Parameters_Memory_Region_T_Recv_Async` ends with `?` instead of `.` — copied from the component.yaml which has the same trailing `?`. This appears in both places and should be a period.
- **(Low) Spec vs. YAML description mismatch:** The `.ads` file opens with "The **Parameters** Component" while the YAML and everything else says "The **Parameter Store** component." Minor but could confuse readers.

---

## 2. Model Review

**component.yaml:**

- Connectors are correctly defined: 2 recv_async (command, parameters_memory_region), 4 send (command_response, parameters_memory_region_release, packet, event), 1 get (sys_time).
- Init parameters are appropriate. The `not_null` constraint on `bytes` is good practice.
- `Dump_Parameters_On_Change` default of `False` is safe.

**commands.yaml / events.yaml / parameters_packets.yaml:**

- Single command (`Dump_Parameter_Store`) with no arguments — clean.
- Events cover all error paths and nominal operations.
- Packet definition is minimal and correct.

**requirements.yaml:**

- 9 requirements covering storage, upload, fetch, dump, and rejection conditions.
- **(Medium) Missing requirement:** No requirement covers the `Validate` operation behavior (returning `Parameter_Error` / unsupported). The implementation handles it, the test covers it, but there is no explicit requirement. This is a traceability gap.

**No issues** with record/array YAML — none present (types are defined elsewhere).

---

## 3. Component Implementation Review

### Init

- Correctly asserts that the parameter table + CRC fits within a max-sized packet. Good defensive check.
- Stores the access value and boolean flag. No heap allocation after init.

### Crc_Parameter_Table

- **(Medium) Relies on pragma Assert for runtime invariant checking.** If assertions are disabled in a release build (`pragma Suppress(All_Checks)` or `-gnatp`), the length check in `Crc_Parameter_Table` would be silently skipped. The length check before the call in `Parameters_Memory_Region_T_Recv_Async` protects the `Set` path, but this function is also called from `Send_Parameters_Packet` where `Self.Bytes.all` is always passed — so in practice the assert is always satisfied. Low real-world risk but worth noting for defense-in-depth.

### Send_Parameters_Packet

- Correctly checks `Is_Packet_T_Send_Connected` before proceeding.
- Computes fresh CRC each dump — good for detecting bit flips in the store.
- The concatenation `Computed_Crc & Self.Bytes.all` creates a temporary on the stack. Given the Init assertion that the table fits in a packet (~4 KB max), this is safe for typical embedded stack sizes, but could be a concern for very constrained targets.
- **(Medium) Serialization status assert:** `pragma Assert (Stat = Success, ...)` — again relies on assertions being enabled. A failed serialization in a no-assert build would silently send an uninitialized/partial packet. Consider an explicit `if` with an error event.

### Parameters_Memory_Region_T_Recv_Async

- Length check is performed first — good.
- CRC validation on `Set` is correct: computes CRC over version+data section, compares to header field.
- `Get` operation copies store to caller's memory region via `Byte_Array_Pointer.Copy_To`.
- `Validate` returns `Parameter_Error` — reasonable for a store that doesn't know parameter semantics.
- All paths release the memory region — **verified, no leak**.
- All enumeration values of `Parameter_Table_Operation_Type` are handled (`Set`, `Get`, `Validate`) — good.

### Dropped Handlers

- `Command_T_Recv_Async_Dropped`: Sends event. Memory region is not involved, so no leak.
- `Parameters_Memory_Region_T_Recv_Async_Dropped`: **Correctly releases the memory region even when dropped** and sets status to `Dropped`. This is critical for preventing memory leaks — well done.

### General

- No heap allocation after init. ✓
- No unbounded loops. ✓
- No tasking/protected objects in the implementation (tasking is in the generated base). ✓
- All `_Send` calls use `_If_Connected` variants where appropriate. ✓

---

## 4. Unit Test Review

**Coverage of requirements and code paths:**

| Test | Paths Covered |
|------|--------------|
| Test_Nominal_Dump_Parameters | Command → dump packet, event, sequence counting |
| Test_Nominal_Table_Upload | Set with valid CRC → store updated, auto-dump, release with Success |
| Test_Nominal_Table_Fetch | Get → memory copied out, release with Success, no auto-dump |
| Test_Table_Upload_Length_Error | Set with wrong length (too small, too large) → event, release with Length_Error |
| Test_Table_Upload_Crc_Error | Set with bad CRC → event, release with Crc_Error, store unchanged |
| Test_Table_Validate_Unimplemented | Validate → event, release with Parameter_Error |
| Test_Table_Fetch_Length_Error | Get with wrong length → event, release with Length_Error |
| Test_No_Dump_On_Change | Dump_Parameters_On_Change=False → no auto-dump on Set |
| Test_Full_Queue | Queue overflow for both command and memory region → events, memory released |
| Test_Invalid_Command | Bad command arg length → Length_Error response, event |

**Findings:**

- **(Medium) Global mutable test state:** `Bytes` is a package-level global `aliased Basic_Types.Byte_Array`. The component's `Init` receives `Bytes'Access`, meaning the test harness and the component share the same mutable array. This is intentional (allows the test to verify internal state), but it means tests are **order-dependent** — `Set_Up_Test` must always reinitialize `Bytes`. Currently it does, so this works, but it is fragile. Any future test that forgets `Set_Up_Test` or runs in parallel would break silently.

- **(Low) No test for Dump_Parameter_Store when packet connector is disconnected.** `Send_Parameters_Packet` has a guard `Is_Packet_T_Send_Connected`. This path is never tested. The command would return `Success` but produce no packet — potentially surprising behavior.

- **(Low) No negative test for Validate with wrong length.** `Test_Table_Validate_Unimplemented` uses correct length. A wrong-length Validate would hit the length mismatch path (same as Set/Get), which is tested elsewhere, so this is minor.

- **(Low) Packet content verification could be stronger.** In `Test_Nominal_Dump_Parameters`, the CRC bytes in the packet are verified against a freshly computed CRC, which is good. However, the test doesn't verify the CRC *field in the header portion* of the stored bytes — it only checks the prepended computed CRC. This is acceptable given the component's design (it always recomputes), but a round-trip integrity check would add confidence.

---

## 5. Summary — Top 5 Findings

| # | Severity | Location | Finding |
|---|----------|----------|---------|
| 1 | **Medium** | `requirements.yaml` | No requirement covers the `Validate` operation (unsupported/Parameter_Error). Traceability gap. |
| 2 | **Medium** | `Send_Parameters_Packet` | `pragma Assert(Stat = Success)` for serialization status — silent failure if assertions disabled. Should use explicit `if`/error event. |
| 3 | **Medium** | `Crc_Parameter_Table` | Length invariant enforced only by `pragma Assert` — safe in current call paths but not defense-in-depth. |
| 4 | **Medium** | Test (global `Bytes`) | Shared mutable global between test harness and component under test creates fragile, order-dependent tests. |
| 5 | **Low** | `.ads` / `.yaml` | Minor comment inconsistencies: trailing `?` instead of `.`, "Parameters Component" vs "Parameter Store". |

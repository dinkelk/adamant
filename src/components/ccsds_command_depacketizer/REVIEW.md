# Code Review: ccsds_command_depacketizer

**Reviewer:** Automated Review  
**Date:** 2026-02-28  
**Component:** `src/components/ccsds_command_depacketizer`

---

## 1. Documentation Review

### 1.1 — PDF and LaTeX Present / **Info** / `doc/`
- `doc/ccsds_command_depacketizer.pdf` — Present ✓
- `doc/ccsds_command_depacketizer.tex` — Present, well-structured, includes all standard sections (Description, Requirements, Design, Connectors, Commands, Events, Data Products, Packets, Unit Tests, Appendix) ✓
- Naming follows Adamant conventions ✓

No documentation issues found.

---

## 2. Model Review

### 2.1 — Validation Order vs. Checksum / **Medium** / `ccsds_command_depacketizer.requirements.yaml`
**Original Code:**
```yaml
requirements:
  - text: The component shall reject CCSDS packets with an invalid length.
  - text: The component shall reject CCSDS packets that do not contain a secondary header.
  - text: The component shall reject CCSDS packets that are not marked as telecommand packets in the secondary header.
  - text: The component shall reject CCSDS packets that contain an invalid 8-bit command checksum in the secondary header.
```
**Issue:** The requirements list length check before secondary header/type/checksum checks, but the implementation checks in order: length → checksum → type → secondary header. The checksum is validated *before* the packet type and secondary header presence. This means the component deserializes the secondary header and computes a checksum over data from packets that may not even have a secondary header (secondary header indicator says "not present"). The deserialized `Secondary_Header` is meaningless in that case, and the checksum computation proceeds over arbitrary data. While not a crash risk (the data buffer exists), the validation order is semantically wrong — the secondary header presence should be verified before accessing secondary header fields.

**Proposed Fix:** Reorder validation in the implementation: (1) length, (2) packet type, (3) secondary header presence, (4) *then* deserialize secondary header and validate checksum.

### 2.2 — Component YAML Connectors Well-Formed / **Info** / `ccsds_command_depacketizer.component.yaml`
All 8 connectors are present with correct kinds (`recv_sync`, `send`, `get`). The `execution: passive` is appropriate. The description accurately documents the unprotected counter caveat. ✓

### 2.3 — Events YAML Complete / **Info** / `ccsds_command_depacketizer.events.yaml`
All 7 events are defined with appropriate parameter types. ✓

### 2.4 — Requirement for Function Code Interpretation Missing Specifics / **Low** / `ccsds_command_depacketizer.requirements.yaml`
**Original Code:**
```yaml
  - text: The component shall calculate the actual command packet length by subtracting the number stored in the secondary header function code from the CCSDS header length.
```
**Issue:** The requirement says "subtracting ... from the CCSDS header length" which is ambiguous — it should say "from the CCSDS data field length" or "from the packet data length". The implementation subtracts `Function_Code` (as pad byte count) from `Data_Length`, which is the data field length, not the "header length."

**Proposed Fix:** Clarify requirement text: "...by subtracting the function code value (pad byte count) from the CCSDS packet data field length."

---

## 3. Component Implementation Review

### 3.1 — Secondary Header Deserialized Before Validation / **High** / `component-ccsds_command_depacketizer-implementation.adb`, lines in `Ccsds_Space_Packet_T_Recv_Sync`
**Original Code:**
```ada
Data_Length : constant Natural := Natural (Arg.Header.Packet_Length) + 1;
...
Secondary_Header : constant Ccsds_Command_Secondary_Header.T :=
   Ccsds_Command_Secondary_Header.Serialization.From_Byte_Array (Arg.Data (Next_Index .. Next_Index + Ccsds_Command_Secondary_Header_Length - 1));
begin
   if Data_Length > Arg.Data'Length then
      -- too large
   else
      -- checksum computed using Data_Length ...
```
**Issue:** The `Secondary_Header` is deserialized in the declarative region *before* the `Data_Length > Arg.Data'Length` check. If `Data_Length` is very small (e.g., 0 or 1 byte), the deserialization still reads `Ccsds_Command_Secondary_Header_Length` bytes from `Arg.Data`. This is safe only because `Arg.Data` is a fixed-size buffer (not length-bounded to `Data_Length`), so no out-of-bounds access occurs. However, the deserialized secondary header contains garbage for short packets, and this garbage is then used in the checksum error event if the checksum check fails on a truncated packet. This produces misleading diagnostic data in error events.

**Proposed Fix:** Move secondary header deserialization inside the `else` branch after confirming `Data_Length >= Ccsds_Command_Secondary_Header_Length`. This also enables the validation reordering from Finding 2.1.

### 3.2 — Race Condition on Counters Documented but Unmitigated / **Low** / `component-ccsds_command_depacketizer-implementation.ads`
**Original Code:**
```ada
-- The component assumes that only a single task is attached to its CCSDS Space Packet invokee connector
```
**Issue:** The counters use `Protected_Variables.Generic_Protected_Counter`, so they *are* individually task-safe. However, the increment-then-read sequence (`Increment_Count` followed by `Get_Count`) in `Drop_Packet` and `Ccsds_Space_Packet_T_Recv_Sync` is not atomic — another task could increment between these two calls. The comment says counters are "unprotected" but they use a protected type. The comment is inaccurate.

**Proposed Fix:** Update the comment to accurately reflect that counters use protected objects but the increment+read sequence is not atomic. If strict accuracy is needed, use an `Increment_And_Return` operation.

### 3.3 — `The_Command` Not Fully Initialized / **Medium** / `component-ccsds_command_depacketizer-implementation.adb`, `Ccsds_Space_Packet_T_Recv_Sync`
**Original Code:**
```ada
The_Command : Command.T;
```
**Issue:** `The_Command` is declared with default initialization (presumably zero-filled by the record defaults). The `Source_Id` field in `The_Command.Header` is never explicitly set — it retains its default value (0). This means all commands produced by this depacketizer have `Source_Id = 0`. This is likely intentional (ground commands have no meaningful source ID), but it is undocumented and could be confusing.

**Proposed Fix:** Add a comment: `-- Source_Id defaults to 0 for ground-originated commands.`

### 3.4 — Deeply Nested if-else Structure / **Low** / `component-ccsds_command_depacketizer-implementation.adb`, `Ccsds_Space_Packet_T_Recv_Sync`
**Issue:** The validation logic is 6 levels deep in nested if-else blocks. While functionally correct, this reduces readability. An early-return pattern using a helper function would improve clarity.

**Proposed Fix:** Consider refactoring into a helper function that uses early returns for each validation failure, reducing nesting depth.

---

## 4. Unit Test Review

### 4.1 — No Set_Up Call Before Tests / **Medium** / `test/ccsds_command_depacketizer_tests-implementation.adb`
**Issue:** The `Set_Up_Test` fixture calls `Init_Base` and `Connect` but never calls `Component_Instance.Set_Up`. The `Set_Up` procedure initializes counters and sends initial data products. In `Test_Reset_Counts`, the test calls `Test_Nominal_Depacketization` to seed data, but the initial `Set_Up` is never invoked. This means the counters start at their default (0) from the protected counter's initialization rather than being explicitly reset via `Set_Up`. Tests pass because the default happens to be 0, but they don't exercise or validate the `Set_Up` path independently.

**Proposed Fix:** Add a call to `Self.Tester.Component_Instance.Set_Up` in `Set_Up_Test` and verify the initial data products are sent (count = 0). Adjust subsequent test expectations for the additional data product sends.

### 4.2 — Test_Pad_Bytes Does Not Verify Data Products / **Low** / `test/ccsds_command_depacketizer_tests-implementation.adb`, `Test_Pad_Bytes`
**Issue:** The `Test_Pad_Bytes` test verifies commands are correctly produced with various function codes but does not check that the accepted packet count data products are correctly incremented.

**Proposed Fix:** Add assertions for `Accepted_Packet_Count_History` in `Test_Pad_Bytes`.

### 4.3 — No Boundary Test for Counter Overflow / **Medium** / `test/ccsds_command_depacketizer_tests-implementation.adb`
**Issue:** The accepted and rejected counters are `Unsigned_16`, which can overflow at 65535. There is no test verifying behavior at or near the counter maximum. In safety-critical systems, counter wrap-around should be explicitly tested and documented.

**Proposed Fix:** Add a test (or a note in requirements) defining expected behavior at `Unsigned_16'Last` and verifying it.

### 4.4 — Good Coverage of Error Paths / **Info**
All error paths are tested: invalid checksum, invalid type, too small, too large (both data-too-large and header-length-too-large variants), missing secondary header, pad bytes, reset command, and invalid command. Each test verifies events, error packets, data products, and command outputs. ✓

---

## 5. Summary — Top 5 Highest-Severity Findings

| # | Severity | Finding | Location |
|---|----------|---------|----------|
| 1 | **High** | Secondary header deserialized before packet length validation; garbage data used in error diagnostics for short/malformed packets | `implementation.adb`, declarative region of `Ccsds_Space_Packet_T_Recv_Sync` |
| 2 | **Medium** | Validation order checks checksum before packet type and secondary header presence — processes secondary header fields from packets that claim no secondary header exists | `implementation.adb`, `Ccsds_Space_Packet_T_Recv_Sync` |
| 3 | **Medium** | `Set_Up` never called in unit test fixture; initial data product emission path untested | `test/ccsds_command_depacketizer_tests-implementation.adb`, `Set_Up_Test` |
| 4 | **Medium** | No test for `Unsigned_16` counter overflow/wrap-around behavior | `test/ccsds_command_depacketizer_tests-implementation.adb` |
| 5 | **Medium** | `The_Command.Header.Source_Id` silently defaults to 0 with no documentation | `implementation.adb`, `Ccsds_Space_Packet_T_Recv_Sync` |

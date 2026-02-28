# Fault Correction Component — Code Review

**Reviewer:** AI Code Review Agent
**Date:** 2026-02-28
**Branch:** `review/components-fault-correction`

---

## 1. Documentation Review

### 1.1 Component Description & Requirements

The YAML description and requirements are clear and consistent with the implementation. The component receives faults, looks up a pre-configured command response, and sends it. Requirements cover the core behaviors (response sending, table configuration, enable/disable commands, telemetry reporting).

### 1.2 LaTeX Document

The LaTeX document (`doc/fault_correction.tex`) is a standard template pulling from generated build artifacts. It includes sections for interrupts, parameters, packets, and faults — none of which this component actually has. While these resolve to "None" in the generated output, the document includes them unconditionally.

**Issue DOC-1: Unnecessary sections in LaTeX document**
- **Location:** `doc/fault_correction.tex`, lines for Interrupts, Parameters, Packets, Faults subsections
- **Original:**
  ```latex
  \subsection{Interrupts}
  \input{build/tex/fault_correction_interrupts.tex}
  ...
  \subsection{Parameters}
  \input{build/tex/fault_correction_parameters.tex}
  ...
  \subsection{Packets}
  \input{build/tex/fault_correction_packets.tex}
  ...
  \subsection{Faults}
  \input{build/tex/fault_correction_faults.tex}
  ```
- **Explanation:** The component has no interrupts, parameters, packets, or faults of its own. Including these sections adds empty/boilerplate content that clutters the design document.
- **Corrected:** Remove the four subsections that do not apply, or guard with conditional inclusion.
- **Severity:** Low

### 1.3 Event Descriptions — Missing Punctuation Consistency

**Issue DOC-2: Inconsistent punctuation in event descriptions**
- **Location:** `fault_correction.events.yaml`
- **Original:**
  ```yaml
  - name: Fault_Response_Disabled
    description: A fault response has been disabled
  ```
- **Explanation:** All other event descriptions end with a period; this one does not.
- **Corrected:**
  ```yaml
    description: A fault response has been disabled.
  ```
- **Severity:** Low

### 1.4 Command Description Accuracy

**Issue DOC-3: Misleading Enable_Fault_Response command description**
- **Location:** `fault_correction.fault_correction_commands.yaml`, Enable_Fault_Response
- **Original:**
  ```yaml
  description: Enable a fault response for the provided ID. This will only succeed if another response with the same Fault ID is not already enabled.
  ```
- **Explanation:** The second sentence is incorrect. Looking at the implementation, `Enable_Fault_Response` returns `Success` regardless of current state — if the entry is already Nominal, Fault_Detected, or Fault_Latched it simply does nothing and returns Success. It does **not** fail when the response is "already enabled." The description appears to describe mutual-exclusion logic that does not exist.
- **Corrected:**
  ```yaml
  description: Enable a fault response for the provided ID. If the response is currently disabled, it transitions to nominal. If already in any other state, no change is made.
  ```
- **Severity:** Medium

---

## 2. Model Review

### 2.1 Component Model (`fault_correction.component.yaml`)

The component model is well-structured. Seven connectors are defined matching the implementation. The init parameter is appropriate.

No issues found.

### 2.2 Events Model (`fault_correction.events.yaml`)

Eleven events are defined covering all operational paths: fault receipt, response actions, commands, drops, and errors. Event parameter types are appropriate.

No issues beyond DOC-2 above.

### 2.3 Commands Model

Five commands are defined. The command argument types (`Packed_Fault_Id.T`) are placeholders that get replaced at assembly time via the custom `fault_correction_commands.py` model — a clever pattern.

No issues beyond DOC-3 above.

### 2.4 Data Products Model

Four data products are defined. `Fault_Response_Statuses` uses a placeholder `Packed_U32.T` that is replaced at assembly time with an auto-generated packed status record via `fault_correction_data_products.py`. This is well-documented in the YAML comment.

No issues found.

### 2.5 Requirements Model

Four requirements are listed. They are concise and traceable to the implementation.

**Issue MODEL-1: No requirement for latching behavior**
- **Location:** `fault_correction.requirements.yaml`
- **Original:** Four requirements covering response sending, table configuration, enable/disable, and telemetry.
- **Explanation:** The component implements significant latching behavior (fault responses that fire once and latch until cleared by command). This is a key safety-related behavior with no corresponding requirement. A requirement should exist for latching/clearing semantics.
- **Corrected:** Add requirement:
  ```yaml
  - text: The component shall support latching fault responses that send their command response only on initial fault detection and remain latched until explicitly cleared by command.
  ```
- **Severity:** Medium

### 2.6 Generator Models (`gen/`)

The `fault_responses.py` model, `fault_responses.py` generator, and the custom command/data-product models are well-implemented. The `fault_responses.py` model correctly validates against the schema, resolves fault/command IDs from the assembly, and checks that the status data product fits within buffer limits.

**Issue MODEL-2: Integer division truncation in statuses_size calculation**
- **Location:** `gen/models/fault_responses.py`, in `load()`
- **Original:**
  ```python
  self.statuses_size = (
      len(self.responses) * 2 + 7
  ) / 8
  ```
- **Explanation:** Python 3 `/` produces a float, so the comparison `self.statuses_size > _get_data_product_buffer_size()` compares a float against an int. This works but is semantically wrong for a byte-count comparison. Should use `//` for integer division to match the intent (ceiling division of bit-count to bytes).
- **Corrected:**
  ```python
  self.statuses_size = (
      len(self.responses) * 2 + 7
  ) // 8
  ```
- **Severity:** Low

---

## 3. Component Implementation Review

### 3.1 Initialization (`Init`)

The `Init` procedure correctly:
- Asserts non-empty configuration list
- Asserts statuses fit in a data product buffer
- Allocates binary tree and table on the heap
- Checks for duplicate fault IDs
- Supports disabled startup state

No issues found.

### 3.2 `Final` Procedure

Uses `Safe_Deallocator.Deallocate_If_Testing` pattern and destroys the binary tree. Correct.

### 3.3 `Get_Fault_Response_Table_Index`

**Issue IMPL-1: Postcondition is incorrect when entry is not found**
- **Location:** `component-fault_correction-implementation.ads`, `Get_Fault_Response_Table_Index` postcondition
- **Original:**
  ```ada
  Post => (Index >= Self.Fault_Response_Table.all'First and then Index <= Self.Fault_Response_Table.all'Last)
  ```
- **Explanation:** This postcondition claims Index is always in range, but the function can return `False` with `Index := Fault_Response_Table_Index'First`. When `Fault_Response_Table_Index'First` equals `Self.Fault_Response_Table.all'First` (which it always does given current allocation), this happens to hold. However, the postcondition is semantically misleading — it promises a valid index even on failure. The postcondition should be conditional on the return value, e.g., `(if Get_Fault_Response_Table_Index'Result then Index in range else True)`. As-is, if the allocation strategy ever changes, this could become a latent defect.
- **Corrected:**
  ```ada
  Post => (if Get_Fault_Response_Table_Index'Result then
              (Index >= Self.Fault_Response_Table.all'First and then Index <= Self.Fault_Response_Table.all'Last)
           else True)
  ```
- **Severity:** Medium

### 3.4 `Send_Fault_Response_Statuses_Data_Product`

**Issue IMPL-2: Off-by-one in `Buffer_Length` calculation**
- **Location:** `component-fault_correction-implementation.adb`, `Send_Fault_Response_Statuses_Data_Product`
- **Original:**
  ```ada
  To_Send.Header.Buffer_Length := Product_Buffer_Index - Data_Product_Types.Data_Product_Buffer_Index_Type'First;
  ```
- **Explanation:** `Product_Buffer_Index` is incremented *after* writing a byte to the buffer. At the end of the loop, if the last write was on a `Record_Slot = 3` boundary, `Product_Buffer_Index` has been incremented past the last written byte, so the subtraction gives the correct count. However, if the loop ends with `Index = 'Last` and `Record_Slot /= 3`, the byte is written at `Product_Buffer_Index` and then `Product_Buffer_Index` is incremented (because the `if` triggers on `Index = 'Last`). So the length is correct in both cases. After careful analysis, this is correct but the logic is fragile and non-obvious. The code would benefit from a comment explaining why this works in both exit paths.
- **Severity:** _Not an issue — withdrawn after analysis._ The logic is correct.

**Issue IMPL-3: Fault_Counter wraps silently at Unsigned_16'Last**
- **Location:** `component-fault_correction-implementation.adb`, `Fault_T_Recv_Async`
- **Original:**
  ```ada
  Self.Fault_Counter := @ + 1;
  ```
- **Explanation:** `Fault_Counter` is `Interfaces.Unsigned_16`, so it wraps from 65535 to 0 with modular arithmetic. In a long-duration mission this counter could wrap without any indication, making telemetry misleading. An event should be emitted on wrap, or the counter should saturate at `Unsigned_16'Last`.
- **Corrected (saturating):**
  ```ada
  if Self.Fault_Counter < Interfaces.Unsigned_16'Last then
     Self.Fault_Counter := @ + 1;
  end if;
  ```
  Or emit a wrap event.
- **Severity:** Medium

### 3.5 `Fault_T_Recv_Async` — Param_Buffer Copy

**Issue IMPL-4: Potential out-of-bounds if Param_Buffer_Length exceeds Fault_Static parameter buffer size**
- **Location:** `component-fault_correction-implementation.adb`, `Fault_T_Recv_Async`
- **Original:**
  ```ada
  Param_Buffer (Param_Buffer'First .. Param_Buffer'First + Arg.Header.Param_Buffer_Length - 1) :=
     Arg.Param_Buffer (Arg.Param_Buffer'First .. Arg.Param_Buffer'First + Arg.Header.Param_Buffer_Length - 1);
  ```
- **Explanation:** `Param_Buffer` is `Fault_Types.Parameter_Buffer_Type` (the static/fixed-size version) while `Arg.Param_Buffer` is the dynamic fault buffer. If `Arg.Header.Param_Buffer_Length` exceeds `Param_Buffer'Length` (the static buffer is smaller), this will raise `Constraint_Error` at runtime. The code should clamp the copy length to `Param_Buffer'Length` or validate before copying. This is a safety concern — a malformed fault from any source could crash the fault correction component.
- **Corrected:**
  ```ada
  declare
     Copy_Len : constant Natural := Natural'Min (
        Natural (Arg.Header.Param_Buffer_Length),
        Param_Buffer'Length
     );
  begin
     Param_Buffer (Param_Buffer'First .. Param_Buffer'First + Copy_Len - 1) :=
        Arg.Param_Buffer (Arg.Param_Buffer'First .. Arg.Param_Buffer'First + Copy_Len - 1);
  end;
  ```
- **Severity:** High

### 3.6 Command Handlers

The command handlers (`Enable_Fault_Response`, `Disable_Fault_Response`, `Clear_Fault_Response`, `Clear_All_Fault_Responses`, `Reset_Data_Products`) are well-structured. State transitions are handled with exhaustive `case` statements. `Clear_All_Fault_Responses` correctly preserves the Disabled state.

No issues found.

### 3.7 Dropped Message Handlers

`Command_T_Send_Dropped`, `Data_Product_T_Send_Dropped`, and `Event_T_Send_Dropped` are all `is null`. For a safety-critical component, silently dropping outgoing commands is concerning.

**Issue IMPL-5: `Command_T_Send_Dropped` is null — silent loss of fault correction commands**
- **Location:** `component-fault_correction-implementation.ads`
- **Original:**
  ```ada
  overriding procedure Command_T_Send_Dropped (Self : in out Instance; Arg : in Command.T) is null;
  ```
- **Explanation:** If the outgoing command queue is full, the fault correction response command is silently lost with no event or telemetry. This is the component's primary safety function — sending corrective commands in response to faults. Losing this silently defeats the component's purpose. At minimum, an event should be emitted.
- **Corrected:** Implement the procedure body to emit a warning/critical event indicating that a fault correction command was dropped.
- **Severity:** Critical

---

## 4. Unit Test Review

### 4.1 Test Coverage

The test suite covers 8 test cases:
1. **Initialization** — empty list, duplicates, too-many entries, Set_Up data products ✓
2. **Fault Handling** — non-latching (first + repeat), latching (first + repeat), disabled ✓
3. **Enable/Disable** — enable disabled entry, send fault, disable, send fault, enable already-enabled ✓
4. **Clear** — clear latched, clear non-latching, clear disabled (no-op), clear nominal (no-op), clear all ✓
5. **Reset Data Products** — resets counters ✓
6. **Unrecognized Fault ID** — all three commands + fault receive ✓
7. **Full Queue** — command drop, fault drop ✓
8. **Invalid Command** — malformed argument length ✓

### 4.2 Test Gaps

**Issue TEST-1: No test for Fault_Counter wraparound**
- **Location:** `test/fault_correction_tests-implementation.adb`
- **Explanation:** The `Fault_Counter` is `Unsigned_16`. No test verifies behavior when the counter reaches `Unsigned_16'Last` and wraps or saturates. Given IMPL-3, this should be tested.
- **Corrected:** Add a test that sets the counter near `Unsigned_16'Last` (e.g., by sending 65535 faults or by using a helper to set the internal state) and verifies correct behavior on overflow.
- **Severity:** Medium

**Issue TEST-2: No test for Param_Buffer_Length exceeding static buffer size**
- **Location:** `test/fault_correction_tests-implementation.adb`
- **Explanation:** Related to IMPL-4, no test sends a fault with `Param_Buffer_Length` larger than the `Fault_Static.Parameter_Buffer_Type` size. This would expose the potential `Constraint_Error`.
- **Corrected:** Add a test sending a fault with a `Param_Buffer_Length` that exceeds the static parameter buffer, and verify graceful handling.
- **Severity:** High

**Issue TEST-3: No test for `Command_T_Send_Dropped` on outgoing command connector**
- **Location:** `test/fault_correction_tests-implementation.adb`
- **Explanation:** Related to IMPL-5, the test for full queue only tests incoming queue drops. There is no test verifying what happens when the *outgoing* `Command_T_Send` connector drops a fault correction command. Since the handler is `is null`, there's nothing to test — but once IMPL-5 is fixed, a test should verify the event is emitted.
- **Severity:** Medium

**Issue TEST-4: `Test_Initialization` calls `Final` but not between `Init_Duplicate` and `Init_Too_Many`**
- **Location:** `test/fault_correction_tests-implementation.adb`, `Test_Initialization`
- **Original:**
  ```ada
  Init_None;
  T.Component_Instance.Final;
  Init_Duplicate;
  T.Component_Instance.Final;
  Init_Too_Many;
  T.Component_Instance.Final;
  ```
- **Explanation:** Each `Init_*` procedure catches the exception, so `Init` never completes successfully, meaning `Final` is called on a partially-initialized or unmodified instance. The `Final` calls are cleaning up the *previous successful* Init from `Set_Up_Test`. After the first `Final`, subsequent `Init_*` calls operate on a finalized instance. This is benign only because the exception fires before any heap allocation changes stick. The pattern is fragile — if a future Init variant partially succeeds before asserting, memory could leak. A comment would help, or restructure to re-init between tests.
- **Severity:** Low

---

## 5. Summary — Top 5 Issues

| # | ID | Severity | Location | Description |
|---|-----|----------|----------|-------------|
| 1 | IMPL-5 | **Critical** | `.ads`, `Command_T_Send_Dropped` | Outgoing fault correction commands silently dropped with `is null` handler — defeats component's safety purpose |
| 2 | IMPL-4 | **High** | `.adb`, `Fault_T_Recv_Async` | Param buffer copy can raise `Constraint_Error` if incoming fault's `Param_Buffer_Length` exceeds static buffer size |
| 3 | TEST-2 | **High** | Test suite | No test for oversized `Param_Buffer_Length` — IMPL-4 is undetected |
| 4 | IMPL-3 | **Medium** | `.adb`, `Fault_T_Recv_Async` | `Fault_Counter` (`Unsigned_16`) wraps silently at 65535 with no event or saturation |
| 5 | DOC-3 | **Medium** | Commands YAML | `Enable_Fault_Response` description claims failure on already-enabled; implementation always returns Success |

# CPU Monitor Component — Code Review

**Reviewer:** Automated Expert Review  
**Date:** 2026-02-28  
**Branch:** `review/components-cpu-monitor`

---

## 1. Documentation Review

### DOC-1: Description says "1 bytes" (grammatical error)

- **Location:** `cpu_monitor.component.yaml`, line 3 of `description`
- **Original:** `The packet produced contains 3 CPU execution numbers (1 bytes in size ranging from 0 - 100)`
- **Explanation:** Minor grammatical error — "1 bytes" should be "1 byte".
- **Corrected:** `The packet produced contains 3 CPU execution numbers (1 byte in size ranging from 0 - 100)`
- **Severity:** Low

### DOC-2: Requirements are vague and lack verifiable acceptance criteria

- **Location:** `cpu_monitor.requirements.yaml`, all three requirements
- **Original:**
  ```yaml
  - text: The component shall produce data reporting the CPU usage of every active component in an assembly.
  - text: The component shall produce data reporting the CPU usage of every interrupt handler in an assembly.
  - text: The component shall produce CPU usage data at a periodic rate that is configurable by command.
  ```
- **Explanation:** Requirements lack specificity: "produce data" does not specify the format (packet), the measurement basis (percentage over a configurable time window), or acceptable accuracy. For safety-critical flight code, requirements should be verifiable. For example, requirement 3 does not mention that a period of zero disables output, which is an important behavioral detail.
- **Corrected:** Add precision, e.g.:
  ```yaml
  - text: The component shall produce a telemetry packet containing CPU usage as a percentage (0–100) for every active task in an assembly, measured over each of three configurable time periods.
  - text: The component shall produce CPU usage as a percentage (0–100) for every interrupt handler in an assembly within the same telemetry packet.
  - text: The component shall send the CPU usage packet at a periodic rate configurable by command. A period of zero shall disable packet output.
  ```
- **Severity:** Medium

### DOC-3: LaTeX document missing Data Products section

- **Location:** `doc/cpu_monitor.tex`
- **Original:** The document has sections for Commands, Events, and Packets but no Data Products section.
- **Explanation:** The component defines the `Packet_Period` data product, but the design document never includes it. This is an omission that could confuse operators or reviewers.
- **Corrected:** Add after the Packets subsection:
  ```latex
  \subsection{Data Products}
  \input{build/tex/cpu_monitor_data_products.tex}
  ```
- **Severity:** Medium

---

## 2. Model Review

### MOD-1: `Num_Measurement_Periods` range type allows index 0 but Execution_Periods default has 3 elements starting at index 0

- **Location:** `cpu_monitor.component.yaml`, preamble
- **Original:**
  ```yaml
  type Num_Measurement_Periods is range 0 .. 2;
  type Execution_Periods_Type is array (Num_Measurement_Periods) of Positive;
  ```
- **Explanation:** This is technically correct (indices 0, 1, 2 = 3 elements), but the range type name `Num_Measurement_Periods` is misleading — it reads as "the number of measurement periods" (which would be 3), but it is actually the *index* range. A name like `Measurement_Period_Index` would be clearer and avoid confusion in a safety-critical context.
- **Corrected:** Rename to `Measurement_Period_Index` or `Measurement_Period_Range`.
- **Severity:** Low

### MOD-2: No validation constraint on `Execution_Periods` values

- **Location:** `cpu_monitor.component.yaml`, init parameter `Execution_Periods`
- **Original:** `type: Execution_Periods_Type` (array of `Positive`)
- **Explanation:** The `Positive` type prevents zero, but there is no upper-bound constraint. Extremely large period values could cause `Max_Count` to overflow `Natural` during the multiplication in `Init` (e.g., three values of 50000 would yield 125,000,000,000,000 which overflows `Natural`). This would raise `Constraint_Error` at initialization — a runtime crash.
- **Corrected:** Either (a) add a constrained subtype for the period values (e.g., `range 1 .. 1000`), or (b) add overflow checking in `Init` with a meaningful error/event.
- **Severity:** High

---

## 3. Component Implementation Review

### IMPL-1: `Max_Count` computation can overflow `Natural`

- **Location:** `component-cpu_monitor-implementation.adb`, `Init` procedure, lines computing `Max_Count`
- **Original:**
  ```ada
  Self.Max_Count := 1;
  for Index in Self.Execution_Periods'Range loop
     Period := Self.Execution_Periods (Index);
     Self.Max_Count := @ * Period;
  end loop;
  ```
- **Explanation:** If execution periods are large (e.g., `[1000, 1000, 1000]`), the product is 1,000,000,000 which fits in `Natural`, but `[50000, 50000, 2]` = 5,000,000,000 which overflows. There is no overflow check or saturation. In a flight context, an unexpected `Constraint_Error` here is a component crash.
- **Corrected:** Add explicit overflow checking:
  ```ada
  Self.Max_Count := 1;
  for Index in Self.Execution_Periods'Range loop
     Period := Self.Execution_Periods (Index);
     if Period > 0 and then Self.Max_Count > Natural'Last / Period then
        -- Handle overflow: raise a meaningful error or clamp
        pragma Assert (False, "Execution_Periods product overflows Natural");
     end if;
     Self.Max_Count := @ * Period;
  end loop;
  ```
- **Severity:** High

### IMPL-2: Heap allocations in `Init` are never freed

- **Location:** `component-cpu_monitor-implementation.adb`, `Init` procedure
- **Original:**
  ```ada
  Self.Task_Cpu_Time_List := new Last_Cpu_Time_Array (Self.Tasks'Range);
  Self.Task_Up_Time_List := new Last_Time_Array (Self.Tasks'Range);
  Self.Interrupt_Cpu_Time_List := new Last_Cpu_Time_Array (Self.Interrupts'Range);
  Self.Interrupt_Up_Time_List := new Last_Time_Array (Self.Interrupts'Range);
  ```
- **Explanation:** Four heap allocations are made but there is no corresponding `Final` or destructor procedure to deallocate them. If `Init` were ever called twice (e.g., during re-initialization), this would leak memory. In a long-running flight system, this is a concern. The tester calls `Final_Base` but the component itself has no `Final`.
- **Corrected:** Add a `Final` procedure (or guard against double-init) that deallocates the arrays using `Ada.Unchecked_Deallocation`.
- **Severity:** Medium

### IMPL-3: `Cpu_Percentage` catches all exceptions with `when others`

- **Location:** `component-cpu_monitor-implementation.adb`, function `Cpu_Percentage`
- **Original:**
  ```ada
  exception
     when others =>
        return 0;
  end Cpu_Percentage;
  ```
- **Explanation:** A blanket `when others` handler silently swallows *all* exceptions including `Storage_Error`, `Program_Error`, and any unexpected fault. In safety-critical code this masks bugs. It should catch only the expected `Constraint_Error` (from divide-by-zero or time arithmetic anomalies) and let other exceptions propagate.
- **Corrected:**
  ```ada
  exception
     when Constraint_Error =>
        return 0;
  end Cpu_Percentage;
  ```
- **Severity:** High

### IMPL-4: Packet buffer index calculation assumes 0-based array ranges

- **Location:** `component-cpu_monitor-implementation.adb`, `Tick_T_Recv_Sync`, buffer index expressions
- **Original (task):**
  ```ada
  Self.Packet_To_Send.Buffer (
     Self.Execution_Periods'Length * (Task_Num - Self.Task_Cpu_Time_List'First) + Natural (Idx - Self.Execution_Periods'First)
  ) := Cpu_Percentage (...);
  ```
  **Original (interrupt):**
  ```ada
  Self.Packet_To_Send.Buffer (
     Self.Execution_Periods'Length * Self.Task_Cpu_Time_List'Length + Self.Execution_Periods'Length * (Interrupt_Num - Self.Interrupt_Cpu_Time_List'First) + Natural (Idx - Self.Execution_Periods'First)
  ) := Cpu_Percentage (...);
  ```
- **Explanation:** The indexing assumes `Packet_To_Send.Buffer` is 0-based. If `Buffer` is 0-based (which it appears to be from `Packet_Types`), this is correct. However, there is no assertion or comment confirming this assumption. If the buffer's `'First` were ever non-zero, all indices would be silently wrong, corrupting the packet. A `pragma Assert (Self.Packet_To_Send.Buffer'First = 0)` would make the assumption explicit and catch violations.
- **Corrected:** Add at the top of `Tick_T_Recv_Sync`:
  ```ada
  pragma Assert (Self.Packet_To_Send.Buffer'First = 0);
  ```
- **Severity:** Low

### IMPL-5: Comment says "Ignore zero entries" but `Positive` type prevents zero

- **Location:** `component-cpu_monitor-implementation.adb`, `Init`, Max_Count loop
- **Original:**
  ```ada
  -- Ignore zero entries, since this special value means that the connector index
  -- is disabled, thus it should not be included in the calculation.
  Period := Self.Execution_Periods (Index);
  Self.Max_Count := @ * Period;
  ```
- **Explanation:** The comment says to ignore zero entries, but the code does not actually check for zero — and cannot receive zero because `Execution_Periods_Type` is an array of `Positive`. The comment is dead/misleading and suggests a previously removed feature. It should be removed or corrected to avoid confusion.
- **Corrected:** Remove the misleading comment, or replace with:
  ```ada
  -- Period is Positive, so no zero-check needed.
  ```
- **Severity:** Medium

### IMPL-6: `Packet_To_Send.Header.Sequence_Count` wraps without explicit modular behavior documentation

- **Location:** `component-cpu_monitor-implementation.adb`, `Tick_T_Recv_Sync`
- **Original:**
  ```ada
  Self.Packet_To_Send.Header.Sequence_Count := @ + 1;
  ```
- **Explanation:** `Sequence_Count` is a modular type (`Sequence_Count_Mod_Type`) so it wraps naturally. This is correct behavior, but a brief comment noting the intentional wrap-around would improve clarity for reviewers of safety-critical code.
- **Severity:** Low

---

## 4. Unit Test Review

### TEST-1: No test for CPU usage values or packet buffer contents

- **Location:** `cpu_monitor_tests-implementation.adb`, `Test_Packet_Period`
- **Original:**
  ```ada
  -- OK we cannot actually check the contents of a packet, but let's at least
  -- check the headers of all the packets.
  ```
- **Explanation:** The test suite explicitly acknowledges it cannot verify packet content. While true CPU percentages are timing-dependent, the test could verify structural properties: (a) buffer bytes are within 0–100 range, (b) bytes for the null-task-id entry (Task_Info_1) are always 0, (c) the buffer length matches expectations. This would catch off-by-one indexing errors (IMPL-4) at the unit test level.
- **Corrected:** Add assertions on packet buffer contents, e.g.:
  ```ada
  -- Verify null-task entries are zero:
  for I in 0 .. 2 loop
     Natural_Assert.Eq (Natural (T.Cpu_Usage_Packet_History.Get (1).Buffer (I)), 0);
  end loop;
  -- Verify all values are in range 0..100:
  for I in 0 .. 11 loop
     Boolean_Assert.Eq (Natural (T.Cpu_Usage_Packet_History.Get (1).Buffer (I)) <= 100, True);
  end loop;
  ```
- **Severity:** Medium

### TEST-2: No test for `Set_Up` procedure behavior

- **Location:** `cpu_monitor_tests-implementation.adb`
- **Explanation:** `Set_Up` is called in `Test_Packet_Period` and its data product emission is checked, but there is no dedicated test verifying `Set_Up` behavior in isolation — for instance, verifying the data product value matches the init parameter when a non-default `Packet_Period` is used. This is minor since it's partially covered.
- **Severity:** Low

### TEST-3: No test for `Execution_Periods` boundary behavior

- **Location:** `cpu_monitor_tests-implementation.adb`
- **Explanation:** There is no test exercising the tick counting and rollover logic (the `Count` / `Max_Count` modular behavior). With `Execution_Periods => [1, 5, 10]`, the `Max_Count` is 50. A test sending 50+ ticks and verifying measurement resets would improve coverage of the core CPU monitoring logic.
- **Severity:** Medium

### TEST-4: No test for dropped-message handler paths

- **Location:** `component-cpu_monitor-implementation.ads`, null `_Dropped` handlers
- **Explanation:** The four `_Dropped` handlers are all `is null`. While these are acceptable as-is (they intentionally do nothing), there are no tests that exercise the "if_connected" paths when connectors are *not* connected. This is low risk since the Adamant framework handles this, but noting for completeness.
- **Severity:** Low

---

## 5. Summary — Top 5 Issues

| # | ID | Severity | Location | Summary |
|---|------|----------|----------|---------|
| 1 | IMPL-3 | **High** | `implementation.adb`, `Cpu_Percentage` | Blanket `when others` exception handler masks all exceptions including `Storage_Error` and `Program_Error`. Should catch only `Constraint_Error`. |
| 2 | IMPL-1 / MOD-2 | **High** | `implementation.adb`, `Init` | `Max_Count` multiplication can overflow `Natural` with large `Execution_Periods` values — no overflow guard exists. |
| 3 | IMPL-5 | **Medium** | `implementation.adb`, `Init` | Dead comment claims zero-entry handling that doesn't exist (and can't occur due to `Positive` type). Misleading for reviewers. |
| 4 | TEST-1 | **Medium** | `cpu_monitor_tests-implementation.adb` | No validation of packet buffer contents — null-task entries should be zero, all values should be 0–100. Misses off-by-one bugs. |
| 5 | DOC-3 | **Medium** | `doc/cpu_monitor.tex` | Data Products section missing from the design document despite the component defining the `Packet_Period` data product. |

## Resolution Notes

| # | Issue | Severity | Status | Commit | Notes |
|---|-------|----------|--------|--------|-------|
| 1 | Blanket when others | High | Fixed | d273657 | Narrowed to Constraint_Error |
| 2 | Max_Count overflow | High | Fixed | 19e83bd | Added overflow guard |
| 3 | Dead comment re zero check | Medium | Fixed | 19e83bd | Co-fixed with overflow guard |
| 4 | Double-init leak | Medium | Fixed | f3f2378 | Added deallocation + guard |
| 5 | Requirements not verifiable | Medium | Fixed | e6dcc52 | Added criteria |
| 6 | Missing Data Products in doc | Medium | Fixed | 2b1dc14 | Added subsection |
| 7 | Test buffer contents | Medium | Fixed | aff0cbb | Validates null-task=0, all≤100 |
| 8 | Missing multi-tick test | Medium | Not Fixed | 40c8579 | Needs build system |
| 9-15 | Low items | Low | Mixed | - | Typo, rename, assertions, comments |

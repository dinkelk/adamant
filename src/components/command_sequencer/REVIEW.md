# Command Sequencer Component — Code Review

**Reviewer:** Automated Code Review (Claude)
**Date:** 2026-02-28
**Branch:** `review/components-command-sequencer`
**Scope:** Component-level files only (excluding `seq/decode`, `seq/engine`, `seq/runtime`, and `build/`)

---

## 1. Documentation Review

### DOC-01 — README.md states unit tests are disabled; no guidance for enabling them
- **Location:** `README.md`
- **Original:**
  ```
  Note that the unit tests for this component have been disabled for continuous integration. The sequence compilation tool that is used to generate the binary sequences used by this component is not yet publicly available, but is planned to be released for use sometime in the future.
  ```
- **Explanation:** The README says tests are disabled and the SEQ compiler "is planned to be released sometime in the future." This gives no actionable path for a developer to run or validate the component. For a safety-critical component, there should be clear instructions on how to obtain the toolchain or a pointer to the internal build procedure.
- **Corrected:** Add a section explaining how to build the test sequences (e.g., reference the `test_sequences/all.do` build system and the SEQ compiler artifact).
- **Severity:** Medium

### DOC-02 — Typo "disabled" vs "disables" in init parameter description
- **Location:** `command_sequencer.component.yaml`, `Packet_Period` init parameter description; also repeated in `component-command_sequencer-implementation.ads`
- **Original:**
  ```
  A value of 0 disabled the packet.
  ```
- **Explanation:** Should be "disables" (present tense, describing the parameter's effect).
- **Corrected:**
  ```
  A value of 0 disables the packet.
  ```
- **Severity:** Low

### DOC-03 — Connector description grammar: "allowed" should be "allowing"
- **Location:** `command_sequencer.component.yaml`, second connector (Command_Response recv_async) description; also repeated in `component-command_sequencer-implementation.ads`
- **Original:**
  ```
  Command responses from sent commands are received on this connector, allowed subsequent commands in a sequence to be sent out.
  ```
- **Explanation:** Grammatical error — "allowed" should be "allowing."
- **Corrected:**
  ```
  Command responses from sent commands are received on this connector, allowing subsequent commands in a sequence to be sent out.
  ```
- **Severity:** Low

### DOC-04 — Comment says "Procedure which build and sends the summary packet" (twice, different packets)
- **Location:** `component-command_sequencer-implementation.adb`, line beginning `procedure Send_Details_Packet`
- **Original:**
  ```ada
  -- Procedure which build and sends the summary packet:
  procedure Send_Details_Packet ...
  ```
- **Explanation:** Copy-paste error — the comment says "summary packet" but the procedure builds the **details** packet. Also "build" should be "builds."
- **Corrected:**
  ```ada
  -- Procedure which builds and sends the details packet:
  procedure Send_Details_Packet ...
  ```
- **Severity:** Low

### DOC-05 — Stale TODO / commented-out code in Command_Response handler
- **Location:** `component-command_sequencer-implementation.adb`, inside `Handle_Command_Response`, within the unexpected-command-ID branch
- **Original:**
  ```ada
  -- Let's report this with an event, but do not continue:
  -- Self.Event_T_Send_If_Connected (Self.Events.Unexpected_Command_Response_Id (...));
  -- ^ This event will be produced whenever we have a spawn or call instruction, which will be confusing.
  --    Is it better to just remove?
  ```
- **Explanation:** Commented-out code with an unresolved design question should not remain in safety-critical flight code. Either re-enable the event and filter at the ground system, or remove the dead code and document the rationale.
- **Severity:** Medium

### DOC-06 — Stale comment: "What is packet_t_send is disconnected?"
- **Location:** `component-command_sequencer-implementation.adb`, `Issue_Details_Packet` command handler
- **Original:**
  ```ada
  -- Send the packet:
  -- What is packet_t_send is disconnected?
  Self.Send_Details_Packet (Arg.Engine_Id);
  ```
- **Explanation:** This looks like a WIP question left in the code. The surrounding `if Self.Is_Packet_T_Send_Connected` already guards it, making the comment incorrect and confusing. Remove it.
- **Severity:** Low

---

## 2. Model Review

### MOD-01 — No severity levels on events
- **Location:** `command_sequencer.events.yaml`
- **Explanation:** None of the 37 events have an explicit severity level (e.g., `Warning`, `Critical`). The Adamant framework defaults unspecified severity to `Informational`. Events like `Sequence_Execution_Error`, `Sequence_Timeout_Error`, `Data_Product_Id_Out_Of_Range_Error`, and `Execute_Recursion_Limit_Exceeded` represent off-nominal conditions that should be classified at `Warning` or higher so ground systems can filter and alert appropriately.
- **Corrected:** Add `severity: Warning` (or appropriate level) to each error/fault event. Example:
  ```yaml
  - name: Sequence_Execution_Error
    description: An error occurred while executing a sequence.
    param_type: Engine_Error_Type.T
    severity: Warning
  ```
- **Severity:** High

### MOD-02 — Event description typo: "of subsequence load"
- **Location:** `command_sequencer.events.yaml`, `Sequence_Timeout_Error`
- **Original:**
  ```
  A sequence timed out waiting on a command response of subsequence load.
  ```
- **Corrected:**
  ```
  A sequence timed out waiting on a command response or subsequence load.
  ```
- **Severity:** Low

### MOD-03 — Event description: "as finished" → "has finished"
- **Location:** `command_sequencer.events.yaml`, `Finished_Sequence`
- **Original:**
  ```
  The sequence engine as finished its execution of the parent sequence.
  ```
- **Corrected:**
  ```
  The sequence engine has finished its execution of the parent sequence.
  ```
- **Severity:** Low

### MOD-04 — Single data product for an entire component
- **Location:** `command_sequencer.data_products.yaml`
- **Explanation:** The only data product is `Summary_Packet_Period`. For a safety-critical sequencer, operators typically need per-engine state data products (e.g., `Active_Engine_Count`, `Total_Command_Errors`, `Engines_In_Error_State`) available in the data product database for autonomous fault monitoring. Currently, this information is only available via packets, which may not be queryable by other components.
- **Severity:** Medium (design observation, not a bug)

---

## 3. Component Implementation Review

### IMP-01 — `Sequence_Load_Return_T_Send_Dropped` and other send-dropped handlers are `is null`
- **Location:** `component-command_sequencer-implementation.ads`, all `*_Send_Dropped` overrides
- **Original:**
  ```ada
  overriding procedure Sequence_Load_Return_T_Send_Dropped (Self : in out Instance; Arg : in Sequence_Load_Return.T) is null;
  overriding procedure Command_T_Send_Dropped (Self : in out Instance; Arg : in Command.T) is null;
  overriding procedure Command_Response_T_Send_Dropped (Self : in out Instance; Arg : in Command_Response.T) is null;
  overriding procedure Packet_T_Send_Dropped (Self : in out Instance; Arg : in Packet.T) is null;
  overriding procedure Data_Product_T_Send_Dropped (Self : in out Instance; Arg : in Data_Product.T) is null;
  overriding procedure Event_T_Send_Dropped (Self : in out Instance; Arg : in Event.T) is null;
  ```
- **Explanation:** Silently dropping a sent command (`Command_T_Send_Dropped`) or a sequence load return (`Sequence_Load_Return_T_Send_Dropped`) is a **critical** loss-of-function scenario. The sequence engine will wait indefinitely for a command response that will never arrive (the command was never sent). At minimum, `Command_T_Send_Dropped` and `Sequence_Load_Return_T_Send_Dropped` should set the engine to an error state or fire an event. Currently these are completely silent, making the failure undiagnosable.
- **Corrected:** Implement non-null handlers that at minimum emit events. For `Command_T_Send_Dropped`, consider transitioning the engine to an error state.
- **Severity:** Critical

### IMP-02 — Potential integer overflow in `Kill_Engines` range check: `First_Engine + Num_Engines - 1`
- **Location:** `component-command_sequencer-implementation.adb`, `Execute_Engine`, `Kill_Engines` case branch
- **Original:**
  ```ada
  if First_Engine < Self.Seq_Engines.all'First or else
      First_Engine > Self.Seq_Engines.all'Last or else
      First_Engine + Num_Engines - 1 > Self.Seq_Engines.all'Last
  ```
- **Explanation:** `Sequence_Engine_Id` is `Interfaces.Unsigned_8`. If `First_Engine + Num_Engines - 1` wraps around 255 → 0 due to unsigned overflow, the range check passes incorrectly and the subsequent `for Idx in First_Engine .. First_Engine + Num_Engines - 1` loop could reset unintended engines. For example, `First_Engine = 200`, `Num_Engines = 100` → `200 + 100 - 1 = 299` which wraps to `43`. The condition `43 > Self.Seq_Engines.all'Last` might still catch it depending on engine count, but the arithmetic itself is unsound. This is partially mitigated by engine counts being small in practice, but represents a latent defect.
- **Corrected:** Perform the arithmetic in a wider type:
  ```ada
  if First_Engine < Self.Seq_Engines.all'First or else
      First_Engine > Self.Seq_Engines.all'Last or else
      Natural(First_Engine) + Natural(Num_Engines) - 1 > Natural(Self.Seq_Engines.all'Last)
  ```
- **Severity:** High

### IMP-03 — `Packet_Counter` can silently wrap around
- **Location:** `component-command_sequencer-implementation.adb`, `Tick_T_Recv_Async`, packet sending logic
- **Original:**
  ```ada
  if (Self.Packet_Counter mod Self.Packet_Period) = 0 then
     Self.Send_Summary_Packet;
     Self.Packet_Counter := 0;
  end if;
  Self.Packet_Counter := @ + 1;
  ```
- **Explanation:** If `Packet_Period` is set to a non-zero value and `Packet_Counter` somehow reaches `Unsigned_16'Last` (65535) without the modulo hitting zero (e.g., if Packet_Period is changed while counter is high), the increment `@ + 1` would cause a constraint error or wrap. In practice, the reset-to-zero on modulo match prevents this for most values, but if `Packet_Period` is set to a value > 32768 that doesn't evenly divide into 65536, the counter could wrap before the modulo matches. This is an edge case, but the standard pattern of resetting only on match and incrementing unconditionally is fragile.
- **Severity:** Low

### IMP-04 — `Get_Load_Command_Id` creates a throwaway command on every command response
- **Location:** `component-command_sequencer-implementation.adb`, `Command_Response_T_Recv_Async`, nested function `Get_Load_Command_Id`
- **Original:**
  ```ada
  function Get_Load_Command_Id return Command_Types.Command_Id is
     Load_Command : constant Command.T := Self.Create_Sequence_Load_Command_Function.all (
        Id => 0, Engine_Number => 0, Engine_Request => Specific_Engine
     );
  begin
     return Load_Command.Header.Id;
  end Get_Load_Command_Id;
  ```
- **Explanation:** This function constructs an entire `Command.T` (which includes a large `Arg_Buffer`) on the stack just to extract the command ID. It is called potentially multiple times within a single command response processing (once for `Wait_Load_New_Seq_Elsewhere` match and once for the inactive/error engine check). The load command ID is constant for the lifetime of the component and should be cached during `Init`.
- **Corrected:** Cache the load command ID in the `Instance` record during `Init`:
  ```ada
  Self.Load_Command_Id := Self.Create_Sequence_Load_Command_Function.all(0, 0, Specific_Engine).Header.Id;
  ```
- **Severity:** Medium

### IMP-05 — `Execute_Engine` precondition is too weak
- **Location:** `component-command_sequencer-implementation.adb`, `Execute_Engine` procedure
- **Original:**
  ```ada
  procedure Execute_Engine (Self : in out Instance; Engine : in out Seq.Engine; Recursion_Depth : in Natural := 0) with
     Pre => (Engine.Get_Engine_State /= Seq_Engine_State.Uninitialized)
  ```
- **Explanation:** The comment says "Execute engine should never be called on a non-active engine," but the precondition only excludes `Uninitialized`. It permits calling `Execute_Engine` on an `Inactive` or `Engine_Error` engine, which could lead to unexpected behavior. All call sites appear to guard against this, but the precondition should match the stated intent.
- **Corrected:**
  ```ada
  Pre => (Engine.Get_Engine_State in Reserved | Active | Waiting)
  ```
- **Severity:** Medium

---

## 4. Unit Test Review

### TST-01 — Tests are disabled in CI
- **Location:** `README.md`, test infrastructure
- **Explanation:** The README explicitly states tests are disabled for CI because the SEQ compiler is not publicly available. This means the component has **no automated regression testing** in the continuous integration pipeline. For safety-critical flight code, this is a significant gap. Even if the binary sequences are pre-compiled, they could be checked in as artifacts to enable CI.
- **Severity:** Critical

### TST-02 — Debug `Print` statement left in test
- **Location:** `command_sequencer_tests-implementation.adb`, `Test_Nominal_Sequence_Telemetry_Compare`
- **Original:**
  ```ada
  T.Event_T_Recv_Sync_History.Print;
  Natural_Assert.Eq (T.Event_T_Recv_Sync_History.Get_Count, 1);
  ```
- **Explanation:** An active `T.Event_T_Recv_Sync_History.Print` call is present (not commented out). This will produce debug output during every test run. Several other occurrences are commented out, but this one is not. In safety-critical test suites, test output should be deterministic and clean.
- **Corrected:** Comment out or remove the `Print` call:
  ```ada
  -- T.Event_T_Recv_Sync_History.Print;
  ```
- **Severity:** Low

### TST-03 — No test for `Kill_All_Engines` resetting engines that are in `Reserved` or `Waiting` states
- **Location:** `command_sequencer_tests-implementation.adb`
- **Explanation:** `Test_Kill_Engine_Command` tests killing individual engines and `Kill_All_Engines`, but only when engines are in `Active` or `Inactive` states. There is no test verifying that `Kill_All_Engines` correctly handles engines in `Reserved` (waiting for subsequence load) or `Waiting` (sleeping on a relative/absolute wait) states. These are important edge cases for operational scenarios where an operator needs to emergency-kill all engines.
- **Severity:** Medium

### TST-04 — No negative test for `Set_Engine_Arguments` with `Waiting` engine state
- **Location:** `command_sequencer_tests-implementation.adb`, `Test_Set_Engine_Arguments`
- **Explanation:** The test validates rejection for an `Active` engine and an out-of-range engine ID, but does not test the `Waiting` or `Reserved` states. `Is_Engine_Available` returns `False` for `Waiting` and `Reserved`, so the command should fail, but this is not verified.
- **Severity:** Low

### TST-05 — Test `command_sequencer.tests.yaml` description typo
- **Location:** `command_sequencer.tests.yaml`, `Test_Command_Invalid_Engine`
- **Original:**
  ```
  This unit test exercises commands send to invalid engine IDs
  ```
- **Corrected:**
  ```
  This unit test exercises commands sent to invalid engine IDs
  ```
- **Severity:** Low

---

## 5. Summary — Top 5 Issues

| # | ID | Severity | Summary |
|---|-----|----------|---------|
| 1 | IMP-01 | **Critical** | All `*_Send_Dropped` handlers are `is null` — silently dropping sent commands leaves engines hung with no diagnosis path |
| 2 | TST-01 | **Critical** | Unit tests disabled in CI — no automated regression for safety-critical flight code |
| 3 | MOD-01 | **High** | No severity levels on events — all 37 events default to Informational, masking errors from ground alerting |
| 4 | IMP-02 | **High** | Unsigned overflow possible in `Kill_Engines` range check arithmetic on `Unsigned_8` |
| 5 | IMP-04 | **Medium** | `Get_Load_Command_Id` needlessly constructs full `Command.T` on stack per call — should cache during Init |

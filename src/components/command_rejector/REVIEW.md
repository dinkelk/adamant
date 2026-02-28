# Command Rejector — Component Code Review

**Component:** `src/components/command_rejector`  
**Reviewer:** Automated Expert Review  
**Date:** 2026-02-28  

---

## 1. Documentation Review

The LaTeX document (`doc/command_rejector.tex`) is a standard template that pulls from generated build artifacts. The component description in `component.yaml` is clear and well-written, explaining the binary tree approach and O(log n) performance.

**Requirements (`requirements.yaml`):**

| # | Issue | Severity |
|---|-------|----------|
| D-1 | Requirements are incomplete. Only 3 requirements are listed, but the component also produces error packets and events on rejection. These behaviors are not captured as requirements and therefore cannot be traced to tests. | **Medium** |

**Details for D-1:**

- **Location:** `command_rejector.requirements.yaml`, lines 4–6
- **Original:**
  ```yaml
  requirements:
    - text: The component shall be configured with a list of command IDs to reject upon initialization.
    - text: The component shall reject commands if found in the command reject list.
    - text: The component shall report the number of commands rejected in telemetry
  ```
- **Explanation:** Missing requirements for: (a) forwarding non-rejected commands, (b) producing an error packet containing the rejected command, (c) emitting a `Rejected_Command` event. All three behaviors are implemented and tested, but untraceable to requirements.
- **Suggested addition:**
  ```yaml
    - text: The component shall forward commands not found in the command reject list.
    - text: The component shall produce an error packet containing any rejected command.
    - text: The component shall emit an event identifying each rejected command.
  ```

---

## 2. Model Review

The `command_rejector.component.yaml` model is well-structured. The connector set is appropriate: one `recv_sync` input, one `send` output for forwarded commands, plus standard event/data-product/packet/sys-time connectors.

| # | Issue | Severity |
|---|-------|----------|
| M-1 | The `Rejected_Command` event has no severity/level specified. In Adamant, events typically carry a severity. If the framework defaults to a benign level, a rejected command (a potential security or safety indicator) may be under-reported. | **Low** |

**Details for M-1:**

- **Location:** `command_rejector.events.yaml`, line 4
- **Original:**
  ```yaml
  events:
    - name: Rejected_Command
      description: A command was rejected (dropped) because it was found in the reject list.
      param_type: Command_Header.T
  ```
- **Explanation:** Consider whether this event should carry a `Warning` severity to ensure ground operators notice command rejections in telemetry streams.

No other model issues found. The preamble type `Command_Id_List` is appropriate.

---

## 3. Component Implementation Review

| # | Issue | Severity |
|---|-------|----------|
| I-1 | **Counter overflow on `Command_Reject_Counter`**: The reject counter is `Interfaces.Unsigned_16` and is incremented with `@ + 1`. After 65,535 rejections, this silently wraps to 0, producing an incorrect (decreasing) telemetry value. In a denial-of-service or repeated-command scenario in flight, this is a silent data corruption of safety telemetry. | **High** |
| I-2 | **`pragma Assert` used for runtime validation in `Init`**: The assertions guarding empty-list, duplicate-ID, and tree-size conditions use `pragma Assert`, which can be compiled out with `-gnatp` or `Assertion_Policy(Ignore)`. If assertions are disabled in a flight build, invalid configurations would silently succeed, leading to undefined behavior. | **Medium** |

**Details for I-1:**

- **Location:** `component-command_rejector-implementation.adb`, line 56
- **Original:**
  ```ada
  Self.Command_Reject_Counter := @ + 1;
  ```
- **Explanation:** `Unsigned_16` wraps modularly. After 65,535 rejections the counter resets to 0. For safety-critical telemetry, the counter should saturate at the maximum value rather than wrap.
- **Corrected code:**
  ```ada
  if Self.Command_Reject_Counter < Interfaces.Unsigned_16'Last then
     Self.Command_Reject_Counter := @ + 1;
  end if;
  ```

**Details for I-2:**

- **Location:** `component-command_rejector-implementation.adb`, lines 16, 25, 28
- **Original:**
  ```ada
  pragma Assert (Command_Id_Reject_List'Length > 0, "Empty protected command list is not allowed.");
  ...
  pragma Assert (not Ret, "Duplicate command ID ...");
  ...
  pragma Assert (Ret, "Binary tree too small to hold ID...");
  ```
- **Explanation:** If the Adamant framework guarantees assertions are always enabled in all builds (including flight), this is acceptable. Otherwise, these should be replaced with explicit `if ... then raise` statements or a project-specific `Assert` that cannot be compiled out.
- **Corrected code (if needed):**
  ```ada
  if Command_Id_Reject_List'Length = 0 then
     raise Constraint_Error with "Empty protected command list is not allowed.";
  end if;
  ```

---

## 4. Unit Test Review

| # | Issue | Severity |
|---|-------|----------|
| T-1 | **Unused `with` / `use` clause**: The test body imports `Command_Protector_Enums` and uses `Command_Protector_Enums.Armed_State`, but neither is referenced anywhere in the test code. This is a copy-paste artifact from the `Command_Protector` component tests and introduces a spurious dependency. | **Low** |
| T-2 | **`Test_Initialization` leaves component in partially-initialized state and calls `Final` on uninitialized component**: After `Init_None` fails (exception caught), `Final` is called on a component whose tree was never allocated (the assert fires before `Self.Command_Reject_List.Init`). This is a potential double-free or use of uninitialized memory in the binary tree's `Destroy`. Similarly, after `Init_Duplicate`, no `Final` is called before `Set_Up` runs on a partially-initialized tree. | **Medium** |
| T-3 | **No test for counter saturation/overflow**: There is no test that exercises the reject counter near or at `Unsigned_16'Last` (65,535). If the counter wraps (see I-1), no test would catch it. | **Medium** |
| T-4 | **No test for all reject-list IDs**: The reject list is `[4, 19, 77, 78]` but `Test_Command_Reject` only exercises IDs `4`, `77`, and `78`. Command ID `19` is never tested for rejection. | **Low** |
| T-5 | **No test for boundary command IDs**: No tests exercise command IDs at the boundaries of `Command_Id` range (e.g., 0, `Command_Id'Last`). Edge-case IDs near or equal to reject-list entries are also untested. | **Low** |

**Details for T-1:**

- **Location:** `test/command_rejector_tests-implementation.adb`, lines 5–6
- **Original:**
  ```ada
  with Command_Protector_Enums; use Command_Protector_Enums.Armed_State;
  ```
- **Explanation:** This type is never used. Likely copied from the `Command_Protector` test template.
- **Corrected code:** Remove the line entirely.

**Details for T-2:**

- **Location:** `test/command_rejector_tests-implementation.adb`, lines 55–79
- **Original flow:**
  ```ada
  T.Component_Instance.Final;   -- OK: finals Set_Up_Test init
  Init_Nominal;                  -- OK: re-inits
  T.Component_Instance.Final;   -- OK: finals nominal
  Init_None;                     -- FAILS: assert before allocation
  T.Component_Instance.Final;   -- PROBLEM: Final on never-allocated tree
  Init_Duplicate;                -- PARTIAL: tree allocated, some nodes added, then assert
  -- No Final before Set_Up      -- PROBLEM: Set_Up on partial state
  ```
- **Explanation:** Calling `Destroy` on an uninitialized/already-destroyed binary tree may be benign if the tree implementation handles it, but this is fragile and assumes implementation details of `Binary_Tree`. The test should guard against this.
- **Corrected code:** Add proper cleanup:
  ```ada
  T.Component_Instance.Final;
  Init_Nominal;
  T.Component_Instance.Final;
  Init_None;
  -- Do NOT call Final here; Init_None never allocated
  Init_Duplicate;
  T.Component_Instance.Final;  -- Clean up partial init
  -- Re-init with the standard list for Set_Up:
  T.Component_Instance.Init (Command_Id_Reject_List => Reject_Command_Id_List);
  ```

**Details for T-3:**

- **Location:** `test/command_rejector_tests-implementation.adb` (missing test)
- **Explanation:** A test should set the counter near `Unsigned_16'Last` and verify behavior (either saturation or documented wrap). This validates the telemetry accuracy requirement.

---

## 5. Summary — Top 5 Issues

| Rank | ID | Severity | Summary |
|------|----|----------|---------|
| 1 | I-1 | **High** | Reject counter (`Unsigned_16`) silently wraps to 0 after 65,535 rejections — corrupts safety telemetry. Should saturate at max value. |
| 2 | T-2 | **Medium** | `Test_Initialization` calls `Final` on a never-initialized component and runs `Set_Up` on a partially-initialized component — fragile test with potential undefined behavior. |
| 3 | I-2 | **Medium** | `pragma Assert` used for init-time validation can be compiled out in flight builds, silently accepting invalid configurations. |
| 4 | T-3 | **Medium** | No test exercises the reject counter near its maximum value; counter overflow (I-1) would go undetected. |
| 5 | D-1 | **Medium** | Three implemented behaviors (forwarding, error packets, events) have no corresponding requirements — gaps in traceability. |

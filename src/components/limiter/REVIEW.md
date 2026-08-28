# Limiter Component Code Review

**Reviewer:** Automated Safety-Critical Code Review  
**Date:** 2026-02-28  
**Branch:** review/components-limiter

---

## 1. Documentation Review

### Issue 1.1 — Missing Data Products Section in LaTeX Document (Low)

**Location:** `doc/limiter.tex`, line ~30

**Original Code:**
```latex
\subsection{Parameters}

\input{build/tex/limiter_parameters.tex}

\subsection{Events}

\input{build/tex/limiter_events.tex}

\section{Unit Tests}
```

**Explanation:** The document includes Commands, Parameters, and Events subsections under Design, and the Data Products section is present in the component YAML but there is no `\subsection{Data Products}` in the LaTeX document between Parameters and Events (or after Events). Users consulting the generated PDF will not find documentation of the `Max_Packet_Sends_Per_Tick` data product in the Design section.

**Corrected Code:**
```latex
\subsection{Parameters}

\input{build/tex/limiter_parameters.tex}

\subsection{Data Products}

\input{build/tex/limiter_data_products.tex}

\subsection{Events}

\input{build/tex/limiter_events.tex}

\section{Unit Tests}
```

**Severity:** Low

---

### Issue 1.2 — Inconsistent Naming: "Send" vs "Sends" (Low)

**Location:** `limiter.events.yaml`, line 3; also `component-limiter-implementation.adb` line ~96

**Original Code (events.yaml):**
```yaml
  - name: Max_Send_Per_Tick_Set
```

**Explanation:** The event is named `Max_Send_Per_Tick_Set` (singular "Send"), while the command is `Sends_Per_Tick` (plural), the parameter is `Max_Sends_Per_Tick` (plural), and the data product is `Max_Packet_Sends_Per_Tick` (plural). This inconsistency could confuse operators correlating telemetry events with commands/parameters.

**Corrected Code:**
```yaml
  - name: Max_Sends_Per_Tick_Set
```

(With corresponding updates to all references in the implementation and test code.)

**Severity:** Low

---

## 2. Model Review

### Issue 2.1 — Parameter Default Does Not Match Init Default (Medium)

**Location:** `limiter.parameters.yaml`, line 7

**Original Code:**
```yaml
    default: "(Value => 1)"
```

**Explanation:** The parameter default for `Max_Sends_Per_Tick` is `1`, but the test suite initializes the component with `Max_Sends_Per_Tick => 3`. While the parameter default and the init value are independent concepts (the init value seeds the protected variable, and the parameter default is the table's reset value), if a parameter update is issued without first staging a value, the component would revert to a rate of 1 rather than the init value. This mismatch between the parameter table default and common init values is a potential source of confusion for integrators. The design should document why these differ or unify them.

**Severity:** Medium

---

### Issue 2.2 — No Requirement for Queue Overflow Behavior (Low)

**Location:** `limiter.requirements.yaml`

**Original Code:**
```yaml
requirements:
  - text: The component shall be able to receive and queue a generic data type.
  - text: The component shall send queued data at a configurable periodic rate.
  - text: The rate at which queued data is sent shall be configurable by command.
  - text: The rate at which queued data is sent shall be configurable by parameter.
```

**Explanation:** There is no requirement covering the queue-full/overflow behavior (i.e., that the component shall emit a `Data_Dropped` event when the queue overflows). The test suite explicitly tests this behavior in `Test_Queue_Overflow`, but it is not traceable to a requirement.

**Corrected Code:**
```yaml
  - text: The component shall emit an event when incoming data is dropped due to a full queue.
```

**Severity:** Low

---

## 3. Component Implementation Review

### Issue 3.1 — Command Does Not Update Parameter Table (Causes Command/Parameter Desynchronization) (High)

**Location:** `component-limiter-implementation.adb`, `Sends_Per_Tick` function (line ~88–99)

**Original Code:**
```ada
   overriding function Sends_Per_Tick (Self : in out Instance; Arg : in Packed_U16.T) return Command_Execution_Status.E is
      use Command_Execution_Status;
      The_Time : constant Sys_Time.T := Self.Sys_Time_T_Get;
   begin
      -- Set the rate:
      Self.P_Max_Sends_Per_Tick.Set_Var (Arg.Value);
      -- Send data product:
      Self.Data_Product_T_Send_If_Connected (Self.Data_Products.Max_Packet_Sends_Per_Tick (The_Time, (Value => Self.P_Max_Sends_Per_Tick.Get_Var)));
      -- Send event:
      Self.Event_T_Send_If_Connected (Self.Events.Max_Send_Per_Tick_Set (The_Time, Arg));
      return Success;
   end Sends_Per_Tick;
```

**Explanation:** When the `Sends_Per_Tick` command is received, only the protected variable `P_Max_Sends_Per_Tick` is updated. The component's parameter table (`Self.Max_Sends_Per_Tick`) is **not** updated. This means:

1. A subsequent `Fetch` parameter operation will return the **old** (stale) parameter value, not the value set by command.
2. If `Update_Parameters` is called on the next tick (via `Self.Update_Parameters` in `Tick_T_Recv_Sync`), and no new parameter was staged, the parameter table value will overwrite the command-set value back to whatever was previously in the table.

This is a **silent reversion** of the commanded rate on the very next tick. The tick handler calls `Self.Update_Parameters` unconditionally, which calls `Update_Parameters_Action`, which copies `Self.Max_Sends_Per_Tick.Value` (the parameter table) back into `P_Max_Sends_Per_Tick` — undoing the command.

**Corrected Code:**
```ada
   overriding function Sends_Per_Tick (Self : in out Instance; Arg : in Packed_U16.T) return Command_Execution_Status.E is
      use Command_Execution_Status;
      The_Time : constant Sys_Time.T := Self.Sys_Time_T_Get;
   begin
      -- Set the rate in both the protected variable and the parameter table
      -- so that they stay in sync:
      Self.P_Max_Sends_Per_Tick.Set_Var (Arg.Value);
      Self.Max_Sends_Per_Tick := (Value => Arg.Value);
      -- Send data product:
      Self.Data_Product_T_Send_If_Connected (Self.Data_Products.Max_Packet_Sends_Per_Tick (The_Time, (Value => Self.P_Max_Sends_Per_Tick.Get_Var)));
      -- Send event:
      Self.Event_T_Send_If_Connected (Self.Events.Max_Send_Per_Tick_Set (The_Time, Arg));
      return Success;
   end Sends_Per_Tick;
```

*Alternatively*, the `Tick_T_Recv_Sync` should only call `Self.Update_Parameters` when a parameter update is actually pending, or `Update_Parameters_Action` should not blindly copy the table value when no update occurred. The exact fix depends on the Adamant framework's `Update_Parameters` semantics — if it is a no-op when nothing is staged, this issue does not manifest at runtime. **This needs verification against the framework.**

**Severity:** High (if `Update_Parameters` unconditionally invokes `Update_Parameters_Action`) / Medium (if it's a no-op when nothing staged)

---

### Issue 3.2 — `Items_Dispatched` Variable Is Unused Beyond the Assertion (Low)

**Location:** `component-limiter-implementation.adb`, `Tick_T_Recv_Sync` (line ~55–66)

**Original Code:**
```ada
      declare
         Max_Items_To_Dispatch : constant Natural := Natural (Self.P_Max_Sends_Per_Tick.Get_Var);
         Items_Dispatched : Natural := 0;
      begin
         -- Dispatch up to our maximum items per tick off the queue:
         if Max_Items_To_Dispatch > 0 then
            Items_Dispatched := Self.Dispatch_N (Max_Items_To_Dispatch);
         end if;

         -- We should never dispatch more items off the queue than was
         -- requested in the call to Dispatch_N:
         pragma Assert (Items_Dispatched <= Max_Items_To_Dispatch);
      end;
```

**Explanation:** `Items_Dispatched` is only used in a `pragma Assert`. In production builds with assertions disabled, the variable and the `Dispatch_N` return value are effectively unused. This is not a bug — the assertion is good defensive practice — but no data product or event is emitted indicating how many items were actually dispatched per tick. For observability in flight, consider emitting a data product with the count of items dispatched.

**Severity:** Low

---

## 4. Unit Test Review

### Issue 4.1 — No Test for Command-Then-Parameter Interaction (Medium)

**Location:** `test/limiter_tests-implementation.adb`

**Explanation:** `Test_Change_Rate_Command` and `Test_Change_Rate_Parameter` each test their respective mechanisms in isolation, but there is no test that:
1. Sets a rate via command, then verifies a subsequent tick uses the commanded rate (without a parameter update reverting it).
2. Sets a rate via command, then issues a parameter update, and verifies which value wins.

Given Issue 3.1 (command/parameter desynchronization), this interaction is the most likely source of a flight anomaly and **must** be tested.

**Corrected Code:** Add a test such as:
```ada
overriding procedure Test_Command_Parameter_Interaction (Self : in out Instance) is
   T : Component_Tester_Package.Instance_Access renames Self.Tester;
   The_Tick : constant Tick.T := ((0, 0), 0);
begin
   -- Set rate to 1 via command:
   T.Command_T_Send (T.Commands.Sends_Per_Tick ((Value => 1)));
   -- Enqueue 3 items:
   T.T_Send (((0, 0), 1));
   T.T_Send (((0, 0), 2));
   T.T_Send (((0, 0), 3));
   -- Tick — should send exactly 1 (commanded rate), not 3 (init) or
   -- the parameter default:
   T.Tick_T_Send (The_Tick);
   Natural_Assert.Eq (T.T_Recv_Sync_History.Get_Count, 1);
end Test_Command_Parameter_Interaction;
```

**Severity:** Medium

---

### Issue 4.2 — Test_Queue_Overflow Does Not Verify T_Send_Dropped_Count (Low)

**Location:** `test/limiter_tests-implementation.adb`, `Test_Queue_Overflow` (line ~157)

**Original Code:**
```ada
      -- OK the next command should overflow the queue.
      T.Expect_T_Send_Dropped := True;
      T.T_Send (((0, 0), 1));

      -- Make sure event thrown:
      Natural_Assert.Eq (T.Event_T_Recv_Sync_History.Get_Count, 1);
      Natural_Assert.Eq (T.Data_Dropped_History.Get_Count, 1);
```

**Explanation:** The tester infrastructure maintains a `T_Send_Dropped_Count` counter, but the test never asserts on it. While the event check is sufficient for verifying the component behavior, asserting `T.T_Send_Dropped_Count = 1` would verify both sides of the drop path (tester and component).

**Corrected Code (add after existing assertions):**
```ada
      Natural_Assert.Eq (T.T_Send_Dropped_Count, 1);
```

**Severity:** Low

---

### Issue 4.3 — No Test for Max_Sends_Per_Tick = Unsigned_16'Last (Boundary) (Low)

**Location:** `test/limiter_tests-implementation.adb`

**Explanation:** No test exercises the boundary condition where `Max_Sends_Per_Tick` is set to `Unsigned_16'Last` (65535). While the conversion `Natural (Self.P_Max_Sends_Per_Tick.Get_Var)` is safe on all practical targets (Natural range includes 65535), a boundary test would confirm this and verify the component handles a very large dispatch limit gracefully (draining the queue without issues).

**Severity:** Low

---

## 5. Summary — Top 5 Issues

| # | Severity | Section | Issue |
|---|----------|---------|-------|
| 1 | **High** | Implementation (3.1) | Command sets protected variable but not parameter table — next tick's `Update_Parameters` may silently revert the commanded rate |
| 2 | **Medium** | Tests (4.1) | No test for command-then-parameter interaction, leaving the desynchronization in Issue 3.1 undetected |
| 3 | **Medium** | Model (2.1) | Parameter default (`1`) differs from typical init value (`3`) with no documented rationale |
| 4 | **Low** | Documentation (1.1) | Data Products subsection missing from LaTeX design document |
| 5 | **Low** | Model (1.2) | Inconsistent naming: `Max_Send_Per_Tick_Set` (singular) vs all other identifiers using plural "Sends" |

## Resolution Notes

| # | Issue | Severity | Status | Commit | Notes |
|---|-------|----------|--------|--------|-------|
| 1 | Command/parameter desync | High | Fixed | b413cb9 | Command now syncs param table |
| 2 | Default mismatch | Medium | Fixed | 48695ea | Aligned to 3 |
| 3 | No interaction test | Medium | Fixed | 64646f3 | Added command-then-tick test |
| 4 | Missing Data Products in doc | Low | Fixed | a703ce9 | Added subsection |
| 5 | Naming inconsistency | Low | Fixed | 004b6f3 | Renamed across all files |
| 6 | Missing overflow requirement | Low | Fixed | 571afe4 | Added |
| 7 | Items_Dispatched observability | Low | Not Fixed | 7d03e65 | Needs model changes |
| 8 | Drop count unasserted | Low | Fixed | 87bdcb8 | Added assertion |
| 9 | Boundary test | Low | Fixed | 3cc5157 | Added Unsigned_16'Last test |

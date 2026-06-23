# Connector Protector — Code Review

**Component:** `src/components/connector_protector`
**Date:** 2026-02-28
**Reviewer:** Automated Expert Review

---

## 1. Documentation Review

### 1.1 Component YAML Description

The YAML description is clear and thorough, explaining the protected-object pass-through semantics, the synchronization guarantee, and the intended deployment use case. No issues found with the YAML itself.

### 1.2 LaTeX Design Document

**DOC-1: Boilerplate sections for features the component does not use**
- **Location:** `doc/connector_protector.tex`, lines referencing `_interrupts`, `_commands`, `_parameters`, `_events`, `_data_products`, `_packets`
- **Severity:** Low
- **Explanation:** The document includes subsections for Interrupts, Commands, Parameters, Events, Data Products, and Packets, none of which this component defines. While these are auto-generated and will render as empty/N-A tables, they add clutter to a component whose entire value proposition is simplicity. This is a standard Adamant template concern and not specific to this component.
- **Recommendation:** No change required — this is standard Adamant practice. Noting for completeness only.

### 1.3 Ada Spec/Body Header Comments

Header comments in the `.ads` and `.adb` files correctly describe the component. The full YAML description is duplicated in the `.ads` which is good practice.

**No actionable documentation issues.**

---

## 2. Model Review

### 2.1 Component YAML Model

The model is minimal and correct:
- `execution: passive` — appropriate; the component does no autonomous work.
- `generic` with a single type parameter `T` — correct.
- Two connectors: `recv_sync` (inbound) and `send` (outbound), both typed `T` — correct.

**MOD-1: No `return_type` on `recv_sync` connector**
- **Location:** `connector_protector.component.yaml`, connector 1
- **Severity:** Low
- **Explanation:** The `recv_sync` connector does not declare a return type. This means callers receive no status or return value from the protected call. For a pure pass-through protector this is fine, but it means errors in the downstream `T_Send` chain cannot be communicated back to the caller through a return value. This is a design choice, not a defect, but worth noting for safety-critical deployments where call-failure awareness matters.
- **Recommendation:** Acceptable as-is for the stated design intent.

**No actionable model issues.**

---

## 3. Component Implementation Review

### 3.1 Protected Object Design

**IMPL-1: Protected procedure parameter shadows component `Self` idiom**
- **Location:** `component-connector_protector-implementation.ads`, line within `Protected_Connector` declaration:
  ```ada
  procedure Call (Self : in out Instance; Arg : in T);
  ```
- **Severity:** Medium
- **Explanation:** The parameter `Self` in the protected procedure `Call` is **not** the protected object's implicit reference — it is a regular parameter referring to the enclosing `Instance`. While Ada distinguishes these correctly at the language level, using the name `Self` here creates a readability hazard: a reviewer or maintainer may confuse it with the implicit protected object state or the standard Adamant component `Self` convention. In safety-critical code, naming clarity directly reduces the risk of future misunderstanding during maintenance.
- **Original code:**
  ```ada
  procedure Call (Self : in out Instance; Arg : in T);
  ```
- **Corrected code:**
  ```ada
  procedure Call (Inst : in out Instance; Arg : in T);
  ```
  (And correspondingly in the body:)
  ```ada
  procedure Call (Inst : in out Instance; Arg : in T) is
  begin
     Inst.T_Send (Arg);
  end Call;
  ```
  ```ada
  -- In T_Recv_Sync:
  Self.P_Connector.Call (Self, Arg);
  ```
  remains unchanged (the actual argument is still `Self`).

### 3.2 Correctness of Mutual Exclusion

The protected object `Protected_Connector` contains no data members. Its sole purpose is to provide the Ada protected-object mutual exclusion guarantee around the call to `T_Send`. This is a correct and idiomatic use of Ada protected objects for serialization. Concurrent calls to `T_Recv_Sync` from different tasks will be serialized through the protected procedure entry, which is the stated design goal.

**IMPL-2: No protection against reentrant/recursive calls**
- **Location:** `component-connector_protector-implementation.adb`, `T_Recv_Sync` procedure
- **Severity:** Medium
- **Explanation:** If the downstream component connected to `T_Send` were to (directly or indirectly) call back into this same component's `T_Recv_Sync`, this would constitute a call to a protected procedure from within that same protected procedure. In Ada, this is a bounded error (ARM 9.5.1) that can result in deadlock or Program_Error depending on the implementation. The component documentation does not warn against this topology. In a complex assembly, a cycle could arise inadvertently.
- **Original code:** (no guard)
- **Recommendation:** Add a note in the YAML description warning that the downstream connection graph must be acyclic with respect to this component's `T_Recv_Sync`. Alternatively, add a runtime guard:
  ```ada
  -- In the protected object:
  In_Call : Boolean := False;
  
  procedure Call (Self : in out Instance; Arg : in T) is
  begin
     pragma Assert (not In_Call, "Reentrant call to Connector_Protector detected");
     In_Call := True;
     Self.T_Send (Arg);
     In_Call := False;
  end Call;
  ```
  However, since Ada's protected object semantics already make reentrant calls a bounded error (likely raising `Program_Error`), a documentation warning may suffice.

### 3.3 T_Send_Dropped

**IMPL-3: `T_Send_Dropped` is silently null**
- **Location:** `component-connector_protector-implementation.ads`:
  ```ada
  overriding procedure T_Send_Dropped (Self : in out Instance; Arg : in T) is null;
  ```
- **Severity:** Low
- **Explanation:** For a `send` connector attached to a synchronous `recv_sync` on the other side, `T_Send_Dropped` should never be invoked (there is no queue to overflow). The null body is therefore correct. However, if the connector were ever mistakenly wired to an async receiver with a queue, dropped messages would be silently lost with no event, log, or assertion. A defensive `pragma Assert (False, ...)` body would catch such assembly errors.
- **Recommendation:** Optional hardening:
  ```ada
  overriding procedure T_Send_Dropped (Self : in out Instance; Arg : in T) is
  begin
     pragma Assert (False, "T_Send_Dropped should never be called for Connector_Protector");
  end T_Send_Dropped;
  ```

---

## 4. Unit Test Review

### 4.1 Test Coverage

**TEST-1: No multi-task / concurrency test**
- **Location:** `test/connector_protector_tests-implementation.adb`, entire test suite
- **Severity:** High
- **Explanation:** The component's **entire purpose** is multi-tasking synchronization via a protected object. However, the only test (`Test_Protected_Call`) exercises the component from a single task, verifying only that arguments pass through correctly. This validates the data-forwarding path but provides **zero validation** of the mutual-exclusion guarantee — which is the sole reason this component exists. A meaningful concurrency test would:
  1. Spawn multiple Ada tasks that concurrently invoke `T_Recv_Sync`.
  2. Verify that downstream calls are serialized (e.g., via a synthetic slow receiver that asserts no overlapping execution).
  3. Verify no data corruption occurs under contention.
- **Original code:**
  ```ada
  overriding procedure Test_Protected_Call (Self : in out Instance) is
     T : Component_Tester_Package.Instance_Access renames Self.Tester;
  begin
     -- Only single-task, sequential invocations
     T.T_Send (((1, 2), 3));
     Natural_Assert.Eq (T.T_Recv_Sync_History.Get_Count, 1);
     ...
  end Test_Protected_Call;
  ```
- **Corrected code (additional test):**
  ```ada
  overriding procedure Test_Concurrent_Protection (Self : in out Instance) is
     T : Component_Tester_Package.Instance_Access renames Self.Tester;
     Task_Count : constant := 10;
     Calls_Per_Task : constant := 50;
     
     task type Caller_Task is
        entry Start (Id : in Natural);
     end Caller_Task;
     
     task body Caller_Task is
        My_Id : Natural;
     begin
        accept Start (Id : in Natural) do
           My_Id := Id;
        end Start;
        for I in 1 .. Calls_Per_Task loop
           T.T_Send (((My_Id, I), My_Id + I));
        end loop;
     end Caller_Task;
     
     Tasks : array (1 .. Task_Count) of Caller_Task;
  begin
     for I in Tasks'Range loop
        Tasks (I).Start (I);
     end loop;
     -- Tasks complete here (block exit waits)
     Natural_Assert.Eq (T.T_Recv_Sync_History.Get_Count,
                        Task_Count * Calls_Per_Task);
  end Test_Concurrent_Protection;
  ```
  *(This would also require a corresponding entry in `connector_protector.tests.yaml`.)*

### 4.2 Test Thoroughness (Single-Threaded Path)

The existing `Test_Protected_Call` is adequate for verifying the single-threaded data pass-through. It tests multiple invocations with distinct data and validates both count and value. This is fine as a basic regression test.

### 4.3 Test Infrastructure

The tester (`component-connector_protector-implementation-tester.adb`) correctly:
- Initializes history with depth 100
- Properly wires bidirectional connections in `Connect`
- Captures forwarded arguments in `T_Recv_Sync_History`
- Cleans up via `Final_Base` and `Safe_Deallocator`

**No issues with test infrastructure.**

---

## 5. Summary — Top 5 Issues

| # | ID | Severity | Location | Description |
|---|------|----------|----------|-------------|
| 1 | TEST-1 | **High** | `test/connector_protector_tests-implementation.adb` | No concurrency test despite component's sole purpose being multi-task synchronization. The mutual-exclusion guarantee is entirely unvalidated. |
| 2 | IMPL-2 | **Medium** | `component-connector_protector-implementation.adb` | No documentation or runtime guard against reentrant/recursive calls, which would be a bounded error (deadlock or `Program_Error`) in Ada. |
| 3 | IMPL-1 | **Medium** | `component-connector_protector-implementation.ads` | Protected procedure parameter named `Self` shadows the Adamant component `Self` idiom, creating a readability/maintenance hazard in safety-critical code. |
| 4 | IMPL-3 | **Low** | `component-connector_protector-implementation.ads` | `T_Send_Dropped` is silently null; a defensive assertion would catch incorrect assembly wiring. |
| 5 | MOD-1 | **Low** | `connector_protector.component.yaml` | No return type on `recv_sync` connector means downstream errors cannot propagate back to callers. Acceptable design choice but worth noting. |

---

*End of review.*

## Resolution Notes

| # | Issue | Severity | Status | Commit | Notes |
|---|-------|----------|--------|--------|-------|
| 1 | No concurrency test | High | Fixed | 87bfa2e | 10 tasks × 50 calls |
| 2 | No reentrant call guard | Medium | Fixed | 67469bf | Added In_Call boolean + pragma Assert |
| 3 | Self naming in protected proc | Medium | Fixed | 6b56db8 | Renamed to Inst |
| 4 | Silent T_Send_Dropped | Low | Fixed | 44d90ae | pragma Assert(False) |
| 5 | No return type on recv_sync | Low | Not Fixed | a3139c3 | Acceptable design |
| 6 | Doc template | Low | Not Fixed | 66e3a39 | Standard practice |

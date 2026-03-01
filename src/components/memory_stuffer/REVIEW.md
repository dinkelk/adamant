# Memory Stuffer Component — Code Review

**Reviewer:** Automated Review  
**Date:** 2026-03-01  
**Branch:** `review/components-memory-stuffer`

---

## 1. Documentation Review

### DOC-01 — LaTeX includes non-existent sections (Low)

**File:** `doc/memory_stuffer.tex`  
**Location:** Lines for Interrupts, Parameters, Packets sections

```latex
\subsection{Interrupts}
\input{build/tex/memory_stuffer_interrupts.tex}
...
\subsection{Parameters}
\input{build/tex/memory_stuffer_parameters.tex}
...
\subsection{Packets}
\input{build/tex/memory_stuffer_packets.tex}
```

**Explanation:** The component defines no interrupts, parameters, or packets, yet the LaTeX document includes sections for all three. While the generated files may contain "None" text, the subsection headings are misleading and add noise to the design document.

**Corrected:** Remove the Interrupts, Parameters, and Packets subsections (or gate them with conditional includes if the template supports it).

**Severity:** Low

### DOC-02 — Requirements do not cover the memory copy feature (Medium)

**File:** `memory_stuffer.requirements.yaml`

```yaml
requirements:
  - text: The component shall write to a memory region on command.
  - text: The component shall reject commands to write to memory in off-limit regions.
  ...
```

**Explanation:** The component has a full memory-copy feature (via `Memory_Region_Copy_T_Recv_Async`) including destination validation and source release. None of the six requirements mention memory copy, destination validation for copies, or source region release. This means the copy feature is untraceable to any requirement.

**Corrected:** Add requirements such as:
```yaml
  - text: The component shall copy a source memory region to a valid destination memory region upon request.
  - text: The component shall reject copy requests whose destination falls outside configured memory regions.
  - text: The component shall release the source memory region after a copy operation completes (success or failure).
```

**Severity:** Medium

### DOC-03 — Component description says copy connector "may be disconnected" but no requirement covers that (Low)

**File:** `memory_stuffer.component.yaml`, description field

**Explanation:** The description states "The memory region copy and release connectors may be disconnected if this feature is not needed." This is an operational constraint that should be documented in a requirement or design note, not just the description.

**Severity:** Low

---

## 2. Model Review

### MOD-01 — No `name` on connectors makes YAML harder to trace (Low)

**File:** `memory_stuffer.component.yaml`, connectors section

**Explanation:** While the assumptions state names may be omitted, explicitly naming connectors (e.g., `Tick_T_Recv_Async`, `Command_T_Recv_Async`) would improve traceability between the YAML model and the generated Ada code. This is a style observation, not a defect.

**Severity:** Low

### MOD-02 — `Memory_Region_Release` connector description says "Memory_Region_T_Send" (Low)

**File:** `component-memory_stuffer-implementation.ads`, line in the send-dropped section

```ada
-- This procedure is called when a Memory_Region_T_Send message is dropped due to a full queue.
overriding procedure Memory_Region_Release_T_Send_Dropped (Self : in out Instance; Arg : in Memory_Region_Release.T) is null;
```

**Explanation:** The comment says "Memory_Region_T_Send" but the procedure is `Memory_Region_Release_T_Send_Dropped`. This is a generated comment mismatch — the connector type is `Memory_Region_Release.T`, not `Memory_Region.T`. If this is auto-generated, it should be reported as a generator bug.

**Corrected comment:**
```ada
-- This procedure is called when a Memory_Region_Release_T_Send message is dropped due to a full queue.
```

**Severity:** Low

---

## 3. Component Implementation Review

### IMPL-01 — Memory copy bypasses protected region checks (High)

**File:** `component-memory_stuffer-implementation.adb`, `Memory_Region_Copy_T_Recv_Async`

```ada
-- There is no protected region checking here, since this is a backdoor copy that
-- bypasses a direct stuff.
```

**Explanation:** The comment explicitly acknowledges this is a "backdoor" that bypasses arm/protect checks. In safety-critical flight software, an unprotected write path to memory that is otherwise designated as protected defeats the purpose of the protection mechanism. An attacker or errant component sending a `Memory_Region_Copy` can overwrite protected regions without arming. If this is intentional, it must be documented in a requirement and justified in a safety analysis. Currently no requirement covers this behavior.

**Corrected:** Either:
1. Add protected region checking to the copy path (consistent with `Write_Memory`), or
2. Add an explicit requirement and safety rationale documenting why the copy path intentionally bypasses protection.

**Severity:** High

### IMPL-02 — `Arm_Protected_Write` does not unarm before re-arming (Medium)

**File:** `component-memory_stuffer-implementation.adb`, `Arm_Protected_Write`

```ada
overriding function Arm_Protected_Write (Self : in out Instance; Arg : in Packed_Arm_Timeout.T) return Command_Execution_Status.E is
   use Command_Execution_Status;
begin
   -- Transition to the armed state with the timeout:
   Self.Command_Arm_State.Arm (New_Timeout => Arg.Timeout);
   ...
```

**Explanation:** Per requirement: "The component shall exit the armed state upon the receipt of any subsequent command (unless it is another arm command)." The parenthetical exception means arm-to-arm is allowed without unarming. However, `Write_Memory` explicitly checks armed state and calls `Do_Unarm`, while `Arm_Protected_Write` directly re-arms. This means a sequence of arm commands resets the timeout without ever producing a `Protected_Write_Disabled` event, which is consistent with the requirement but creates an asymmetry. The test `Test_Arm_Unarm` does verify arm→arm→write works. This is acceptable but worth noting — repeated arm commands silently extend the armed window.

**Severity:** Low (design intent verified by test)

### IMPL-03 — `Write_Memory` reads armed state and then unarms in a non-atomic sequence (Medium)

**File:** `component-memory_stuffer-implementation.adb`, `Write_Memory`

```ada
State : constant Command_Protector_Enums.Armed_State.E := Self.Command_Arm_State.Get_State (Ignore_Timeout);
...
case State is
   when Armed =>
      Do_Unarm (Self);
   when Unarmed =>
      Was_Armed := False;
end case;
```

**Explanation:** The armed state is read via `Get_State` and then acted upon separately via `Do_Unarm`. Although `Command_Arm_State` is a `Protected_Arm_State` (protected object), the get-then-act pattern is not a single atomic operation on the protected object. If the tick handler's `Decrement_Timeout` fires between `Get_State` and `Unarm` (both are on the same active task so this cannot actually happen in the single-queue dispatch model), the state could change. In the current Adamant active component model with a single dispatch queue, this is safe because tick and command are serialized. However, if the architecture ever changes to allow concurrent dispatch, this would become a race condition.

**Corrected:** Consider an atomic `Get_And_Unarm` operation on the protected object for defense-in-depth, or add a comment documenting the serialization assumption.

**Severity:** Medium (latent risk)

### IMPL-04 — `Tick_T_Recv_Async_Dropped` is silently null (Medium)

**File:** `component-memory_stuffer-implementation.ads`

```ada
overriding procedure Tick_T_Recv_Async_Dropped (Self : in out Instance; Arg : in Tick.T) is null;
```

**Explanation:** If a tick is dropped due to a full queue, the armed state timeout will not decrement for that tick period. This means the armed window could silently extend beyond the configured timeout. For safety-critical code, a dropped tick should at minimum produce a warning event so operators know the timeout is unreliable. The same concern applies to `Command_T_Recv_Async_Dropped` (dropped commands are silently lost) and `Memory_Region_Copy_T_Recv_Async_Dropped`.

**Corrected:**
```ada
overriding procedure Tick_T_Recv_Async_Dropped (Self : in out Instance; Arg : in Tick.T) is
begin
   Self.Event_T_Send_If_Connected (Self.Events.Tick_Dropped (Self.Sys_Time_T_Get));
end Tick_T_Recv_Async_Dropped;
```
(Would require adding a new event definition.)

**Severity:** Medium

### IMPL-05 — No validation of `Arg.Length` against `Arg.Data` bounds in `Write_Memory` (High)

**File:** `component-memory_stuffer-implementation.adb`, `Write_Memory`

```ada
Copy_To (Ptr, Arg.Data (Arg.Data'First .. Arg.Data'First + Arg.Length - 1));
```

**Explanation:** The `Arg.Length` field is taken from the command argument and used to slice `Arg.Data`. If `Arg.Length` is larger than `Arg.Data'Length`, this will cause an index out-of-bounds (Constraint_Error) at runtime. While the `Memory_Region_Write.T` type may constrain `Length` to be ≤ `Data'Length` via its packed type definition, there is no explicit guard in this code. In safety-critical software, defense-in-depth requires an explicit check before performing the slice, especially since the value comes from an external command.

**Corrected:**
```ada
if Arg.Length > Arg.Data'Length then
   Self.Event_T_Send_If_Connected (Self.Events.Invalid_Memory_Region (Self.Sys_Time_T_Get, Region));
   return Failure;
end if;
Copy_To (Ptr, Arg.Data (Arg.Data'First .. Arg.Data'First + Arg.Length - 1));
```

**Severity:** High

---

## 4. Unit Test Review

### TEST-01 — Tests rely on shared mutable state across test cases (Medium)

**File:** `test/memory_stuffer_tests-implementation.adb`

```ada
Region_1 : aliased Basic_Types.Byte_Array := [1, 2, 3, 4, 5, 6, 7, 8, 9, 10];
Region_2 : aliased Basic_Types.Byte_Array := [98, 97, 96, 95, ...];
```

**Explanation:** `Region_1` and `Region_2` are package-level mutable variables shared across all tests. Tests execute sequentially via AUnit, and later tests depend on memory state left by earlier tests. For example, `Test_Protected_Stuffing` expects `Region_2` to contain `[254, 254, ...]` which was written by `Test_Unprotected_Stuffing`. If test execution order changes or a test is run in isolation, it will fail. `Test_Memory_Region_Copy` and `Test_Memory_Region_Copy_Invalid_Address` correctly reset regions at the start, but the other tests do not.

**Corrected:** Each test should reset `Region_1` and `Region_2` to known values at the beginning (as the copy tests already do).

**Severity:** Medium

### TEST-02 — No test for zero-timeout arm command (Low)

**File:** `test/memory_stuffer_tests-implementation.adb`

**Explanation:** All arm tests use `Timeout => 2`. There is no test for `Timeout => 0` which would test the edge case of an immediately-expiring arm. The `Test_Arm_Timeout` test decrements the timeout via ticks but never tests what happens if the initial timeout is zero.

**Severity:** Low

### TEST-03 — No test for `Memory_Region_Copy` to a protected region (Medium)

**File:** `test/memory_stuffer_tests-implementation.adb`

**Explanation:** `Test_Memory_Region_Copy` initializes with `null` protection list (all unprotected). There is no test that verifies memory copy behavior when the destination is a protected region. This is directly related to IMPL-01 — the bypass is not tested with protection enabled, so if protection checking were added to the copy path, no test would catch regressions.

**Corrected:** Add a test case that initializes with `Protection_List'Access` and attempts a copy to a protected region, verifying whether it succeeds or is rejected (depending on the resolution of IMPL-01).

**Severity:** Medium

### TEST-04 — `Test_Invalid_Command` does not call `Init` (Low)

**File:** `test/memory_stuffer_tests-implementation.adb`, `Test_Invalid_Command`

**Explanation:** `Test_Invalid_Command` never calls `T.Component_Instance.Init(...)`. It relies on state from prior tests (specifically the Init from `Test_Invalid_Address`). This compounds the TEST-01 ordering dependency issue.

**Corrected:** Add `T.Component_Instance.Init (Regions'Access, Protection_List'Access);` at the start of the test.

**Severity:** Low

### TEST-05 — `Test_Invalid_Initialization` test name is misleading (Low)

**File:** `test/memory_stuffer.tests.yaml`

```yaml
  - name: Test_Invalid_Initialization
    description: This unit test makes sure that an invalid initialization results in a runtime assertion.
```

**Explanation:** The test actually exercises both valid and invalid initialization scenarios, as well as `Set_Up`. The name suggests only invalid cases are tested.

**Severity:** Low

---

## 5. Summary — Top 5 Issues

| # | ID | Severity | Summary |
|---|-----|----------|---------|
| 1 | IMPL-01 | **High** | Memory copy bypasses protected region checks — unprotected "backdoor" write path to protected memory with no requirement or safety justification. |
| 2 | IMPL-05 | **High** | No explicit validation of `Arg.Length` against `Arg.Data` array bounds before slicing in `Write_Memory` — potential Constraint_Error from external command input. |
| 3 | DOC-02 | **Medium** | Memory copy feature (copy, destination validation, release) has no traceability to any requirement. |
| 4 | IMPL-04 | **Medium** | Dropped tick/command/copy messages are silently ignored (`is null`), which can extend the armed timeout window without any indication to operators. |
| 5 | TEST-01 | **Medium** | Unit tests share mutable package-level memory regions and depend on execution order; most tests do not reset state, making them fragile and non-independent. |

## Resolution Notes

| # | Issue | Severity | Status | Commit | Notes |
|---|-------|----------|--------|--------|-------|
| 1 | Memory copy bypasses region checks | High | Fixed | - | Added protected region checking |
| 2 | No length guard on Write_Memory | High | Fixed | - | Added bounds check |
| 3 | No copy requirements | Medium | Fixed | - | Added 4 requirements |
| 4 | Get-then-unarm race | Medium | Fixed | - | Documented safety assumption |
| 5 | Null dropped handlers | Medium | Fixed | - | Added event YAML (needs regen) |
| 6 | Test state sharing | Medium | Fixed | - | Added resets |
| 7 | No copy-to-protected test | Medium | Fixed | - | Added test |
| 8-15 | Low items | Low | Mixed | - | Doc cleanup, tests, comments |

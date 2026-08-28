# Code Review: `Seq.Engine` Package

**Package:** `src/components/command_sequencer/seq/engine`
**Files:** `seq.ads`, `seq.adb`
**Reviewer:** Automated Ada Code Review
**Date:** 2026-02-28

---

## 1. Package Specification Review

### 1.1 — `Get_Stack_Depth` return type inconsistent with semantic meaning

- **Location:** `seq.ads`, line ~55
- **Original Code:**
  ```ada
  function Get_Stack_Depth (Self : in Engine) return Max_Seq_Num;
  ```
- **Explanation:** `Get_Stack_Depth` returns the *allocated length* of the stack, which represents a count/depth. The return type is `Max_Seq_Num`, which is an index type used elsewhere for stack indexing (e.g., `Get_Stack_Level`, the `Index` parameters). Using the same type for both a count and an index is error-prone: if `Max_Seq_Num` is zero-based, a depth of N means valid indices are 0..N-1, but callers comparing `Get_Stack_Level <= Get_Stack_Depth` (as in the `Load` precondition) may be off-by-one. The `Load` precondition `Self.Get_Stack_Level <= Self.Get_Stack_Depth` should likely be `Self.Get_Stack_Level < Self.Get_Stack_Depth` or use `Stack_Depth_Type` for the return.
- **Corrected Code:**
  ```ada
  function Get_Stack_Depth (Self : in Engine) return Stack_Depth_Type;
  ```
  Or fix the precondition:
  ```ada
  Pre => (... and then Self.Get_Stack_Level < Self.Get_Stack_Depth),
  ```
- **Severity:** **Medium**

### 1.2 — `Set_Engine_Error` lacks precondition guard

- **Location:** `seq.ads`, line ~47
- **Original Code:**
  ```ada
  procedure Set_Engine_Error (Self : in out Engine; Error_Code : in Seq_Error.E);
  ```
- **Explanation:** Unlike nearly every other subprogram, `Set_Engine_Error` has no precondition. It accesses `Self.Stack.all(Self.Current)` in the body, which will dereference null if called on an uninitialized engine. A precondition of `Self.Get_Engine_State /= Uninitialized` should be added for consistency, even though the body has a null check on `Self.Stack`. The null check protects the `Force_Error` call but still sets `Self.State := Engine_Error` on an uninitialized engine, corrupting state.
- **Corrected Code:**
  ```ada
  procedure Set_Engine_Error (Self : in out Engine; Error_Code : in Seq_Error.E) with
     Pre => (Self.Get_Engine_State /= Uninitialized);
  ```
- **Severity:** **High**

### 1.3 — `Get_Stack_Depth` missing precondition (inconsistent with peers)

- **Location:** `seq.ads`, line ~55
- **Original Code:**
  ```ada
  function Get_Stack_Depth (Self : in Engine) return Max_Seq_Num;
  ```
- **Explanation:** This function has no precondition while most other getters require `Get_Engine_State /= Uninitialized`. While the body has a null guard, the lack of a contract is inconsistent with the package's defensive style and may confuse callers about expected usage.
- **Corrected Code:**
  ```ada
  function Get_Stack_Depth (Self : in Engine) return Max_Seq_Num with
     Pre => (Self.Get_Engine_State /= Uninitialized);
  ```
  Or document that returning 0 for uninitialized engines is intentional.
- **Severity:** **Low**

### 1.4 — Index-taking functions lack bounds preconditions

- **Location:** `seq.ads`, multiple functions (e.g., `Get_Sequence_Header`, `Get_Sequence_State`, `Get_Sequence_Region`, `Get_Sequence_Position`, `Get_Sequence_Start_Time`, `Get_Sequence_Last_Executed_Time`, `Get_Sequence_Telemetry_Wait_Start_Time`)
- **Original Code (representative):**
  ```ada
  function Get_Sequence_Header (Self : in Engine; Index : in Max_Seq_Num) return Sequence_Header.T;
  ```
- **Explanation:** These functions accept an arbitrary `Max_Seq_Num` index and directly index into `Self.Stack.all(Index)` without any precondition ensuring `Index` is within the allocated stack bounds or that the stack is non-null. In a safety-critical system, an out-of-bounds index will raise `Constraint_Error` at best, or cause memory corruption with suppressed checks.
- **Corrected Code:**
  ```ada
  function Get_Sequence_Header (Self : in Engine; Index : in Max_Seq_Num) return Sequence_Header.T with
     Pre => (Self.Get_Engine_State /= Uninitialized and then
             Index <= Self.Get_Stack_Level);
  ```
- **Severity:** **Critical**

### 1.5 — `Is_Done_Waiting` is a function with side effects

- **Location:** `seq.ads`, line ~127
- **Original Code:**
  ```ada
  function Is_Done_Waiting (Self : in out Engine; Current_Time : in Sys_Time.T) return Done_Waiting_Status with
     Pre => (Self.Get_Engine_State = Waiting);
  ```
- **Explanation:** This is declared as a function (returns a value) but takes `Self` as `in out`, meaning it modifies engine state (transitions from `Waiting` to `Active`). While Ada 2012 allows `in out` on functions, in safety-critical code this is a surprising side-effect in a function named with an interrogative ("Is_Done_Waiting"). Consider making this a procedure with an out parameter, or documenting the state-transition side effect prominently.
- **Corrected Code (option — procedure form):**
  ```ada
  procedure Check_Done_Waiting (Self : in out Engine; Current_Time : in Sys_Time.T; Status : out Done_Waiting_Status) with
     Pre => (Self.Get_Engine_State = Waiting);
  ```
- **Severity:** **Low**

---

## 2. Package Implementation Review

### 2.1 — `Initialize`: Stack allocation overflow with `Stack_Depth = 0`

- **Location:** `seq.adb`, line ~8
- **Original Code:**
  ```ada
  procedure Initialize (Self : in out Engine; Stack_Depth : in Stack_Depth_Type; Engine_Id : in Sequence_Engine_Id) is
  begin
     pragma Assert (Stack_Depth < 255, "GNAT SAS points out that 255 can break things.");
     Self.Stack := new Seq_Array (Max_Seq_Num'First .. Max_Seq_Num'First + Stack_Depth - 1);
  ```
- **Explanation:** If `Stack_Depth_Type` allows a value of 0, then `Max_Seq_Num'First + 0 - 1` underflows the index range (assuming `Max_Seq_Num'First = 0`, this produces `0 .. -1` which is a null range — benign in Ada). However, the engine would then have no stack entries and any subsequent `Load` or `Execute` would index into a zero-length array. There is no guard against `Stack_Depth = 0`. The `pragma Assert` only checks `< 255`, not `> 0`.
- **Corrected Code:**
  ```ada
  pragma Assert (Stack_Depth > 0 and then Stack_Depth < 255,
                 "Stack depth must be between 1 and 254.");
  ```
- **Severity:** **High**

### 2.2 — `Commands_Sent` wraps silently on overflow

- **Location:** `seq.adb`, `Execute` function, `Wait_Command` branch
- **Original Code:**
  ```ada
  when Seq_Runtime_State.Wait_Command =>
     Self.Last_Command_Id := Self.Stack.all (Self.Current).Get_Command_Id;
     Self.Commands_Sent := @ + 1;
  ```
- **Explanation:** `Commands_Sent` is `Interfaces.Unsigned_16`, which wraps at 65535 → 0 silently (modular arithmetic). In a safety-critical flight system, silent counter wrap-around could mask anomalies. If the counter is used for telemetry or diagnostics, wrap-around should either be documented as acceptable or a saturation strategy should be used.
- **Corrected Code:**
  ```ada
  if Self.Commands_Sent < Interfaces.Unsigned_16'Last then
     Self.Commands_Sent := @ + 1;
  end if;
  ```
- **Severity:** **Medium**

### 2.3 — Recursive call in `Execute` may exhaust the runtime stack

- **Location:** `seq.adb`, `Execute` function, `Done` branch
- **Original Code:**
  ```ada
  when Seq_Runtime_State.Done =>
     if Self.Current > Self.Stack.all'First then
        ...
        Self.Current := @ - 1;
        return Self.Execute (Instruction_Limit, Timestamp);
     else
  ```
- **Explanation:** When a child sequence finishes, `Execute` calls itself recursively. If a child sequence finishes immediately (e.g., empty or trivial sequences), the recursion will chain: depth N calls Execute, child is done → depth N-1 calls Execute, child is done → ... This creates up to `Stack_Depth` levels of Ada runtime stack recursion. Worse, within each recursive call, the next sequence could run up to `Instruction_Limit` instructions before returning, so the Ada call stack accumulates. In embedded/safety-critical systems with limited stack space, this is risky. An iterative loop would be safer.
- **Corrected Code (sketch):**
  ```ada
  -- Replace the recursive call with a loop in Execute:
  loop
     Runtime_State := Self.Stack.all (Self.Current).Execute_Sequence (...);
     case Runtime_State is
        when Done =>
           if Self.Current > Self.Stack.all'First then
              -- pop stack, continue loop
              ...
           else
              Self.Reset;
              return Self.Last_Execute_State;
           end if;
        when others =>
           -- handle other states and return
           ...
     end case;
  end loop;
  ```
- **Severity:** **High**

### 2.4 — `Execute` does not set `Self.State` for most non-waiting states

- **Location:** `seq.adb`, `Execute` function, branches for `Wait_Command`, `Wait_Telemetry_Set`, `Wait_Telemetry_Value`, `Kill_Engine`, `Print`, etc.
- **Original Code (representative):**
  ```ada
  when Seq_Runtime_State.Wait_Command =>
     Self.Last_Command_Id := Self.Stack.all (Self.Current).Get_Command_Id;
     Self.Commands_Sent := @ + 1;
     Self.Last_Execute_State := Seq_Execute_State.Wait_Command;
     return Self.Last_Execute_State;
  ```
- **Explanation:** Only `Wait_Relative`, `Wait_Absolute`, and `Error` branches update `Self.State`. For all other blocking states (`Wait_Command`, `Wait_Telemetry_*`, `Kill_Engine`, `Print`, `Wait_Load_Seq`), the engine's `State` remains `Active` even though the engine is blocked. This means `Get_Engine_State` will return `Active` when the engine is actually waiting for a command, telemetry, etc. Callers relying on `Get_Engine_State` to determine the engine's condition will get misleading information. The `Last_Execute_State` is set, but these are two separate state fields with divergent semantics — a maintenance hazard.
- **Corrected Code:** Either set `Self.State` consistently in all branches, or document that `Get_Engine_State` returns coarse state and `Get_Last_Execute_State` should be used for fine-grained status.
- **Severity:** **Medium**

### 2.5 — `Load` dereferences `Self.Stack` without null check

- **Location:** `seq.adb`, `Load` function, first line of body
- **Original Code:**
  ```ada
  function Load (Self : in out Engine; Sequence_Region : in Memory_Region.T) return Load_Status is
     Load_State : Seq_Runtime.Load_State_Type;
  begin
     if Self.Stack.all (Self.Current).Get_State = Seq_Runtime_State.Wait_Load_New_Sub_Seq then
  ```
- **Explanation:** The precondition ensures `Get_Engine_State /= Uninitialized`, and `Finish_Initialization` sets state to `Inactive` only when both `Initialized` and `Source_Id_Set` are true (which implies `Stack /= null`). So this is *logically* safe. However, the contract chain is indirect — the body relies on an invariant (state /= Uninitialized ⟹ Stack /= null) that is not formally expressed. A defensive null check or a stronger type invariant would add resilience against future refactoring errors.
- **Severity:** **Low**

### 2.6 — `Destroy` calls `Reset` which may operate on partially valid state

- **Location:** `seq.adb`, `Destroy` procedure
- **Original Code:**
  ```ada
  procedure Destroy (Self : in out Engine) is
     ...
  begin
     Self.Reset;
     Free (Self.Stack);
     Self.Stack := null;
     Self.Initialized := False;
     Self.Source_Id_Set := False;
     Self.State := Uninitialized;
  end Destroy;
  ```
- **Explanation:** After `Reset`, `Self.State` will be `Inactive` (if previously initialized) or `Uninitialized`. Then `Destroy` sets `Self.State := Uninitialized` again redundantly. More concerning: `Destroy` sets `Self.Initialized := False` and `Self.Source_Id_Set := False` *after* freeing the stack. If `Destroy` were called on an already-uninitialized engine, `Reset` would iterate over a null stack (but `Reset` has a null check, so this is safe). The post-condition says `Get_Engine_State = Uninitialized` which is satisfied. This is structurally sound but the redundant state manipulation suggests the Reset/Destroy interaction could be simplified.
- **Severity:** **Low**

---

## 3. Model Review

No model files (`.record_model.yaml`, `.assembly_model.yaml`, etc.) exist in this package directory. This is consistent with the package being a pure Ada implementation package with no auto-generated types. **No issues.**

---

## 4. Unit Test Review

No unit test files exist in this package directory or a `test/` subdirectory. Testing is likely performed at a higher level (the `command_sequencer` component level). However, for a safety-critical sequence engine with complex state machine logic, stack management, and recursive execution, **dedicated unit tests for the `Seq.Engine` package would significantly improve confidence**. Key areas lacking coverage:

- Stack overflow behavior (loading beyond depth)
- `Stack_Depth = 0` initialization
- Recursive `Execute` unwinding across multiple stack levels
- `Set_Engine_Error` on boundary conditions
- `Commands_Sent` counter wrap-around
- Index-based getter functions with out-of-range indices

**Severity:** **Medium** (absence of local unit tests for a complex state machine)

---

## 5. Summary — Top 5 Issues

| # | Severity | Location | Issue |
|---|----------|----------|-------|
| 1 | **Critical** | `seq.ads` — Index-taking functions | No precondition bounds-checking on `Index` parameter for 7+ getter functions. Out-of-bounds access will cause `Constraint_Error` or memory corruption with checks suppressed. |
| 2 | **High** | `seq.adb` — `Execute`, `Done` branch | Recursive call to `Self.Execute` risks Ada runtime stack exhaustion on embedded targets with deep sequence call stacks. Should be iterative. |
| 3 | **High** | `seq.adb` — `Initialize` | No guard against `Stack_Depth = 0`, which creates a zero-length stack array. All subsequent operations will fail. |
| 4 | **High** | `seq.ads` — `Set_Engine_Error` | Missing precondition allows call on uninitialized engine; corrupts state by setting `Engine_Error` on an engine that was never initialized. |
| 5 | **Medium** | `seq.adb` — `Execute` state management | `Self.State` is not updated in most `Execute` branches, causing `Get_Engine_State` to return `Active` when the engine is actually blocked on commands, telemetry, loads, or prints. |

## Resolution Notes

| # | Issue | Severity | Status | Commit | Notes |
|---|-------|----------|--------|--------|-------|
| 1 | Missing index bounds preconditions | Critical | Fixed | ca42d55 | Added to 7 getters |
| 2 | Set_Engine_Error no precondition | High | Fixed | 432bcb6 | Added guard |
| 3 | Stack_Depth=0 not guarded | High | Fixed | a0e7a24 | Added Initialize guard |
| 4 | Recursive Execute | High | Fixed | 9d29b23 | Converted to iterative loop |
| 5 | Off-by-one in stack depth check | Medium | Fixed | 771da4a | <= changed to < |
| 6 | Commands_Sent overflow | Medium | Fixed | fd865ef | Saturating increment |
| 7 | State not updated in blocking branches | Medium | Fixed | f1b5038 | Set Waiting state |
| 8 | No unit tests | Medium | Not Fixed | 549cc49 | Needs separate effort |
| 9 | Get_Stack_Depth precondition | Low | Fixed | 3fa109b | Added |
| 10 | Return type API change | Low | Not Fixed | e340d1f | Would break callers |
| 11 | Null check in Load | Low | Fixed | f818104 | Added pragma Assert |
| 12 | Structural concern | Low | Not Fixed | 416a4fb | Code is sound |

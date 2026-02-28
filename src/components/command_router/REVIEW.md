# Command Router Component — Code Review

**Reviewer:** Automated Expert Review  
**Date:** 2026-02-28  
**Branch:** `review/components-command-router`

---

## 1. Documentation Review

The component description in `command_router.component.yaml` is thorough and well-written. It explains the routing mechanism, registration process, command response forwarding, and NOOP self-test pattern clearly. The connector descriptions are detailed and the init parameter is well-documented.

**No documentation issues found.**

---

## 2. Model Review

### Issue M-1: `Command_T_To_Route_Recv_Sync` Race Condition Warning is Documentation-Only

**Location:** `command_router.component.yaml`, `Command_T_To_Route_Recv_Sync` connector description  
**Severity:** Low  

The sync connector description warns about a race condition if called before registration completes, but there is no runtime guard or assertion to enforce this. The protection is purely by convention.

**Original:**
```yaml
- description: "...It should only be called after command registration has occurred, or a race condition is present."
```

**Explanation:** In safety-critical systems, relying on documentation-only guards for race conditions is fragile. A runtime assertion or state check (e.g., a `Registration_Complete` flag set after `Set_Up`) would provide defense-in-depth.

**Suggested Enhancement (in implementation):**
```ada
pragma Assert (Self.Registration_Complete,
   "Command_T_To_Route_Recv_Sync called before registration completed");
```

---

## 3. Component Implementation Review

### Issue I-1: `Command_Success_Count` Lacks Thread Protection (Critical)

**Location:** `component-command_router-implementation.ads`, lines in private section  
**Severity:** **Critical**

`Command_Receive_Count` and `Command_Failure_Count` use `Protected_U16_Counter` (a protected object), but `Command_Success_Count` is a bare `Interfaces.Unsigned_16`. The `Command_T_To_Route_Recv_Sync` connector is declared `recv_sync`, meaning it can be called from a different task context than the async handler. Both the sync path and the async `Command_Response_T_Recv_Async` handler can be active concurrently. The success count is incremented in `Command_Response_T_Recv_Async`, while the sync path triggers commands that eventually produce responses processed on the async queue — but if multiple tasks call the sync connector while responses are being processed, concurrent reads/writes to `Command_Success_Count` are possible without protection.

**Original:**
```ada
Command_Receive_Count : Protected_U16_Counter.Counter;
Command_Failure_Count : Protected_U16_Counter.Counter;
Command_Success_Count : Interfaces.Unsigned_16 := 0;
```

**Explanation:** `Command_Success_Count` is modified in `Command_Response_T_Recv_Async` (the async task's handler), and this handler can also be invoked synchronously via `Command_Response_T_Recv_Async_Dropped` and `Command_T_Send_Dropped`. If `Command_T_To_Route_Recv_Sync` triggers a dropped command path that synchronously calls `Command_Response_T_Recv_Async`, then the success count could be accessed from the sync caller's task while the async task is also processing responses. All three counters should have the same protection level.

**Corrected:**
```ada
Command_Receive_Count : Protected_U16_Counter.Counter;
Command_Failure_Count : Protected_U16_Counter.Counter;
Command_Success_Count : Protected_U16_Counter.Counter;
```

And update all usages in the body accordingly (use `.Increment_Count` / `.Get_Count` / `.Set_Count` instead of direct `:= @ + 1`).

---

### Issue I-2: Unsigned_16 Counter Overflow Without Saturation (High)

**Location:** `component-command_router-implementation.adb`, multiple locations in `Command_T_To_Route_Recv_Sync` and `Command_Response_T_Recv_Async`  
**Severity:** **High**

The counters (`Command_Receive_Count`, `Command_Success_Count`, `Command_Failure_Count`) are 16-bit unsigned integers. On a long-duration mission, these will silently wrap around from 65535 to 0. The data products (`Packed_U16.T`) will report incorrect counts after overflow.

**Original (example):**
```ada
Self.Command_Receive_Count.Increment_Count;
```
and:
```ada
Self.Command_Success_Count := @ + 1;
```

**Explanation:** In safety-critical flight software, silent counter wrap-around can cause misleading telemetry. Counters should either saturate at `Unsigned_16'Last` or the overflow should be explicitly documented as acceptable behavior.

**Suggested Fix:** Use saturating increment:
```ada
if Self.Command_Success_Count < Interfaces.Unsigned_16'Last then
   Self.Command_Success_Count := @ + 1;
end if;
```

Or document the wrap-around as intentional if operationally acceptable.

---

### Issue I-3: `Command_T_To_Route_Recv_Sync` Uses Non-Protected `Command_T_Send` (Medium)

**Location:** `component-command_router-implementation.adb`, `Command_T_To_Route_Recv_Sync` procedure  
**Severity:** **Medium**

```ada
Self.Command_T_Send (Command_T_Send_Index (Send_Index), Arg);
```

The sync connector can be called from any task. `Command_T_Send` on an async connector enqueues a message. If the framework's generated `Command_T_Send` is itself task-safe this is fine, but the dropped handler `Command_T_Send_Dropped` then synchronously calls `Self.Command_Response_T_Recv_Async`, which modifies component state (counters, events). This creates a re-entrant call path where the sync caller's task executes `Command_Response_T_Recv_Async` logic that is normally exclusive to the component's own task.

**Explanation:** The `Command_T_Send_Dropped` handler directly calls `Self.Command_Response_T_Recv_Async(...)`, which modifies `Command_Failure_Count` (protected) and sends events. While `Command_Failure_Count` is protected, the event sends and data product sends in that path may not be thread-safe if the framework assumes single-task access for `_Send_If_Connected` calls.

**Recommendation:** Review whether the Adamant framework's generated send connectors are thread-safe. If not, the dropped handler's synchronous call to `Command_Response_T_Recv_Async` needs synchronization or should be restructured to enqueue the response instead.

---

### Issue I-4: `Set_Up` Does Not Guard Against Unconnected Forward Connectors (Medium)

**Location:** `component-command_router-implementation.adb`, `Set_Up` procedure, source ID registration loop  
**Severity:** **Medium**

**Original:**
```ada
for Index in Self.Connector_Command_Response_T_To_Forward_Send'Range loop
   Self.Command_Response_T_To_Forward_Send (Command_Response_T_To_Forward_Send_Index (Index), (
      Source_Id => Command_Source_Id (Index),
      Registration_Id => 0,
      Command_Id => 0,
      Status => Register_Source
   ));
end loop;
```

**Explanation:** Unlike the command registration loop above it (which checks `Is_Command_T_Send_Connected`), the source ID registration loop does **not** check if the forward send connector at `Index` is connected before sending. If an index is unconnected, this will either raise an exception or silently fail depending on the framework. The pattern should be consistent with the command send loop.

**Corrected:**
```ada
for Index in Self.Connector_Command_Response_T_To_Forward_Send'Range loop
   if Self.Is_Command_Response_T_To_Forward_Send_Connected (Command_Response_T_To_Forward_Send_Index (Index)) then
      Self.Command_Response_T_To_Forward_Send (Command_Response_T_To_Forward_Send_Index (Index), (
         Source_Id => Command_Source_Id (Index),
         Registration_Id => 0,
         Command_Id => 0,
         Status => Register_Source
      ));
   end if;
end loop;
```

---

### Issue I-5: `Noop_Response` Calls `Command_T_To_Route_Recv_Sync` Recursively Within the Task (Low)

**Location:** `component-command_router-implementation.adb`, `Noop_Response` function  
**Severity:** Low

**Original:**
```ada
overriding function Noop_Response (Self : in out Instance) return Command_Execution_Status.E is
begin
   Self.Event_T_Send_If_Connected (Self.Events.Noop_Response_Received (Self.Sys_Time_T_Get));
   Self.Command_T_To_Route_Recv_Sync (Self.Commands.Noop);
   return Success;
end Noop_Response;
```

**Explanation:** This is a self-call within the component's own task context. `Noop_Response` is executing as a command handler (dispatched from the queue), and it synchronously calls `Command_T_To_Route_Recv_Sync`, which modifies counters and sends data products/events. This is re-entrant with respect to the component's state. It works because Ada's tasking model allows a task to call its own operations, but it creates a deep call chain and couples the NOOP self-test to the synchronous routing path. This is by design and documented, but worth noting for maintainers.

---

## 4. Unit Test Review

### Issue T-1: Router Table Test Uses Command_Id = 0 Which Is Filtered in Production (Medium)

**Location:** `router_table/test/router_table_tests-implementation.adb`, `Add_To_Table`  
**Severity:** **Medium**

**Original:**
```ada
Status_Assert.Eq (Self.Table.Add ((Registration_Id => 19, Command_Id => 0)), Router_Table.Success);
```

**Explanation:** In the actual component, `Register_Command` explicitly filters out `Command_Id = 0` ("We only want to register commands that have ID > 0 since an ID of zero is the special internal register command"). The router table unit test inserts entries with `Command_Id => 0`, which would never happen in production. While the table itself has no such restriction, this test does not reflect real usage and could mask integration issues. A test with only production-valid IDs (> 0) would be more representative.

---

### Issue T-2: No Test for Counter Wrap-Around Behavior (Low)

**Location:** `test/command_router_tests-implementation.adb`  
**Severity:** Low

There is no test that exercises the behavior of the 16-bit counters near `Unsigned_16'Last`. Given the overflow concern in I-2, a test verifying the expected behavior at boundary values would be valuable.

---

### Issue T-3: No Test for `Final` / Cleanup (Low)

**Location:** `test/command_router_tests-implementation.adb`, `Tear_Down_Test`  
**Severity:** Low

`Tear_Down_Test` calls `Final_Base` then `Final`, but there is no explicit test that exercises `Final` (heap deallocation) correctness, double-free protection, or use-after-free scenarios. For flight software, memory management tests are valuable.

---

## 5. Summary — Top 5 Issues

| # | ID | Severity | Summary |
|---|-----|----------|---------|
| 1 | I-1 | **Critical** | `Command_Success_Count` is unprotected bare `Unsigned_16` while other counters use protected objects. Potential data race via sync connector path. |
| 2 | I-2 | **High** | All 16-bit counters can silently overflow/wrap on long-duration missions, producing incorrect telemetry. |
| 3 | I-4 | **Medium** | `Set_Up` source-ID registration loop doesn't check connector connectivity, inconsistent with command registration loop. |
| 4 | I-3 | **Medium** | Sync connector dropped-handler path re-enters `Command_Response_T_Recv_Async` from caller's task context — review thread safety of framework send calls. |
| 5 | T-1 | **Medium** | Router table unit test uses `Command_Id => 0` which is filtered in production code, reducing test representativeness. |

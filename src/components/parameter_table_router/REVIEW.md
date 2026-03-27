# Parameter Table Router - Self-Review Findings

Review of all implementation code conducted after initial PR review round.

## Bugs

### 1. Send_And_Wait timeout detection is broken

**File:** `component-parameter_table_router-implementation.adb`, lines 39-43

When a timeout occurs, `Wait_Timed_Out` is True so `Send_And_Wait` returns False. The caller then does `Self.Response.Get_Var` to check if `Status = Success` to distinguish timeout from failure. Problem: on a timeout, the response was never set by the downstream component. `Get_Var` returns whatever stale value was in the protected variable from a previous call. The `case Release.Status is when Success => "must have been a timeout"` logic is fragile -- it works by accident if the previous response happened to be Success. If the previous response was a failure, a timeout would be misreported as `Table_Update_Failure`.

**Fix:** `Send_And_Wait` should return an enum (`Success`, `Timed_Out`, `Failure`) or have a `Timed_Out : out Boolean` parameter, so callers can distinguish the two failure modes without inspecting stale state.

### 2. Load_Single_Table Get region uses wrong length

**File:** `component-parameter_table_router-implementation.adb`, line 141

We call `Self.Staging_Buffer.Get_Table_Region` which returns a region pointing to buffer index 0 with length `Buffer_Index`. But for the Get (load) flow, the buffer may be empty or contain stale data from a previous receive. The downstream Parameter_Store needs a region with the full buffer capacity so it has room to write into. This needs the Parameter_Store fix documented in `parameter_store/TODO_get_length_check.md`, but even with that fix, we are sending a region with length 0 or stale length instead of the full buffer size.

**Fix:** Add a `Get_Full_Buffer_Region` function back to `Parameter_Table_Buffer` (returns buffer address with full capacity as length), or pass `Buffer_Size` directly. Use this for the Get operation instead of `Get_Table_Region`.

### 3. Last_Table_Received DP sent on failed distributions

**File:** `component-parameter_table_router-implementation.adb`, lines 397-402

The `Last_Table_Received` data product is sent even when `Send_Table_To_Destinations` fails. It's inside the `else` (ID found) branch but outside the success check. The DP name is "last table received" not "last table successfully updated", so this may be intentionally correct, but it should be a conscious decision with a comment.

**Fix:** Either move inside the success branch (only report successfully distributed tables) or add a comment clarifying that "received" means "reassembled" regardless of distribution outcome.

## Design Weaknesses

### 4. Duplicated Has_Load_From pattern

The logic to iterate destinations and check for `Load_From` is repeated in `Send_Table_To_Destinations`, `Load_Single_Table`, `Set_Up`, and `Load_All_Parameter_Tables`.

**Fix:** Extract a helper function `Has_Load_From_Destination(Entry) return Boolean`, or better, precompute and cache the Load_From index at Init time in the binary tree entry.

### 5. Duplicated timeout-vs-failure event emission

Lines 64-75, 85-94, 146-154, 172-180 are nearly identical blocks that read the response and emit either a timeout or failure event.

**Fix:** Extract a helper procedure like `Emit_Send_Failure_Event(Self, Id_Param, The_Time)`.

### 6. All four data products sent on every packet

Lines 415-418 send all four counter DPs on every single CCSDS packet received, even if only `Packet_Count` changed. Most packets are `Buffering_Table` which only changes one counter.

**Fix:** Only send DPs for counters that actually changed, or accept the overhead as simplicity trade-off and document the choice.

### 7. No event severity levels

The events YAML does not specify severity. Events like `Table_Update_Failure`, `Table_Update_Timeout`, `Staging_Buffer_Overflow` should probably be warnings. `Packet_Ignored` and `Receiving_New_Table` should be informational.

**Fix:** Add appropriate severity levels to the events YAML once the event severity model is confirmed.

## Code Quality

### 8. Dead comment on line 25

`-- No standalone helper needed...` is a leftover from removing the `Increment_Counter` helper. Should be deleted.

### 9. Search key with null Destinations

Lines 109 and 374 construct a `Router_Table_Entry` with `Destinations => null` solely for binary tree search. This works because the comparison only uses `Table_Id`, but it constructs an entry that violates our own Init assertion (destinations must not be null). Worth a comment explaining why this is safe.

### 10. Zero-length continuation segments silently accepted

`parameter_table_buffer.adb` lines 82-83: A zero-length continuation segment is accepted as `Buffering_Table` without advancing the buffer. This is technically correct (null range assignment is valid Ada) but may warrant either explicit handling or a comment.

### 11. Dropped packets not reflected in counters

`Ccsds_Space_Packet_T_Recv_Async_Dropped` emits `Packet_Dropped` but does not increment `Reject_Count` or `Packet_Count`. Dropped packets are invisible to the data product counters. This is a design choice (counters reflect processed packets only) but should be documented.

## Missing Pieces

### 12. No component unit tests

Only the `Parameter_Table_Buffer` standalone package has unit tests. The component implementation (Init validation, packet reception state machine, send/wait pattern, command handlers, Set_Up loading) is completely untested.

### 13. SPEC.md is stale

The spec describes the old design including CRC checking, Reset method, Buffer_Overflowed flag, and other elements removed during review. It should be updated to reflect the current implementation.

### 14. No bulk load start/completion event

`Load_All_Parameter_Tables` has no event indicating the operation started or completed as a whole. Individual tables emit events, but there is no way to tell from telemetry that the bulk operation was invoked.

# Review Fix Plan

Fixes for findings in REVIEW.md, prioritized by severity.

## Fix #1: Send_And_Wait timeout detection

**Problem:** Caller inspects stale `Self.Response.Get_Var` to distinguish timeout from failure.

**Fix:** Follow the Parameter Manager pattern exactly:
- Split into two functions: `Wait_For_Response` and `Send_And_Wait`
- `Wait_For_Response` handles timeout vs failure internally:
  - On timeout: emits `Table_Update_Timeout` event, returns False
  - On failure: emits `Table_Update_Failure` event, returns False
  - On success: returns True
- `Send_And_Wait` does: Reset sync object, send, call `Wait_For_Response`
- Both take `Table_Id_Param` and `The_Time` for event emission
- Callers never inspect `Self.Response.Get_Var` directly — only `Parameters_Memory_Region_Release_T_Recv_Sync` sets it

**Impact:** `Send_Table_To_Destinations` and `Load_Single_Table` become much simpler — all the duplicated timeout/failure case blocks are eliminated (fixes #5 too).

## Fix #2: Load_Single_Table Get region

**Problem:** Uses `Get_Table_Region` (stale length) instead of full buffer capacity.

**Fix:** Re-add `Get_Full_Buffer_Region` to `Parameter_Table_Buffer`:
```ada
function Get_Full_Buffer_Region (Self : in Instance) return Memory_Region.T;
-- Returns (Address => Buffer(0)'Address, Length => Buffer.all'Length)
```
Use this in `Load_Single_Table` for the Get operation.

## Fix #3: Richer Last_Table_Received data product

**Problem:** DP lacks status information and in-progress visibility.

**Fix:**
1. Create `types/parameter_table_router_enums.enums.yaml` with status enum:
   - `Idle`, `Receiving_Table`, `Complete_Table`, `Table_Updated`, `Table_Update_Failed`, `Unrecognized_Id`, `Buffer_Overflow`, `Too_Small`, `Packet_Ignored`
2. Update `types/parameter_table_received_info.record.yaml` to include:
   - `Status` (the enum above)
   - `Bytes_Received` (Unsigned_32 — current Buffer_Index from staging buffer)
   - `Packets_Received` (Unsigned_32 — count of packets for current table)
3. Add `Current_Table_Packet_Count : Interfaces.Unsigned_32` to the component instance record, reset to 0 on each FirstSegment
4. Send `Last_Table_Received` DP in the "update data products at end of handler" block on every packet with current status

## Fix #4: Extract Has_Load_From helper

**Problem:** Duplicated iteration pattern in 4 places.

**Fix:** Add a helper function:
```ada
function Find_Load_From_Index (
   Destinations : in Destination_Table_Access;
   Index : out Connector_Types.Connector_Index_Type
) return Boolean;
```
Returns True if a Load_From destination exists, with its connector index in the out parameter. Use in `Send_Table_To_Destinations`, `Load_Single_Table`, `Set_Up`, `Load_All_Parameter_Tables`.

## Fix #5: Extract failure event emission

Resolved by Fix #1 — `Wait_For_Response` handles all event emission internally.

## Fix #6: Send DPs only when changed

**Problem:** All four counter DPs sent on every packet.

**Fix:** Send each counter DP immediately after incrementing it. Remove the "update all DPs at end of handler" block. `Last_Table_Received` DP is sent at end of handler since it always changes (includes status and bytes_received).

## Fix #8: Remove dead comment

**Fix:** Delete the `-- No standalone helper needed...` comment on line 25.

## Fix #9: Comment null-destinations search key

**Fix:** Add comment above the search key construction:
```ada
-- Construct a search key with only Table_Id populated. Destinations is null
-- here which would fail the Init assertion, but the binary tree comparison
-- only uses Table_Id so this is safe for searching:
```

## Fix #11: Protected reject counter for dropped packets

**Problem:** `Ccsds_Space_Packet_T_Recv_Async_Dropped` is called from the sender's context, not the component's task. Incrementing `Self.Reject_Count` from this context is a data race.

**Fix:**
- Instantiate `Protected_Variables.Generic_Protected_Counter` with `Interfaces.Unsigned_32` for the reject counter
- Change `Reject_Count` in the instance record from `Interfaces.Unsigned_32` to the protected counter type
- `Ccsds_Space_Packet_T_Recv_Async_Dropped` calls `Self.Reject_Count.Increment_Count`
- All other reads use `Self.Reject_Count.Get_Count`

## Fix #14: Bulk load start/completion events

**Fix:** Add two new events to the events YAML:
- `Loading_All_Parameter_Tables` — emitted at start of `Load_All_Parameter_Tables` (no param)
- `All_Parameter_Tables_Loaded` — emitted on completion (no param)
Emit in both the command handler and the `Set_Up` path.

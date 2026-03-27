# Parameter Table Router - Component Unit Test Plan

## Infrastructure

### Routing Table

Use the autocoded table from `test/test_assembly/` (`Test_Assembly_Parameter_Table_Router_Table.Router_Table_Entries`) as the primary routing table for all tests. The YAML covers:

- **Table ID 10**: Working_Params (idx 1) + Primary_Param_Store (idx 2, Load_From=True) — multi-dest with load_from
- **Table ID 1** (Test_Parameter_Table): Another_Params (idx 3) + Primary_Param_Store (idx 2, Load_From=True) — name resolution + load_from
- **Table ID 3**: Working_Params (idx 1) + Another_Params (idx 3) + Primary_Param_Store (idx 2, Load_From=True) — 3 destinations with load_from
- **Table ID 4**: Multi_Connector_Dest.specific_connector (idx 5) — dot-notation, single dest, no load_from

Table ID 4 (no load_from) is used to test the `No_Load_Source` command failure path.

Hand-crafted routing tables are only used for Init assertion edge cases (null destinations, out-of-range indexes, duplicate IDs).

### Simulator Task

A background task (same pattern as `parameter_manager` tests in ema-gnc-fsw) controlled by global variables:

- `Task_Response_Status : Parameter_Table_Update_Status.E` — what status to return
- `Task_Send_Response : Boolean` — flag to trigger a release response
- `Task_Send_Timeout : Boolean` — flag to send timeout ticks instead of response
- `Task_Exit : Boolean` — flag to terminate the task

The simulator:
- Polls flags every ~5ms
- When `Task_Send_Response` is True: sends `Parameters_Memory_Region_Release_T` with the configured status, clears the flag
- When `Task_Send_Timeout` is True: sends timeout ticks via `T.Timeout_Tick_Send`, clears after enough ticks to exceed the timeout limit
- Runs in a loop until `Task_Exit` is set

### CCSDS Packet Helpers

Helper functions to construct `Ccsds_Space_Packet.T` with:
- Correct `Packet_Length` (data length - 1 per CCSDS convention)
- Configurable `Sequence_Flag` (Firstsegment, Continuationsegment, Lastsegment, Unsegmented)
- Data payload: `[Table_ID_MSB, Table_ID_LSB, payload...]` for FirstSegment/Unsegmented

### Test Lifecycle

Each test:
1. `Set_Up_Test`: Reset globals, Init_Base tester with queue size and arrayed send count, Connect, Init component with autocoded table + buffer size + timeout, start simulator task
2. `Tear_Down_Test`: Set Task_Exit, call Final, Final_Base

## Test Cases

### Init and Set_Up

| Test | Description |
|------|-------------|
| `Test_Init` | Verify Init populates binary tree, creates staging buffer. White-box check tree size matches table entries. |
| `Test_Set_Up` | Verify Set_Up publishes all 5 initial DPs (counters at zero, Last_Table_Received with Table_Update_Success). |
| `Test_Set_Up_Load_All` | Init with `Load_All_Parameter_Tables_On_Set_Up => True`. Verify Loading_All_Parameter_Tables and All_Parameter_Tables_Loaded events, Loading_Table + Table_Loaded per loadable entry. |

### Packet Reception — Nominal

| Test | Description |
|------|-------------|
| `Test_Nominal_Segmented_Upload` | Send First + Continuation + Last for Table ID 10. Simulator returns Success. Verify events: Receiving_New_Table, Table_Received, Table_Updated. Verify DPs: Num_Packets_Received=3, Num_Tables_Updated=1, Last_Table_Received with Table_Update_Success. |
| `Test_Unsegmented_Upload` | Send single Unsegmented packet for Table ID 10. Verify Table_Received + Table_Updated (no Receiving_New_Table for unsegmented). |
| `Test_Multi_Destination_Order` | Send complete table for Table ID 3 (3 destinations). Check arrayed send history to verify non-Load_From destinations sent first (in YAML order), Load_From (Primary_Param_Store) sent last. |

### Packet Reception — Error Paths

| Test | Description |
|------|-------------|
| `Test_Packet_Ignored` | Send Continuation and Last without prior First. Verify Packet_Ignored events and Num_Packets_Rejected counter. |
| `Test_Too_Small_Table` | Send FirstSegment with <2 bytes. Verify Too_Small_Table event and reject counter. |
| `Test_Buffer_Overflow` | Send FirstSegment then large Continuation exceeding buffer. Verify Staging_Buffer_Overflow event and reject counter. |
| `Test_Unrecognized_Table_Id` | Send complete table with unknown ID (e.g., 999). Verify Unrecognized_Table_Id event and Num_Tables_Invalid counter. |

### Downstream Failure and Timeout

| Test | Description |
|------|-------------|
| `Test_Destination_Failure` | Simulator returns Parameter_Error. Verify Table_Update_Failure event contains correct Table_Id, Connector_Index, and status. Verify Num_Tables_Invalid incremented. |
| `Test_Destination_Timeout` | Simulator sends ticks, never responds. Verify Table_Update_Timeout event with Table_Id and Connector_Index. Verify Num_Tables_Invalid incremented. |
| `Test_Partial_Failure_Stops` | Table ID 3 (3 destinations). First non-Load_From fails. Verify remaining destinations not sent to (check arrayed send history count). Load_From never reached. |

### Commands — Load_Parameter_Table

| Test | Description |
|------|-------------|
| `Test_Load_Table_Nominal` | Command Load_Parameter_Table for Table ID 10. Simulator returns Success for Get and Set. Verify Loading_Table + Table_Loaded events, command Success. |
| `Test_Load_Table_No_Load_Source` | Command for Table ID 4 (no load_from). Verify No_Load_Source event, command Failure. |
| `Test_Load_Table_Unrecognized` | Command for unknown ID. Verify Unrecognized_Table_Id event, command Failure. |
| `Test_Load_Table_Get_Failure` | Simulator returns failure on Get. Verify Table_Load_Failure event (Is_Load path), command Failure. |
| `Test_Load_Table_Set_Failure` | Get succeeds, Set to non-Load_From fails. Verify Table_Update_Failure event, command Failure. |

### Commands — Load_All_Parameter_Tables

| Test | Description |
|------|-------------|
| `Test_Load_All_Nominal` | Command Load_All. Simulator returns Success for all. Verify Loading_All + Loading_Table (per loadable) + Table_Loaded (per loadable) + All_Loaded events. Command Success. |
| `Test_Load_All_Partial_Failure` | One table fails. Verify command Failure, other tables still attempted, events for each. |

### Dropped Handlers

| Test | Description |
|------|-------------|
| `Test_Packet_Dropped` | Overflow CCSDS packet queue. Verify Packet_Dropped event and reject counter. |
| `Test_Command_Dropped` | Overflow command queue. Verify Command_Dropped event. |

### Invalid Command

| Test | Description |
|------|-------------|
| `Test_Invalid_Command` | Send command with corrupted arg buffer length. Verify Invalid_Command_Received event. |

### Data Products

| Test | Description |
|------|-------------|
| `Test_Data_Product_Updates` | Comprehensive check of all DP values after a sequence of operations: upload success, upload failure, buffer overflow. Verify Last_Table_Received status transitions and counter consistency. |

## Coverage Targets

- **Line coverage**: 100% on `component-parameter_table_router-implementation.adb`
- **Functional coverage**:
  - All 6 `Append_Status` return paths exercised
  - All `Table_Status` enum values appear in Last_Table_Received DP
  - All events emitted at least once
  - Both command Success and Failure paths
  - Load_From last ordering verified
  - Timeout and failure distinguished
  - Set_Up with and without Load_All
  - Dropped handlers for both async connectors

## Notes

- The test assembly (`test/test_assembly/`) exists for the autocoder. The component unit test (`test/`) uses the reciprocal tester pattern and imports the autocoded table via the build path.
- The `Parameters_Memory_Region_T_Send` is an arrayed connector. The tester history captures sends with index information for verifying ordering.
- `Dispatch_All` processes async queue entries. Commands and CCSDS packets both go through recv_async.
- `Final` must be called in `Tear_Down_Test` to destroy the binary tree and staging buffer.

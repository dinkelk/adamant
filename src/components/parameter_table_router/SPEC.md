# Parameter Table Router - Component Specification

## Overview

The Parameter Table Router is an **active component** that replaces the current Parameter Manager. It receives segmented CCSDS packets containing parameter tables, reassembles them in a staging buffer, and routes completed tables to downstream components that accept a `Parameters_Memory_Region` type via an arrayed output connector. It supports loading parameter tables from a designated component on command, which will often be a `Parameter_Store` sitting in front of persistent storage.

The component runs at **background priority** and processes packets from its queue whenever they are available.

## Reference Components

Study these existing components for patterns used in this design:

- **`src/components/ccsds_router/`** -- Generator pattern (YAML -> Python model -> generated `.ads` with routing table). The Parameter Table Router generator follows this same architecture. Note: the CCSDS Router codebase refers to this as an "autocoder" but we use "generator" here.
- **`ema-gnc-fsw/src/components/parameter_manager/`** -- Synchronous send/wait/response pattern using `Task_Synchronization.Wait_Release_Timeout_Counter_Object` and `Protected_Variables`. The Parameter Table Router uses this same mechanism for communicating with downstream components.
- **`src/components/parameters/`** -- Downstream component that receives `Parameters_Memory_Region.T` with `Set`/`Get` operations and returns `Parameters_Memory_Region_Release.T` with status.
- **`src/components/parameter_store/`** -- Downstream component for persistent (e.g., MRAM) parameter table storage. Also receives `Parameters_Memory_Region.T`.

## Component Directory Layout

```
src/components/parameter_table_router/
  parameter_table_router.component.yaml
  parameter_table_router.events.yaml
  parameter_table_router.commands.yaml
  parameter_table_router.data_products.yaml
  parameter_table_router_types.ads              -- Router table types (Destination_Entry, etc.)
  parameter_table_buffer.ads                    -- Staging buffer package spec
  parameter_table_buffer.adb                    -- Staging buffer package body
  component-parameter_table_router-implementation.ads
  component-parameter_table_router-implementation.adb
  gen/
    models/parameter_table_router_table.py
    generators/parameter_table_router_table.py
    schemas/parameter_table_router_table.yaml
    templates/parameter_table_router_table/name.ads
  types/
    parameter_table_received_info.record.yaml   -- For Last_Table_Received data product
  test/
    ...
```

## Component YAML Model

```yaml
---
description: |
  This component receives segmented CCSDS packets containing parameter tables,
  reassembles them in a staging buffer, and routes completed tables to downstream
  components that accept a Parameters_Memory_Region type. It supports loading
  parameter tables from a designated component on command, which will often be a
  Parameter_Store sitting in front of persistent storage.

  A generator exists to produce the routing table that maps parameter table IDs
  to output connector indexes. See the gen/ subdirectory for documentation.
execution: active
init:
  description: Initialization parameters for the Parameter Table Router.
  parameters:
    - name: Table
      type: Parameter_Table_Router_Types.Router_Table
      description: The routing table mapping parameter table IDs to destination connector indexes. Typically produced by the generator.
    - name: Ticks_Until_Timeout
      type: Natural
      description: The number of timeout ticks to wait for a response from a downstream component before declaring a timeout. For example, if attached to a 10Hz rate group with this value set to 7, the timeout is 700-800ms.
    - name: Warn_Unexpected_Sequence_Counts
      type: Boolean
      default: "False"
      description: If True, an event is produced when a CCSDS packet is received with an unexpected (non-incrementing) sequence count. No other action is taken.
connectors:
  ###################################
  # Invokee Connectors
  ###################################
  - description: Receives segmented CCSDS packets containing parameter table data. Queue size should be large enough to handle slop.
    type: Ccsds_Space_Packet.T
    kind: recv_async
  - description: The command receive connector.
    type: Command.T
    kind: recv_async
  - description: Periodic tick used for timeout counting when waiting for downstream responses.
    name: Timeout_Tick_Recv_Sync
    type: Tick.T
    kind: recv_sync
  - description: Synchronous response from downstream Parameters/Parameter_Store components after a Set or Get operation.
    type: Parameters_Memory_Region_Release.T
    kind: recv_sync
  ###################################
  # Invoker Connectors
  ###################################
  - description: Arrayed output connector for sending parameter table memory regions to downstream components. Each index corresponds to a destination in the routing table.
    type: Parameters_Memory_Region.T
    kind: send
    count: 0  # variable size arrayed output
  - description: Send command responses.
    type: Command_Response.T
    kind: send
  - description: Events are sent out of this connector.
    type: Event.T
    kind: send
  - description: Data products are sent out of this connector.
    type: Data_Product.T
    kind: send
  - description: The system time is retrieved via this connector.
    return_type: Sys_Time.T
    kind: get
```

## Staging Buffer Package (`parameter_table_buffer`)

This is a **standalone Ada package** (not a component) that lives next to the component. It manages a heap-allocated byte buffer for reassembling segmented CCSDS parameter table packets.

### Types

```ada
-- Return status from the Append operation:
type Append_Status is (
   Packet_Ignored,   -- ContinuationSegment/LastSegment without prior FirstSegment,
                     --   or Unsegmented packet at any time
   Buffering_Table,  -- ContinuationSegment received after valid FirstSegment, data appended
   New_Table,        -- Valid FirstSegment received, buffer reset and data stored
   Complete_Table,   -- LastSegment received after valid FirstSegment, table is complete
   Too_Small_Table   -- FirstSegment data is less than 2 bytes (cannot extract Table ID)
);

-- Internal state machine:
type Buffer_State is (Idle, Receiving_Table);
```

### Record Type

```ada
type Instance is record
   Buffer        : Basic_Types.Byte_Array_Access := null;  -- Heap-allocated staging buffer
   Buffer_Length  : Natural := 0;                           -- Total allocated size
   Buffer_Index   : Natural := 0;                           -- Next byte to write (0-based)
   Table_Id       : Parameter_Types.Parameter_Table_Id := 0;
   State          : Buffer_State := Idle;
end record;
```

### API

```ada
-- Allocate the internal buffer. Buffer_Size is the number of bytes to allocate.
procedure Create (Self : in out Instance; Buffer_Size : in Positive);

-- Deallocate the internal buffer.
procedure Destroy (Self : in out Instance);

-- Append CCSDS packet data to the buffer.
-- Data: the CCSDS packet data payload (everything in the CCSDS data field)
-- Sequence_Flag: from the CCSDS primary header
-- Returns: Append_Status indicating result
function Append (
   Self           : in out Instance;
   Data           : in Basic_Types.Byte_Array;
   Sequence_Flag  : in Ccsds_Enums.Ccsds_Sequence_Flag.E
) return Append_Status;

-- Get a Memory_Region.T pointing to the table data in the buffer,
-- starting AFTER the 2-byte Table ID. This is what gets sent to
-- downstream Parameters/Parameter_Store components (they expect
-- data starting with Parameter_Table_Header: [CRC(2)][Version(4)][param data...]).
function Get_Table_Region (Self : in Instance) return Memory_Region.T;

-- Get the Table ID extracted from the most recent FirstSegment.
function Get_Table_Id (Self : in Instance) return Parameter_Types.Parameter_Table_Id;

-- Get the total number of table data bytes received (excluding the 2-byte Table ID).
function Get_Table_Length (Self : in Instance) return Natural;

-- Reset the buffer state to Idle and index to 0.
procedure Reset (Self : in out Instance);
```

### Append Behavior

The `Sequence_Flag` parameter comes from `Ccsds_Enums.Ccsds_Sequence_Flag` (defined in `src/types/ccsds/ccsds_enums.enums.yaml`):

| Sequence Flag | Current State | Action | Return |
|---|---|---|---|
| `Unsegmented` | Any | Ignore | `Packet_Ignored` |
| `FirstSegment` | Any | Reset buffer index to 0. Check data length >= 2 bytes. Extract Table ID from first 2 bytes. Copy remaining data to buffer. State -> `Receiving_Table`. | `New_Table` (or `Too_Small_Table` if data < 2 bytes) |
| `ContinuationSegment` | `Idle` | Ignore | `Packet_Ignored` |
| `ContinuationSegment` | `Receiving_Table` | Append data to buffer at current index. If buffer would overflow, **do not write**, remain in `Receiving_Table` state, and the **component** (not the buffer) reports the overflow event and silently drops further continuation packets until a new FirstSegment. | `Buffering_Table` (or a buffer-full indication that the component handles) |
| `LastSegment` | `Idle` | Ignore | `Packet_Ignored` |
| `LastSegment` | `Receiving_Table` | Append data to buffer. State -> `Idle`. | `Complete_Table` (or overflow if buffer full) |

**Buffer overflow detail:** When a `ContinuationSegment` or `LastSegment` would cause the buffer index to exceed the buffer length, the append returns a distinct indication (e.g., a `Boolean` out parameter, or a separate status value). The component is responsible for emitting the `Staging_Buffer_Overflow` event. The buffer remains in `Receiving_Table` state -- it does NOT transition. Further continuation/last packets are silently dropped (component checks overflow flag and does not act on them) until a new `FirstSegment` resets the buffer.

**Note on FirstSegment while receiving:** If a `FirstSegment` arrives while in `Receiving_Table` state, the buffer resets and starts receiving the new table. The previous incomplete table is discarded. This is by design -- no event is needed for this case since `New_Table` is returned.

### Memory Layout in Buffer

When a FirstSegment is received, the CCSDS data field contains:

```
[Table_ID (2 bytes)] [CRC (2 bytes)] [Version (4 bytes)] [param data...]
```

The buffer stores everything starting from byte 0:
```
Buffer: [Table_ID (2)] [CRC (2)] [Version (4)] [param data...] [more from continuation packets...]
```

- `Table_Id` is extracted from bytes 0-1 and stored in `Self.Table_Id`
- `Get_Table_Region` returns a `Memory_Region.T` pointing to `Buffer(2)` (after Table ID) with length `Buffer_Index - 2`
- This gives downstream components the expected layout: `[CRC][Version][param data...]`

## Routing Table Types (`parameter_table_router_types.ads`)

Follow the pattern from `src/components/ccsds_router/ccsds_router_types.ads`:

```ada
with Parameter_Types;
with Connector_Types;

package Parameter_Table_Router_Types is

   -- A single destination entry with metadata:
   type Destination_Entry is record
      Connector_Index : Connector_Types.Connector_Index_Type := Connector_Types.Connector_Index_Type'First;
      Load_From : Boolean := False;
   end record;

   -- Destination table: array of destination entries for a single table ID:
   type Destination_Table is array (Natural range <>) of Destination_Entry;
   type Destination_Table_Access is access all Destination_Table;

   -- A router table entry maps a parameter table ID to its destinations:
   type Router_Table_Entry is record
      Table_Id : Parameter_Types.Parameter_Table_Id := 0;
      Destinations : Destination_Table_Access := null;
   end record;

   -- The full router table passed to Init:
   type Router_Table is array (Natural range <>) of Router_Table_Entry;

end Parameter_Table_Router_Types;
```

**Key difference from CCSDS Router:** Each destination is a `Destination_Entry` record (not just a bare connector index) because we need the `Load_From` flag. This also allows future metadata extensions.

## Generator

### Input YAML Schema

File: `<assembly_name>.parameter_table_router_table.yaml`

```yaml
---
parameter_table_router_instance_name: My_Parameter_Table_Router
description: Routes parameter tables to their destinations.
table:
  - table_id: My_Parameter_Table  # Reference to a parameter table model name (resolved to numeric ID)
    destinations:
      - component_name: Working_Params
        load_from: false
      - component_name: Primary_Param_Store
        load_from: true
  - table_id: 42  # Raw numeric table ID also supported
    destinations:
      - component_name: Another_Params
```

**Resolution rules:**
- `table_id` can be a parameter table model name (string) that resolves to a `Parameter_Types.Parameter_Table_Id` via the assembly model, OR a raw integer.
- `component_name` resolves to a connector index on the arrayed output connector, using the same resolution logic as the CCSDS Router generator (see `ccsds_router_table.py:resolve_router_destinations`).
- `load_from` defaults to `false` if omitted.
- **Validation:** At most one destination per table entry may have `load_from: true`. The generator enforces this.

### Generated Ada Output

File: `<assembly_name>_parameter_table_router_table.ads`

```ada
with Parameter_Table_Router_Types; use Parameter_Table_Router_Types;

package My_Assembly_Parameter_Table_Router_Table is

   -- Destination table for Table ID 1 (My_Parameter_Table):
   Destination_Table_1 : aliased Destination_Table := [
      0 => (Connector_Index => 1, Load_From => False),
      1 => (Connector_Index => 3, Load_From => True)
   ];

   -- Destination table for Table ID 42:
   Destination_Table_42 : aliased Destination_Table := [
      0 => (Connector_Index => 2, Load_From => False)
   ];

   -- Router table:
   Router_Table_Entries : constant Router_Table := [
      0 => (Table_Id => 1, Destinations => Destination_Table_1'Access),
      1 => (Table_Id => 42, Destinations => Destination_Table_42'Access)
   ];

end My_Assembly_Parameter_Table_Router_Table;
```

### Generator File Structure

Follow the CCSDS Router generator pattern exactly:

- **`gen/models/parameter_table_router_table.py`** -- Model class extending `assembly_submodel`. Loads YAML, resolves destination component names to connector indexes via the assembly model, validates `load_from` constraints.
- **`gen/generators/parameter_table_router_table.py`** -- Generator class. Loads assembly model, instantiates the table model, calls `resolve_router_destinations()`, renders the Jinja2 template.
- **`gen/schemas/parameter_table_router_table.yaml`** -- YAML schema for validation.
- **`gen/templates/parameter_table_router_table/name.ads`** -- Jinja2 template producing the Ada package.

## Component Internal State

```ada
type Instance is new Parameter_Table_Router.Base_Instance with record
   -- Routing table (binary tree keyed by Table_Id for O(log n) lookup):
   Table : Router_Table_B_Tree.Instance;

   -- Staging buffer for reassembling segmented packets:
   Staging_Buffer : Parameter_Table_Buffer.Instance;

   -- Synchronization for downstream responses:
   Response : Protected_Parameters_Memory_Region_Release.Variable;
   Sync_Object : Task_Synchronization.Wait_Release_Timeout_Counter_Object;

   -- Sequence count tracking:
   Warn_Unexpected_Sequence_Counts : Boolean := False;
   Last_Sequence_Count : Ccsds_Primary_Header.Ccsds_Sequence_Count_Type := 0;

   -- Overflow tracking (set when staging buffer overflows, cleared on next FirstSegment):
   Buffer_Overflowed : Boolean := False;
end record;
```

### State Machine

The component has three logical states driven by what it's doing:

1. **Idle / Receiving Packets** -- Normal operation. Pulls CCSDS packets from queue, feeds them to the staging buffer. The staging buffer tracks its own `Idle`/`Receiving_Table` state internally.

2. **Updating Table** -- A complete table has been received. The component iterates through the destination list for the table's ID, sending `Parameters_Memory_Region.T` with `Operation => Set` to each destination (except `Load_From`, which is sent last), waiting for each response before proceeding to the next.

3. **Loading Table** -- A `Load_Parameter_Table` or `Load_All_Parameter_Tables` command is executing. The component sends `Operation => Get` to the `Load_From` destination, waits for response, then sends `Operation => Set` to the other destinations in order.

## Init Procedure

```ada
overriding procedure Init (
   Self : in out Instance;
   Table : in Parameter_Table_Router_Types.Router_Table;
   Ticks_Until_Timeout : in Natural;
   Warn_Unexpected_Sequence_Counts : in Boolean := False
);
```

**Init must:**
1. Set the timeout limit on `Self.Sync_Object`.
2. Store `Warn_Unexpected_Sequence_Counts`.
3. Populate the binary tree from the `Table` parameter (keyed by `Table_Id`).
4. **Validate** each entry:
   - All destination connector indexes are within valid range for the arrayed output connector (`1 .. Self.Connector_Count`).
   - At most one destination per entry has `Load_From = True`.
   - No duplicate `Table_Id` values.
5. The staging buffer is **not** created in Init -- it should be created separately or via an Init parameter for buffer size. (Alternatively, add a `Buffer_Size` init parameter.)

**Note:** Consider adding a `Buffer_Size : in Positive` init parameter for the staging buffer allocation (e.g., 150 KB). The buffer is created in Init via `Parameter_Table_Buffer.Create(Self.Staging_Buffer, Buffer_Size)`.

## Packet Reception Flow (recv_async for CCSDS packets)

```
procedure Ccsds_Space_Packet_T_Recv_Async (Self : in out Instance; Arg : in Ccsds_Space_Packet.T):

1. Increment Num_Packets_Received data product counter.

2. Extract sequence flag from Arg.Header.Sequence_Flag.

3. If Warn_Unexpected_Sequence_Counts = True:
   - Check Arg.Header.Sequence_Count against Self.Last_Sequence_Count + 1
   - If mismatch, emit Unexpected_Sequence_Count event
   - Update Self.Last_Sequence_Count

4. If Self.Buffer_Overflowed and sequence flag is NOT FirstSegment:
   - Silently drop the packet (already reported overflow)
   - Return

5. If sequence flag IS FirstSegment:
   - Clear Self.Buffer_Overflowed

6. Call Self.Staging_Buffer.Append(Data => Arg.Data, Sequence_Flag => sequence_flag)

7. Handle return status:
   - Packet_Ignored:
       Increment Num_Packets_Rejected counter.
       Emit Packet_Ignored event (include CCSDS primary header from Arg).

   - Too_Small_Table:
       Increment Num_Packets_Rejected counter.
       Emit Too_Small_Table event (include CCSDS primary header from Arg).

   - New_Table:
       Emit Receiving_New_Table event (include Table ID).
       Look up Table ID in routing table.
       If not found: emit Unrecognized_Table_Id event, call Staging_Buffer.Reset, return.

   - Buffering_Table:
       No action (or check for buffer overflow -- see step 4 note).

   - Complete_Table:
       Increment Num_Tables_Received counter.
       Emit Table_Received event.
       Proceed to table update flow (below).

   - Buffer overflow (detected by checking if append would exceed buffer):
       Set Self.Buffer_Overflowed := True
       Emit Staging_Buffer_Overflow event.
```

## Table Update Flow (after Complete_Table)

```
1. Look up Table_Id in routing table to get destination list.
   (Should already be validated from New_Table step, but check again for safety.)
   If not found: emit Unrecognized_Table_Id event, return.

2. Build Parameters_Memory_Region.T:
   Region => Self.Staging_Buffer.Get_Table_Region  -- points past Table ID
   Operation => Parameter_Enums.Parameter_Table_Operation_Type.Set

3. Iterate through destinations IN ORDER (as specified in YAML), but SKIP the
   Load_From destination (it is sent last):

   For each non-Load_From destination:
     a. Self.Sync_Object.Reset
     b. Self.Parameters_Memory_Region_T_Send (destination.Connector_Index, region)
     c. Self.Sync_Object.Wait (Timed_Out)
     d. If Timed_Out:
          Emit Table_Update_Timeout event.
          Update Num_Tables_Invalid counter.
          Return (abandon remaining destinations).
     e. Check Self.Response.Get_Var.Status:
          If not Success:
            Emit Table_Update_Failure event (include status, Table ID).
            Update Num_Tables_Invalid counter.
            Return (abandon remaining destinations).

4. If a Load_From destination exists:
     Same send/wait/check pattern as step 3.
     This is sent LAST so that if any validation fails above, we don't
     persist an invalid table.

5. If all destinations succeeded:
     Emit Table_Updated event (include Table ID).

6. Update Last_Table_Received data product (Table ID, length, timestamp).
```

## Load Parameter Table Flow (command)

### `Load_Parameter_Table` Command

**Argument:** `Parameter_Types.Parameter_Table_Id`

```
1. Look up Table_Id in routing table.
   If not found:
     Emit Unrecognized_Table_Id event.
     Return Command_Execution_Status.Failure.

2. Find the Load_From destination in the entry.
   If no Load_From destination exists:
     Emit No_Load_Source event.
     Return Command_Execution_Status.Failure.

3. Send Get request to Load_From destination:
   a. Build Parameters_Memory_Region.T:
      Region => Self.Staging_Buffer.Get_Table_Region  -- buffer for receiving table data
      Operation => Parameter_Enums.Parameter_Table_Operation_Type.Get
   b. Self.Sync_Object.Reset
   c. Self.Parameters_Memory_Region_T_Send (load_from.Connector_Index, region)
   d. Self.Sync_Object.Wait (Timed_Out)
   e. Handle timeout/failure as in update flow.

4. The Load_From destination (Parameter_Store) populates the buffer with the
   current table contents.

5. Send Set request to each non-Load_From destination (in order):
   Same send/wait/check pattern as table update flow step 3.
   If any fails, stop and report failure.

6. If all succeeded:
   Emit Table_Loaded event.
   Return Command_Execution_Status.Success.
```

### `Load_All_Parameter_Tables` Command

**Argument:** None

```
1. Iterate through all entries in the routing table.

2. For each entry that has a Load_From destination:
   Execute the same logic as Load_Parameter_Table for that Table_Id.
   If any individual table load fails:
     Emit per-table failure event.
     Continue to next table (do not abort the entire operation).

3. Return Command_Execution_Status.Success (even if individual tables failed --
   failures are reported via events).
```

## Timeout Tick Handler

```ada
overriding procedure Timeout_Tick_Recv_Sync (Self : in out Instance; Arg : in Tick.T) is
   Ignore : Tick.T renames Arg;
begin
   Self.Sync_Object.Increment_Timeout_If_Waiting;
end Timeout_Tick_Recv_Sync;
```

## Response Handler

```ada
overriding procedure Parameters_Memory_Region_Release_T_Recv_Sync (
   Self : in out Instance;
   Arg  : in Parameters_Memory_Region_Release.T
) is
begin
   Self.Response.Set_Var (Arg);
   Self.Sync_Object.Release;
end Parameters_Memory_Region_Release_T_Recv_Sync;
```

Same pattern and same race-condition documentation as the existing Parameter Manager.

## Events

```yaml
events:
  - name: Receiving_New_Table
    description: A new parameter table FirstSegment has been received and buffering has started.
    param_type: Parameter_Table_Id.T

  - name: Table_Received
    description: A complete parameter table has been reassembled from CCSDS segments.
    param_type: Parameter_Table_Id.T

  - name: Table_Updated
    description: A parameter table has been successfully sent to all downstream destinations.
    param_type: Parameter_Table_Id.T

  - name: Table_Loaded
    description: A parameter table has been successfully loaded from persistent storage and sent to all destinations.
    param_type: Parameter_Table_Id.T

  - name: Table_Update_Failure
    description: A downstream component rejected a parameter table update.
    param_type: Parameters_Memory_Region_Release.T

  - name: Table_Update_Timeout
    description: Timed out waiting for a response from a downstream component during table update.
    param_type: Parameter_Table_Id.T

  - name: Table_Load_Failure
    description: Failed to load a parameter table from persistent storage.
    param_type: Parameters_Memory_Region_Release.T

  - name: No_Load_Source
    description: Load_Parameter_Table command received for a table ID that has no load_from destination.
    param_type: Parameter_Table_Id.T

  - name: Unrecognized_Table_Id
    description: Received a parameter table with a Table ID not found in the routing table.
    param_type: Parameter_Table_Id.T

  - name: Packet_Ignored
    description: A CCSDS packet was ignored (continuation/last segment without prior first segment, or unsegmented).
    param_type: Ccsds_Primary_Header.T

  - name: Too_Small_Table
    description: A FirstSegment packet was too small to contain a Table ID (less than 2 bytes of data).
    param_type: Ccsds_Primary_Header.T

  - name: Staging_Buffer_Overflow
    description: The staging buffer is full. Dropping continuation/last segment packets until a new FirstSegment resets the buffer.
    param_type: Ccsds_Primary_Header.T

  - name: Unexpected_Sequence_Count
    description: A CCSDS packet was received with an unexpected sequence count. Only emitted when Warn_Unexpected_Sequence_Counts is True.
    param_type: Unexpected_Sequence_Count.T

  - name: Invalid_Command_Received
    description: A command was received with invalid parameters.
    param_type: Invalid_Command_Info.T

  - name: Command_Dropped
    description: A command was dropped due to a full queue.
    param_type: Command_Header.T
```

**Note:** `Unexpected_Sequence_Count.T` is an existing type at `src/types/ccsds/unexpected_sequence_count.record.yaml` that holds `received` and `expected` sequence count values.

## Data Products

```yaml
data_products:
  - name: Num_Packets_Received
    type: Packed_U32.T
    description: Total number of CCSDS packets received on the async connector.

  - name: Num_Packets_Rejected
    type: Packed_U32.T
    description: Number of packets rejected (ignored, too small, or buffer overflow).

  - name: Num_Tables_Received
    type: Packed_U32.T
    description: Number of complete parameter tables successfully reassembled.

  - name: Num_Tables_Invalid
    type: Packed_U32.T
    description: Number of parameter tables that failed downstream validation or timed out.

  - name: Last_Table_Received
    type: Parameter_Table_Received_Info.T
    description: Information about the last complete parameter table received.
```

### `Parameter_Table_Received_Info` Type

New packed record at `types/parameter_table_received_info.record.yaml`:

```yaml
---
description: Information about the last parameter table received by the Parameter Table Router.
fields:
  - name: Table_Id
    type: Parameter_Types.Parameter_Table_Id
    description: The parameter table ID.
  - name: Table_Length
    type: Interfaces.Unsigned_32
    format: U32
    description: The total length in bytes of the table data (excluding the 2-byte Table ID).
  - name: Timestamp
    type: Sys_Time.T
    description: The time the table was fully received.
```

## Commands

```yaml
commands:
  - name: Load_Parameter_Table
    description: Load a single parameter table from its load_from source and distribute to other destinations.
    arg_type: Parameter_Table_Id.T

  - name: Load_All_Parameter_Tables
    description: Load all parameter tables that have a load_from source configured and distribute to their destinations.
```

`Parameter_Table_Id.T` is the existing packed record at `src/types/parameter/parameter_table_id.record.yaml` wrapping a `U16`.

## Synchronization Pattern

The component uses the same sync pattern as the existing Parameter Manager:

```ada
-- In the package spec (implementation.ads):
with Protected_Variables;
with Task_Synchronization;
with Parameters_Memory_Region_Release;

-- Protected variable for response:
package Protected_Parameters_Memory_Region_Release is
   new Protected_Variables.Generic_Variable (Parameters_Memory_Region_Release.T);

-- In the instance record:
Response    : Protected_Parameters_Memory_Region_Release.Variable;
Sync_Object : Task_Synchronization.Wait_Release_Timeout_Counter_Object;
```

**Send-and-wait helper pattern** (from Parameter Manager):

```ada
function Send_And_Wait (Self : in out Instance; Index : in Connector_Types.Connector_Index_Type; Region : in Parameters_Memory_Region.T) return Boolean is
   Wait_Timed_Out : Boolean;
begin
   Self.Sync_Object.Reset;
   Self.Parameters_Memory_Region_T_Send (Index, Region);
   Self.Sync_Object.Wait (Wait_Timed_Out);

   if Wait_Timed_Out then
      -- Emit timeout event
      return False;
   end if;

   declare
      Release : constant Parameters_Memory_Region_Release.T := Self.Response.Get_Var;
   begin
      if Release.Status /= Parameter_Enums.Parameter_Table_Update_Status.Success then
         -- Emit failure event
         return False;
      end if;
   end;

   return True;
end Send_And_Wait;
```

## Binary Tree for Table Lookup

Follow the CCSDS Router pattern using a binary tree keyed by `Parameter_Table_Id`:

```ada
with Binary_Tree;

-- Internal entry stored in the tree:
type Internal_Router_Table_Entry is record
   Table_Entry : Parameter_Table_Router_Types.Router_Table_Entry;
end record;

function Less_Than (Left, Right : Internal_Router_Table_Entry) return Boolean is
   (Left.Table_Entry.Table_Id < Right.Table_Entry.Table_Id);

function Greater_Than (Left, Right : Internal_Router_Table_Entry) return Boolean is
   (Left.Table_Entry.Table_Id > Right.Table_Entry.Table_Id);

package Router_Table_B_Tree is new Binary_Tree (
   T => Internal_Router_Table_Entry,
   Less_Than => Less_Than,
   Greater_Than => Greater_Than
);
```

## Key Design Decisions

1. **Component does NOT compute CRC.** The staging buffer treats everything after the 2-byte Table ID as opaque data. CRC validation is the responsibility of downstream `Parameters` and `Parameter_Store` components.

2. **Component does NOT parse the parameter table header.** It only extracts the Table ID (first 2 bytes of FirstSegment data). The rest is opaque.

3. **Load_From destination is sent last** during table updates. This ensures that if any validation fails at a working/active destination, the persistent store is not updated with an invalid table.

4. **If any destination fails, remaining destinations are skipped.** This fail-fast behavior prevents partial updates.

5. **Buffer overflow does not change buffer state.** The buffer remains in `Receiving_Table` but the component sets an overflow flag and silently drops subsequent packets until a new FirstSegment.

6. **Sequence count checking is optional** and controlled by `Warn_Unexpected_Sequence_Counts` init parameter. It only produces events, never affects packet processing.

7. **`Unsegmented` packets are always ignored.** Parameter tables must always be sent as segmented CCSDS packets (FirstSegment + optional ContinuationSegments + LastSegment).

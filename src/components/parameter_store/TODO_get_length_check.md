# Parameter Store: Fix Length Check for Get Operations

## Problem

The Parameter_Store component currently validates that `Arg.Region.Length == Self.Bytes.all'Length` for all operations (Set, Get, Validate). This is correct for Set and Validate, where the caller provides a table that must match the expected size exactly. However, for Get operations, the caller is providing a buffer to receive data into, and that buffer only needs to be **large enough** to hold the table — it does not need to match exactly.

This blocks the Parameter_Table_Router's Load flow, which sends a Get request using its staging buffer (which is sized for the largest possible table, not a specific table's exact size).

## Current Code

In `component-parameter_store-implementation.adb` (around line 95):

```ada
if Arg.Region.Length /= Self.Bytes.all'Length then
   -- Reject with Length_Error
```

This check applies uniformly to all operations.

## Proposed Change

Split the length validation by operation type:

- **Set / Validate**: Keep the exact length check (`Arg.Region.Length /= Self.Bytes.all'Length`)
- **Get**: Change to a capacity check (`Arg.Region.Length < Self.Bytes.all'Length`)

For Get, the store writes `Self.Bytes.all'Length` bytes into the provided region and returns a release with `Region.Length` set to the actual bytes written (i.e., `Self.Bytes.all'Length`), so the caller knows the true data size.

## Impact

- The `Parameters_Memory_Region_Release.T` returned from a Get will have `Region.Length` reflecting the actual table size, not the buffer capacity that was sent
- The Parameter_Table_Router uses this returned length when forwarding the table data via Set to other destinations
- No change to Set or Validate behavior

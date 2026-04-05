# Code Review: Ccsds_Downsampler_Types

## 1. Package Specification Review

**File:** `ccsds_downsampler_types.ads`

The package defines two record types and an array/access type for CCSDS packet downsampling configuration.

**Observations:**

- **Inconsistent default for `Filter_Factor`:** `Ccsds_Downsampler_Tree_Entry.Filter_Factor` defaults to `1` (pass-through, no filtering), while `Ccsds_Downsample_Packet_Entry.Filter_Factor` defaults to `Unsigned_16'First` which is `0`. A filter factor of 0 is semantically ambiguous — it could mean "drop all packets" or could cause a division-by-zero if the factor is used as a divisor or modulus operand. If 0 is intentionally "disabled/unset," this should be documented. If not, consider defaulting to `1` for consistency and safety.
- **Inconsistent default for `Apid`:** The tree entry defaults `Apid` to `Ccsds_Apid_Type'Last` (sentinel/unused marker), while the packet entry defaults to `Ccsds_Apid_Type'First` (APID 0, which is a valid APID). This asymmetry is likely intentional (tree = runtime, packet list = configuration), but worth verifying that APID 0 won't be silently matched if a packet entry is left uninitialized.
- **Index type of `Ccsds_Downsample_Packet_List`:** The array is indexed by `Data_Product_Types.Data_Product_Id`, which ties packet downsampling entries to data product IDs. This coupling may be intentional for the component's design but is worth noting — the relationship between a data product ID and a CCSDS APID downsampling entry is not self-evident from the types alone.

No other issues. The package is straightforward and the types are appropriately simple.

## 2. Package Implementation Review

No implementation files to review.

## 3. Model Review

**File:** `filter_factor_cmd_type.record.yaml`

Defines a packed command record with `Apid` (U16) and `Filter_Factor` (U16). This is clean and consistent with the Ada types. No issues.

## 4. Unit Test Review

No unit tests to review.

## 5. Summary

The package is small and largely correct. The one semantic concern worth investigating is the **default value of `Filter_Factor` being `0`** in `Ccsds_Downsample_Packet_Entry` — if this value can reach the runtime filtering logic without being explicitly set, it could cause unexpected behavior (e.g., division by zero or dropping all packets). Consider defaulting to `1` or documenting the semantics of a zero filter factor.

## Resolution Notes

| # | Issue | Severity | Status | Commit | Notes |
|---|-------|----------|--------|--------|-------|
| 1 | Inconsistent default for `Filter_Factor` (0 vs 1) | Medium | Fixed | 2c5d0fd | Changed default from 0 to 1, consistent with tree entry |
| 2 | Inconsistent default for `Apid` (`Last` vs `First`) | Low | Fixed | 698d248 | Changed default to `Ccsds_Apid_Type'Last` (sentinel) |
| 3 | Array indexed by `Data_Product_Id` | Info | N/A | — | Design coupling, noted for awareness only |

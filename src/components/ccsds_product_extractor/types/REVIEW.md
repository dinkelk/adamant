# Review: Product_Extractor_Types

**Date:** 2026-02-28
**Verdict:** Largely correct; minor observations below.

## product_extractor_types.ads

1. **Unused `with`:** `Invalid_Product_Data` is `with`'d but only used as a parameter type in the access-to-function profile. This is fine syntactically, but `Invalid_Product_Length` is notably *not* `with`'d even though a corresponding record YAML exists. If `Invalid_Product_Length` is intended to be referenced from this package (e.g., in a future extraction path for `Length_Error`), the asymmetry is worth noting.

2. **Null access types:** `Extractor_List_Access`, `Product_Id_List_Access`, and `Extracted_Product_List_Access` are general (not `not null`) access types with no accessibility checks. Users must null-check before dereferencing. This is intentional (default `null` in the record), but any caller iterating over `Extract_List` without a null guard would raise `Constraint_Error`. Consider whether `not null access` with mandatory initialization would be safer for `Extracted_Product_List_Access` at the top level.

3. **`Product_Id_List` declared but unused in this package:** `Product_Id_List` and `Product_Id_List_Access` are defined here but not referenced by `Ccsds_Product_Apid_List` or anything else in scope. If these are only used externally, that's fine as a shared types package, but it may indicate an incomplete design (e.g., should `Ccsds_Product_Apid_List` also carry a `Product_Id_List_Access`?).

4. **Access-to-function signature:** The `Extract_And_Validate` profile takes `Id_Base` but the extraction function is expected to know its own offset/index within the packet. The contract is implicit — callers must ensure the extractor list order matches the packet layout. No semantic issue per se, but worth documenting.

## Record YAMLs

Both `invalid_product_data.record.yaml` and `invalid_product_length.record.yaml` are straightforward and correct. Field types and formats are consistent with Adamant conventions.

## Summary

No safety-critical bugs found. The main observations are the asymmetric `with` of `Invalid_Product_Data` (but not `Invalid_Product_Length`), nullable access types requiring discipline from callers, and the orphaned `Product_Id_List` type. All are minor design-level notes rather than defects.

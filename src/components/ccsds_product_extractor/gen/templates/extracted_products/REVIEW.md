# Code Review: `extracted_products` Generator Templates

**Files reviewed:** `name.ads`, `name.adb`
**Date:** 2026-02-28
**Verdict:** Essentially correct with one minor observation.

## Summary

These Jinja2 templates generate an Ada package that extracts and validates data products from CCSDS packets by APID. The generated code dispatches through access-to-function arrays, extracts byte slices from packets, overlays typed records for validation, and reports errant fields on failure. The design is clean and the generated code structure is sound.

## Findings

### 1. Unused `Ignore` rename (cosmetic / benign)

```ada
{% if data_product.time_type == "packet_time" %}
   Ignore : Sys_Time.T renames Timestamp;
{% endif %}
```

This suppresses the "unreferenced parameter" warning when `Timestamp` is replaced by a time extracted from the packet. Standard Ada idiom — no issue.

### 2. `pragma Assert` for APID check — disabled at runtime by default

```ada
pragma Assert (Pkt.Header.Apid = {{apid}});
```

`pragma Assert` is suppressed unless compiled with `-gnata` or `Assertion_Policy(Check)`. If an incorrect APID is passed, the function silently proceeds. This is likely intentional (defense-in-depth during development only), but worth noting: **there is no runtime APID guard in production builds**.

### 3. `Safe_Right_Copy` into `P_Type` on validation failure — correct

The copy from `Pkt.Data` into `P_Type` uses the product's offset and size, which is consistent with the earlier extraction. No off-by-one: the slice `offset .. offset + Size_In_Bytes - 1` matches the extraction call.

### 4. No range check on template input values

The templates trust that `data_product.offset`, `data_product.local_id`, etc. are sane. An out-of-range offset would cause a runtime `Constraint_Error` at the slice. This is acceptable for generated code driven by validated YAML, but the safety boundary lives in the generator/model, not in the Ada code.

## Conclusion

The templates are **trivially correct** for their purpose. The only substantive note is that the APID assertion (finding #2) is a debug-only check, which is a deliberate design choice in Adamant's assertion philosophy. No semantic bugs or safety concerns found.

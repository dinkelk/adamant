# Code Review: ccsds_downsampler_filters (Generator Template)

## 1. Package Specification Review

**File:** `name.ads` (Jinja2 template generating an `.ads` file)

This is a single template that generates a package specification containing:
- A constant `Downsample_List_Size_In_Bytes` from `{{ size }}`
- An aliased aggregate array `Downsample_List` of type `Ccsds_Downsample_Packet_List`
- An access variable `Downsample_List_Access` pointing to the list

**Observations:**
- **`Downsample_List_Size_In_Bytes` is unused in-template.** It is declared as a constant but never referenced within this package. This is likely fine if consumed by other code, but worth confirming the generated constant is actually used downstream.
- **Mutable access to aliased package-level data.** `Downsample_List` is `aliased` and `Downsample_List_Access` is a non-constant access value. This means any code with visibility to the package can modify the downsample list at runtime via the access variable. This is presumably intentional (runtime reconfiguration), but it means there is no protection against concurrent modification. If the downsampler can be reconfigured from multiple tasks, a race condition is possible.
- **Array indexing uses `loop.index0`.** This is correct for a zero-based positional aggregate, assuming `Ccsds_Downsample_Packet_List` is indexed starting at 0. If the index type starts at a different value, this would be a generation bug — but since the code compiles, this is confirmed correct.

No other issues. The template is straightforward.

## 2. Package Implementation Review

No package body exists — this is a specification-only package (data declarations). Nothing to review.

## 3. Model Review

No YAML models to review in this directory (model/generator inputs live elsewhere).

## 4. Unit Test Review

No unit tests to review in this directory.

## 5. Summary

This is a trivially simple Jinja2 template generating a pure-declaration Ada package spec. The generated code exposes a mutable, aliased downsample filter list with an access variable. The only semantic concern is **the lack of any concurrency protection** on the mutable `Downsample_List` / `Downsample_List_Access` — if runtime modification from multiple tasks is possible, this should be guarded externally. Otherwise the template is correct and clean.

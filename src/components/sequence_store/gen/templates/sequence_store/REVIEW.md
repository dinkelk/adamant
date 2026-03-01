# Code Review: `sequence_store` Template Package

**Reviewed:** 2026-03-01
**Files:** `name.ads`, `name_record.record.yaml`
**Supporting:** `gen/models/sequence_store.py`, `gen/generators/sequence_store.py`

## Summary

Clean, well-structured Jinja2 templates for generating Ada slot definitions and a YAML record type. The model layer provides good validation (minimum slot size, summary-fits-in-packet). Two medium issues and a few minor items noted below.

---

## Findings

### 1. `Slots` array declared non-constant and at library level (Medium — code smell)

**File:** `name.ads`

```ada
Slots : aliased Component.Sequence_Store.Sequence_Slot_Array := [
   ...
];
```

This is a mutable library-level variable. While `Slots_Access` needs `'Access` (requiring `aliased`), the data itself is logically constant — slot definitions don't change at runtime. Ada's `aliased constant` would prevent accidental modification, but `'Access` on a constant requires `access constant` on the pointer side, which the component type (`Sequence_Slot_Array_Access`) may not declare. This is likely an intentional design trade-off — the component copies slots at `Init` — but worth verifying that nothing mutates `Slots` post-initialization.

**Recommendation:** If `Sequence_Slot_Array_Access` is `access all`, consider changing it to `access constant` and marking `Slots` as `aliased constant`. If not feasible, add a comment explaining why it's mutable.

### 2. Zero-slot edge case produces invalid Ada (Medium — edge case)

**File:** `name.ads`

If `slots` is an empty list, the template generates:

```ada
Slots : aliased Component.Sequence_Store.Sequence_Slot_Array := [
];
```

This is syntactically invalid Ada. The model code (`sequence_store.py`) iterates `self.data["slots"]` without checking for an empty list. The schema may enforce non-empty, and the component's doc says "the list must not be empty" (enforced by runtime assertion), but the *generator* would still produce uncompilable code.

**Recommendation:** Add a validation check in the model's `load()` method:
```python
if not self.data["slots"]:
    raise ModelException("At least one slot must be defined.")
```

### 3. `sequence_store_instance_name` variable used but not set in model (Low — minor)

**File:** `name.ads`, line:
```
-- A list of the slots for the {{ sequence_store_instance_name }} component.
```

The model class sets `self.name` but there is no `self.sequence_store_instance_name`. This likely resolves via a base-class attribute or the template render context, but if missing it would silently render as empty string (Jinja2 `undefined`). Depending on Jinja2 `undefined` configuration, this could be silent or raise an error.

**Recommendation:** Verify this variable is always populated. Consider using `self.name` or documenting the source.

### 4. Slot numbering uses both `slot.number` and `loop.index0` (Low — minor)

**File:** `name.ads`

Constants use `Slot_{{ slot.number }}` while the array index uses `{{ loop.index0 }}`. Since `slot.number` is assigned sequentially from 0 in the model, these always match. However, if the model ever changes to non-sequential numbering, the array indices would diverge from constant names.

**Recommendation:** Use `slot.number` consistently for both, or add a comment that sequential numbering is assumed.

### 5. YAML record template lacks description field (Low — cosmetic)

**File:** `name_record.record.yaml`

The top-level `description` is hardcoded. It could incorporate the user-provided `{{ description }}` or `{{ name }}` to make generated records more identifiable.

---

## Not Flagged (Verified OK)

- **Include deduplication:** Model uses `list(set(...))`, template filters out already-present packages. ✓
- **Slot length validation:** Model enforces minimum header size. ✓
- **Summary size validation:** Model checks against packet buffer size. ✓
- **Trailing comma handling:** `{{ "," if not loop.last }}` is correct. ✓
- **Non-integer address/length:** Model handles symbolic Ada references and extracts package includes. ✓

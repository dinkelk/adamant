# Code Review: `parameter_table` Template Package

**Reviewer:** Claude (automated review)
**Date:** 2026-03-01
**Branch:** `review/components-parameters-gen-templates-parameter-table`
**Scope:** All files in `src/components/parameters/gen/templates/parameter_table/` (excluding `build/`)

**Files reviewed:**
- `name.ads` — Jinja2 template generating an Ada package specification
- `name_record.record.yaml` — Jinja2 template generating an Adamant record model
- `name.xml` — Jinja2 template generating a ground-system display page definition

> **Note:** This package is entirely template-based (Jinja2 code-generation templates). There is no `.adb` implementation file, no unit test files, and no standalone model file — only the templates that produce them at generation time. Sections are scoped accordingly.

---

## 1. Package Specification Review (`name.ads`)

### Issue 1.1 — Off-by-one risk in `End_Index` comment vs. semantics

- **Location:** `name.ads`, aggregate literal for each parameter entry
- **Original code:**
  ```
        Start_Index => {{ table_entry.start_index}},
        End_Index => {{ table_entry.end_index}}
  ```
- **Explanation:** There is no comment or documentation anywhere in this template (or in `Parameters_Component_Types`) specifying whether `End_Index` is *inclusive* or *exclusive*. In safety-critical code, ambiguity about index boundaries is a classic source of off-by-one errors that cause buffer overruns or data corruption during parameter table parsing. The `Start_Index` / `End_Index` pair should have a comment in the generated output clarifying the convention.
- **Suggested fix:** Add a comment to the generated output, e.g.:
  ```
        -- Byte range [Start_Index .. End_Index] (inclusive).
        Start_Index => {{ table_entry.start_index }},
        End_Index => {{ table_entry.end_index }}
  ```
- **Severity:** Medium

### Issue 1.2 — Inconsistent trailing-space in Jinja expressions

- **Location:** `name.ads`, lines with `{{ table_entry.start_index}}` and `{{ table_entry.end_index}}`
- **Original code:**
  ```
        Start_Index => {{ table_entry.start_index}},
        End_Index => {{ table_entry.end_index}}
  ```
- **Explanation:** All other Jinja2 expressions in the file use symmetric spacing (`{{ expr }}`), but these two omit the trailing space before `}}`. While this has no functional impact on output, inconsistent template style hinders maintainability and review of safety-critical templates.
- **Suggested fix:**
  ```
        Start_Index => {{ table_entry.start_index }},
        End_Index => {{ table_entry.end_index }}
  ```
- **Severity:** Low

### Issue 1.3 — Size comment says "bytes" but division uses `(table_entry.size/8)|int` suggesting size is in bits

- **Location:** `name.ads`, comment line inside the loop
- **Original code:**
  ```
      -- Parameter {{ param.name }}, size of {{ (table_entry.size/8)|int }} byte(s), Entry_ID {{ table_entry.entry_id }}.
  ```
- **Explanation:** The expression `(table_entry.size/8)|int` performs Python floating-point division then truncates to integer. If `table_entry.size` is not a multiple of 8 (e.g., a 12-bit field), the truncation silently rounds down, producing a misleading comment. For a safety-critical system, the comment would report the wrong size. Use integer floor-division (`//`) to make the intent explicit, or better, add a guard.
- **Suggested fix:**
  ```
      -- Parameter {{ param.name }}, size of {{ (table_entry.size // 8) }} byte(s), Entry_ID {{ table_entry.entry_id }}.
  ```
  And ideally, the generator should assert `table_entry.size % 8 == 0` before producing this template.
- **Severity:** Medium

### Issue 1.4 — `Parameter_Table_Entries` uses unconstrained `aliased` array with aggregate bounds starting at 0

- **Location:** `name.ads`, declaration of `Parameter_Table_Entries`
- **Original code:**
  ```ada
   Parameter_Table_Entries : aliased Parameter_Table_Entry_List := [
      0 => (...),
      1 => (...),
      ...
   ];
  ```
- **Explanation:** The array is indexed starting at 0 by the template's `param_index` counter. This is correct Ada and will produce bounds `0 .. N-1`. However, the variable is declared `aliased` (for access-type usage), meaning consumers will take `'Access` on it. There is no explicit subtype constraint — the bounds are inferred from the aggregate. If any consumer assumes 1-based indexing (common Ada convention), this is a latent defect. A comment stating the intended bounds convention would improve safety.
- **Suggested fix:** Add a clarifying comment:
  ```ada
   -- 0-indexed parameter table entries for use via 'Access.
   Parameter_Table_Entries : aliased Parameter_Table_Entry_List := [
  ```
- **Severity:** Low

---

## 2. Package Implementation Review

No `.adb` (package body) exists for this template. The generated package is a pure specification containing only constants and a static array aggregate — no subprograms requiring a body. **No issues.**

---

## 3. Model Review (`name_record.record.yaml`)

### Issue 3.1 — `Crc_Calculated` placed before `Header` may conflict with over-the-wire layout expectations

- **Location:** `name_record.record.yaml`, field ordering
- **Original code:**
  ```yaml
  fields:
    - name: Crc_Calculated
      ...
    - name: Header
      ...
  ```
- **Explanation:** The CRC field is placed *first* in the record, before the header. In many parameter-table protocols, the CRC covers the header + data and is either appended at the end or stored separately. Placing it first means a straight memory overlay of an incoming parameter table buffer would expect the CRC to precede the header. This may be intentional for this system's protocol, but it is unusual and warrants verification. If the CRC is intended to be computed over the bytes that follow it, the `byte_image: True` and `skip_validation: True` flags are consistent with that intent. However, if any code computes the CRC over the entire record *including* the CRC field itself, the result would be wrong.
- **Suggested fix:** Add a comment in the description clarifying that the CRC precedes the table by design and specifying which bytes the CRC covers:
  ```yaml
    - name: Crc_Calculated
      description: "CRC-16 computed over the Header and all parameter data fields (does not include itself). Placed first in the record to match the uplink protocol format."
  ```
- **Severity:** Medium

### Issue 3.2 — No `default_value` specified for parameter entries

- **Location:** `name_record.record.yaml`, the `{% for %}` loop generating parameter fields
- **Original code:**
  ```yaml
    - name: {{ table_entry.parameters[0].component_name }}_{{ table_entry.parameters[0].parameter_name }}
      description: "..."
      type: {{ table_entry.parameters[0].parameter.type }}
  ```
- **Explanation:** The generated record fields for each parameter entry have no `default_value`. If the Adamant record framework initializes fields to binary zero when no default is specified, this is acceptable. However, if default values are defined in the parameter model (e.g., a parameter's nominal/safe value), they should propagate here so that a default-initialized parameter table contains safe values rather than all-zeros. In a safety-critical system, all-zero defaults could represent dangerous states (e.g., a gain of 0.0 disabling a control loop).
- **Suggested fix:** If the generator has access to parameter defaults, propagate them:
  ```yaml
    - name: {{ table_entry.parameters[0].component_name }}_{{ table_entry.parameters[0].parameter_name }}
      description: "..."
      type: {{ table_entry.parameters[0].parameter.type }}
  {% if table_entry.parameters[0].parameter.default_value is defined %}
      default_value: {{ table_entry.parameters[0].parameter.default_value }}
  {% endif %}
  ```
- **Severity:** High

---

## 4. Unit Test Review

No unit test files exist in this directory. Since this is a code-generation template, testing would occur at the generator level or via integration tests on generated output. **No template-level test issues to flag**, but the absence is noted.

---

## 5. Summary — Top 5 Issues

| # | ID | Severity | Summary |
|---|-----|----------|---------|
| 1 | 3.2 | **High** | No default values propagated for parameter entries in the record model — all-zero defaults may be unsafe |
| 2 | 1.1 | **Medium** | `End_Index` inclusive/exclusive semantics undocumented — off-by-one risk for consumers |
| 3 | 1.3 | **Medium** | Float division + truncation (`/8\|int`) silently rounds non-byte-aligned sizes in comment |
| 4 | 3.1 | **Medium** | CRC-before-Header field ordering is unusual; no documentation of which bytes the CRC covers |
| 5 | 1.4 | **Low** | 0-indexed array convention undocumented; consumers taking `'Access` may assume 1-based |

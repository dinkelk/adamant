# Code Review: `{{ name }}_Event_To_Text` Assembly Template Package

**Reviewed:** 2026-02-28
**Branch:** `review/components-event-text-logger-gen-templates-assembly`
**Scope:** `src/components/event_text_logger/gen/templates/assembly/`

---

## 1. Package Specification Review (`name_event_to_text.ads`)

### Issue 1.1 — Missing `Preelaborate` or `Pure` Pragma

- **Location:** `name_event_to_text.ads`, line 6 (package declaration)
- **Original Code:**
  ```ada
  package {{ name }}_Event_To_Text is
  ```
- **Explanation:** This package has no state and its single function is a pure mapping from `Event.T` to `String`. In Adamant's safety-critical context, stateless library packages should carry `pragma Preelaborate;` (or `pragma Pure;` if `Event` supports it) to enforce elaboration safety and prevent elaboration-order issues. Without it, the generated package may introduce elaboration dependencies that are difficult to diagnose at the assembly level, especially when the function access is passed as a discriminant during component elaboration.
- **Corrected Code:**
  ```ada
  package {{ name }}_Event_To_Text is
     pragma Preelaborate;
  ```
- **Severity:** **Medium** — Elaboration-order problems manifest silently as `Program_Error` at startup in deployed builds.

### No other specification issues found.

The specification is minimal, clean, and correctly typed. The `in` mode on the parameter is appropriate. Returning an unconstrained `String` matches the `Event_To_Text_Function_Access` signature used by the `Event_Text_Logger` component.

---

## 2. Package Implementation Review (`name_event_to_text.adb`)

### Issue 2.1 — Potential Unbounded String Construction in `when others`

- **Location:** `name_event_to_text.adb`, line 25
- **Original Code:**
  ```ada
  when others => return "Unrecognized event received with Id: " & Event_Types.Event_Id'Image (The_Event.Header.Id);
  ```
- **Explanation:** The `'Image` attribute on an integer type produces a string with a leading space for non-negative values (Ada RM 3.5(33)). In a text log this results in output like `"Unrecognized event received with Id:  42"` (double space). For flight telemetry logs that may be parsed by ground tools, this inconsistent formatting can cause parsing issues. Consider using `Trim` or a custom image function. Note: this is a cosmetic/interoperability issue, not a safety defect.
- **Corrected Code:**
  ```ada
  when others => return "Unrecognized event received with Id:" & Event_Types.Event_Id'Image (The_Event.Header.Id);
  ```
  Or, if leading-space removal is preferred:
  ```ada
  when others =>
     declare
        Id_Img : constant String := Event_Types.Event_Id'Image (The_Event.Header.Id);
     begin
        return "Unrecognized event received with Id: " & Id_Img (Id_Img'First + 1 .. Id_Img'Last);
     end;
  ```
- **Severity:** **Low** — Cosmetic formatting in fallback log path.

### Issue 2.2 — Empty Body When Assembly Has No Components

- **Location:** `name_event_to_text.adb`, lines 12–30 (the `{% if components %}` block)
- **Original Code:**
  ```jinja
  {% if components %}
     ...
     function Event_To_Text ...
  {% endif %}
  ```
- **Explanation:** When `components` is empty (or falsy), the template generates a package body with **no function body** for `Event_To_Text`, which was declared in the spec. This would be a compilation error. However, since the generator is an `assembly_generator` and assemblies without components wouldn't instantiate the `Event_Text_Logger`, this path is likely unreachable. Nonetheless, for template defensiveness, the else branch should provide a stub implementation. If a future assembly model has components but none with events, this same issue applies — the function body would be missing.
- **Corrected Code:**
  ```jinja
  {% if components %}
     function Event_To_Text (The_Event : in Event.T) return String is
     begin
        case The_Event.Header.Id is
  {% for component in components.values() %}
  ...
  {% endfor %}
           when others => return "Unrecognized event received with Id: " & Event_Types.Event_Id'Image (The_Event.Header.Id);
        end case;
     end Event_To_Text;
  {% else %}
     function Event_To_Text (The_Event : in Event.T) return String is
        pragma Unreferenced (The_Event);
     begin
        return "No events registered in this assembly.";
     end Event_To_Text;
  {% endif %}
  ```
- **Severity:** **High** — A missing function body is a compilation failure. While unlikely to be triggered by current usage, template robustness is important for a code generator.

### Issue 2.3 — `with Event_Types;` May Be Unused When No Components Exist

- **Location:** `name_event_to_text.adb`, line 2
- **Original Code:**
  ```ada
  with Event_Types;
  ```
- **Explanation:** If the `{% if components %}` guard removes the function body, `Event_Types` is `with`'d but never referenced, causing an unused-with warning (though our assumptions say "compiles without warnings," this template path may not be tested). This is a direct consequence of Issue 2.2.
- **Severity:** **Low** — Dependent on Issue 2.2; fixing 2.2 resolves this.

### Issue 2.4 — No Guard for Components With Events but Empty Event Lists

- **Location:** `name_event_to_text.adb`, lines 18–22
- **Original Code:**
  ```jinja
  {% for component in components.values() %}
  {% if component.events %}
  {% for event in component.events %}
           when {{ event.id }} => return {{ component.events.name }}.Representation.{{ event.name }}_Image (The_Event, "{{ component.instance_name }}");
  {% endfor %}
  {% endif %}
  {% endfor %}
  ```
- **Explanation:** If **all** components exist but **none** have events, the `case` statement would contain only the `when others` arm. While this is valid Ada, generating a `case` with only `when others` is a style concern and could trigger compiler notes. More importantly, the `with` clauses at the top (generated by the `{% if components[0].events %}` guard in the import loop) would be empty, but the iteration logic uses `component_types_dict` (keyed by type) while the body iterates `components` (keyed by instance). If these collections diverge, the wrong `Representation` package could be `with`'d or missed.
- **Severity:** **Medium** — Data model coupling between `component_types_dict` and `components` is implicit and fragile.

---

## 3. Model Review (`event_to_text.py`)

### Issue 3.1 — No Template Validation or Error Handling

- **Location:** `gen/generators/event_to_text.py`, entire file
- **Original Code:**
  ```python
  class event_to_text_ads(assembly_generator, generator_base):
      def __init__(self):
          this_file_dir = os.path.dirname(os.path.realpath(__file__))
          template_dir = os.path.join(this_file_dir, ".." + os.sep + "templates")
          assembly_generator.__init__(
              self, "name_event_to_text.ads", template_dir=template_dir
          )
  ```
- **Explanation:** The generator classes do no validation of the assembly model before rendering. For a safety-critical code generator, it would be prudent to assert preconditions (e.g., that event IDs are unique across all components, that `component.events.name` is defined when `component.events` is truthy). Duplicate event IDs in the model would generate a `case` statement with duplicate `when` values — a compilation error, but one that is hard to trace back to the model. An explicit check with a clear error message at generation time would save significant debugging effort.
- **Corrected Code:**
  ```python
  class event_to_text_adb(assembly_generator, generator_base):
      def __init__(self):
          this_file_dir = os.path.dirname(os.path.realpath(__file__))
          template_dir = os.path.join(this_file_dir, ".." + os.sep + "templates")
          assembly_generator.__init__(
              self, "name_event_to_text.adb", template_dir=template_dir
          )

      def generate(self, model):
          # Validate unique event IDs across all components
          seen_ids = {}
          for comp in model.components.values():
              if comp.events:
                  for event in comp.events:
                      if event.id in seen_ids:
                          raise ValueError(
                              f"Duplicate event ID {event.id}: "
                              f"{seen_ids[event.id]} and {comp.instance_name}.{event.name}"
                          )
                      seen_ids[event.id] = f"{comp.instance_name}.{event.name}"
          return super().generate(model)
  ```
- **Severity:** **Medium** — Lack of generator-side validation shifts error discovery to compile time with poor diagnostics.

---

## 4. Unit Test Review

No unit tests exist within the `assembly/` directory or its parent `templates/` directory for the generated output of these templates.

### Issue 4.1 — No Template-Level Tests

- **Location:** N/A (missing files)
- **Explanation:** While the `Event_Text_Logger` component has integration tests (in `test/`), there are no tests that exercise the template rendering directly — e.g., verifying that a known assembly model produces expected Ada source, or that edge cases (no components, no events, single component) generate compilable code. For a safety-critical code generator, template-level tests would catch regressions in the Jinja templates independently of a full assembly build.
- **Severity:** **Medium** — Template regressions would only be caught by downstream compilation, not at the generator level.

---

## 5. Summary — Top 5 Issues

| # | Severity | Location | Description |
|---|----------|----------|-------------|
| 1 | **High** | `name_event_to_text.adb` (template) | Missing function body when `components` is empty/falsy — generates uncompilable Ada (Issue 2.2) |
| 2 | **Medium** | `name_event_to_text.adb` (template) | Implicit coupling between `component_types_dict` (imports) and `components` (body) could produce mismatched `with` clauses (Issue 2.4) |
| 3 | **Medium** | `event_to_text.py` | No generator-side validation of event ID uniqueness or model consistency (Issue 3.1) |
| 4 | **Medium** | `name_event_to_text.ads` | Missing `pragma Preelaborate` on stateless package risks elaboration-order issues (Issue 1.1) |
| 5 | **Medium** | N/A | No template-level unit tests for edge cases in code generation (Issue 4.1) |

# Last Chance Manager — Code Review

**Component:** `src/components/last_chance_manager`
**Branch:** `review/components-last-chance-manager`
**Date:** 2026-02-28
**Reviewer:** Automated (Claude)

---

## 1. Documentation Review

### DOC-01 — Requirements refer to wrong component name (Low)

**File:** `last_chance_manager.requirements.yaml`, line 4
```yaml
description: The requirements for the Last Chance Handler component.
```
**Explanation:** The component is *Last Chance Manager*; the description says "Last Chance Handler component." This inconsistency propagates into the generated PDF.
```yaml
description: The requirements for the Last Chance Manager component.
```

### DOC-02 — LaTeX escape in YAML description is fragile (Low)

**File:** `last_chance_manager.packets.yaml`, line 2
```yaml
description: The second packet listed here is not actually produced by the Last Chance Manager component, but instead should be produced by the implementation of the Last\_Chance\_Handler.
```
**Explanation:** The backslash-escaped underscore (`Last\_Chance\_Handler`) is LaTeX markup embedded in a YAML description field. If consumed by any non-LaTeX renderer (ground system UI, auto-generated Ada comments, etc.) the backslash appears literally. The YAML description should use plain text; LaTeX escaping should be handled by the document generator.
```yaml
description: The second packet listed here is not actually produced by the Last Chance Manager component, but instead should be produced by the implementation of the Last_Chance_Handler.
```

### DOC-03 — `.tex` includes sections that do not apply (Low)

**File:** `doc/last_chance_manager.tex`, lines for `\subsection{Interrupts}` and `\subsection{Parameters}`
```latex
\subsection{Interrupts}
\input{build/tex/last_chance_manager_interrupts.tex}
...
\subsection{Parameters}
\input{build/tex/last_chance_manager_parameters.tex}
```
**Explanation:** This component has no interrupts and no parameters. Including these sections produces empty or "N/A" subsections in the PDF, adding clutter. Remove them or guard with a conditional.

---

## 2. Model Review

### MOD-01 — Events do not specify severity (Medium)

**File:** `last_chance_manager.events.yaml`
```yaml
  - name: Last_Chance_Handler_Called
    description: The component detected that the LCH was called ...
    param_type: Packed_Stack_Trace_Info.T
```
**Explanation:** None of the four events declare a severity/criticality. In Adamant, event severity drives ground-system alarm routing. `Last_Chance_Handler_Called` is a safety-significant indicator (an unhandled exception occurred in flight) and should carry at least `Warning` or `Critical` severity. `Invalid_Command_Received` should be `Warning`. The informational events (`Dumped…`, `Cleared…`) should be `Informational`. Without explicit severity the generator picks a default, which may be too low for `Last_Chance_Handler_Called`.

**Corrected (example):**
```yaml
  - name: Last_Chance_Handler_Called
    description: ...
    param_type: Packed_Stack_Trace_Info.T
    severity: Critical
  - name: Dumped_Last_Chance_Handler_Region
    description: ...
    severity: Informational
  - name: Cleared_Last_Chance_Handler_Region
    description: ...
    severity: Informational
  - name: Invalid_Command_Received
    description: ...
    param_type: Invalid_Command_Info.T
    severity: Warning
```

### MOD-02 — Requirements are incomplete (Low)

**File:** `last_chance_manager.requirements.yaml`
**Explanation:** The component also (a) reports a data product with stack-trace info, (b) raises an event when it detects the LCH was called, and (c) optionally dumps the region at startup. None of these behaviours are captured as requirements. Traceability from requirements → implementation is therefore incomplete.

**Suggested additions:**
```yaml
  - text: The component shall report a data product containing the stack trace depth and bottom address after every dump.
  - text: The component shall emit an event when it detects the last chance handler was invoked.
  - text: The component shall optionally dump the memory region at startup based on an initialization parameter.
```

---

## 3. Component Implementation Review

### IMPL-01 — Data product not updated when `Dump_Exception_Data_At_Startup` is False (Medium)

**File:** `component-last_chance_manager-implementation.adb`, `Set_Up` procedure (≈line 40)
```ada
   overriding procedure Set_Up (Self : in out Instance) is
      The_Time : constant Sys_Time.T := Self.Sys_Time_T_Get;
   begin
      if Self.Dump_Exception_Data_At_Startup then
         Self.Send_Out_Packet_And_Data_Product (The_Time);
      end if;
   end Set_Up;
```
**Explanation:** When `Dump_Exception_Data_At_Startup` is `False`, `Set_Up` does nothing — no data product is published and no LCH-called event is raised, even though the memory region may contain valid exception data from a previous crash. An operator relying on the `Lch_Stack_Trace_Info` data product or the `Last_Chance_Handler_Called` event to detect a prior crash will receive no indication at all. The data product and event check should always be performed; only the (potentially large) packet dump should be gated by the flag.

**Corrected:**
```ada
   overriding procedure Set_Up (Self : in out Instance) is
      The_Time : constant Sys_Time.T := Self.Sys_Time_T_Get;
   begin
      if Self.Dump_Exception_Data_At_Startup then
         -- Send the full packet dump:
         Self.Packet_T_Send_If_Connected (
            Self.Packets.Lch_Memory_Region_Dump (The_Time, Self.Exception_Data.all));
      end if;

      -- Always report data product and check for LCH invocation:
      declare
         Stack_Trace_Info : constant Packed_Stack_Trace_Info.T :=
            (Stack_Trace_Depth          => Self.Exception_Data.Stack_Trace_Depth,
             Stack_Trace_Bottom_Address => Self.Exception_Data.Stack_Trace (0));
      begin
         Self.Data_Product_T_Send_If_Connected (
            Self.Data_Products.Lch_Stack_Trace_Info (The_Time, Stack_Trace_Info));
         if Stack_Trace_Info.Stack_Trace_Depth > 0
           or else Stack_Trace_Info.Stack_Trace_Bottom_Address.Address
                   /= To_Address (Integer_Address (0))
         then
            Self.Event_T_Send_If_Connected (
               Self.Events.Last_Chance_Handler_Called (The_Time, Stack_Trace_Info));
         end if;
      end;
   end Set_Up;
```
**Severity:** Medium

### IMPL-02 — `Sys_Time_T_Get` called even when `Dump_Exception_Data_At_Startup` is False (Low)

**File:** `component-last_chance_manager-implementation.adb`, `Set_Up` (≈line 39)
```ada
      The_Time : constant Sys_Time.T := Self.Sys_Time_T_Get;
   begin
      if Self.Dump_Exception_Data_At_Startup then
```
**Explanation:** The system-time getter is invoked unconditionally, but its result is discarded when the flag is `False`. This is a minor inefficiency and a wasted connector call. Move the call inside the `if` (or always use it per IMPL-01 fix).

---

## 4. Unit Test Review

### TEST-01 — No test for `Dump_Exception_Data_At_Startup => False` (High)

**File:** `test/last_chance_manager_tests-implementation.adb`, `Set_Up_Test` (≈line 27)
```ada
      Self.Tester.Component_Instance.Init (
         Exception_Data              => Exception_Data'Access,
         Dump_Exception_Data_At_Startup => True);
```
**Explanation:** Every test case initialises the component with `Dump_Exception_Data_At_Startup => True`. The `False` path in `Set_Up` is never exercised, so the behaviour when the flag is `False` is completely untested. This is a significant coverage gap, especially considering the design issue in IMPL-01. A dedicated test should init with `False`, populate the exception region, call `Set_Up`, and verify:
- No packet is sent (if dump is suppressed).
- The data product IS sent (if IMPL-01 is fixed) or is NOT sent (current behaviour — test documents it).
- The `Last_Chance_Handler_Called` event fires or does not fire appropriately.

### TEST-02 — Tests do not exercise the `_Dropped` callbacks (Low)

**File:** `component-last_chance_manager-implementation.ads`
```ada
   overriding procedure Command_Response_T_Send_Dropped (Self : in out Instance; Arg : in Command_Response.T) is null;
   overriding procedure Event_T_Send_Dropped (Self : in out Instance; Arg : in Event.T) is null;
   overriding procedure Packet_T_Send_Dropped (Self : in out Instance; Arg : in Packet.T) is null;
   overriding procedure Data_Product_T_Send_Dropped (Self : in out Instance; Arg : in Data_Product.T) is null;
```
**Explanation:** All `_Dropped` handlers are `is null`. While this is a deliberate design choice (passive component, sync connectors), there is no test confirming that dropping a message is benign. This is low severity because the handlers are literally no-ops, but a brief test calling them documents the intent.

### TEST-03 — `Set_Up` called twice in `Test_Region_Clear` without re-init (Low)

**File:** `test/last_chance_manager_tests-implementation.adb`, `Test_Region_Clear` (≈line 118)
```ada
      Self.Tester.Component_Instance.Set_Up;
```
**Explanation:** `Set_Up` is called once in the fixture (`Set_Up_Test`) and then again explicitly in this test after modifying `Exception_Data`. Calling `Set_Up` twice is not necessarily wrong, but it is unusual for Adamant components and could mask issues if `Set_Up` ever acquires one-time-only side effects (e.g. command registration). A comment explaining the intentional double call would improve clarity.

---

## 5. Summary — Top 5 Issues

| # | ID | Severity | Summary |
|---|-----|----------|---------|
| 1 | TEST-01 | **High** | `Dump_Exception_Data_At_Startup => False` path is entirely untested. |
| 2 | MOD-01 | **Medium** | Events lack explicit severity; `Last_Chance_Handler_Called` should be Critical. |
| 3 | IMPL-01 | **Medium** | Data product and LCH-called event are suppressed when startup dump is disabled, hiding prior crashes. |
| 4 | MOD-02 | **Low** | Requirements do not cover data-product reporting, LCH-detected event, or startup-dump behaviour. |
| 5 | DOC-01 | **Low** | Requirements description references "Last Chance Handler component" instead of "Last Chance Manager." |

## Resolution Notes

| # | Issue | Severity | Status | Commit | Notes |
|---|-------|----------|--------|--------|-------|
| 1 | Dump_At_Startup=False untested | High | Fixed | 9e22815 | Added test |
| 2 | Events lack severity | Medium | Not Fixed | 266379b | No schema support |
| 3 | Silent crash evidence hiding | Medium | Fixed | 0a0a952 | Always sends DP + event |
| 4 | Wrong component name in reqs | Low | Fixed | a497de9 | Corrected |
| 5 | LaTeX escapes in YAML | Low | Fixed | f401e47 | Removed |
| 6 | Empty LaTeX sections | Low | Fixed | bec2791 | Removed |
| 7 | Missing requirements | Low | Fixed | e2c9770 | Added 3 |
| 8 | Unused time connector | Low | Fixed | b67a077 | Resolved by item 3 |
| 9 | Null handlers | Low | Not Fixed | c14e53f | Can't test meaningfully |
| 10 | Double Set_Up intent | Low | Fixed | 75fe90a | Added comment |

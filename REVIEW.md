# REVIEW.md — Issues Found During Spelling/Grammar Review

This file tracks potential bugs, logic errors, and inconsistencies discovered during the automated spelling and grammar review of the Adamant codebase. These go beyond simple typos and may warrant human review.

---

## Issue #1: Comment/code mismatch — event_component tester tick count

- **Date found:** 2026-02-11
- **File:** `doc/example_architecture/event_component/test/component-event_component-implementation-tester.adb`
- **Description:** Comment for `Ten_More_Ticks_Received` said "every 20 ticks" but the event YAML, the `.ads` tester spec, and the actual component implementation all say "every 10 ticks".
- **Resolution:** Fixed — comment updated to say "10 ticks".
- **Severity:** Low (comment only, no runtime impact)

## Issue #2: Comment/code mismatch — test_better3 and test_better4 expected value

- **Date found:** 2026-02-12
- **Files:**
  - `doc/example_architecture/simple_package/test_better3/simple_package_tests-implementation.adb`
  - `doc/example_architecture/simple_package/test_better4/simple_package_tests-implementation.adb`
- **Description:** Comment says "Result should equal -9" but the assertion checks for `-8` (`Integer_Assert.Eq(..., -8)`). The arithmetic is `7 + (-15) = -8`, so the code is correct and the comment was wrong.
- **Resolution:** Fixed — comment updated to say "-8".
- **Severity:** Low (comment only, no runtime impact)
- **Note:** Worth verifying the intended test values if the original author meant `-9` (which would imply different input values).

### Issue 5 — 2026-02-12
- **File(s):**
  - `src/components/event_filter/event_filter.events.yaml`
  - `src/components/event_filter/component-event_filter-implementation.adb`
  - `src/components/event_filter/test/component-event_filter-implementation-tester.adb`
  - `src/components/event_filter/test/component-event_filter-implementation-tester.ads`
  - `src/components/event_limiter/event_limiter.events.yaml`
  - `src/components/event_limiter/component-event_limiter-implementation.adb`
  - `src/components/event_limiter/test/component-event_limiter-implementation-tester.adb`
  - `src/components/event_limiter/test/component-event_limiter-implementation-tester.ads`
- **Description:** Event name `Dump_Event_States_Recieved` is misspelled (should be `Received`). However, this name is defined in YAML event models and propagates into auto-generated Ada identifiers and hand-written code. Renaming in YAML alone would break the build; a coordinated rename across YAML + generated code + implementation + tests is required.
- **Severity:** Low (cosmetic typo in identifier, no functional impact)
- **Note:** Requires coordinated rename across ~32 references in 8+ files. Not safe to fix as a simple spelling correction.

## Issue #6: ARM64 CI workflows only test one component instead of entire repo

- **Date found:** 2026-02-13
- **Files:**
  - `.github/workflows/style_all_arm64.yml`
  - `.github/workflows/test_all_arm64.yml`
- **Description:** The ARM64 style workflow runs `redo src/components/command_router/style_all` (only command_router) while the non-ARM64 version runs `redo style_all` (entire repo). Similarly, the ARM64 test workflow runs `redo src/components/command_router/coverage_all` instead of `redo coverage_all`. This means ARM64 CI only validates one component.
- **Severity:** Medium (CI coverage gap — ARM64 builds are not fully tested)
- **Note:** Likely a copy-paste error from testing. The x86 workflows are correct.

## Issue #7: Missing `disp` call in MATLAB test file

- **Date found:** 2026-02-13
- **File:** `doc/example_architecture/record_m/test.m`
- **Description:** Line `("serializing and deserializing example record:");` is missing `disp` — should be `disp("serializing...")`. Without it, MATLAB would try to index `ans` with a string, causing a runtime error.
- **Resolution:** Fixed — added `disp`.
- **Severity:** Medium (test would fail at runtime)

## Issue #8: "two's compliment" → "two's complement" in MATLAB Bit_Array

- **Date found:** 2026-02-13
- **File:** `gnd/matlab/Bit_Array.m`
- **Description:** Two comments use "compliment" (a flattering remark) instead of "complement" (the mathematical term for two's complement representation).
- **Resolution:** Fixed.
- **Severity:** Low (comment only)

## Issue #9: Duplicate `<b>Summary:</b>` in seq template

- **Date found:** 2026-02-13
- **File:** `src/components/command_sequencer/gen/templates/assembly/name_seq.html`
- **Description:** The Summary label appears twice in the info block.
- **Resolution:** Fixed — removed duplicate.
- **Severity:** Low (cosmetic in generated HTML)

## Issue #10: Extra `>` in CPU monitor XML template

- **Date found:** 2026-02-13
- **File:** `src/components/cpu_monitor/gen/templates/assembly/name_cpu_monitor.xml`
- **Description:** Line has `</tableHeading>>` with an extra `>` — invalid XML that would cause parsing errors in generated output.
- **Resolution:** Fixed.
- **Severity:** Medium (would produce malformed XML)

## Issue #11: Copy-paste error in parameter table XML template section name

- **Date found:** 2026-02-13
- **File:** `src/components/parameters/gen/templates/parameter_table/name.xml`
- **Description:** Section name says "Cpu Usage Packet Header:" but this is the parameter table template, not CPU monitor. Should be "Parameter Packet Header:".
- **Resolution:** Fixed.
- **Severity:** Low (cosmetic in generated UI)

## Deep Review Pass - 2026-02-13

### Bugs / Significant Issues Found

1. **architecture_description_document.tex**: Says "component without a queue" but the next sentence references "messages from its queue" — contradictory. Fixed to "with a queue".

2. **event_limiter .ads/.adb**: Init parameter descriptions for `event_Id_Start` and `event_Id_Stop` were copy-pasted from `event_packetizer` and described packet counts/timeouts instead of event ID ranges. Fixed to match YAML model.

3. **pid_controller .ads**: Init parameter comment listed `diagnostic_Stats_Length : Unsigned_16` but actual parameter is `Moving_Average_Max_Samples : Natural`. Fixed.

4. **event_filter .adb**: Assert messages referenced "Event Limiter" instead of "Event Filter" (copy-paste from event_limiter). Fixed.

5. **event_filter .adb**: Comment said "enable the component level variable" in `Disable_Event_Filtering` function. Fixed to "disable".

6. **fault_correction .adb**: "to product that data product" → "to produce that data product".

7. **memory_stuffer .adb**: "Do copy memory is the destination" → "Do copy memory if the destination".

### Spelling/Grammar Fixes

- user_guide.tex: "permeates" → "permeate", "an all below it" → "and all below it" (3x), "an Ada package an unit testing" → "and", "a error message" → "an error message", "a event model" → "an event model"
- src/README.md: "data_structure/" → "data_structures/"
- database/README.md: "lookuplike" → "lookup like"
- copy_all_matlab_autocode.sh: usage message referenced wrong script name
- instructions.md: "an sequence" → "a sequence"
- logger tests: "pointer send via" → "pointer sent via" (36 occurrences across 2 files)
- memory_stuffer: "requiring and arm command" → "requiring an arm command" (3 files)
- memory_stuffer: "Disabled protected write" → "Disable protected write"
- stack_monitor: "first bye not matching" → "first byte not matching"
- fault_correction: "not allowed fault response table" → "not allowed in fault response table"
- socket_event_decoder.py: "a event log" → "an event log"
- ccsds_downsampler requirements: "a initial list" → "an initial list"
- moving_average test: "a invalid initialization" → "an invalid initialization"

## Batch 2026-02-14 Deep Read (doc/example_architecture continued)

### Fixes Applied
- init_base_component .ads: "an base package" → "a base package" (grammar)
- example_component_set_id_bases commands.yaml: "Command Router component" → "Example Component" (copy-paste from command_router)

### Potential Bugs (not fixed — need maintainer review)
- initialized_component .adb: `Enabled_At_Startup` parameter is stored in Init but never checked in `Tick_T_Recv_Sync`. The description says "If False, no packets will be produced" but the code always sends packets regardless. Likely missing an `if Self.Enabled_At_Startup then` guard.

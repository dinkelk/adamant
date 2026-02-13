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

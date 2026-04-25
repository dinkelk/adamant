# Pico Command Router Test Prototype

## Goal

Determine whether the `command_router` unit test can be compiled for embedded Pico hardware using the Adamant example repo/container, and identify what blocks a full embedded test workflow.

## Bottom line

We got the `command_router` Pico test prototype to **compile successfully into an ARM embedded ELF**.

The final failure is no longer a compile problem. The remaining failure is that the normal `redo test` flow tries to **execute the embedded ELF on the Linux host**, which results in:

- `Exec format error`

So the prototype answered the original question:

- **Can it compile for Pico?** Yes.
- **Can the existing `redo test` path run it unchanged?** No — because the default test flow assumes host execution.

## Environment used

- Repo: `adamant`
- Container: `adamant_example_container`
- Test target explored: `Pico_Test` (prototype)
- Component under test: `src/components/command_router/test`

## Major findings

### 1. There was no existing `Pico_Test` target

The first blocker was simply that `Pico_Test` was not defined in the current setup.

A prototype target was added in `adamant_example/redo/targets/`:

- `pico_test.py`
- `gpr/pico_test.gpr`

This gave us a way to iterate on an embedded unit-test-specific target separately from the existing host test targets.

### 2. Build path conflict: duplicate `diagnostic_uart.ads`

A build path collision blocked early Pico attempts:

- `src/components/ccsds_serial_interface/uart/diagnostic_uart.ads`
- `adamant_example/src/pico_util/uart/diagnostic_uart.ads`

Temporary workaround during testing:

- disable `src/components/ccsds_serial_interface/uart/.all_path`

Important:

- this was only a temporary compile workaround during experiments
- the file was restored afterward

### 3. Host-only unit test support code had to be split from Pico-safe code

The existing test support stack assumed Linux/host features.

To make Pico compilation possible, target-specific variants were introduced for:

#### File logger

- host version moved to `src/unit_test/file_logger/linux_test/`
- Pico no-op version added in `src/unit_test/file_logger/pico/`

#### Unit test termination handler

- host version moved to `src/unit_test/termination_handler/linux_test/`
- Pico no-op version added in `src/unit_test/termination_handler/pico/`

#### Smart assert

- host version moved to `src/unit_test/smart_assert/linux_test/`
- Pico-safe version added in `src/unit_test/smart_assert/pico/`

This pattern turned out to be the right shape for embedded test support:

- keep host behavior for Linux test targets
- provide stripped/no-op variants for embedded targets

### 4. The generic generated test scaffold had several host assumptions

The generated `*_tests.ads/adb` scaffold pulled in a number of host/runtime assumptions that blocked embedded builds.

These were removed or worked around during the prototype:

#### Calendar dependency

The generated scaffold used `Ada.Calendar` only for test start time / duration logging.

That was removed from:

- `gen/templates/tests/name.ads`
- `gen/templates/tests/name.adb`

and from the current generated `command_router` build copies used for the prototype.

#### Host filesystem / argv dependency

The scaffold used:

- `Ada.Command_Line`
- `Ada.Directories`

only to derive a log filename.

For embedded tests this was replaced with a simpler logger init that does not depend on host filesystem discovery.

### 5. Ada 2022 image generation exposed embedded runtime limitations

While compiling for Pico, Ada 2022 `Put_Image` behavior caused the compiler/runtime to descend into protected internals that the embedded runtime/profile did not support well.

A targeted workaround was added by defining a trivial explicit `Put_Image` for:

- `Component.Command_Router.Implementation.Instance`

This avoided one of the protected-type image-related failures.

### 6. AUnit under Jorvik was a major incompatibility point

AUnit caused several classes of problems for embedded Pico/Jorvik:

- local protected object restrictions
- allocator restrictions
- fixture construction behavior not friendly to the Jorvik profile
- missing cross-built AUnit library artifacts for `arm-eabi-zfp-cross`

The prototype conclusion is that **AUnit is not the right execution path for this embedded workflow**, at least not without substantial dedicated support.

### 7. Dynamic tester allocation had to be removed

The generated/component test stack used heap allocation for the tester object.

Under the embedded profile this caused allocator/protected-object issues.

The prototype was changed to use a statically held tester/runner path instead of the original heap-based fixture pattern.

### 8. History and Smart_Assert needed to stop leaning on AUnit assertions

Even after removing the AUnit suite runner, AUnit was still being pulled in transitively by support packages.

To reduce that dependency chain:

- `History` was changed to use `Smart_Assert`
- Pico `Smart_Assert` was reduced to use direct assertion failure behavior rather than AUnit assertions
- `Basic_Assertions` visibility was restored for the new target-specific smart-assert layout

### 9. The real breakthrough: remove AUnit inheritance from the generated test base

The critical generator-level issue turned out to be this:

- generated `Base_Instance` inherited from `AUnit.Test_Fixtures.Test_Fixture`

Even after bypassing the AUnit suite runner, that inheritance alone forced AUnit back into the build.

For the prototype, the generated `command_router_tests` base was changed into a plain tagged limited type with normal setup/teardown procedures.

This was the key step that allowed the embedded compile to finish.

### 10. Final compile outcome

After all of the above, `redo test` for the Pico prototype progressed far enough to build:

- `build/bin/Pico_Test/test.elf`

The final failure was:

- Linux trying to execute the ARM embedded ELF locally

That means the prototype succeeded at compile time.

## What was accomplished

### Successfully demonstrated

- embedded compilation of the `command_router` test stack is possible
- the main issues are in the test framework/support/generation layers, not in `command_router` alone
- a target-specific embedded test path can be prototyped without requiring the existing Linux/AUnit path to be thrown away

### Produced a working prototype direction

The prototype established a viable architecture for embedded component tests:

1. define a dedicated embedded test target (`Pico_Test`)
2. use Pico-safe support packages for logging/assertion/termination
3. avoid host-only runtime services in generated test scaffolds
4. avoid AUnit inheritance and suite-running for embedded targets
5. use a custom embedded runner
6. treat the embedded ELF as a build artifact unless a flash/deploy/run step is explicitly provided

## Most important lessons learned

### Embedded tests should not reuse host `redo test` semantics unchanged

For Linux tests, `redo test` means:

- build binary
- run binary on host

For embedded tests, that is the wrong mental model.

For Pico-like targets, `redo test` should probably mean one of:

- build only
- build + flash
- build + deploy + run-through-hardware harness
- build + emulator run (if supported)

But not “build embedded ARM ELF and try to exec it on x86 Linux.”

### The biggest blockers were framework assumptions, not component logic

The prototype did **not** fail because `command_router` itself is inherently unportable.

The main blockers were:

- test support packages assuming host IO / host runtime features
- AUnit-specific type hierarchy and runner behavior
- generator output tailored only for host-style testing

### Target-specific unit-test support is the right design

The split into:

- `linux_test/`
- `pico/`

for unit-test support code worked well conceptually.

That looks like the correct long-term pattern for embedded Adamant tests.

## Recommended next steps

### Short-term practical next step

Add a clean embedded-test mode where:

- the target builds the test ELF
- the build stops successfully after ELF creation
- it does **not** attempt host execution

This alone would make the prototype usable as a compile validation path.

### Medium-term generator work

Teach the test generator to support an embedded mode that:

- does not inherit from `AUnit.Test_Fixtures`
- does not generate AUnit suite wiring
- emits a plain tagged limited base type
- emits setup/teardown hooks usable by a custom embedded runner

### Medium-term runner work

Create a standard embedded runner pattern that:

- invokes generated test procedures directly
- does not require AUnit
- can optionally report via UART/semihosting/other embedded output path

### Longer-term execution options

For real embedded test execution:

- flash to Pico hardware and run there
- add deployment hooks into redo for embedded test targets
- or support emulator-based execution if available

## Summary in one sentence

We proved that `command_router` embedded Pico unit tests are **compilable**, but the current Adamant unit-test framework and `redo test` flow are still host-centric and need an embedded-specific generation/execution path.

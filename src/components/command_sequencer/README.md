Note that the unit tests for this component have been disabled for continuous integration. The sequence compilation tool (SEQ compiler) that is used to generate the binary sequences used by this component is not yet publicly available, but is planned to be released for use sometime in the future.

## Running Unit Tests Locally

To run the unit tests, you must have access to the LASP SEQ compiler tool. Once available:

1. Navigate to `test/test_sequences/`
2. Run `redo all.do` (or equivalent build command) to compile the `.txt` sequence source files into `.bin` binary sequences
3. The `default.bin.do` and `default.txt.do` build scripts control per-sequence compilation
4. Return to the component `test/` directory and run the test suite via the standard Adamant test harness

Pre-compiled binary sequences are not currently checked in due to the proprietary nature of the SEQ compiler. When the tool becomes publicly available, CI integration should be re-enabled.

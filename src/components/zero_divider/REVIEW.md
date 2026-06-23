# Zero Divider — Component Review

**Date:** 2026-03-01
**Reviewer:** Automated (Claude)

## Summary

The Zero Divider is a **passive** Adamant component that provides a commandable way to intentionally trigger Ada's Last Chance Handler via a divide-by-zero exception. It includes a magic number protection mechanism to prevent accidental execution.

## Architecture & Design

**Purpose:** Intentional fault injection — allows operators to test the system's Last Chance Handler path.

**Connectors:**
- `Command.T` recv_sync (inbound commands)
- `Command_Response.T` send (command acknowledgement)
- `Sys_Time.T` get (timestamps for events)
- `Event.T` send (event reporting)

**Init parameters:**
- `Magic_Number` (Unsigned_32, range 2..U32'Last) — guards against accidental execution
- `Sleep_Before_Divide_Ms` (Natural, default 1000) — delay before the divide, allowing events to flush

## Strengths

1. **Clean safety design** — The magic number guard effectively prevents accidental execution. Restricting values 0 and 1 via the subtype is a nice touch.
2. **Good event coverage** — Events for both success path (`Dividing_By_Zero`) and failure path (`Invalid_Magic_Number`, `Invalid_Command_Received`).
3. **Well-structured tests** — Three focused unit tests covering the bad magic number, successful divide-by-zero (catching `Constraint_Error`), and invalid command handling.
4. **Thoughtful sleep mechanism** — The configurable delay before the divide gives the system time to flush the "about to crash" event, which is operationally important.
5. **LCH packet definition** — Embedding the Last Chance Handler packet definition here (even though the component doesn't send it) is a practical approach to ensure ground system tooling picks it up.
6. **Sensible defaults** — The private record initializes `Magic_Number` to `Magic_Number_Type'Last - 5` as a fallback if `Init` is never called, making accidental triggering unlikely.

## Observations & Minor Concerns

1. **`Sleep` in a passive component** — The component calls `Sleep.Sleep_Ms` during command execution. Since this is a `recv_sync` connector, the caller's task is blocked for the sleep duration. This is documented/intentional, but worth noting that it ties up the commanding task.

2. **`Zero` field in the record** — The `Zero : Natural := 0` field exists solely to produce a divide-by-zero at runtime. The compiler could theoretically optimize `1000 / 0` if it were a literal. Using a record field is the correct workaround, but a comment explaining *why* it's a field (to prevent compile-time detection) would help future readers.

3. **No command registration in `Set_Up`** — `Set_Up` is null. If command registration is handled elsewhere in the framework, this is fine. Just noting it.

4. **Test coverage gap** — No test for the edge case where `Magic_Number` equals the actual magic number but `Sleep_Before_Divide_Ms` is 0. This is minor since the sleep path is trivial.

5. **LaTeX doc references `build/` artifacts** — The `.tex` file includes many `build/tex/` and `build/eps/` files. Standard for Adamant's doc generation, but the doc can't render standalone without a build.

## Requirements Traceability

| Requirement | Implementation |
|---|---|
| Shall provide a command that causes an unhandled exception | `Divide_By_Zero` command → `1_000 / Self.Zero` |
| Shall protect the command from accidental execution | Magic number argument validation with subtype range 2..U32'Last |

Both requirements are met and tested.

## Verdict

**Well-implemented, minimal-scope component.** The code is clean, the safety mechanism is sound, and the tests cover the important paths. No bugs or significant issues found. The only actionable suggestion is adding a brief comment on the `Zero` field explaining the compile-time optimization avoidance rationale.

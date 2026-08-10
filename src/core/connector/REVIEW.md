# Code Review: `src/core/connector`

**Date:** 2026-03-01
**Reviewer:** Gus (automated)

## Overview

This package implements a **type-safe, generic connector (port) system** for wiring Adamant components together. Four connector variants cover all input/output/return combinations:

| Generic Package | Direction | Has Input? | Has Return? | Queue Semantics? |
|---|---|---|---|---|
| `In_Connector` | Caller → Invokee | ✅ | Status only | ✅ (`Full_Queue_Action`) |
| `Return_Connector` | Caller ← Invokee | ❌ | ✅ | ❌ |
| `In_Return_Connector` | Caller → Invokee, returns value | ✅ | ✅ | ❌ |
| `In_Out_Connector` | Caller ↔ Invokee (in-out param) | ✅ (mutable) | ❌ | ❌ |

`Connector_Types` provides shared index/count types and queue-related enumerations. `Common_Connectors` consolidates frequently-used instantiations to avoid code bloat from duplicate generic expansions.

## Architecture Assessment

**Strengths:**

1. **Clean generic design.** Each connector variant is a small, focused generic with a uniform `Attach`/`Call`/`Is_Connected` API. Minimal surface area, easy to reason about.
2. **Code-size optimization.** `Common_Connectors` centralizes instantiations — critical for embedded/flight targets where binary size matters.
3. **Inline hints on hot paths.** `Call` and `Is_Connected` are marked `Inline`, appropriate for what are essentially dispatched function-pointer calls.
4. **Runtime safety.** `pragma Assert` on `Connected` in every `Call` catches wiring errors during integration testing without runtime overhead in production (assertions typically stripped).
5. **Arrayed connector support.** The `Index` parameter allows a single hook to service multiple connector instances, enabling fan-in patterns without duplicating handler code.
6. **Consistent structure.** All four variants follow an identical internal pattern — easy to maintain, easy to code-generate.

**Observations / Minor Issues:**

1. **No `Detach` or reconnection support.** Once attached, a connector cannot be disconnected or re-targeted. This is likely intentional for flight software (static topology), but worth documenting explicitly.
2. **`Connected` flag is redundant with null checks.** `Component_Access` and `Hook` are initialized to `null`; `Connected` could be derived from `Hook /= null`. The explicit flag is fine for clarity but is a minor duplication of state that could theoretically drift (though `Attach` sets all three atomically).
3. **No thread-safety on `Attach`.** `Attach` is presumably called during init before tasking starts, but there's no documented precondition or barrier. In a concurrent context, calling `Call` while `Attach` is mid-execution could read a partially-initialized record. A comment or precondition would help.
4. **`In_Connector` is the only variant with queue semantics** (`Full_Queue_Action`, `Connector_Status`). The asymmetry is correct — only push-style connectors interact with queued components — but a brief rationale comment in the other specs would aid newcomers.
5. **`In_Out_Connector.Call` is a procedure, not a function.** Correct for `in out` parameter semantics, but the spec comment still says "Public function to call the function attached" — minor doc inconsistency.
6. **`Common_Connectors` pulls in many dependencies.** Any package that `with`s `Common_Connectors` transitively depends on all listed types (Tick, Fault, Pet, Ccsds_Space_Packet, etc.). This is a deliberate trade-off (dedup vs coupling); just noting it.

## Recommendations

- **P3 (low):** Fix the "Public function" comment in `In_Out_Connector` spec — it's a procedure.
- **P3 (low):** Add a one-line note to each non-queued connector spec explaining why queue semantics are absent (e.g., "This connector is synchronous; queue behavior is managed by the invokee").
- **P4 (nit):** Consider adding a `-- Precondition: Must be called before any concurrent Call` comment to `Attach`.

## Verdict

**Well-designed, minimal, and fit for purpose.** The connector system is the backbone of Adamant's component wiring and it shows thoughtful embedded-systems engineering: small generics, controlled instantiation, zero unnecessary abstraction. No functional issues found.

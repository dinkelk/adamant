# Splitter Component — Code Review

**Reviewer:** Automated (Claude)
**Date:** 2026-03-01
**Component:** `src/components/splitter`

---

## 1. Documentation Review

| # | Severity | Finding |
|---|----------|---------|
| D1 | Low | The `.tex` document is entirely auto-generated scaffolding (`\input{build/tex/...}`). There is no hand-written design rationale, behavioral notes, or discussion of edge cases (e.g., what happens when one downstream is connected and another is not, or when a send is dropped). For a trivial component this is acceptable, but a one-paragraph design note would add value. |
| D2 | Low | The YAML `description` and the `.ads` comment are nearly identical but diverge slightly ("and the distribute" in the `.ads` vs. "and then distribute" in the YAML). The YAML is correct; the `.ads` has a typo ("and the distribute"). Minor copy-paste drift. |

**Overall:** Documentation is minimal but proportionate to the component's simplicity. No significant issues.

---

## 2. Model Review (splitter.component.yaml)

| # | Severity | Finding |
|---|----------|---------|
| M1 | Medium | The send connector has `count: 0` (unconstrained array, sized at assembly). This is the intended pattern for a generic splitter, but there is **no guard or assertion for the degenerate case where the array is instantiated with zero outputs**. If an assembly wires zero outputs, the component silently accepts and discards all data — a potential latent misconfiguration. A minimum-count constraint or an initialization-time assertion would make misconfiguration fail-fast. |
| M2 | Low | The recv connector is `recv_sync` (passive/synchronous invocation). This is appropriate for a zero-copy fan-out, but it means the splitter executes in the caller's task context. If any downstream `T_Send` target is queued/async, the caller blocks until all sends complete. This is a design choice, not a defect, but is worth documenting for assembly authors. |

**Overall:** The model is clean and idiomatic for Adamant. The unconstrained array with no minimum is the only substantive concern.

---

## 3. Component Implementation Review

| # | Severity | Finding |
|---|----------|---------|
| I1 | Medium | **`T_Send_Dropped` is silently null.** When a downstream queue is full and a send is dropped, the component takes no action — no error counter, no event, no log. In a safety-critical system, silent data loss is a concern. At minimum, an event or telemetry counter should record drop occurrences so operators/fault management can detect the condition. This is the most significant finding in the review. |
| I2 | Low | **No partial-failure semantics.** The fan-out loop iterates all outputs sequentially. If output N is connected but its queue is full (drop), the loop continues to output N+1. This is correct behavior, but there is no mechanism to report *which* output dropped, making debugging harder in systems with many downstream consumers. |
| I3 | Low | The implementation has no internal state (`null` record), which is correct and clean for this component. No concerns. |

**Overall:** The implementation is correct and minimal. The silent drop handler is the primary concern.

---

## 4. Unit Test Review

| # | Severity | Finding |
|---|----------|---------|
| T1 | High | **No unit tests exist.** There is no `test/` directory and no test files anywhere under the splitter component tree. The `.tex` document references `build/tex/splitter_unit_test.tex`, suggesting the framework expects tests, but none are provided. For a generic component, testing requires instantiation with a concrete type, which is straightforward. Missing tests means the following behaviors are unverified: (a) fan-out to multiple connected outputs, (b) behavior with partially-connected outputs, (c) behavior when all outputs are disconnected, (d) drop behavior when a downstream queue is full. |

**Overall:** The complete absence of unit tests is the highest-severity finding.

---

## 5. Summary — Top 5 Findings

| Rank | ID | Severity | Finding |
|------|-----|----------|---------|
| 1 | T1 | **High** | No unit tests exist for the component. Fan-out, partial-connection, and drop scenarios are untested. |
| 2 | I1 | **Medium** | `T_Send_Dropped` is `null` — silent data loss with no telemetry, event, or error reporting. |
| 3 | M1 | **Medium** | No minimum-count constraint on the output array; zero-output instantiation silently discards all data. |
| 4 | I2 | Low | No per-output drop identification; debugging fan-out failures in large assemblies is difficult. |
| 5 | D2 | Low | Minor typo in `.ads` comment ("and the distribute" → "and then distribute"). |

---

*End of review.*

## Resolution Notes

| # | Issue | Severity | Status | Commit | Notes |
|---|-------|----------|--------|--------|-------|
| 1 | No unit tests | High | Not Fixed | - | Requires test infrastructure setup |
| 2 | Silent dropped sends | Medium | Not Fixed | - | Requires event YAML |
| 3 | Zero-output guard | Medium | Not Fixed | - | Assembly-level concern |
| 4 | Typo in spec comment | Low | Fixed | 6c55ae7 | Grammar correction |

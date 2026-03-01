# Ticker Component Review

**Date:** 2026-03-01
**Reviewer:** Gus (automated)

---

## Documentation

The component has a LaTeX design document (`doc/ticker.tex`) that follows the standard Adamant template with sections for description, requirements, design (diagram, connectors, initialization), unit tests, and appendix. However, the `.tex` file relies entirely on `build/tex/` includes for substantive content — the document itself contains no inline prose beyond section headings. The YAML model description is minimal: *"This is the ticker component."* — this is insufficient; it should describe the component's purpose (periodic tick generation for rate group scheduling) and behavior (active task that delays and emits `Tick.T` at a fixed period).

**Issues:**
- Description in YAML and generated docs is too vague — doesn't explain *what* the ticker does or *why*.
- No mention of jitter behavior, drift characteristics, or first-tick timing semantics.

---

## Model

**File:** `ticker.component.yaml`

The model defines:
- **Execution:** `active` (has its own task/cycle)
- **Discriminant:** `period_us : Positive` — tick period in microseconds
- **Connectors:**
  - `send` of `Tick.T` — emits the periodic tick
  - `get` returning `Sys_Time.T` — retrieves system time

The model is clean and minimal. Two observations:

- No `recv` or `command` connectors — the ticker cannot be started/stopped/reconfigured at runtime. This is a design choice but limits operational flexibility.
- No data products or events — there is no telemetry for tick count, period, or missed deadlines, making runtime observability difficult.

---

## Implementation

**Files:** `component-ticker-implementation.ads`, `component-ticker-implementation.adb`

### Spec (`.ads`)
- Instance record holds: `Period` (Time_Span), `Next_Period` (Time), `Count` (Unsigned_32), `First` (Boolean).
- `Period` and `Next_Period` are initialized from the discriminant at elaboration time — `Next_Period` is set to `Clock + period` at instantiation, but then overwritten on the first `Cycle` call. The elaboration-time initialization of `Next_Period` is wasted work.
- `Tick_T_Send_Dropped` is overridden as `null` — silently drops ticks on queue full with no event or counter. This is a **significant observability gap**.

### Body (`.adb`)
- On the first cycle, `Next_Period` is reset to `Clock` (current time), so the first tick fires immediately.
- `delay until Self.Next_Period` provides Ada real-time periodic scheduling — good for deterministic timing.
- After sending, `Next_Period` is advanced by `Period`, preventing drift accumulation (absolute time scheduling, not relative).
- `Count` uses `Unsigned_32` which wraps at ~4.29 billion. At 1 Hz this is ~136 years — fine. At 1 kHz it's ~50 days — could wrap in long-duration missions. No wrap handling.
- The `@` syntax (Ada 2022 target name) is used — confirms modern Ada standard.

**Issues:**
1. **Silent tick drops** — `Tick_T_Send_Dropped` is null; no event, no fault, no counter.
2. **No overrun detection** — if `Cycle` takes longer than `Period`, `delay until` returns immediately and ticks pile up with no warning.
3. **Redundant initialization** of `Next_Period` in the record default (overwritten in first Cycle).
4. **Count overflow** unhandled for high-frequency tickers.

---

## Unit Test

**No unit tests exist.** There is no `test/` directory for this component. The LaTeX document references `build/tex/ticker_unit_test.tex` which would be auto-generated, but without test source files it is presumably empty or states "no tests."

This is the most critical gap. An active, timing-sensitive component with no tests means:
- Tick period correctness is unverified.
- First-tick behavior is unverified.
- Count incrementing is unverified.
- Queue-full behavior is unverified.

---

## Summary (Top 5)

| # | Priority | Finding |
|---|----------|---------|
| 1 | **High** | **No unit tests** — an active timing component with zero test coverage. |
| 2 | **High** | **Silent tick drops** — `Tick_T_Send_Dropped` is null; downstream components will silently miss ticks with no telemetry or fault indication. |
| 3 | **Medium** | **No overrun detection** — if the cycle exceeds the period, ticks will bunch up with no warning, potentially flooding downstream queues. |
| 4 | **Medium** | **No runtime observability** — no data products (tick count, period) or events; the component is a black box at runtime. |
| 5 | **Low** | **Inadequate documentation** — the YAML description is generic ("This is the ticker component") and does not describe behavior, timing semantics, or first-tick policy. |

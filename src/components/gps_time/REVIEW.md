# Gps_Time Component Code Review

**Component:** `src/components/gps_time`
**Date:** 2026-02-28
**Reviewer:** Automated Expert Review

---

## 1. Documentation Review

### 1.1 — Requirements are insufficient and untraceable

**Location:** `gps_time.requirements.yaml`, line 4
```yaml
requirements:
  - text: FSW will store time as 32 bits of seconds and 32 bits of subseconds.
```
**Explanation:** There is only a single requirement covering the storage format. There are no requirements covering the component's actual behavior — namely that it shall return the current system time in GPS format via `Ada.Real_Time.Clock`, that it shall handle conversion overflow/underflow, or how errors from `To_Sys_Time` shall be managed. Additionally, the requirement lacks an identifier (e.g., `GPS_TIME-001`) making formal traceability impossible.
**Corrected code:**
```yaml
requirements:
  - id: GPS_TIME-001
    text: The Gps_Time component shall return the current system time in Sys_Time.T (GPS) format when the Sys_Time_T_Return connector is invoked.
  - id: GPS_TIME-002
    text: FSW shall store time as 32 bits of seconds and 32 bits of subseconds.
  - id: GPS_TIME-003
    text: The Gps_Time component shall report a diagnostic event if the time conversion fails due to overflow or underflow.
```
**Severity:** High

### 1.2 — Component description says "servicing" but execution is "passive"

**Location:** `gps_time.component.yaml`, line 2
```yaml
description: The System Time component is a servicing component which provides...
execution: passive
```
**Explanation:** The description states "servicing component" but the execution model is `passive`. In Adamant, a "servicing" component implies an active component with its own task. The description should match the execution model to avoid confusion during integration.
**Corrected code:**
```yaml
description: The GPS Time component is a passive component which provides the system time in GPS format to any component that requests it. Internally, the system time is provided by the Ada.Real_Time library.
```
**Severity:** Low

### 1.3 — LaTeX doc references unit tests that do not exist

**Location:** `doc/gps_time.tex`, line 23
```latex
\section{Unit Tests}
\input{build/tex/gps_time_unit_test.tex}
```
**Explanation:** There is no `test/` directory for this component. The unit test section will either produce a build error or render an empty/misleading section. It should either be removed or a placeholder added noting the absence of component-level tests (if type-level tests in `sys_time` are considered sufficient, that should be stated).
**Corrected code:**
```latex
\section{Unit Tests}
No component-level unit tests exist. Time conversion logic is tested via the \texttt{Sys\_Time.Arithmetic} type tests.
```
**Severity:** Medium

---

## 2. Model Review

### 2.1 — No event or status connector for conversion failure reporting

**Location:** `gps_time.component.yaml`
```yaml
connectors:
  - description: The system time is provided via this connector.
    return_type: Sys_Time.T
    kind: return
```
**Explanation:** The component has only a single `return` connector. There is no event connector to report if `To_Sys_Time` returns `Underflow` or `Overflow`. In safety-critical flight software, silently returning a potentially incorrect time (e.g., `Sys_Time_Zero` on underflow or `Sys_Time_Max` on overflow) without any notification is a hazard. The component model should include an event send connector.
**Corrected code:**
```yaml
connectors:
  - description: The system time is provided via this connector.
    return_type: Sys_Time.T
    kind: return
  - description: Event connector for reporting time conversion status.
    type: Event_Forward.Event_Send
    kind: send
```
**Severity:** Critical

---

## 3. Component Implementation Review

### 3.1 — Conversion status is silently discarded

**Location:** `component-gps_time-implementation.adb`, lines 22–27
```ada
Status := To_Sys_Time (Current_Time, To_Return);
-- To do generate an event here, maybe
return To_Return;
```
**Explanation:** The return value of `To_Sys_Time` is assigned to `Status` which is then `pragma Unreferenced`. The `-- To do generate an event here, maybe` comment confirms this was recognized as incomplete. If `To_Sys_Time` returns `Overflow` (system time exceeds `Unsigned_32` seconds — after ~136 years from epoch, or on certain targets) or `Underflow` (negative `Ada.Real_Time.Clock` relative to epoch), the component will silently return `Sys_Time_Max` or `Sys_Time_Zero` respectively. In flight software, silently returning a saturated time value can cause downstream components to make incorrect decisions (e.g., sequence timing, telemetry timestamps, safe-mode timers).
**Corrected code:**
```ada
Status := To_Sys_Time (Current_Time, To_Return);
if Status /= Success then
   Self.Event_T_Send_If_Connected (Self.Events.Time_Conversion_Error (
      (Status => Status, Time => To_Return)));
end if;
return To_Return;
```
**Severity:** Critical

### 3.2 — TODO comment left in production code

**Location:** `component-gps_time-implementation.adb`, line 26
```ada
-- To do generate an event here, maybe
```
**Explanation:** A "To do" comment in safety-critical flight code indicates incomplete implementation. All TODO items must be resolved or formally tracked prior to delivery. The word "maybe" further suggests the design decision was never finalized.
**Corrected code:** Remove the comment and implement the event (see issue 3.1), or if intentionally deferred, track in a formal issue tracker and add a reference:
```ada
-- Issue GPS-042: Event generation deferred per [rationale].
```
**Severity:** High

### 3.3 — `Self` parameter is unused via `Ignore` rename

**Location:** `component-gps_time-implementation.adb`, line 20
```ada
overriding function Sys_Time_T_Return (Self : in out Instance) return Sys_Time.T is
   Ignore : Instance renames Self;
```
**Explanation:** The function takes `Self` as `in out` (required by the Adamant framework for overriding) but immediately renames it to `Ignore`, meaning no instance state is read or written. This is acceptable for a stateless component. However, if issue 3.1 is fixed (adding event output), `Self` will be needed. This is informational — no change needed unless events are added.
**Severity:** Low

---

## 4. Unit Test Review

### 4.1 — No unit tests exist for the component

**Location:** No `test/` directory exists under `src/components/gps_time/`.

**Explanation:** The component has zero unit tests. While `Sys_Time.Arithmetic` has its own tests, those do not exercise the component's `Sys_Time_T_Return` connector, integration with `Ada.Real_Time.Clock`, or the handling of conversion status. At minimum, tests should verify:
1. Nominal: returned time is non-zero and monotonically increasing across two calls.
2. The returned `Sys_Time.T` round-trips correctly through `To_Time`/`To_Sys_Time`.
3. (If events are added) Overflow/underflow paths produce the expected event.

**Severity:** High

---

## 5. Summary — Top 5 Issues

| # | Severity | Location | Issue |
|---|----------|----------|-------|
| 1 | **Critical** | `implementation.adb:22–27` | `To_Sys_Time` status silently discarded — incorrect time returned without any notification (§3.1) |
| 2 | **Critical** | `component.yaml` | No event connector exists to report conversion failures (§2.1) |
| 3 | **High** | `test/` (missing) | No unit tests for the component (§4.1) |
| 4 | **High** | `implementation.adb:26` | TODO comment left in deliverable flight code (§3.2) |
| 5 | **High** | `requirements.yaml` | Single requirement with no ID; missing behavioral and error-handling requirements (§1.1) |

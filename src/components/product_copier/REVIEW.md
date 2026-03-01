# Product Copier — Code Review

**Reviewer:** Claude (automated)
**Date:** 2026-03-01
**Component:** `src/components/product_copier`

---

## 1. Documentation Review

The component YAML description, LaTeX document, and requirements are clear and well-aligned. The description accurately conveys the "stable snapshot" use case.

| # | Finding | Severity |
|---|---------|----------|
| D1 | The `.tex` document references many `build/tex/` includes (commands, parameters, packets, faults, interrupts, data dependencies, enumerations). Since this component has none of those, these sections will render as empty/boilerplate. Consider conditionally including only relevant sections. | Low |
| D2 | The `.ads` spec comment says "if the values stored in the source database **is** constantly in flux" — grammatical error ("is" should be "are"). | Low |
| D3 | Events YAML descriptions say "was not sent to the destination" / "was not read from the source" inconsistently (the tester body says "not read from the source" for both). The component YAML says "not available" which is clearer. Minor wording inconsistency. | Low |

---

## 2. Model Review

### `product_copier.component.yaml`

| # | Finding | Severity |
|---|---------|----------|
| M1 | **Destination ID is never applied to the copied product.** The `Tick_T_Recv_Sync` handler fetches a `Data_Product` by `Source_Id` and, on success, sends `Dp_Return.The_Data_Product` **unchanged** — the product's header still carries the *source* ID. The `Destination_Id` field in `Product_Mapping` is stored but never used at runtime. The duplicate-destination check in `Init` protects against a semantic that is never actually enforced. If the downstream consumer (e.g., Product_Database) uses the header ID for storage, products will be written to the *source* ID slot, not the destination slot. This defeats the stated design intent of source→destination copying. | **Critical** |
| M2 | The `Init` parameter `Products_To_Copy` is documented as "Raises an error on Init if the list is null," but `not_null: true` already makes a null access a compile-time/language-level constraint. The documentation is misleading — the check is not an explicit runtime validation in the `Init` body. | Low |

### `product_mapping.record.yaml` / `product_copier_error_info.record.yaml`

Records are straightforward and correctly typed. No issues.

---

## 3. Component Implementation Review

### `Init` (`component-product_copier-implementation.adb`)

| # | Finding | Severity |
|---|---------|----------|
| I1 | **Duplicate-destination check uses `pragma Assert`, which is removable.** In production builds with assertions suppressed (`-gnata` not set, or `pragma Suppress(All_Checks)`), the duplicate-destination validation silently disappears. For a safety-related initialization guard, this should use an explicit `raise` or `Ada.Assertions.Assert` (which is not suppressible), or a dedicated validation function that raises a named exception. A requirement states the component "shall fail at initialization" — relying on a suppressible pragma does not guarantee this. | **High** |
| I2 | **Empty mapping array silently accepted.** An empty `Products_To_Copy` array passes `Init` without error and causes `Tick_T_Recv_Sync` to do nothing. While arguably harmless, in a safety-critical context an empty mapping list likely indicates misconfiguration. Consider at minimum a warning event, or document this as intentional. | Medium |
| I3 | **Re-initialization is unguarded.** `Init` can be called multiple times (the tests do this), replacing `Mappings` without any protection. If a tick fires between two `Init` calls on different threads, the component could operate on a partially-updated or stale mapping pointer. The component is `passive` (no task), so this depends on the caller's discipline, but a guard or assertion would be defensive. | Medium |

### `Tick_T_Recv_Sync`

| # | Finding | Severity |
|---|---------|----------|
| I4 | **(Same as M1)** The fetched data product is sent with its original header ID unchanged. `Mapping.Destination_Id` is never written into the outgoing product's header. This is the central defect in the component. | **Critical** |
| I5 | **No handling of `Self.Mappings = null`.** If `Tick_T_Recv_Sync` is called before `Init` (e.g., due to assembly wiring order), dereferencing `Self.Mappings.all` will raise `Constraint_Error`. A defensive null check or pre-condition would be appropriate. | Medium |
| I6 | `Data_Product_T_Send_Dropped` and `Event_T_Send_Dropped` are null overrides. If the send queue is full, copied data products are silently lost with no event or telemetry. In a system relying on snapshot consistency, this could cause stale data to persist undetected. | Medium |

---

## 4. Unit Test Review

| # | Finding | Severity |
|---|---------|----------|
| T1 | **Tests do not verify Destination_Id is applied.** All ID checks in `Test_Nominal_Tick` and `Test_Fetch_Fail_Behavior` validate the *source* ID pattern (`Id mod 10`). No test asserts that the sent product's header ID equals the mapping's `Destination_Id`. This means the Critical defect (M1/I4) is untested and undetected. | **High** |
| T2 | **Tester counters (`Case_1_Ctr` .. `Case_5_Ctr`) are never reset between test cases or re-initializations.** Since `Set_Up_Test` creates the tester once and multiple tests call `Init` with different mappings, the simulated database state accumulates across logical test scenarios within a single test procedure. This makes the test fragile and order-dependent. The comment "S,F,F,S,S" etc. in `Test_Fetch_Fail_Behavior` relies on exact counter state carried from previous ticks. | Medium |
| T3 | **`Test_Fetch_Fail_Event` does not verify event payload contents.** There is a TODO comment acknowledging this. The test checks event *counts* but not that the `Product_Copier_Error_Info` contains the correct `Tick` count and `Mapping`. | Medium |
| T4 | **`Test_Nominal_Tick` re-inits with `Non_Error_Products` (1 mapping) but `Set_Up_Test` already inited with 6 mappings.** The first `Init` in `Set_Up_Test` is immediately overwritten. While not a bug, it obscures test intent and wastes the fixture setup. | Low |
| T5 | Multiple TODO comments remain in test code (`TODO named declare?`, `TODO do we care about order within ticks?`, `TODO make more descriptive names`). These indicate incomplete review/cleanup. | Low |
| T6 | **No test for tick before init (null mappings).** The defensive scenario of receiving a tick before initialization is not tested. | Medium |
| T7 | **No test for `Data_Product_T_Send_Dropped` or `Event_T_Send_Dropped` behavior.** Queue-full scenarios are not exercised. | Low |

---

## 5. Summary — Top 5 Findings

| Rank | ID | Severity | Finding |
|------|----|----------|---------|
| 1 | M1/I4 | **Critical** | `Destination_Id` is never written into the outgoing data product header. Products are sent with the source ID, defeating the copy semantic. |
| 2 | T1 | **High** | No test verifies that the destination ID is applied to copied products, so the critical defect goes undetected. |
| 3 | I1 | **High** | Duplicate-destination guard uses suppressible `pragma Assert`; in production builds with assertions off, invalid configurations are silently accepted. |
| 4 | I5 | Medium | No null-check on `Self.Mappings` before dereference in `Tick_T_Recv_Sync`; a tick before init causes `Constraint_Error`. |
| 5 | I6 | Medium | Dropped sends (full queue) are silently ignored — no event, no counter — risking undetected stale snapshots. |

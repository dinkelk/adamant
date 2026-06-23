# Review: `task_watchdog/types`

**Date:** 2026-03-01
**Reviewer:** Gus's Agent

## Summary

This package defines the type system for the Task Watchdog component — a software watchdog that monitors periodic "pets" from upstream tasks and takes configurable actions (warn, fault) when pets are missed. The types are well-structured and the package is small and focused.

## File Inventory

| File | Purpose |
|------|---------|
| `task_watchdog_enums.enums.yaml` | Enum definitions: `Watchdog_Enabled_State`, `Watchdog_Action_State` |
| `task_watchdog_types.ads` | Core Ada types: counters, init record, init list |
| `packed_missed_pet_limit.record.yaml` | Serialized limit value (U16) |
| `packed_watchdog_component_state.record.yaml` | Serialized component enable/disable state (E8) |
| `packed_watchdog_pet_states.record.yaml` | Packed status for 4 action-state entries (4×E2 = 1 byte) |
| `watchdog_action_cmd.record.yaml` | Command record: change a connector's action |
| `watchdog_limit_cmd.record.yaml` | Command record: change a connector's missed-pet limit |
| `watchdog_state_change.record.yaml` | Command record: enable/disable a connector |
| `.all_path` | Empty; build system path marker |

## Observations

### Positives

1. **Clean enum design.** Both enums use explicit integer values starting at 0, which is good for packed serialization and ground-system interop.
2. **Appropriate range constraints.** `Missed_Pet_Limit_Type` excludes 0 (no zero-limit) and `Missed_Pet_Count_Type'Last` (likely reserved as sentinel), which is a smart defensive choice.
3. **Consistent command structure.** All three command records (`action_cmd`, `limit_cmd`, `state_change`) share the same `Index` field as a `Connector_Index_Type` / U16, making dispatching uniform.
4. **Compact telemetry.** `packed_watchdog_pet_states` packs 4 action states into a single byte via E2 format — good for bandwidth-constrained downlink.

### Issues & Suggestions

1. **Description copy-paste errors:**
   - `watchdog_action_cmd.record.yaml` description says *"changing the limit"* but it changes the **action**. Should read: *"changing the action of a specific watchdog connector."*
   - `watchdog_state_change.record.yaml` field `Index` description says *"change the limit of"* but this record changes the **state**. Should read: *"change the state of."*

2. **`packed_watchdog_pet_states` is fixed at 4 entries.** If the number of monitored connectors changes, this record must be manually updated. Consider whether code generation from the init list length would be more maintainable. (May be an Adamant framework limitation — noting for awareness.)

3. **`Two_Bit_Padding_Type` is declared but not used in any YAML record.** It's presumably consumed by the component implementation or generated code. If it's only used internally, consider moving it closer to the consumer to keep this types package minimal.

4. **`Petter_Has_Fault` naming.** The field name is slightly ambiguous — it could mean "the petter itself is in a fault state" or "the petter carries a fault ID." A name like `Petter_Reports_Fault` or a comment clarifying the runtime semantics would help.

5. **No explicit `with` for `Missed_Pet_Limit_Type` in YAML.** The `packed_missed_pet_limit.record.yaml` references `Task_Watchdog_Types.Missed_Pet_Limit_Type` — this works because the build system resolves it, but it's worth verifying the dependency is declared in the component model.

## Verdict

**Solid.** The type package is small, well-constrained, and follows Adamant conventions. The only real bugs are the copy-paste description errors in two YAML files — those should be fixed to avoid confusion in auto-generated documentation.

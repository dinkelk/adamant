# Code Review: Database Packages

**Date:** 2026-03-01
**Packages:** `Database`, `Variable_Database`
**Reviewer:** Claude (automated)

---

## Summary

Two generic Ada packages implementing constant-time key→value lookup databases for the Adamant framework. `Database` handles fixed-size types with a double-index scheme; `Variable_Database` handles variable-length serialized types with direct indexing and an override mechanism. Both are well-structured, well-tested, and appropriate for embedded/flight-software use.

**Overall Assessment: Solid.** A few minor observations below, nothing blocking.

---

## Package: `Database` (database.ads / database.adb)

### Design

- **Double-index architecture** is clearly documented and sound: a compact value table (`Db_Table`, sized to `Max_Num_Values`) plus a lookup table (`Index_Table`, spanning the full ID range). Good trade-off when `Max_Num_Values << Id range`.
- Append-only allocation (no delete/remove). Documented implicitly by the absence of a `Delete` operation, but worth noting — the database can fill up and never reclaim slots.

### Observations

1. **No `Delete` / `Remove` operation.** Once an ID is allocated a slot, it can never be freed. This is likely intentional for deterministic embedded use, but the spec comment could mention it explicitly.

2. **`Fetch` leaves `Value` uninitialized on failure.** The `out` parameter `Value` is not assigned when returning `Id_Out_Of_Range` or `Data_Not_Available`. The GNATSAS annotations acknowledge this. Callers must check the status before reading `Value`. This is a defensible performance choice but creates a footgun for careless callers.

3. **`Get_Count` returns `Self.Head - 1`.** Before `Init` is called, `Head` defaults to `Database_Index'First` (1), so `Get_Count` returns 0 — correct. But if `Destroy` is called (resets `Head` to `Positive'First` = 1), subsequent calls also return 0, which is fine. No issue here, just verified.

4. **Memory management via `Safe_Deallocator.Deallocate_If_Testing`.** This means memory is only freed in test builds. Standard pattern for Adamant (no heap deallocation in flight). Good.

5. **No thread safety.** Expected for Adamant (components handle concurrency at a higher level), but worth noting for anyone considering standalone reuse.

6. **`Init` doesn't guard against double-init.** Calling `Init` twice leaks the first allocation (in test mode). Minor, since the framework likely prevents this.

### Code Quality

- Clean, readable, well-commented.
- Good use of `pragma Assert` for internal invariants (`Db_Index < Self.Head`).
- Ada 2022 `@` syntax used appropriately (`Self.Head := @ + 1`).

---

## Package: `Variable_Database` (variable_database.ads / variable_database.adb)

### Design

- Single direct-indexed table (one entry per possible ID). Simpler than `Database` but uses more memory for sparse ID spaces — correctly documented in the README and spec.
- Entries store serialized byte arrays via `Variable_Serializer`, enabling variable-length packed types.
- **Override mechanism** is a nice feature: allows locking entries against `Update` for testing/debugging/ground-override scenarios.

### Observations

1. **No `Is_Full` / `Is_Empty` / `Get_Count`.** Unlike `Database`, there's no way to query occupancy. Since every ID has a pre-allocated slot this is less critical, but `Get_Count` (number of `Filled`/`Override` entries) could still be useful.

2. **`Update` silently succeeds when entry is in `Override` state.** Returns `Success` without modifying data. This is documented behavior but could surprise callers. Consider whether a distinct status like `Overridden` would be more informative. (Trade-off: current design lets callers be unaware of override, which may be the intent.)

3. **`Clear_Override` on an `Empty` entry is a no-op returning `Success`.** Harmless, but slightly inconsistent — it doesn't transition state. Arguably correct since there's nothing to "clear."

4. **`Fetch` asserts on deserialization failure** (`pragma Assert (Stat = Success, ...)`). In production this would be a hard crash if a bit-flip corrupts the internal buffer. For flight software this is likely the desired behavior (fail-fast), but worth documenting.

5. **`Any_Overridden` is O(n) over the full ID range.** Fine for small databases. If performance matters, a counter could track override count.

6. **Same double-init and thread-safety notes as `Database`.**

### Code Quality

- Clean, well-organized.
- Good use of `case` statements for state transitions — makes state machine explicit.
- `T_Serializer.Byte_Array` sized at instantiation via the variable serializer — elegant.

---

## Tests: `database/test/`

### Coverage

| Test | What it covers |
|------|---------------|
| `Test_Nominal_Update_Fetch` | Insert, fetch, update-in-place, capacity tracking |
| `Test_Id_Out_Of_Range` | Out-of-range IDs on both Update and Fetch |
| `Test_Not_Enough_Memory` | Full database rejects new IDs, allows re-update of existing |
| `Test_Data_Not_Available` | Fetch before store returns correct status |

### Observations

- **Good coverage** of all three error statuses plus nominal flow.
- Tests use a deliberately offset ID range (`Id_Type 15..30`, database range `17..29`) — good for catching off-by-one bugs.
- `Put_Line` debug output left in tests — acceptable for AUnit test runners.
- No test for `Destroy` + re-`Init` cycle.
- No test for single-element database (`Max_Num_Values = 1`).

---

## Tests: `database/variable_test/`

### Coverage

| Test | What it covers |
|------|---------------|
| `Test_Nominal_Update_Fetch` | Insert, fetch, re-update (forward and reverse order) |
| `Test_Id_Out_Of_Range` | Out-of-range IDs |
| `Test_Data_Not_Available` | Fetch before store, partial fill |
| `Test_Serialization_Failure` | Oversized values rejected, existing data preserved |
| `Test_Override` | Override, update-while-overridden, partial clear, clear-all |

### Observations

- **Excellent override test** — covers override, update-no-effect, selective clear, clear-all, and re-update after clear. Thorough.
- `simple_variable.record.yaml` defines a 10-byte variable-length buffer — good test type.
- Tests verify that failed operations don't corrupt existing data (serialization failure test).
- Missing: override on an `Empty` entry (never updated), and `Clear_Override` on a non-overridden entry.
- Missing: `Any_Overridden` is tested inline via `pragma Assert` rather than through the assertion framework — slightly inconsistent but functional.

---

## README.md

Clear and accurate. Correctly distinguishes the two packages' use cases and trade-offs.

---

## Recommendations (Priority Order)

1. **Document the no-delete design** in `Database.ads` spec comment.
2. **Consider adding a distinct `Update` return status** in `Variable_Database` when an entry is overridden (low priority — depends on design intent).
3. **Add edge-case tests:** single-element DB, destroy/re-init cycle, override-on-empty-entry.
4. **Minor:** the `Database.ads` comment says "3 parameters" for init but `Init` takes 4 (including `Self`). Pedantic, but the comment means "3 user-supplied parameters" — could be clearer.

---

*No critical issues found. Code is production-quality for its intended embedded/flight-software context.*

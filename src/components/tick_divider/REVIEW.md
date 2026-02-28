# Tick Divider Component — Code Review

**Reviewer:** Automated Expert Review  
**Date:** 2026-02-28  
**Component:** `src/components/tick_divider`

---

## 1. Documentation Review

- **`doc/tick_divider.pdf`** — Present and correctly named. PDF exists and matches the component name.
- **`doc/tick_divider.tex`** — LaTeX source is co-located, which is good practice.

**No issues found.**

---

## 2. Model Review

### `tick_divider.component.yaml`

- Well-structured with clear descriptions for all connectors.
- `preamble` correctly defines `Divider_Array_Type` and `Tick_Source_Type`.
- `init` parameters are properly documented with types and defaults.
- Connector array `count: 0` (assembly-determined) is appropriate.

### `tick_divider.events.yaml`

- Single event `Component_Has_Full_Queue` with appropriate parameter type.

### `event_args/td_full_queue_param.record.yaml`

- Fields `Dropped_Tick` and `Index` are well-chosen for diagnosing full-queue conditions.

**No issues found.**

---

## 3. Component Implementation Review

### `component-tick_divider-implementation.ads`

**No issues found.** The spec is clean, correctly mirrors the model, and the private record fields are appropriately typed.

### `component-tick_divider-implementation.adb`

#### Issue 1 — Max_Count multiplication can silently overflow (Critical)

**Location:** `component-tick_divider-implementation.adb:36-41`

```ada
36:            Self.Max_Count := 1;
37:            for Index in Self.Dividers'Range loop
38:               Divider := Self.Dividers (Index);
39:               if Divider > 0 then
40:                  Self.Max_Count := @ * Divider;
41:               end if;
42:            end loop;
```

**Problem:** `Interfaces.Unsigned_32` is a modular type — multiplication wraps around silently without raising an exception. If the product of non-zero dividers exceeds 2^32, `Max_Count` wraps to a small (but non-zero) value. The subsequent `pragma Assert (Self.Max_Count < Unsigned_32'Last)` would pass on the wrapped value, masking the overflow entirely.

For example, dividers `[70000, 70000, 70000]` would wrap, and the resulting `Max_Count` would be incorrect, causing some divisors to skip ticks unpredictably.

**Severity:** **Critical** — Silent data corruption affecting tick scheduling correctness in safety-critical systems.

**Suggested fix:** Track the product in a 64-bit accumulator and assert it fits in 32 bits:

```ada
declare
   Acc : Interfaces.Unsigned_64 := 1;
begin
   for Index in Self.Dividers'Range loop
      Divider := Self.Dividers (Index);
      if Divider > 0 then
         Acc := Acc * Interfaces.Unsigned_64 (Divider);
      end if;
   end loop;
   pragma Assert (Acc < Interfaces.Unsigned_64 (Interfaces.Unsigned_32'Last),
      "Product of dividers overflows Unsigned_32!");
   Self.Max_Count := Interfaces.Unsigned_32 (Acc);
end;
```

#### Issue 2 — Comment inaccuracy in Tick_T_Recv_Sync (Low)

**Location:** `component-tick_divider-implementation.adb:60-62`

```ada
60:            Self.Count := (@ + 1) mod Self.Max_Count;
61:            -- ^ Note: this will fail with a divide by zero error if init is
62:            -- never called. This behavior is by design, to alert the developer.
```

**Problem:** The comment says "divide by zero error" but `Unsigned_32` is modular — `mod 0` on a modular type raises `Constraint_Error`, not a "divide by zero error." While the intent is correct (crash on uninitialized use), the comment is technically inaccurate.

**Severity:** **Low** — Misleading comment; no runtime impact.

**Suggested fix:**
```ada
            -- ^ Note: this will raise Constraint_Error if Init is never called
            -- (Max_Count defaults to 0). This behavior is by design, to alert
            -- the developer.
```

---

## 4. Unit Test Review

### Test Coverage Assessment

The test suite covers:
- ✅ Nominal operation with mixed divisors including disabled (zero) entries
- ✅ Bad initialization parameters (wrong array bounds/lengths)
- ✅ Full queue event reporting
- ✅ Tick_Counter mode with sequential, skipped, and rollover counts
- ✅ Unsigned_32 boundary values
- ✅ Edge-case divider configurations (all-disabled, divisor-of-1, large divisors)
- ✅ Mode comparison (Internal vs Tick_Counter)
- ❌ **Missing:** No test for Max_Count overflow protection (Issue 1 above)
- ❌ **Missing:** No test for calling `Tick_T_Recv_Sync` without calling `Init` first (the intentional crash path)

### `tests-implementation.adb`

#### Issue 3 — Inaccurate comment in Nominal test (Low)

**Location:** `tests-implementation.adb:50-52`

```ada
50:      -- We are expecting 74/7 + 74/5 + 2 (for 0th iteration) for
51:      -- a total number invocations of 26:
52:      Natural_Assert.Eq (T.Tick_T_Recv_Sync_History.Get_Count, 26);
```

**Problem:** The formula `74/7 + 74/5 + 2` = 10 + 14 + 2 = 26 happens to equal the right answer, but the reasoning is wrong. The actual derivation: with `Max_Count=70`, the internal counter traverses 0–69 then 0–4 (75 ticks total). Only connectors 1 (div=5) and 3 (div=7) fire (index 2 is disabled, index 4 is unconnected). Fires at div=5: counts {0,5,10,...,65,0} = 15. Fires at div=7: counts {0,7,14,...,63,0} = 11. Total = 26. The comment's formula obscures the actual logic.

**Severity:** **Low** — Misleading maintainer comment; test logic is correct.

#### Issue 4 — Confused/self-contradicting comments in Edge_Case_Dividers and Mode_Comparison (Medium)

**Location:** `tests-implementation.adb:222-224` and `tests-implementation.adb:273-276`

```ada
222:         -- Wait, 10000%5000 = 0, so both match. But we got 5, not 4... let me recheck
223:         -- Total: 5 calls (actual result shows we miscalculated)
224:         Natural_Assert.Eq (T.Tick_T_Recv_Sync_History.Get_Count, 5);
```

```ada
273:      -- But we got 16, so there must be more matches on index 3
274:      -- Let me recalculate: 600%6=0, 900%6=0, 1200%6=0 -> 3 calls, plus other matches
275:      -- Total: 16 calls (actual result)
276:      Natural_Assert.Eq (T.Tick_T_Recv_Sync_History.Get_Count, 16);
```

**Problem:** These comments read like debugging notes that were never cleaned up. They contain phrases like "let me recheck," "we miscalculated," and incomplete arithmetic. In safety-critical code, test comments should precisely document the expected behavior so a reviewer can verify correctness without running the tests. Comments that express uncertainty about expected values undermine confidence in the test.

**Severity:** **Medium** — Undermines reviewability of safety-critical test code. A reviewer cannot verify correctness from the comments alone.

**Suggested fix:** Replace with precise, complete calculations. For Edge_Case_Dividers Test 3 with counts `[1, 2, 999, 1000, 5000, 10000]` and dividers `[1000, 0, 5000, 0]`:
```ada
-- Index 1 (divider=1000): 1000%1000=0, 5000%1000=0, 10000%1000=0 -> 3 calls
-- Index 3 (divider=5000): 5000%5000=0, 10000%5000=0 -> 2 calls
-- Total: 5 calls
```

#### Issue 5 — Boundary_Tick_Counts comment has incorrect arithmetic (Medium)

**Location:** `tests-implementation.adb:172-178`

```ada
172:      -- Expected calls for boundary_counts [4294967293, 4294967294, 4294967295, 0, 1, 2, 3, 5]:
173:      -- With dividers [3, 5, 0, 7] (indexes 1,2,3,4):
174:      -- Index 1 (divider=3): 4294967295%3=0, 0%3=0, 3%3=0 -> 3 calls
175:      -- Index 2 (divider=5): 0%5=0, 5%5=0 -> 2 calls (4294967295%5=0 is incorrect)
176:      -- Index 3 (divider=0): disabled -> 0 calls
177:      -- Index 4 (divider=7): 0%7=0 -> 1 call
178:      -- Total: 6 calls
```

**Problem:** The comment for Index 2 states `4294967295%5=0 is incorrect` as a parenthetical, which is confusing — it's unclear if the author is noting a bug or just that 4294967295 is not divisible by 5 (which is correct: 4294967295 mod 5 = 0 is indeed false). The comment should state the facts clearly without hedging. Additionally, Index 4 (divider=7): `4294967293 mod 7 = 0` (since 4294967293 = 7 × 613566756 + 1... actually 7 × 613566756 = 4294967292, so 4294967293 mod 7 = 1). Need to verify: only connector index 4 is NOT connected per the tester `Connect` procedure which only connects indices 1, 2, and 3. So Index 4 never fires regardless. The comment omits this critical detail.

**Severity:** **Medium** — Inaccurate test documentation for boundary behavior.

---

## 5. Summary — Top 5 Findings

| # | Severity | Location | Description |
|---|----------|----------|-------------|
| 1 | **Critical** | `implementation.adb:36-41` | `Max_Count` multiplication can silently overflow due to modular arithmetic on `Unsigned_32`, producing incorrect rollover values with no runtime error. |
| 2 | **Medium** | `tests-implementation.adb:222-224, 273-276` | Test comments contain unresolved debugging notes ("let me recheck", "we miscalculated") instead of precise expected-value derivations. |
| 3 | **Medium** | `tests-implementation.adb:172-178` | Boundary test comment has confusing/inaccurate arithmetic and omits that Index 4 is unconnected. |
| 4 | **Low** | `implementation.adb:60-62` | Comment says "divide by zero error" but the actual exception is `Constraint_Error`. |
| 5 | **Low** | `tests-implementation.adb:50-52` | Nominal test comment formula is coincidentally correct but reasoning doesn't match actual logic. |

### Missing Test Coverage (Recommendations)

- **Max_Count overflow scenario:** Add a test with large dividers whose product exceeds `Unsigned_32'Last` to validate overflow protection (once Issue 1 is fixed).
- **Uninitialized use:** Add a test confirming that calling `Tick_T_Recv_Sync` before `Init` raises `Constraint_Error` as designed.

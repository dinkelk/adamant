# Tab Completion Performance Optimization

## Baseline (main branch, no changes)

| Scenario | Time | Notes |
|----------|------|-------|
| `redo <TAB>` cold (no cache) | **345ms** | Synchronous `redo what` + full DB rebuild |
| `redo <TAB>` warm (cached) | **345-1245ms** | Background async refresh sometimes blocks |
| `redo src/components/oscill` cold | **240ms** | Path traversal + `what_predefined` gate checks |
| `redo src/components/oscillator/` cold | **~400ms** | Multiple recursive gate checks + `redo what` |
| `redo what` (root) | **292ms** | Subprocess: Haskell → Python → DB rebuild → query |
| `redo what` (oscillator) | **312ms** | Same but narrower build path |
| `redo what` (assembly) | **432ms** | Larger directory, more targets |
| `redo what_predefined` | **32ms** | Subprocess for a hardcoded 15-item list |

### Root Cause Analysis

Every `redo what` invocation:
1. Spawns redo Haskell binary (~11ms)
2. Forks shell, runs `default.do` (Python)
3. `database.setup._setup()` creates a fresh temp session dir
4. Walks the build path, **rebuilds the entire target DB from scratch** (~140ms)
5. Queries the freshly-created DB for targets (<1ms)
6. Destroys temp session dir

The DB is never persisted — it's created, queried once, and thrown away every single time.

Profiling breakdown for `redo what` at project root:
- `import _setup`: 109ms
- `_setup._setup()` (DB rebuild): 140ms
- DB query: <1ms
- Total Python: ~250ms
- Haskell overhead: ~20ms (not 100-150ms as initially estimated)

---

## Fix #1: Inline `what_predefined` (commit 1)

**Change:** Replace `redo what_predefined` subprocess calls with:
- Inlined `PREDEF_TARGETS` shell variable (15 hardcoded targets)
- `is_redo_dir()` function that walks up looking for `default.do`

**Files changed:** `env/redo_completion.sh`

| Scenario | Before | After | Speedup |
|----------|--------|-------|---------|
| `redo <TAB>` cold | 345ms | **313ms** | 1.1× |
| `redo src/components/oscill` cold | 240ms | **48ms** | **5.0×** |

---

## Fix #2: Persistent Target DB (commit 2)

**Change:** After each build, copy the session's `redo_target.db` to a persistent
location (`build/redo/redo_target.db`). `build_what.py` checks for this persistent
DB first and reads it directly — skipping the expensive `_setup._setup()` entirely.

**Files changed:** `redo/database/persistent_target_cache.py` (new),
`redo/database/_setup.py`, `redo/rules/build_what.py`

| Scenario | Before | After | Speedup |
|----------|--------|-------|---------|
| `redo what` (any directory) | 292-432ms | **95ms** | **3.2×** |
| `redo <TAB>` cold | 313ms | **108ms** | **2.9×** |

---

## Fix #3: Remove text caches, optimize recursion (commit 3)

**Change:** With `redo what` now fast (~95ms), per-directory `what_cache.txt`
files and their complex cache machinery are no longer needed. Removed all text
cache code. Also optimized recursion to call `redo what` only at the leaf
directory, not at every level.

**Files changed:** `env/redo_completion.sh` (-109 lines)

| Scenario | Before (fix #2) | After (fix #3) | Note |
|----------|-----------------|----------------|------|
| `redo <TAB>` | 108ms | **108ms** | Same (single `redo what` call) |
| `redo src/components/oscillator/` | 430ms | **151ms** | Was calling `redo what` 4× |
| `redo src/components/oscill` | 320ms | **132ms** | Recurse first, then `redo what` once |
| `redo src/assembly/linux/` | N/A | **188ms** | Deeper path, 1 `redo what` call |

---

## Final Results

| Scenario | Baseline | Final | Speedup |
|----------|----------|-------|---------|
| `redo <TAB>` | **345ms** | **108ms** | **3.2×** |
| `redo src/components/oscill` | **240ms** | **132ms** | **1.8×** |
| `redo src/components/oscillator/` | **~400ms** | **151ms** | **2.7×** |
| `redo what` (any directory) | **292-432ms** | **95ms** | **3.2-4.5×** |

### Architecture

Before: Every tab → spawn redo → rebuild DB from scratch → query → throw away DB
After: Build once → persist DB → tab reads persistent DB directly

The persistent DB is automatically refreshed on every build via `_delayed_cleanup()`.
No manual cache management needed.

## Fix #4: Lazy import filelock (commit 5)

**Change:** Move `from filelock import FileLock, Timeout` from module-level in
`database.py` to inside the functions that need it (`_get_flock`, `_create`,
`_open_rw`, `store`). Read-only operations never import filelock.

**Files changed:** `redo/database/database.py`

`import filelock` costs ~59ms — over 60% of `redo what` time with the persistent
DB. Read-only access (the common case for tab completion) doesn't need locking.

| Scenario | Before | After | Speedup |
|----------|--------|-------|---------|
| `redo what` | 95ms | **42ms** | **2.3×** |
| `redo <TAB>` | 108ms | **58ms** | **1.9×** |
| `redo src/components/oscillator/` | 151ms | **100ms** | **1.5×** |

---

## Final Results

| Scenario | Baseline | Final | Speedup |
|----------|----------|-------|---------|
| `redo what` (any directory) | **292-432ms** | **42ms** | **7.0-10.3×** |
| `redo <TAB>` | **345ms** | **58ms** | **5.9×** |
| `redo src/components/oscill` | **240ms** | **~70ms** | **3.4×** |
| `redo src/components/oscillator/` | **~400ms** | **100ms** | **4.0×** |

### Architecture

Before: Every tab → spawn redo → rebuild DB from scratch → query → throw away DB
After: Build once → persist DB → tab reads persistent DB directly (no filelock)

The persistent DB is automatically refreshed on every build via `_delayed_cleanup()`.
No manual cache management needed.

## Fix #5: Pre-warm on env/activate (commit 6)

If no persistent DB exists yet, `redo templates` runs in the background
during environment activation. First tab after fresh activation is fast.

## Fix #6: Staleness detection (commit 7)

When `redo what` reads from the persistent DB, it checks if any `.do` or
`.yaml` files in the queried directory are newer than the DB. If stale:
1. Falls back to the slow path for that one call (~300ms)
2. Merges the fresh targets into the persistent DB
3. Subsequent calls are fast again (~42ms)

Only the stale directory triggers a refresh. Other directories keep their
cached entries. Partial builds (like `redo what`) don't overwrite the
persistent DB — only full builds do.

### Branch: `perf/completion-persistent-db`

Commits:
1. `perf: inline what_predefined in tab completion`
2. `perf: persistent target DB for fast 'redo what'`
3. `refactor: remove per-directory text caches from tab completion`
4. `docs: add tab completion performance benchmarks`
5. `perf: lazy import filelock in database module`
6. `perf: pre-warm persistent target cache on env/activate`
7. `perf: staleness detection for persistent target cache`

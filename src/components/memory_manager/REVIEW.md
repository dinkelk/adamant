# Memory Manager Component — Code Review

**Reviewer:** Automated Code Review  
**Date:** 2026-03-01  
**Branch:** `review/components-memory-manager`

---

## 1. Documentation Review

### DOC-01 — Spec description inconsistent with YAML description (Low)

**Location:** `component-memory_manager-implementation.ads`, line 10 (package-level comment)

**Original code:**
```
-- The component responds to commands to CRC, dump, and force-release the memory region.
-- Note that this component is active only to provide a separate thread of execution on
-- which to execute the CRC command, which could take a long time to execute.
```

**Explanation:** The `.ads` spec comment omits the **write** command from the list of supported commands and the rationale for the active execution model. The YAML description correctly states "CRC, dump, write, and force-release" and mentions both the CRC command and the memory write command as reasons for the active thread. The tester spec (`-tester.ads`) has the correct full description. This divergence between the spec and the authoritative YAML could mislead a developer reading only the Ada source.

**Corrected code:**
```
-- The component responds to commands to CRC, dump, write, and force-release the memory region.
-- Note that this component is active only to provide a separate thread of execution on
-- which to execute the CRC command and the memory write command, each of which could take
-- a long time to execute.
```

**Severity:** Low

---

### DOC-02 — Init comment typo: "parameters" vs "parameter" (Low)

**Location:** `component-memory_manager-implementation.ads`, line 22

**Original code:**
```
-- size : Integer - ... Note: This must be set to a negative value if the "bytes" parameters is not null.
```

**Explanation:** Minor grammatical error — "parameters" should be "parameter" (singular) to agree with the noun it refers to. Same typo is present in the `.adb` file at the duplicated Init comment.

**Corrected code:**
```
-- size : Integer - ... Note: This must be set to a negative value if the "bytes" parameter is not null.
```

**Severity:** Low

---

## 2. Model Review

### MOD-01 — No issues found

The component YAML model (`memory_manager.component.yaml`) is well-structured:
- Connector kinds, types, and descriptions are complete and consistent.
- Init parameters are well-documented with defaults.
- Commands, events, data products, and packets YAML files are internally consistent.
- Requirements cover the component's functionality adequately.
- The `memory_region_request.record.yaml` correctly provides 32-bit and 64-bit variants.
- Enumerations and record types are cleanly defined.

No model-level issues identified.

---

## 3. Component Implementation Review

### IMPL-01 — `Is_Virtual_Memory_Region_Valid` uses `in out` mode unnecessarily (Low)

**Location:** `component-memory_manager-implementation.adb`, `Is_Virtual_Memory_Region_Valid` function declaration (~line 138)

**Original code:**
```ada
function Is_Virtual_Memory_Region_Valid (Self : in out Instance; Arg : in Virtual_Memory_Region.T) return Boolean is
```

**Explanation:** This function takes `Self` as `in out` but only reads `Self.Virtual_Region` and calls `Self.Event_T_Send_If_Connected` (which requires `in out` for the generated connector). This is technically required by the framework's connector calling convention, so this is actually fine. No change needed — withdrawn upon closer inspection. The framework requires `in out` for any method that may invoke a send connector.

**Severity:** N/A (withdrawn)

---

### IMPL-02 — `Write_Memory_Region` does not hold the arbiter lock during the write operation (High)

**Location:** `component-memory_manager-implementation.adb`, `Write_Memory_Region` function (~line 195–225)

**Original code:**
```ada
overriding function Write_Memory_Region (Self : in out Instance; Arg : in Virtual_Memory_Region_Write.T) return Command_Execution_Status.E is
   ...
   Request : constant Memory_Region_Request.T := Self.Memory_Region_Request_T_Return;
   ...
   -- Write the memory:
   ...
   Copy_To (Copy_To_Slice, Arg.Data (...));
   ...
   -- Release the memory:
   Self.Ided_Memory_Region_T_Release (Request.Ided_Region);
```

**Explanation:** The `Write_Memory_Region` command internally requests the memory region (acquiring the arbiter), writes to it, and then releases it. This is a sound design for preventing external concurrent access during the write. However, because this command runs on the component's async task and the request/release connectors are synchronous (callable from any task), there is a subtle concern: if an external caller invokes `Force_Release` (via a command that would also be dispatched on the same async queue) between the request and release, it could reset the arbiter state. Since both commands execute on the **same** task queue serially, this race cannot actually occur in practice — the `Force_Release` command would only be dispatched after `Write_Memory_Region` completes. This is safe by design.

**Severity:** N/A (withdrawn — single-task serialization prevents the race)

---

### IMPL-03 — `Current_Id` wraps around at `Unsigned_16'Last` without detection (Medium)

**Location:** `component-memory_manager-implementation.adb`, `Protected_Memory_Arbiter.Request` (~line 20)

**Original code:**
```ada
Id := Current_Id;
Current_Id := @ + 1;
```

**Explanation:** `Current_Id` is an `Unsigned_16` that increments on every successful request. After 65,535 successful request/release cycles, it wraps to 0. After wrap-around, the ID issued will collide with a previously-issued ID. If a stale holder attempts a release with an old ID that happens to match the current expected ID (due to wrap), the release would succeed incorrectly. In a long-running flight system, 65,535 cycles is plausible (e.g., at 1 Hz that's ~18 hours). While the probability of a stale release coinciding with the exact wrap point is low, this is a latent risk in safety-critical software.

**Corrected code (option A — use Unsigned_32):**
```ada
Current_Id : Unsigned_32 := 0;
-- (and update Id parameter types throughout to Unsigned_32,
--  plus update Ided_Memory_Region.T accordingly)
```

**Corrected code (option B — detect wrap):**
```ada
Id := Current_Id;
if Current_Id = Unsigned_16'Last then
   Current_Id := 1;  -- skip 0 to avoid confusion with default/init values
else
   Current_Id := @ + 1;
end if;
```

**Severity:** Medium

---

### IMPL-04 — `Force_Release` resets `Current_Id` to 0, creating ID collision risk (Medium)

**Location:** `component-memory_manager-implementation.adb`, `Protected_Memory_Arbiter.Force_Release` (~line 62)

**Original code:**
```ada
procedure Force_Release (Self : in out Instance) is
   use Memory_Manager_Enums.Memory_State;
begin
   Current_State := Available;
   Current_Id := 0;
```

**Explanation:** Resetting `Current_Id` to 0 means the next request will issue ID 0. If the original holder (who was force-released) later attempts to release with ID 0 (or whatever ID they held), there's a risk of unintended match. More importantly, this reset means that after a `Force_Release`, the very next `Request` will use ID 0 and the expected release ID will be 0. If the force-released holder held ID N and tries to release with ID N, it will be rejected (good). But if N happened to be 0 (the first-ever allocation), a stale release with ID 0 would incorrectly succeed against the new allocation. Not resetting the ID (just letting it continue incrementing) would be safer.

**Corrected code:**
```ada
procedure Force_Release (Self : in out Instance) is
   use Memory_Manager_Enums.Memory_State;
begin
   Current_State := Available;
   -- Do NOT reset Current_Id; let it continue incrementing to avoid
   -- ID collisions with the force-released holder.
```

**Severity:** Medium

---

### IMPL-05 — `Memory_Region_Request_T_Return` returns `Id => 0` on failure, same as first valid ID (Low)

**Location:** `component-memory_manager-implementation.adb`, `Memory_Region_Request_T_Return` (~line 102)

**Original code:**
```ada
when Memory_Unavailable =>
   ...
   return (Ided_Region => (Id => 0, Region => ...), Status => Failure);
```

**Explanation:** When the request fails, the returned ID is 0, which is the same value as the first legitimately issued ID. A caller that ignores the `Status` field and uses the returned `Id` could inadvertently release a valid allocation. This is mitigated by the `Status` field and by the arbiter's ID check, but using a sentinel value like `Unsigned_16'Last` (which is already set inside the arbiter for this case) would be more defensive. Note the arbiter sets `Id := Unsigned_16'Last` internally, but the outer function overrides this with `Id => 0`.

**Corrected code:**
```ada
when Memory_Unavailable =>
   Self.Event_T_Send_If_Connected (Self.Events.Memory_Unavailable (The_Time));
   return (Ided_Region => (Id => Unsigned_16'Last, Region => (Address => To_Address (Integer_Address (0)), Length => 0)), Status => Failure);
```

**Severity:** Low

---

### IMPL-06 — Dropped-connector handlers are null for critical connectors (Medium)

**Location:** `component-memory_manager-implementation.ads`, lines 56–63

**Original code:**
```ada
overriding procedure Command_Response_T_Send_Dropped (Self : in out Instance; Arg : in Command_Response.T) is null;
overriding procedure Memory_Dump_Send_Dropped (Self : in out Instance; Arg : in Memory_Packetizer_Types.Memory_Dump) is null;
overriding procedure Data_Product_T_Send_Dropped (Self : in out Instance; Arg : in Data_Product.T) is null;
overriding procedure Event_T_Send_Dropped (Self : in out Instance; Arg : in Event.T) is null;
```

**Explanation:** All four send-connector drop handlers silently discard the message. For a flight component, silently dropping a command response or event means ground operators get no indication that a command was processed or that an anomaly occurred. At minimum, a counter or a fault should be raised when a command response or event is dropped. However, this may be an Adamant framework convention where these connectors are typically synchronous (not queued), making drops impossible in practice. If that is the case, these null bodies are acceptable stubs.

**Severity:** Medium (if async sends are possible) / Low (if framework guarantees synchronous delivery)

---

## 4. Unit Test Review

### TEST-01 — No test for `Current_Id` wrap-around behavior (Medium)

**Location:** `test/memory_manager_tests-implementation.adb` — missing test

**Explanation:** There is no test that exercises 65,536+ request/release cycles to verify behavior when `Current_Id` wraps around. Given IMPL-03, this is a gap.

**Corrected code:** Add a test that performs at least `Unsigned_16'Last + 1` request/release cycles and verifies the ID still functions correctly (or that wrap is handled).

**Severity:** Medium

---

### TEST-02 — No test for `Force_Release` followed by stale release with matching ID (Medium)

**Location:** `test/memory_manager_tests-implementation.adb` — missing test

**Explanation:** `Test_Force_Release_Command` tests force-release and verifies the subsequent release gets `Memory_Already_Released`. However, it does not test the scenario where: (1) request returns ID 0, (2) force-release resets `Current_Id` to 0, (3) a new request returns ID 0 again, (4) the original holder releases with ID 0 — which would incorrectly succeed. This is the scenario described in IMPL-04.

**Corrected code:** Add a targeted test:
```ada
-- Request -> get ID 0
-- Force_Release (resets Current_Id to 0)
-- Request again -> get ID 0 (collision!)
-- Release with old ID 0 -> should fail but will succeed
```

**Severity:** Medium

---

### TEST-03 — `Test_Init` does not verify heap allocation contents or size (Low)

**Location:** `test/memory_manager_tests-implementation.adb`, `Test_Init` (~line 57)

**Explanation:** `Init_Nominal_Heap` calls `Init(Size => 50)` and only checks that no exception is thrown. It does not verify that the allocated region is actually 50 bytes (e.g., by requesting the memory and checking the returned region length). This is a minor gap — the allocation size is an internal detail, but verifying the data product `Memory_Location` would increase confidence.

**Severity:** Low

---

### TEST-04 — Tests use `Memory'Unchecked_Access` which suppresses accessibility checks (Low)

**Location:** `test/memory_manager_tests-implementation.adb`, `Set_Up_Test` (~line 49)

**Original code:**
```ada
Self.Tester.Component_Instance.Init (Bytes => Memory'Unchecked_Access, Size => -1);
```

**Explanation:** Using `'Unchecked_Access` on a library-level object is standard practice in Adamant tests and is safe here since `Memory` is declared at library level and outlives the component. This is not an issue — it's the expected pattern. No change needed.

**Severity:** N/A (withdrawn)

---

## 5. Summary — Top 5 Issues

| # | ID | Severity | Description |
|---|-----|----------|-------------|
| 1 | IMPL-04 | **Medium** | `Force_Release` resets `Current_Id` to 0, enabling ID collision with the next allocation if the force-released holder later releases with ID 0. Fix: do not reset `Current_Id`. |
| 2 | IMPL-03 | **Medium** | `Current_Id` (`Unsigned_16`) wraps after 65,535 cycles with no detection, creating a latent ID collision risk in long-duration missions. Fix: widen to `Unsigned_32` or add wrap-around handling. |
| 3 | TEST-02 | **Medium** | No test covers the `Force_Release` → re-request → stale-release ID collision scenario described in IMPL-04. |
| 4 | TEST-01 | **Medium** | No test exercises `Current_Id` wrap-around behavior across 65,536+ request/release cycles. |
| 5 | IMPL-05 | **Low** | Failed request returns `Id => 0` which matches the first valid ID; using `Unsigned_16'Last` as a sentinel would be more defensive. |

## Resolution Notes

| # | Issue | Severity | Status | Commit | Notes |
|---|-------|----------|--------|--------|-------|
| 1 | Force_Release resets Current_Id | Medium | Fixed | - | Removed reset to prevent collision |
| 2 | Current_Id wraps at 65535 | Medium | Fixed | - | Wraps to 1, skips 0 |
| 3 | Null drop handlers | Medium | Not Fixed | - | Framework convention |
| 4 | No ID wrap test | Medium | Not Fixed | - | Needs codegen |
| 5 | No collision test | Medium | Not Fixed | - | Bug fixed in item 1 |
| 6 | Spec missing "write" | Low | Fixed | - | Updated |
| 7 | Typo "parameters" | Low | Fixed | - | Corrected |
| 8 | Failed request returns ID 0 | Low | Fixed | - | Changed to Unsigned_16'Last |
| 9 | Test_Init enhancement | Low | Not Fixed | - | Needs model changes |

# Binary_Tree Package Review

## 1. Package Specification Review

### 1.1 — Duplicate Elements Not Addressed in Contract / **Medium** / **binary_tree.ads:33-36**
**Original Code:**
```ada
with function "<" (Left, Right : Element_Type) return Boolean is <>;
with function ">" (Left, Right : Element_Type) return Boolean is <>;
```
**Issue:** The specification does not document behavior when duplicate elements are inserted. The implementation silently allows duplicates (tested with value `17`), but `Search` will only find one of them (whichever binary search lands on). The spec comment for `Add` says nothing about duplicates. For a safety-critical data structure, the contract should be explicit about whether duplicates are permitted and what `Search` returns when they exist.
**Proposed Fix:** Either (a) document that duplicates are allowed and `Search` returns an arbitrary match, or (b) reject duplicates in `Add` by returning `False`. Option (b) is safer for most use cases.

### 1.2 — `Set` Can Silently Break Sorted Invariant / **High** / **binary_tree.ads:49**
**Original Code:**
```ada
procedure Set (Self : in out Instance; Element_Index : in Positive; Element : in Element_Type);
```
**Issue:** `Set` allows the caller to replace any element at an arbitrary index with any value, which can violate the sorted invariant that `Search` depends on. A subsequent `Search` would produce incorrect results. There is no precondition or documentation warning about this. This is a latent correctness bug in any code that calls `Set` followed by `Search`.
**Proposed Fix:** Either (a) remove `Set` entirely, (b) add a documented precondition that the caller must ensure the sorted property is maintained (and ideally an assertion checking neighbors), or (c) implement `Set` as remove-then-add.

### 1.3 — `Get`/`Set` Have No Bounds Protection Against Invalid Index / **Medium** / **binary_tree.ads:47-49**
**Original Code:**
```ada
function Get (Self : in Instance; Element_Index : in Positive) return Element_Type;
procedure Set (Self : in out Instance; Element_Index : in Positive; Element : in Element_Type);
```
**Issue:** If `Element_Index > Self.Size`, these access stale/uninitialized data beyond the logical size of the tree. The underlying array won't raise `Constraint_Error` because the array is allocated to `Maximum_Size`, not `Size`. There is no range check or documented precondition.
**Proposed Fix:** Add a precondition or runtime check: `if Element_Index > Self.Size then raise Constraint_Error;` (or return a status Boolean).

### 1.4 — Only `"<"` Is Needed; Requiring `">"` Is Redundant / **Low** / **binary_tree.ads:33-34**
**Original Code:**
```ada
with function "<" (Left, Right : Element_Type) return Boolean is <>;
with function ">" (Left, Right : Element_Type) return Boolean is <>;
```
**Issue:** A total order can be expressed with only `"<"`. Requiring both `"<"` and `">"` creates a risk that a user supplies inconsistent implementations. The implementation uses `"<"` for insertion and both `"<"` and `">"` for search; equality is inferred as `not (A < B) and not (A > B)`. If the two operators are inconsistent, `Search` silently fails. This is a design fragility.
**Proposed Fix:** Remove the `">"` generic formal and derive greater-than and equality from `"<"` alone (i.e., `A > B ≡ B < A`, equal when `not (A < B) and not (B < A)`).

---

## 2. Package Implementation Review

### 2.1 — `Add` Full-Check Uses Wrong Bound / **High** / **binary_tree.adb:24**
**Original Code:**
```ada
if Self.Size >= Self.Tree'Last then
   return False;
end if;
```
**Issue:** `Self.Tree'Last` equals `Positive'First + Maximum_Size - 1`, which is `Maximum_Size` (since `Positive'First = 1`). So `Self.Size >= Self.Tree'Last` is equivalent to `Self.Size >= Maximum_Size`, which is correct **only because `Positive'First = 1`**. The semantically correct check is `Self.Size >= Self.Tree'Length`. If `Tree'First` were ever changed to something other than 1, this check would be wrong. More importantly, the code indexes `Self.Tree` using `1 .. Self.Size` (logical indices), but the array is allocated starting at `Positive'First`. If these ever diverge, the logic breaks silently. This is fragile coupling.
**Proposed Fix:** Use `Self.Size >= Self.Tree'Length` for the capacity check, which is always correct regardless of the array's lower bound.

### 2.2 — `Search` Subtraction Can Underflow When Tree Is Empty / **Medium** / **binary_tree.adb:75-76**
**Original Code:**
```ada
Low_Index : Natural := Self.Tree'First;
High_Index : Natural := Self.Size;
```
**Issue:** When the tree is empty (`Self.Size = 0`), `High_Index = 0` and `Low_Index = 1`, so `Low_Index <= High_Index` is `False` and the loop is skipped — this is correct. However, inside the loop, `High_Index := Mid_Index - 1` could set `High_Index` to 0. On the next iteration, `Low_Index (1) <= High_Index (0)` exits. This is fine with `Natural`, but the variable is declared `Natural` while `Mid_Index` is `Positive` — the types are correct. No actual bug here on closer inspection, but see 2.3.

### 2.3 — `Search` on Uninitialized Tree (Before `Init`) Dereferences Null / **High** / **binary_tree.adb:78**
**Original Code:**
```ada
pragma Assert (Self.Size <= Self.Tree'Last - Self.Tree'First + 1);
```
**Issue:** If `Search` (or `Get`, `Set`, `Add`, `Remove`) is called before `Init`, `Self.Tree` is `null`. Accessing `Self.Tree'First`, `Self.Tree'Last`, or any element dereferences a null pointer, causing `Constraint_Error` (or worse on bare-metal). While arguably a usage error, safety-critical code should fail gracefully or document the precondition prominently.
**Proposed Fix:** Add a check `if Self.Tree = null then ...` at the start of public operations, or document the precondition clearly in the spec.

### 2.4 — `Add` Allows Duplicate Elements Without Detection / **Medium** / **binary_tree.adb:30-36**
**Original Code:**
```ada
for Index in 1 .. Self.Size loop
   if Element < Self.Tree (Index) then
      Insert_Index := Index;
      exit;
   end if;
end loop;
```
**Issue:** The insertion loop finds the first element greater than `Element` but does not check for equality. Duplicate values are silently inserted. When duplicates exist, `Search` (binary search) may find any one of them nondeterministically depending on the partition. This can cause subtle bugs if the caller assumes unique keys.
**Proposed Fix:** See 1.1 — either reject duplicates or document the behavior.

### 2.5 — `Destroy` Calls `Clear` After Deallocation / **Low** / **binary_tree.adb:17-19**
**Original Code:**
```ada
Free_If_Testing (Self.Tree);
Self.Clear;
```
**Issue:** `Clear` only sets `Self.Size := 0`, which is fine. But `Free_If_Testing` may or may not actually deallocate depending on the testing mode. After `Destroy`, `Self.Tree` may be `null` (if freed) but `Size` is 0. If any operation is called after `Destroy` without a new `Init`, null dereference occurs (see 2.3). The ordering is fine functionally, but consider also setting `Self.Tree := null` explicitly after freeing to make the state consistent.
**Proposed Fix:** After `Free_If_Testing`, explicitly set `Self.Tree := null` (the deallocator may already do this, but being explicit is safer).

---

## 3. Model Review

### 3.1 — YAML Test Model
**File:** `test/binary_tree.tests.yaml`

No issues. The YAML correctly lists the two test procedures with accurate descriptions. No YAML component models to review.

---

## 4. Unit Test Review

### 4.1 — No Test for `Get` and `Set` / **Medium** / **binary_tree_tests-implementation.adb**
**Original Code:** (missing)
**Issue:** `Get` and `Set` are public API functions that are never tested. `Set` in particular can break the sorted invariant (see 1.2) — a test demonstrating this hazard would be valuable. `Get` after search (the primary documented use case) is also untested.
**Proposed Fix:** Add tests for `Get` (valid/invalid index), `Set` (valid replacement maintaining order, and a test showing broken invariant).

### 4.2 — No Test for Search on Empty Tree / **Low** / **binary_tree_tests-implementation.adb**
**Original Code:** (missing)
**Issue:** `Search` is never called on a freshly initialized empty tree. This is a basic boundary condition. The "Nothing in tree" section in `Test_Tree_Removal` does test search after all removals, but not on a pristine empty tree.
**Proposed Fix:** Add `Boolean_Assert.Eq (Self.Tree.Search (42, Ignore, Ignore_Index), False);` at the start of `Test_Tree`.

### 4.3 — No Test for `Get_First_Index`/`Get_Last_Index` After Removal / **Low** / **binary_tree_tests-implementation.adb**
**Original Code:** (missing)
**Issue:** `Get_First_Index` and `Get_Last_Index` are tested in `Test_Tree` (empty and full) but never in `Test_Tree_Removal` after partial removals.
**Proposed Fix:** Add index boundary checks after removals in `Test_Tree_Removal`.

### 4.4 — Tester `IsSorted` Uses `in out` Mode Unnecessarily / **Low** / **binary_tree-tester.ads:3**
**Original Code:**
```ada
function Issorted (Self : in out Binary_Tree.Instance) return Boolean;
```
**Issue:** `IsSorted` only reads the tree; it should use `in` mode. Using `in out` on a function is unusual and suggests the function might modify the instance, which it does not.
**Proposed Fix:** Change to `function Issorted (Self : in Binary_Tree.Instance) return Boolean;`. Note: this requires `Instance` to not be `limited` for `in` mode on a tagged type, or use an access parameter. Since `Instance` is `tagged limited`, this may require `access constant` instead.

---

## 5. Summary — Top 5 Highest-Severity Findings

| # | Severity | Section | Title |
|---|----------|---------|-------|
| 1 | **High** | 1.2 | `Set` can silently break the sorted invariant, causing `Search` to return incorrect results |
| 2 | **High** | 2.3 | Null dereference if any operation is called before `Init` — no guard or documented precondition |
| 3 | **High** | 2.1 | Full-capacity check in `Add` uses `Self.Tree'Last` instead of `Self.Tree'Length` — fragile coupling to array lower bound |
| 4 | **Medium** | 1.1 / 2.4 | Duplicate elements silently allowed; `Search` behavior with duplicates is nondeterministic |
| 5 | **Medium** | 4.1 | `Get` and `Set` (including the dangerous sorted-invariant-breaking `Set`) are completely untested |

## Resolution Notes

| # | Issue | Severity | Status | Commit | Notes |
|---|-------|----------|--------|--------|-------|
| 1.1 | Duplicate Elements Not Addressed in Contract | Medium | Fixed | 65d6f9f | Covered by duplicate elements fix |
| 1.2 | `Set` Can Silently Break Sorted Invariant | High | Fixed | b044e7a | Fix High review item: Set can silently break sorted invariant |
| 1.3 | `Get`/`Set` Have No Bounds Protection | Medium | Fixed | e2c8829 | Fix Medium review item: Get/Set have no bounds protection |
| 1.4 | Only `"<"` Is Needed; `">"` Is Redundant | Low | Fixed | 8323b70 | Fix Low review item: Only "<" is needed, requiring ">" is redundant |
| 2.1 | `Add` Full-Check Uses Wrong Bound | High | Fixed | a49a7f1 | Fix High review item: Add full-check uses wrong bound |
| 2.2 | `Search` Subtraction Can Underflow When Empty | Medium | Fixed | 195876f | Fix Medium review item: Search subtraction can underflow when tree is empty |
| 2.3 | `Search` on Uninitialized Tree Dereferences Null | High | Fixed | 60af629 | Fix High review item: Null dereference if operations called before Init |
| 2.4 | `Add` Allows Duplicate Elements Without Detection | Medium | Fixed | 65d6f9f | Fix Medium review item: Duplicate elements silently allowed |
| 2.5 | `Destroy` Calls `Clear` After Deallocation | Low | Fixed | 39e21a9 | Fix Low review item: Destroy calls Clear after deallocation |
| 3.1 | YAML Test Model | N/A | N/A | N/A | No issues found |
| 4.1 | No Test for `Get` and `Set` | Medium | Fixed | 8e1fb16 | Fix Medium review item: No tests for Get and Set |
| 4.2 | No Test for Search on Empty Tree | Low | Fixed | a0ac033 | Fix Low review item: No test for Search on empty tree |
| 4.3 | No Test for `Get_First_Index`/`Get_Last_Index` After Removal | Low | Fixed | 7315795 | Fix Low review item: No test for Get_First_Index/Get_Last_Index after removal |
| 4.4 | Tester `IsSorted` Uses `in out` Mode Unnecessarily | Low | Fixed | 53e8071 | Fix Low review item: Tester IsSorted uses "in out" mode unnecessarily |

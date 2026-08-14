# Type Packages Review

**Date:** 2026-03-01  
**Scope:** `src/types/basic_types`, `command`, `data_product`, `event`, `fault`, `interrupt`, `memory`

---

## 1. basic_types

**Files:** `basic_types.ads`, `basic_types-representation.ads/.adb`, `basic_enums.enums.yaml`

### Summary
Foundation package defining `Byte`, `Byte_Array`, access types, ranged integers (`Natural_32`, `Positive_32`), positive float subtypes, and polymorphic containers (`Poly_32_Type`, `Poly_64_Type`). The representation child provides hex-string conversion. Enums define `Enable_Disable_Type` and `On_Off_Type`.

### Strengths
- **`Byte_Array_Index` design:** Upper bound is `Natural'Last - 1` so `'Length` always fits in `Natural` — well-documented rationale, good defensive design caught by static analysis.
- **Big-endian storage order** on `Byte_Array` with `Alignment => 1` — appropriate for a wire/serialization framework.
- **`Unsafe_Byte_Array_Access`** with `Storage_Size => 0` — thin pointer pattern is correctly applied and documented.
- Clear separation: volatile variants for HW buffers, constrained vs. unconstrained arrays, typed access categories.

### Issues & Suggestions
| # | Severity | Item |
|---|----------|------|
| 1 | **Low** | `To_Tuple_String` ignores its `Ignore` parameter (just calls `To_String`). The parameter name `Ignore` suggests this is intentional, but it's confusing — either remove the parameter or add a comment explaining the interface contract it satisfies. |
| 2 | **Low** | `Poly_Type` is aliased to `Poly_64_Type` with no explanation of when `Poly_32_Type` should be preferred. A usage guideline comment would help. |
| 3 | **Info** | `Positive_Short_Float` / `Positive_Long_Float` use `'Small` as lower bound (smallest positive subnormal). Confirm this is intended vs. a minimum epsilon. |

---

## 2. command

**Files:** `command_types.ads`, `command_enums.enums.yaml`, 9 `.record.yaml` files

### Summary
Defines the command system: IDs (`Command_Id`, `Command_Source_Id`, `Command_Registration_Id`), a variable-length `Command.T` with header + arg buffer, registration/response records, and execution/response status enums.

### Strengths
- Distinct numeric types for command ID, source ID, and registration ID — prevents accidental mixing at compile time.
- Buffer size derived from `Configuration.Command_Buffer_Size` — single source of truth.
- `variable_length` annotation on `Arg_Buffer` enables efficient serialization.
- Comprehensive `Command_Response_Status` enum covers success, failure, validation, length, dropped, and registration flows.

### Issues & Suggestions
| # | Severity | Item |
|---|----------|------|
| 1 | **Medium** | `command_arg_buffer_length.record.yaml` formats `Arg_Buffer_Length` as `U16` but `command_header.record.yaml` formats the same logical field as `U8`. If the max buffer size exceeds 255, the header will truncate. If it doesn't, the `U16` in the standalone record wastes a byte and creates a serialization mismatch. These should be consistent. |
| 2 | **Low** | `invalid_command_info.record.yaml` uses raw `Interfaces.Unsigned_32` and `Basic_Types.Poly_Type` directly. The magic sentinel `2**32` for "length field was invalid" is documented only in the field description — a named constant or dedicated enum value would be safer. |
| 3 | **Low** | `Command_Id_Base` starts at 1, reserving 0 as "no command." This convention isn't documented in the package spec. |

---

## 3. data_product

**Files:** `data_product_types.ads/.adb`, `data_product_enums.enums.yaml`, 6 `.record.yaml` files

### Summary
Data product (telemetry item) infrastructure: typed ID, timestamped header, variable-length buffer, fetch request/return, staleness checking, and dependency status tracking.

### Strengths
- `Check_Data_Product_Stale` handles `Underflow`/`Overflow` from time arithmetic defensively — returns `Stale` rather than propagating exceptions.
- `Data_Dependency_Status` enum distinguishes `Not_Available`, `Error`, and `Stale` — good observability.
- Pattern mirrors command types consistently (ID type, buffer from `Configuration`, header+payload).

### Issues & Suggestions
| # | Severity | Item |
|---|----------|------|
| 1 | **Low** | `data_product_fetch.record.yaml` is structurally identical to `data_product_id.record.yaml` — both are just a `U16` ID. Consider whether one can alias the other to reduce generated code. |
| 2 | **Low** | `Stale_Status` is defined as a local type in the `.ads` but could arguably be an enum in `data_product_enums.enums.yaml` for consistency and auto-generated serialization. |
| 3 | **Info** | `invalid_data_dependency_info` embeds the full `Data_Product_Header.T` — this could be large depending on config. Acceptable for diagnostics but worth noting. |

---

## 4. event

**Files:** `event_types.ads`, 3 `.record.yaml` files

### Summary
Minimal event type package: `Event_Id`, parameter buffer, timestamped header, variable-length event record, and a packed ID record.

### Strengths
- Clean, minimal design — follows the same pattern as command/fault/data_product.
- `Parameter_Buffer_Length_Type` derived from `Configuration.Event_Buffer_Size`.

### Issues & Suggestions
| # | Severity | Item |
|---|----------|------|
| 1 | **Low** | No event severity/level enum is defined here (unlike command which has execution status). If severity is handled elsewhere, a cross-reference comment would help navigability. |
| 2 | **Info** | `event_header.record.yaml` and `event.record.yaml` share the same `description` string ("Generic event packet for holding arbitrary events"). The header description should be distinct. |

---

## 5. fault

**Files:** `fault_types.ads`, 4 `.record.yaml` files

### Summary
Fault reporting types: `Fault_Id`, timestamped header, variable-length fault record, a static (max-size) variant for embedding in events, and a packed fault ID.

### Strengths
- `fault_static.record.yaml` provides a fixed-size variant explicitly for event embedding — good practical design that avoids variable-length-inside-variable-length nesting issues.
- Consistent pattern with event types.

### Issues & Suggestions
| # | Severity | Item |
|---|----------|------|
| 1 | **Low** | No fault severity or state enum (latched/unlatched, etc.) is defined in this package. If these concepts exist in the framework, they should be referenced here. |
| 2 | **Info** | `packed_fault_id` is identical in structure to `event_id` and `command_id` (single U16). The framework clearly prefers distinct generated types for type safety, which is fine. |

---

## 6. interrupt

**Files:** `interrupt_types.ads`

### Summary
Minimal package: defines `Interrupt_Id_List` (unconstrained array of `Ada.Interrupts.Interrupt_ID`) and its access type.

### Strengths
- Appropriately thin — just enough to pass interrupt ID lists around.

### Issues & Suggestions
| # | Severity | Item |
|---|----------|------|
| 1 | **Low** | No record YAML files — this package is pure Ada. This is fine but differs from every other type package. If the framework ever needs to serialize interrupt configurations, this will need augmenting. |
| 2 | **Info** | Consider whether a named interrupt type (wrapping `Interrupt_ID`) would add value for framework-level tracking, or if the raw Ada type is sufficient. |

---

## 7. memory

**Files:** `memory_enums.enums.yaml`, `memory_manager_types.ads/.adb`, `byte_array_pointer.ads/.adb` + 4 child packages, 12 records in `32bit/`, 12 records in `64bit/`, 5 virtual memory records, 2 test directories

### Summary
The largest and most complex type package. Provides:
- **`Byte_Array_Pointer`**: Safe abstraction over raw `System.Address` + length, with slicing, heap allocation, type-safe serialization/deserialization via generics, stream I/O, packed representation, and assertion helpers.
- **Physical memory regions** in 32-bit and 64-bit variants: region descriptors, copy/write/CRC/release/operation records.
- **Virtual memory regions**: address-as-index variants for memory-mapped abstractions.
- **`Memory_Manager_Types`**: region validation against managed region lists.

### Strengths
- **`Byte_Array_Pointer` is well-designed**: private type prevents accidental tampering, `Slice` enables safe sub-range access, generic `To_Type`/`Copy_From_Type` provide type-safe serialization without exposing raw pointers.
- **Defensive coding**: `Is_Null` uses negative length sentinel, `Length` clamps to 0, `From_Address` accepts `Integer` for size to handle edge cases.
- **32-bit/64-bit split**: Clean separation via directory structure. Records are structurally identical except for address format (`U32` vs `U64`), enabling platform-appropriate selection at build time.
- **`Memory_Manager_Types.Is_Region_Valid`**: Proper bounds checking — verifies both start AND end of requested region fall within a managed region. Overloaded for `Memory_Region.T` and `Memory_Region_Positive.T`.
- **Test coverage**: Both basic pointer operations and serialization round-trips are tested.

### Issues & Suggestions
| # | Severity | Item |
|---|----------|------|
| 1 | **Medium** | `Create_On_Heap` allocates via `new Byte_Array(...)` and takes the address, but the `Byte_Array_Access` is never stored — only the raw address is kept. This means the heap memory **cannot be freed** through this abstraction. `Destroy` only nulls the pointer fields; it doesn't deallocate. This is a memory leak if used outside of long-lived/permanent allocations. Document this limitation or add `Ada.Unchecked_Deallocation`. |
| 2 | **Medium** | `Copy_To` and `Copy` do not validate that `Self.Length` matches `Bytes'Length` before the assignment. `Copy` has a `pragma Assert` but this is a no-op in production builds. A runtime check or precondition would be safer for a memory-manipulation primitive. |
| 3 | **Medium** | `Is_Region_Valid` computes `Region_End` as `Address + Storage_Offset(Length - 1)`. If `Length` is 0, this underflows (`Storage_Offset(-1)`), producing an address before the region start. The function should check for zero-length regions first. |
| 4 | **Low** | The 32-bit and 64-bit record YAML files are ~95% identical (only `format: U32` vs `U64` and address arithmetic constants differ). Consider a template/generation approach to avoid maintaining two copies that could drift. |
| 5 | **Low** | `memory_region_write` preamble uses `Command_Arg_Buffer_Index_Type'Last - 4 - 2` (32-bit) / `- 8 - 2` (64-bit) with magic numbers. Named constants for address size and length field size would improve readability. |
| 6 | **Low** | `byte_array_pointer-stream.adb`: `Read` declares `Ignore : Stream_Element_Offset` that is unused — compiler warning likely suppressed but should be cleaned up. |
| 7 | **Info** | `register_value` in 64-bit uses `Unsigned_64` for `Address_Mod_Type` but `Unsigned_32` for the register value — this is correct for 32-bit MMIO registers on 64-bit systems, but a comment clarifying the design intent would help. |

---

## Cross-Cutting Observations

### Consistency (Positive)
- All entity types (command, event, fault, data_product) follow the same pattern: dedicated `_types.ads` with strong ID type, `Configuration`-driven buffer sizes, header+payload records with `variable_length`, and packed ID records.
- YAML record definitions are well-structured with consistent field descriptions.

### Consistency (Gaps)
| # | Severity | Item |
|---|----------|------|
| 1 | **Medium** | `command_header` uses `U8` for `Arg_Buffer_Length` while `data_product_header` and `event_header` also use `U8` for their length fields, but `command_arg_buffer_length.record.yaml` uses `U16`. The standalone record disagrees with the header. |
| 2 | **Low** | `event` and `fault` both name their buffer type `Parameter_Buffer_*` while `command` uses `Command_Arg_Buffer_*` and `data_product` uses `Data_Product_Buffer_*`. The naming convention is inconsistent — `event`/`fault` share naming but not the others. Minor but noticeable. |
| 3 | **Low** | `data_product` has a `_types.adb` body (for staleness checking). No other entity type package has a body. This is fine but worth noting — the staleness logic could alternatively live in a utility package. |

### Architecture
The type system is well-suited for an embedded/real-time component framework:
- Strong typing prevents ID misuse across subsystems.
- Variable-length serialization with fixed-max buffers avoids heap allocation in the hot path.
- Big-endian byte ordering ensures wire-format consistency.
- The YAML-driven code generation approach keeps record definitions declarative and auditable.

---

## Summary

| Package | Verdict | Key Action Items |
|---------|---------|-----------------|
| **basic_types** | ✅ Solid | Clean up `To_Tuple_String` ignore parameter |
| **command** | ✅ Good | Resolve `U8` vs `U16` length format mismatch |
| **data_product** | ✅ Good | Consider deduplicating fetch/id records |
| **event** | ✅ Clean | Fix duplicate description string |
| **fault** | ✅ Clean | No action required |
| **interrupt** | ✅ Minimal | No action required |
| **memory** | ⚠️ Needs attention | Address heap leak in `Create_On_Heap`, zero-length guard in `Is_Region_Valid`, bounds checks in `Copy_To` |

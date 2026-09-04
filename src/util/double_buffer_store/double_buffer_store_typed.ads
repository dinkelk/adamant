with Basic_Types;
with Double_Buffer_Store_Types; use Double_Buffer_Store_Types;
with Interfaces; use Interfaces;
with Sys_Time;

-- A double buffer store for a fixed size packed record. The instantiator binds the
-- two copies, supplies the record type, its serialized length, its serialization
-- functions, and a layout version, and then saves and restores the record in one call
-- without touching bytes. See Double_Buffer_Store for the store itself.
--
-- The layout id written to the store combines the layout version (upper 16 bits)
-- with the serialized length (lower 16 bits). Bump the layout version whenever the
-- meaning or order of the record's fields changes in a way that keeps the same size,
-- so that a store written by an older layout can never be restored into the new one.
-- A size change is caught by the length half without a version bump.
--
-- Serialized_Length must equal the length of the byte array returned by
-- To_Byte_Array and accepted by From_Byte_Array. For an Adamant packed record this
-- is its Size_In_Bytes, and the serialization functions are its
-- Serialization.To_Byte_Array and Serialization.From_Byte_Array.
generic
   -- The memory holding the two copies. Each must be at least Store_Length_In_Bytes long:
   Region_A : in out Persistent_Bytes;
   Region_B : in out Persistent_Bytes;
   type T is private;
   Serialized_Length : Positive_Data_Length_Type;
   with function To_Byte_Array (Src : in T) return Basic_Types.Byte_Array;
   with function From_Byte_Array (Src : in Basic_Types.Byte_Array) return T;
   Layout_Version : Unsigned_16;
package Double_Buffer_Store_Typed with SPARK_Mode => On is

   -- The layout id written to and checked against the store:
   Layout_Id : constant Unsigned_32 :=
      Shift_Left (Unsigned_32 (Layout_Version), 16) or Unsigned_32 (Serialized_Length);

   -- The size of one copy of this store, in bytes:
   Store_Length_In_Bytes : constant Store_Length_Type := Store_Length (Serialized_Length);

   -- Save Value into the store. See Double_Buffer_Store.Save.
   procedure Save (Value : in T; Save_Time : in Sys_Time.T; Info : out Copy_Info)
      with Global => (In_Out => (Region_A, Region_B));

   -- Restore Value from the store. See Double_Buffer_Store.Restore. If no copy is
   -- valid, Value is the deserialization of an all zero byte array.
   procedure Restore (Value : out T; Status : out Restore_Status; Info : out Copy_Info)
      with Global => (Input => (Region_A, Region_B));

   -- Status of one copy, for reporting:
   function Is_Valid (Copy : in Copy_Type) return Boolean
      with Global => (Input => (Region_A, Region_B));
   function Save_Counter (Copy : in Copy_Type) return Unsigned_32
      with Global => (Input => (Region_A, Region_B));
   function Save_Time (Copy : in Copy_Type) return Sys_Time.T
      with Global => (Input => (Region_A, Region_B));

end Double_Buffer_Store_Typed;

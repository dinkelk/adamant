-- A typed convenience layer over Double_Buffer_Store for a fixed size packed
-- record. The instantiator supplies the record type, its serialized length, its
-- serialization functions, and a layout version. A component then saves and
-- restores its record in one call without touching bytes.
--
-- The layout id written to the store combines the layout version (upper 16 bits)
-- with the serialized length (lower 16 bits). Bump the layout version whenever the
-- meaning or order of the record's fields changes in a way that keeps the same size,
-- so that a store written by an older layout can never be restored into the new one.
-- A size change is caught by the length half without a version bump.
--
-- Serialized_Length must equal the length of the byte array returned by
-- To_Byte_Array and accepted by From_Byte_Array. For an Adamant packed record this
-- is its Serialization.Serialized_Length, and the serialization functions are its
-- Serialization.To_Byte_Array and Serialization.From_Byte_Array.
generic
   type T is private;
   Serialized_Length : Positive_Data_Length_Type;
   with function To_Byte_Array (Src : in T) return Basic_Types.Byte_Array;
   with function From_Byte_Array (Src : in Basic_Types.Byte_Array) return T;
   Layout_Version : Unsigned_16;
package Double_Buffer_Store.Typed with SPARK_Mode => On is

   -- The layout id written to and checked against the store:
   Layout_Id : constant Unsigned_32 :=
      Shift_Left (Unsigned_32 (Layout_Version), 16) or Unsigned_32 (Serialized_Length);

   -- The size of one copy of the store, in bytes. Each of the two byte arrays given
   -- to Save and Restore must be at least this long.
   Store_Length_In_Bytes : constant Store_Length_Type := Store_Length (Serialized_Length);

   -- True if a byte array is large enough to hold one copy of this store:
   function Fits (Copy : in Basic_Types.Byte_Array) return Boolean is
      (Copy'Length >= Store_Length_In_Bytes);

   -- True if a copy is valid for this layout:
   function Is_Valid (Copy : in Basic_Types.Byte_Array) return Boolean
      with Global => null,
           Pre => Fits (Copy);

   -- Save Value into the store. See Double_Buffer_Store.Save.
   procedure Save (
      Bytes_A : in out Basic_Types.Byte_Array;
      Bytes_B : in out Basic_Types.Byte_Array;
      Value : in T;
      Save_Time : in Sys_Time.T;
      Info : out Copy_Info
   )
      with Global => null,
           Pre => Fits (Bytes_A) and then Fits (Bytes_B);

   -- Restore Value from the store. See Double_Buffer_Store.Restore. If no copy is
   -- valid, Value is the deserialization of an all zero byte array.
   procedure Restore (
      Bytes_A : in Basic_Types.Byte_Array;
      Bytes_B : in Basic_Types.Byte_Array;
      Value : out T;
      Status : out Restore_Status;
      Info : out Copy_Info
   )
      with Global => null,
           Pre => Fits (Bytes_A) and then Fits (Bytes_B);

end Double_Buffer_Store.Typed;

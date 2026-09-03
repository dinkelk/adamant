-- A typed convenience layer over Double_Buffer_Store for a fixed size packed
-- record. The instantiator supplies the record type, its serialized length, and its
-- serialization functions. A component then saves and restores its record in one
-- call without touching bytes.
--
-- Serialized_Length must equal the length of the byte array returned by
-- To_Byte_Array and accepted by From_Byte_Array. For an Adamant packed record this
-- is its Size_In_Bytes, and the serialization functions are its
-- Serialization.To_Byte_Array and Serialization.From_Byte_Array.
generic
   type T is private;
   Serialized_Length : Positive_Data_Length_Type;
   with function To_Byte_Array (Src : in T) return Basic_Types.Byte_Array;
   with function From_Byte_Array (Src : in Basic_Types.Byte_Array) return T;
package Double_Buffer_Store.Typed with SPARK_Mode => On is

   -- The size of one copy of the store, in bytes. Each of the two byte arrays given
   -- to Save and Restore must be at least this long.
   Store_Length_In_Bytes : constant Store_Length_Type := Store_Length (Serialized_Length);

   -- True if a byte array is large enough to hold one copy of this store:
   function Fits (Copy : in Basic_Types.Byte_Array) return Boolean is
      (Copy'Length >= Store_Length_In_Bytes);

   -- True if a copy is valid:
   function Is_Valid (Copy : in Basic_Types.Byte_Array) return Boolean
      with Global => null,
           Pre => Fits (Copy);

   -- Save Value into the store. See Double_Buffer_Store.Save.
   procedure Save (
      Bytes_A : in out Basic_Types.Byte_Array;
      Bytes_B : in out Basic_Types.Byte_Array;
      Value : in T;
      Save_Time : in Sys_Time.T;
      Written : out Copy_Type
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
      Source : out Copy_Type
   )
      with Global => null,
           Pre => Fits (Bytes_A) and then Fits (Bytes_B);

end Double_Buffer_Store.Typed;

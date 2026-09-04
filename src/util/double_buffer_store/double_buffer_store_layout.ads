with Basic_Types;
with Double_Buffer_Store_Types; use Double_Buffer_Store_Types;
with Interfaces; use Interfaces;
with Sys_Time;

-- The encoding, validity and copy selection logic of the double buffer store, over
-- ordinary byte arrays holding the contents of a copy. Double_Buffer_Store reads its
-- copies out of memory into byte arrays, uses this package to decide and to build the
-- new contents, and writes the result back. This package holds no state and touches
-- no memory of its own.
package Double_Buffer_Store_Layout with SPARK_Mode => On is

   -- True if a byte array is large enough to hold one copy of the store for the
   -- given data length:
   function Fits (Copy : in Basic_Types.Byte_Array; Data_Length : in Data_Length_Type) return Boolean is
      (Copy'Length >= Store_Length (Data_Length));

   -- True if Counter is newer than Than. The comparison is wraparound-aware, so it
   -- remains correct after the 32-bit counter rolls over. Equal counters are not newer.
   function Is_Newer (Counter : in Unsigned_32; Than : in Unsigned_32) return Boolean is
      (Counter /= Than and then Counter - Than < 2 ** 31);

   -- A copy is valid if its CRC matches the CRC computed over its contents, its
   -- layout id matches, and its data length matches.
   function Is_Valid (Copy : in Basic_Types.Byte_Array; Layout_Id : in Unsigned_32; Data_Length : in Data_Length_Type) return Boolean
      with Global => null,
           Pre => Fits (Copy, Data_Length);

   -- Read header fields from a copy. These do not check validity.
   function Read_Save_Counter (Copy : in Basic_Types.Byte_Array) return Unsigned_32
      with Global => null,
           Pre => Copy'Length >= Header_Length;
   function Read_Save_Time (Copy : in Basic_Types.Byte_Array) return Sys_Time.T
      with Global => null,
           Pre => Copy'Length >= Header_Length;

   -- Find the valid copy holding the newest save counter. If neither copy is valid,
   -- Valid_Found is False and Newest is meaningless. When both copies are valid and
   -- hold equal counters, which cannot happen through the store's own saves, copy A
   -- is chosen.
   procedure Find_Newest_Valid (
      Bytes_A : in Basic_Types.Byte_Array;
      Bytes_B : in Basic_Types.Byte_Array;
      Layout_Id : in Unsigned_32;
      Data_Length : in Data_Length_Type;
      Valid_Found : out Boolean;
      Newest : out Copy_Type
   )
      with Global => null,
           Pre => Fits (Bytes_A, Data_Length) and then Fits (Bytes_B, Data_Length);

   -- Build the complete contents of a copy holding Data: header fields, data, and the
   -- CRC over everything after itself. Copy must be exactly one store long.
   procedure Encode (
      Copy : out Basic_Types.Byte_Array;
      Data : in Basic_Types.Byte_Array;
      Layout_Id : in Unsigned_32;
      Save_Time : in Sys_Time.T;
      Save_Counter : in Unsigned_32
   )
      with Global => null,
           Pre => Data'Length <= Max_Data_Length and then Copy'Length = Store_Length (Data'Length);

   -- Extract the data held in a copy. Data must be the copy's data length long.
   procedure Decode (Copy : in Basic_Types.Byte_Array; Data : out Basic_Types.Byte_Array)
      with Global => null,
           Pre => Data'Length <= Max_Data_Length and then Fits (Copy, Data'Length);

end Double_Buffer_Store_Layout;

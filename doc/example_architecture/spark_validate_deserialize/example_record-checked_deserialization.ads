with Interfaces;

-- Prototype of validating and deserializing a packed record in one SPARK
-- operation. The generated Validation.Valid overlays the record on the bytes and
-- checks each field with 'Valid, and Serialization.From_Byte_Array then copies
-- the same bytes into a record. Neither is expressible in SPARK, since both
-- reinterpret bytes as a type that has invalid bit patterns.
--
-- Here the bytes are converted, with one unchecked conversion, to a raw twin of
-- the record: the same layout, but every field typed so that every bit pattern
-- is a valid value. Each raw field is then checked and converted to the real
-- field type, and the record is built from the converted fields, so the result
-- is a valid T by construction and the whole operation is proved. The only code
-- outside the proof is a one instruction reinterpretation of a float's bits,
-- called only after its bits have been proved to hold a finite value. This
-- package is written by hand for Example_Record to see what the generated form
-- would look like. Two forms are offered, differing only in how the record is
-- produced once its bytes are known to be valid.
package Example_Record.Checked_Deserialization with SPARK_Mode => On is

   -- The contracts in this package exist for proof with GNATprove only. The
   -- assertion policy below disables them at runtime.
   pragma Assertion_Policy (Pre => Ignore, Post => Ignore);

   use type Interfaces.Unsigned_32;

   -- Validate the bytes and, if every field is a valid value of its type,
   -- deserialize them into Item. On failure Errant_Field is the number of the
   -- first field that failed, counted from 1, and Item is a default value.
   function Valid_And_Deserialize (Bytes : in Serialization.Byte_Array; Item : out T; Errant_Field : out Interfaces.Unsigned_32) return Boolean
      with
         Side_Effects,
         -- On success no field is reported, on failure the reported field exists.
         Post => (if Valid_And_Deserialize'Result then Errant_Field = 0 else Errant_Field in 1 .. Interfaces.Unsigned_32 (Num_Fields));

   -- The same validation, but on success the record is produced by copying the
   -- checked bytes rather than by building it field by field. The copy is a one
   -- line reinterpretation outside the proof, called only once every field has
   -- been proved to hold a value of its type, so the result is a valid record.
   -- This trades a slightly larger trusted line for the code size of the copy.
   function Valid_And_Copy (Bytes : in Serialization.Byte_Array; Item : out T; Errant_Field : out Interfaces.Unsigned_32) return Boolean
      with
         Side_Effects,
         -- On success no field is reported, on failure the reported field exists.
         Post => (if Valid_And_Copy'Result then Errant_Field = 0 else Errant_Field in 1 .. Interfaces.Unsigned_32 (Num_Fields));

end Example_Record.Checked_Deserialization;

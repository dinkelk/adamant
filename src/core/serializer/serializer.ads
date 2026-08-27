-- Standard includes:
with Basic_Types;

-- Generic package which provides conversions from a given type into bytes arrays
-- using overlays.
generic
   type T is private;
-- This package is in SPARK. Serialization copies the bytes of a value through
-- an overlay of the form X'Address, which SPARK permits, so those bodies are
-- proved free of runtime errors. Deserialization produces a value of T from
-- arbitrary bytes, which may not be a valid value of T; SPARK can only admit
-- that with the Potentially_Invalid aspect, which GNATprove 15 does not yet
-- support, so those bodies are not analyzed and SPARK callers should validate
-- the bytes before deserializing them.
package Serializer with SPARK_Mode => On is

   -- The contracts in this package exist for proof with GNATprove only. The
   -- assertion policy below disables them at runtime.
   pragma Assertion_Policy (Pre => Ignore, Post => Ignore);
   -- Note: 'Object_Size is used here because it represents the actual
   -- size of the type when instantiated in memory, not the minimum
   -- size of the type (as the 'Size attribute specifies)
   -- See: https://gcc.gnu.org/onlinedocs/gnat_rm/Value_005fSize-and-Object_005fSize-Clauses.html
   -- The length in bytes of the serialized type.
   Serialized_Length : constant Natural := T'Object_Size / Basic_Types.Byte'Object_Size; -- in bytes
   -- Byte_Array type:
   subtype Byte_Array_Index is Natural range 0 .. (Serialized_Length - 1);
   -- The bounds are written out rather than given by Byte_Array_Index so that SPARK
   -- accepts overlays of this type.
   subtype Byte_Array is Basic_Types.Byte_Array (0 .. Serialized_Length - 1);

   -- Note: All the subprograms below convert from a type to a byte array or a byte
   -- array to a type. They perform similarly to an unchecked conversion between the
   -- two types. In terms of performance, a copy is executed when converting one type
   -- to another. If this is not desired, the user can use an overlay directly instead
   -- in their own code. You are encouraged to use the Byte_Array type, above, when
   -- performing the overlay in order to prevent any size mismatches. Examples of the
   -- proper overlays are shown below:
   --
   -- -- Overlay a type with a Byte_Array
   -- t : T;
   -- Overlaid_Bytes : constant Byte_Array with Import, Convention => Ada, Address => t'Address;
   --
   -- -- Overlay a Byte_Array with a type:
   -- b : Byte_Array -- make sure size is correct using Serialized_Length if necessary
   -- Overlaid_Type : constant T with Import, Convention => Ada, Address => b'Address;
   --
   -- The functions below use this pattern internally, but must perform a copy of the result
   -- to the caller, thus making them inefficient for some specific operations. When in
   -- doubt, use the functions below. Overlays can be easily misused.

   -- Convert type to byte array:
   procedure To_Byte_Array (Dest : out Byte_Array; Src : in T);
   function To_Byte_Array (Src : in T) return Byte_Array;

   -- Convert byte array to type:
   procedure From_Byte_Array (Dest : out T; Src : in Byte_Array);
   function From_Byte_Array (Src : in Byte_Array) return T;

   -- Same as the functions above, but the length of the dest array is not checked.
   -- Warning: Only use this function if you know what you are doing.
   -- This allows you to avoid a Constraint_Error due to a failed length check if the
   -- src Byte_Array is bigger or smaller than the exact size needed for serializing
   -- to the record. If the array is bigger, you should not run into problems, as only
   -- the first bytes of the array will be filled with the type. If the array is smaller,
   -- a Constraint_Error will likely be called, or a segmentation fault may occur.
   -- Use the To_Byte_Array function above whenever possible.
   function To_Byte_Array_Unchecked (Dest : out Basic_Types.Byte_Array; Src : in T) return Natural
      with Side_Effects,
           -- The destination is exactly one serialized value long.
           Pre => Dest'Length = Serialized_Length;
   procedure To_Byte_Array_Unchecked (Dest : out Basic_Types.Byte_Array; Src : in T)
      with
         -- The destination is exactly one serialized value long.
         Pre => Dest'Length = Serialized_Length;
   function To_Byte_Array_Unchecked (Src : in T) return Basic_Types.Byte_Array;

   -- Same as the functions above, but the length of the src array is not checked.
   -- Warning: Only use this function if you know what you are doing.
   -- This allows you to avoid a Constraint_Error due to a failed length check if the
   -- src Byte_Array is bigger or smaller than the exact size needed for deserializing
   -- to the record. If the array is bigger, you should not run into problems, as only
   -- the first bytes will be copied into the type. If the array is smaller, a portion of
   -- the type will not receive updated serialized data from the array. If this is not
   -- your intended behavior, then you might be in trouble. Use the From_Byte_Array
   -- function above whenever possible.
   function From_Byte_Array_Unchecked (Dest : out T; Src : in Basic_Types.Byte_Array) return Natural
      with Side_Effects,
           -- The source holds at least one serialized value.
           Pre => Src'Length >= Serialized_Length;
   procedure From_Byte_Array_Unchecked (Dest : out T; Src : in Basic_Types.Byte_Array)
      with
         -- The source holds at least one serialized value.
         Pre => Src'Length >= Serialized_Length;
   function From_Byte_Array_Unchecked (Src : in Basic_Types.Byte_Array) return T
      with
         -- The source holds at least one serialized value.
         Pre => Src'Length >= Serialized_Length;
end Serializer;

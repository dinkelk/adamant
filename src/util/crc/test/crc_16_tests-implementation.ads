--------------------------------------------------------------------------------
-- Crc_16 Tests Spec
--------------------------------------------------------------------------------

-- This is a unit test suite for the crc 16 algorithm
package Crc_16_Tests.Implementation is
   -- Test data and state:
   type Instance is new Crc_16_Tests.Base_Instance with private;
private
   -- Fixture procedures:
   overriding procedure Set_Up_Test (Self : in out Instance);
   overriding procedure Tear_Down_Test (Self : in out Instance);

   -- This test sends in a bit pattern and validates that the correct CRC is returned.
   overriding procedure Test_Crc (Self : in out Instance);
   -- This test sends in a bit scattered pattern and validates that the correct CRC is returned.
   overriding procedure Test_Crc_Seeded (Self : in out Instance);
   -- This test verifies that CRC of an empty array returns the seed unchanged.
   overriding procedure Test_Crc_Empty (Self : in out Instance);
   -- This test verifies CRC computation on a single-byte input.
   overriding procedure Test_Crc_Single_Byte (Self : in out Instance);
   -- This test verifies CRC computation on an all-zeros input.
   overriding procedure Test_Crc_All_Zeros (Self : in out Instance);
   -- This test verifies CRC computation on an all-0xFF input.
   overriding procedure Test_Crc_All_Ones (Self : in out Instance);
   -- This test verifies the Byte_Array_Pointer overload produces the same result as the array overload.
   overriding procedure Test_Crc_Pointer (Self : in out Instance);

   -- Test data and state:
   type Instance is new Crc_16_Tests.Base_Instance with record
      null;
   end record;
end Crc_16_Tests.Implementation;

--------------------------------------------------------------------------------
-- Crc_16 Tests Body
--------------------------------------------------------------------------------

with AUnit.Assertions; use AUnit.Assertions;
with Crc_16;
with Basic_Types;
with Byte_Array_Pointer;
with String_Util;
with Ada.Text_IO; use Ada.Text_IO;

package body Crc_16_Tests.Implementation is

   -------------------------------------------------------------------------
   -- Fixtures:
   -------------------------------------------------------------------------

   overriding procedure Set_Up_Test (Self : in out Instance) is
   begin
      null;
   end Set_Up_Test;

   overriding procedure Tear_Down_Test (Self : in out Instance) is
   begin
      null;
   end Tear_Down_Test;

   -------------------------------------------------------------------------
   -- Tests:
   -------------------------------------------------------------------------

   overriding procedure Test_Crc (Self : in out Instance) is
      use Crc_16;
      use Basic_Types;
      Ignore : Instance renames Self;
      Bytes : constant Basic_Types.Byte_Array (0 .. 14) := [16#06#, 16#00#, 16#0c#, 16#f0#, 16#00#, 16#04#, 16#00#, 16#55#, 16#88#, 16#73#, 16#c9#, 16#00#, 16#00#, 16#05#, 16#21#];
      Result : constant Crc_16_Type := Compute_Crc_16 (Bytes);
      Expected : constant Crc_16_Type := [0 => 16#75#, 1 => 16#fb#];
   begin
      Put_Line ("Returned CRC: " & String_Util.Bytes_To_String (Result));
      Put_Line ("Expected CRC: " & String_Util.Bytes_To_String (Expected));
      Assert (Result = Expected, "Test CRC failed!");
   end Test_Crc;

   overriding procedure Test_Crc_Seeded (Self : in out Instance) is
      use Crc_16;
      use Basic_Types;
      Ignore : Instance renames Self;
      Bytes : constant Basic_Types.Byte_Array (0 .. 14) := [16#06#, 16#00#, 16#0c#, 16#f0#, 16#00#, 16#04#, 16#00#, 16#55#, 16#88#, 16#73#, 16#c9#, 16#00#, 16#00#, 16#05#, 16#21#];
      Result1 : constant Crc_16_Type := Compute_Crc_16 (Bytes (0 .. 0));
      Result2 : constant Crc_16_Type := Compute_Crc_16 (Bytes (1 .. 1), Result1);
      Result3 : constant Crc_16_Type := Compute_Crc_16 (Bytes (2 .. 6), Result2);
      Result : constant Crc_16_Type := Compute_Crc_16 (Bytes (7 .. 14), Result3);
      Expected : constant Crc_16_Type := [0 => 16#75#, 1 => 16#fb#];
   begin
      Put_Line ("Returned CRC: " & String_Util.Bytes_To_String (Result));
      Put_Line ("Expected CRC: " & String_Util.Bytes_To_String (Expected));
      Assert (Result = Expected, "Test CRC failed!");
   end Test_Crc_Seeded;

   procedure Test_Crc_Empty (Self : in out Instance) is
      use Crc_16;
      use Basic_Types;
      Ignore : Instance renames Self;
      Bytes : constant Basic_Types.Byte_Array (1 .. 0) := [others => 0];
      Result : constant Crc_16_Type := Compute_Crc_16 (Bytes);
      Expected : constant Crc_16_Type := [0 => 16#FF#, 1 => 16#FF#];
   begin
      Put_Line ("Returned CRC (empty): " & String_Util.Bytes_To_String (Result));
      Put_Line ("Expected CRC (empty): " & String_Util.Bytes_To_String (Expected));
      Assert (Result = Expected, "Empty input CRC should equal the default seed!");
   end Test_Crc_Empty;

   procedure Test_Crc_Byte_Array_Pointer (Self : in out Instance) is
      use Crc_16;
      use Basic_Types;
      Ignore : Instance renames Self;
      Bytes : aliased Basic_Types.Byte_Array (0 .. 14) := [16#06#, 16#00#, 16#0c#, 16#f0#, 16#00#, 16#04#, 16#00#, 16#55#, 16#88#, 16#73#, 16#c9#, 16#00#, 16#00#, 16#05#, 16#21#];
      Ptr : constant Byte_Array_Pointer.Instance := Byte_Array_Pointer.From_Address (Bytes'Address, Bytes'Length);
      Result_Array : constant Crc_16_Type := Compute_Crc_16 (Bytes);
      Result_Ptr : constant Crc_16_Type := Compute_Crc_16 (Ptr);
   begin
      Put_Line ("Array CRC:   " & String_Util.Bytes_To_String (Result_Array));
      Put_Line ("Pointer CRC: " & String_Util.Bytes_To_String (Result_Ptr));
      Assert (Result_Ptr = Result_Array, "Byte_Array_Pointer overload must match Byte_Array overload!");
   end Test_Crc_Byte_Array_Pointer;

   procedure Test_Crc_Ccitt_Vector (Self : in out Instance) is
      use Crc_16;
      use Basic_Types;
      Ignore : Instance renames Self;
      -- Standard CCITT test vector: ASCII "123456789"
      Bytes : constant Basic_Types.Byte_Array (0 .. 8) := [16#31#, 16#32#, 16#33#, 16#34#, 16#35#, 16#36#, 16#37#, 16#38#, 16#39#];
      Result : constant Crc_16_Type := Compute_Crc_16 (Bytes);
      Expected : constant Crc_16_Type := [0 => 16#29#, 1 => 16#B1#];
   begin
      Put_Line ("Returned CRC (CCITT): " & String_Util.Bytes_To_String (Result));
      Put_Line ("Expected CRC (CCITT): " & String_Util.Bytes_To_String (Expected));
      Assert (Result = Expected, "CCITT standard test vector failed!");
   end Test_Crc_Ccitt_Vector;

end Crc_16_Tests.Implementation;

with Xor_8; use Xor_8;
with Basic_Types;
with Ada.Text_IO; use Ada.Text_IO;

procedure Test is
   Result : Xor_8_Type;
begin
   -- Test 1: Empty array returns the seed unchanged (default seed 0xFF).
   Result := Compute_Xor_8 (Basic_Types.Byte_Array'(1 .. 0 => 0));
   pragma Assert (Result = 16#FF#, "Empty array with default seed should return 0xFF");
   Put_Line ("PASS: Empty array returns default seed 0xFF");

   -- Test 2: Empty array with explicit seed of 0x00.
   Result := Compute_Xor_8 (Basic_Types.Byte_Array'(1 .. 0 => 0), Seed => 16#00#);
   pragma Assert (Result = 16#00#, "Empty array with seed 0x00 should return 0x00");
   Put_Line ("PASS: Empty array returns explicit seed 0x00");

   -- Test 3: Single byte XOR with default seed.
   Result := Compute_Xor_8 ([16#AB#]);
   pragma Assert (Result = (16#FF# xor 16#AB#), "Single byte XOR failed");
   Put_Line ("PASS: Single byte XOR with default seed");

   -- Test 4: Known pattern with seed 0x00 (identity for XOR).
   Result := Compute_Xor_8 ([16#01#, 16#02#, 16#04#, 16#08#], Seed => 16#00#);
   pragma Assert (Result = 16#0F#, "Known pattern XOR failed, expected 0x0F");
   Put_Line ("PASS: Known pattern [01,02,04,08] with seed 0x00 = 0x0F");

   -- Test 5: Self-check property — XORing the parity byte into the data yields 0x00 (with seed 0x00).
   Result := Compute_Xor_8 ([16#01#, 16#02#, 16#04#, 16#08#, 16#0F#], Seed => 16#00#);
   pragma Assert (Result = 16#00#, "Self-check property failed, expected 0x00");
   Put_Line ("PASS: Self-check property (XOR of data + parity = 0x00)");

   -- Test 6: All 0xFF bytes with seed 0xFF (odd count => 0x00, even count => 0xFF).
   Result := Compute_Xor_8 ([16#FF#, 16#FF#, 16#FF#], Seed => 16#FF#);
   pragma Assert (Result = 16#FF#, "All 0xFF odd+seed failed");
   Put_Line ("PASS: Three 0xFF bytes with seed 0xFF");

   Put_Line ("All Xor_8 tests passed.");
end Test;

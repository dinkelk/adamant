with Xor_8; use Xor_8;
with Basic_Types;

procedure Test is
   Result : Xor_8_Type;
begin
   -- Test 1: Known XOR result for a multi-byte array
   Result := Compute_Xor_8 ([16#01#, 16#02#, 16#03#, 16#04#]);
   -- Expected: 0xFF xor 0x01 xor 0x02 xor 0x03 xor 0x04 = 0xFB
   pragma Assert (Result = 16#FB#, "Multi-byte XOR failed");

   -- Test 2: Empty array returns seed unchanged
   Result := Compute_Xor_8 (Basic_Types.Byte_Array'(1 .. 0 => 0));
   pragma Assert (Result = 16#FF#, "Empty array should return default seed");

   -- Test 3: Empty array with custom seed returns seed unchanged
   Result := Compute_Xor_8 (Basic_Types.Byte_Array'(1 .. 0 => 0), Seed => 16#AB#);
   pragma Assert (Result = 16#AB#, "Empty array should return custom seed");

   -- Test 4: Single byte XOR with default seed (0xFF)
   Result := Compute_Xor_8 ([1 => 16#AA#]);
   -- Expected: 0xFF xor 0xAA = 0x55
   pragma Assert (Result = 16#55#, "Single byte XOR failed");

   -- Test 5: Seed override behavior
   Result := Compute_Xor_8 ([16#01#, 16#02#, 16#03#], Seed => 16#00#);
   -- Expected: 0x00 xor 0x01 xor 0x02 xor 0x03 = 0x00
   pragma Assert (Result = 16#00#, "Seed override XOR failed");

   -- Test 6: Round-trip: XOR of (data ++ xor_result) with seed 0x00 should equal 0x00
   declare
      Data : constant Basic_Types.Byte_Array := [16#DE#, 16#AD#, 16#BE#, 16#EF#];
      Parity : constant Xor_8_Type := Compute_Xor_8 (Data, Seed => 16#00#);
      Data_With_Parity : constant Basic_Types.Byte_Array := Data & [1 => Parity];
   begin
      Result := Compute_Xor_8 (Data_With_Parity, Seed => 16#00#);
      pragma Assert (Result = 16#00#, "Round-trip parity check failed");
   end;
end Test;

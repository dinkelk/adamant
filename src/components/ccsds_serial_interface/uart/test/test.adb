with Diagnostic_Uart;
with Basic_Types;

procedure Test is
   -- Build-verification test: exercises all four API entry points.
   -- True round-trip verification would require a loopback or mocked
   -- Ada.Text_IO, which is not available in this bare-board context.

   -- "Hello, world!" as ASCII byte values:
   Hello : constant Basic_Types.Byte_Array :=
     [Character'Pos ('H'), Character'Pos ('e'), Character'Pos ('l'),
      Character'Pos ('l'), Character'Pos ('o'), Character'Pos (','),
      Character'Pos (' '), Character'Pos ('w'), Character'Pos ('o'),
      Character'Pos ('r'), Character'Pos ('l'), Character'Pos ('d'),
      Character'Pos ('!')];

   Single : Basic_Types.Byte;
   Buf    : Basic_Types.Byte_Array (0 .. 0);
begin

   -- Test array Put
   Diagnostic_Uart.Put (Hello);

   -- Test single-byte Put
   Diagnostic_Uart.Put (Character'Pos ('A'));

   -- Test single-byte Get (blocks waiting for Rx input)
   Single := Diagnostic_Uart.Get;
   -- Echo back what we received to confirm it works
   Diagnostic_Uart.Put (Single);

   -- Test array Get (blocks waiting for Rx input)
   Diagnostic_Uart.Get (Buf);
   -- Echo back
   Diagnostic_Uart.Put (Buf);

end Test;

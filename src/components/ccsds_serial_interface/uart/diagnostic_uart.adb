with Ada.Text_IO;

package body Diagnostic_Uart is

   function Get return Basic_Types.Byte is
      Val : Character;
      -- Overlay val with a byte to perform the type translation in a fast way:
      A_Byte : Basic_Types.Byte with Import, Convention => Ada, Address => Val'Address;
   begin
      Ada.Text_IO.Get (Val);
      return A_Byte;
   end Get;

   procedure Get (Bytes : out Basic_Types.Byte_Array) is
   begin
      for B of Bytes loop
         B := Get;
      end loop;
   end Get;

   procedure Put (B : in Basic_Types.Byte) is
      -- Copy to a local variable first to avoid overlaying an in-mode formal
      -- parameter, which may be passed by copy in a register (Ada RM 13.3(16)).
      Local : constant Basic_Types.Byte := B;
      Val : Character with Import, Convention => Ada, Address => Local'Address;
   begin
      Ada.Text_IO.Put (Val);
   end Put;

   procedure Put (Bytes : in Basic_Types.Byte_Array) is
   begin
      for B of Bytes loop
         Put (B);
      end loop;
   end Put;

end Diagnostic_Uart;

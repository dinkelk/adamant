package body File_Logger is

   procedure Open (Self : in out Instance; File_Directory : in String) is
      pragma Unreferenced (Self, File_Directory);
   begin
      null;
   end Open;

   procedure Log (Self : in Instance; String_To_Write : in String) is
      pragma Unreferenced (Self, String_To_Write);
   begin
      null;
   end Log;

   procedure Close (Self : in out Instance) is
      pragma Unreferenced (Self);
   begin
      null;
   end Close;

end File_Logger;

package File_Logger is

   type Instance is tagged limited private;
   type Instance_Access is access all Instance;
   procedure Open (Self : in out Instance; File_Directory : in String);
   procedure Log (Self : in Instance; String_To_Write : in String);
   procedure Close (Self : in out Instance);

private

   type Instance is tagged limited null record;

end File_Logger;

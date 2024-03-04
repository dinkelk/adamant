package body Component is

   function Get_Queue_Current_Percent_Used (Self : in out Core_Instance) return Basic_Types.Byte is
      pragma Annotate (Codepeer, Intentional, "subp always fails",
         "Intentional - this subp should never be called on a component without a queue.");
      Ignore : Core_Instance renames Self;
   begin
      pragma Assert (False, "This component does not contain a queue because this subprogram was not overridden.");
      return Basic_Types.Byte'Last;
   end Get_Queue_Current_Percent_Used;

   function Get_Queue_Maximum_Percent_Used (Self : in out Core_Instance) return Basic_Types.Byte is
      pragma Annotate (Codepeer, Intentional, "subp always fails",
         "Intentional - this subp should never be called on a component without a queue.");
      Ignore : Core_Instance renames Self;
   begin
      pragma Assert (False, "This component does not contain a queue because this subprogram was not overridden.");
      return Basic_Types.Byte'Last;
   end Get_Queue_Maximum_Percent_Used;

end Component;

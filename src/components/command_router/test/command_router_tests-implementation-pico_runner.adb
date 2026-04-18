package body Command_Router_Tests.Implementation.Pico_Runner is

   Self : Instance;

   procedure Run_One
     (Proc : not null access procedure (Self : in out Instance))
   is
   begin
      Set_Up_Test (Self);
      Proc (Self);
      Tear_Down_Test (Self);
   end Run_One;

   procedure Run_All is
   begin
      Run_One (Test_Nominal_Routing'Access);
      Run_One (Test_Nominal_Registration'Access);
      Run_One (Test_Routing_Errors'Access);
      Run_One (Test_Registration_Errors'Access);
      Run_One (Test_Full_Queue_Errors'Access);
      Run_One (Test_Invalid_Argument_Length'Access);
      Run_One (Test_Invalid_Argument_Value'Access);
      Run_One (Test_Failed_Command'Access);
      Run_One (Test_Synchronous_Command'Access);
      Run_One (Test_Command_Response_Forwarding'Access);
      Run_One (Test_Command_Response_Forwarding_Dropped'Access);
      Run_One (Test_Outgoing_Command_Dropped'Access);
   end Run_All;

end Command_Router_Tests.Implementation.Pico_Runner;

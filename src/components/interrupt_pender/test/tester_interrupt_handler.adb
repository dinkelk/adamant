with Interfaces;

-- An example of a custom interrupt handler for unit testing purposes:
package body Tester_Interrupt_Handler is

   procedure Handler (Data : in out Tick.T) is
      use Interfaces;
   begin
      -- Increment the count:
      Data.Count := @ + 1;
      -- Zero out the time (will be set by the component after wake-up):
      Data.Time := (0, 0);
   end Handler;

end Tester_Interrupt_Handler;

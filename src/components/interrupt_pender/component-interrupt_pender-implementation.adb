--------------------------------------------------------------------------------
-- Interrupt_Pender Component Implementation Body
--------------------------------------------------------------------------------

package body Component.Interrupt_Pender.Implementation is

   ---------------------------------------
   -- Invokee connector primitives:
   ---------------------------------------
   -- The tick wait connection
   overriding function Wait_On_Interrupt_Data_Type_Return (Self : in out Instance) return Interrupt_Data_Type is
      To_Return : Interrupt_Data_Type;
   begin
      -- Wait for the interrupt to release this task:
      Self.The_Signal.Wait (To_Return);

      -- Get the time after wake-up and store it in the interrupt data. Note: this captures
      -- the time when the waiting task resumes, not the instant the interrupt fires,
      -- so it includes scheduling latency.
      if Self.Is_Sys_Time_T_Get_Connected then
         Set_Interrupt_Data_Time (To_Return, Self.Sys_Time_T_Get);
      end if;

      -- Return the data to the caller:
      return To_Return;
   end Wait_On_Interrupt_Data_Type_Return;

end Component.Interrupt_Pender.Implementation;

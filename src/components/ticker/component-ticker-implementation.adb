--------------------------------------------------------------------------------
-- Ticker Component Implementation Body
--------------------------------------------------------------------------------

package body Component.Ticker.Implementation is

   ---------------------------------------
   -- Cycle function:
   ---------------------------------------
   overriding procedure Cycle (Self : in out Instance) is
      use Ada.Real_Time;
      Now : Time;
   begin
      -- Set the next period to the current clock just the first iteration:
      if Self.First then
         Self.First := False;
         Self.Next_Period := Clock;
      end if;

      -- Delay until the next period:
      delay until Self.Next_Period;

      -- Calculate the next wake-up time (before send, to keep timing tight):
      Self.Next_Period := @ + Self.Period;

      -- Detect overrun: if current time already exceeds next period, we are behind.
      Now := Clock;
      if Now >= Self.Next_Period then
         -- TODO: Emit an event/data product for overrun detection once model
         -- supports events. For now, the overrun is detectable via the dropped
         -- counter and downstream timing analysis.
         null;
      end if;

      -- Send the tick and update the count:
      Self.Tick_T_Send ((Time => Self.Sys_Time_T_Get, Count => Self.Count));

      -- Increment count (wraps naturally for Unsigned_32):
      Self.Count := @ + 1;
   end Cycle;

   ---------------------------------------
   -- Drop handler:
   ---------------------------------------
   overriding procedure Tick_T_Send_Dropped (Self : in out Instance; Arg : in Tick.T) is
      pragma Unreferenced (Arg);
   begin
      -- Track dropped ticks. A non-zero value indicates downstream queue saturation.
      -- TODO: Emit a fault or event once the model supports it.
      Self.Dropped_Count := @ + 1;
   end Tick_T_Send_Dropped;

end Component.Ticker.Implementation;

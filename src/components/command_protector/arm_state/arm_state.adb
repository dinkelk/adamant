
package body Arm_State is

   protected body Protected_Arm_State is
      --
      -- Functions that provide read-only access to the private data:
      --
      function Get_State return Command_Protector_Enums.Armed_State.E is
      begin
         return State;
      end Get_State;

      function Get_Timeout return Packed_Arm_Timeout.Arm_Timeout_Type is
      begin
         return Timeout;
      end Get_Timeout;

      --
      -- Procedures requiring full mutual exclusion:
      --
      -- Arm the system and provide a timeout value:
      procedure Arm (New_Timeout : in Packed_Arm_Timeout.Arm_Timeout_Type) is
         use Packed_Arm_Timeout;
      begin
         -- Only arm if timeout is positive; a zero timeout is meaningless
         -- and would create a stuck Armed state that never times out.
         if New_Timeout > Arm_Timeout_Type'First then
            -- Arm the system
            State := Command_Protector_Enums.Armed_State.Armed;
            -- Set the timeout:
            Timeout := New_Timeout;
         end if;
      end Arm;

      -- Unarm the system and cancel the timeout:
      procedure Unarm is
         use Packed_Arm_Timeout;
      begin
         -- Unarm the system
         State := Command_Protector_Enums.Armed_State.Unarmed;
         -- Set the timeout to zero:
         Timeout := 0;
      end Unarm;

      -- Decrement the timeout, and transition to the unarmed state if the
      -- timeout has expired.
      procedure Decrement_Timeout (Timeout_Val : out Packed_Arm_Timeout.Arm_Timeout_Type; New_State : out Command_Protector_Enums.Armed_State.E; Timed_Out : out Boolean) is
         use Packed_Arm_Timeout;
         use Command_Protector_Enums.Armed_State;
      begin
         -- By default we set the out parameter to not timing out:
         Timed_Out := False;

         -- We only need to do timeout logic if we are currently armed.
         case State is
            when Armed =>
               -- If timeout is positive, then decrement it.
               if Timeout > Arm_Timeout_Type'First then
                  -- Decrement:
                  Timeout := @ - 1;

                  -- If timeout is now equal to zero, then we have
                  -- timed out.
                  if Timeout = Arm_Timeout_Type'First then
                     -- We timed out, unarm and set the out parameter:
                     State := Command_Protector_Enums.Armed_State.Unarmed;
                     Timed_Out := True;
                  end if;
               else
                  -- Armed with zero timeout — defensive measure to prevent
                  -- a stuck Armed state. Force transition to Unarmed.
                  State := Command_Protector_Enums.Armed_State.Unarmed;
                  Timed_Out := True;
               end if;

            when Unarmed =>
               null; -- Nothing to do.
         end case;

         -- Set the timeout out parameter:
         Timeout_Val := Timeout;
         New_State := State;
      end Decrement_Timeout;

   end Protected_Arm_State;

end Arm_State;

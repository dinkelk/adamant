--------------------------------------------------------------------------------
-- {{ formatType(model_name) }} {{ formatType(model_type) }} Base Body
--
-- Generated from {{ filename }} on {{ time }}.
--------------------------------------------------------------------------------

-- Includes:
with String_Util;
{% if component and not component.generic %}
with Safe_Deallocator;
{% endif %}

package body {{ name }} is

   ---------------------------------------
   -- Test Logging:
   ---------------------------------------

   procedure Log (Self : in out Base_Instance; String_To_Log : in String) is
   begin
      -- Make sure we have a log file to log to.
      Self.Logger.Log (String_Util.Trim_Both (String_To_Log));
   end Log;

   -- Initialize the logging for the log file ensuring the correct directory is available
   procedure Init_Logging (Self : in out Base_Instance; File_Name : in String) is
   begin
      -- On embedded targets the logger may be a no-op; avoid host filesystem dependencies here.
      Self.Logger.Open ("");
      Self.Log ("    Beginning log for " & File_Name);
   end Init_Logging;

   procedure End_Logging (Self : in out Base_Instance; File_Name : in String) is
   begin
      -- Close the log that was used during this test.
      Self.Log ("    Ending log for " & File_Name);
      Self.Logger.Close;
   end End_Logging;

   ------------------------------------------------------------
   -- Fixtures:
   ------------------------------------------------------------

   procedure Set_Up (Self : in out Base_Instance) is
      Test_String : constant String := To_String (Test_Name_List (Self.Test_Name_Index));
   begin
      -- Use the helper function to get the name of the test to setup
      Self.Init_Logging (Test_String);
      -- Log that we are starting to setup
      Self.Log ("    Starting Set_Up for test " & Test_String);
{% if component and not component.generic %}
      -- Dynamically allocate the component tester:
      Self.Tester := new Component.{{ component.name }}.Implementation.Tester.Instance;
      -- Link the log access type to the logger in the reciprocal
      Self.Tester.Set_Logger (Self.Logger'Unchecked_Access);
{% endif %}
      -- Call up to the implementation setup
      Base_Instance'Class (Self).Set_Up_Test;
      Self.Log ("    Finishing Set_Up for test " & Test_String);
   end Set_Up;

   overriding procedure Tear_Down (Self : in out Base_Instance) is
{% if component and not component.generic %}
      procedure Free_Tester is new Safe_Deallocator.Deallocate_If_Testing (
         Object => Component.{{ component.name }}.Implementation.Tester.Instance,
         Name => Component.{{ component.name }}.Implementation.Tester.Instance_Access
      );
{% endif %}
      Closing_Test : constant String := To_String (Test_Name_List (Self.Test_Name_Index));
   begin
      -- Log the tear down
      Self.Log ("    Starting Tear_Down for test " & Closing_Test);
      -- Call up to the implementation for any tear down
      Base_Instance'Class (Self).Tear_Down_Test;
      -- End the logging for the current test
      Self.Log ("    Finishing Tear_Down for test " & Closing_Test);
      Self.End_Logging (Closing_Test);
      -- Increment counter for the next test name in the list and pass the log to close back up to the tear down (or component unit test)
      Self.Test_Name_Index := @ + 1;
   end Tear_Down;
end {{ name }};

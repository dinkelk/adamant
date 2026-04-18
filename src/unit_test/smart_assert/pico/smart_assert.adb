with Ada.Assertions;
with String_Util;
with Ada.Text_IO;

package body Smart_Assert is

   procedure Assert (Condition : in Boolean; Message : in String := ""; Filename : in String := Sinfo.File; Line : in Natural := Sinfo.Line) is
      procedure Raise_Assertion_Failure is
         pragma Annotate (GNATSAS, Intentional, "subp always fails", "intentional assertion failure in test framework");
      begin
         if Message'Length > 0 then
            Ada.Text_IO.Put_Line (Message);
         end if;
         raise Ada.Assertions.Assertion_Error with " at " & Filename & ":" & String_Util.Trim_Both (Natural'Image (Line));
         pragma Annotate (GNATSAS, Intentional, "raise exception", "intentional assertion failure in test framework");
      end Raise_Assertion_Failure;
   begin
      if not Condition then
         Raise_Assertion_Failure;
      end if;
   end Assert;

   procedure Call_Assert (Condition : in Boolean; T1 : in T; T2 : in T; Comparison : in String := "compared to"; Message : in String := ""; Filename : in String := Sinfo.File; Line : in Natural := Sinfo.Line) is
      Assert_Message : constant String := "Assertion: " & ASCII.LF & Image (T1) & ASCII.LF & Comparison & ASCII.LF & Image (T2) & ASCII.LF & "failed.";
   begin
      if Message = "" then
         Assert (Condition, Assert_Message, Filename, Line);
      else
         Assert (Condition, Assert_Message & ASCII.LF & "Message: " & Message, Filename, Line);
      end if;
   exception
      when Constraint_Error =>
         declare
            Safe_Assert_Message : constant String := "Assertion: " & ASCII.LF & "Item 1" & ASCII.LF & Comparison & ASCII.LF & "Item 2" & ASCII.LF & "failed due to either Item 1 or Item 2 issuing a Constraint_Error.";
         begin
            if Message = "" then
               Assert (False, Safe_Assert_Message, Filename, Line);
            else
               Assert (False, Safe_Assert_Message & ASCII.LF & "Message: " & Message, Filename, Line);
            end if;
         end;
         raise Constraint_Error;
   end Call_Assert;

   package body Basic is
      procedure Basic_Assert is new Call_Assert (T, Image_Basic);
      procedure Eq (T1 : in T; T2 : in T; Message : in String := ""; Filename : in String := Sinfo.File; Line : in Natural := Sinfo.Line) is
      begin
         Basic_Assert (T1 = T2, T1, T2, "=", Message, Filename, Line);
      end Eq;
      procedure Neq (T1 : in T; T2 : in T; Message : in String := ""; Filename : in String := Sinfo.File; Line : in Natural := Sinfo.Line) is
      begin
         Basic_Assert (T1 /= T2, T1, T2, "/=", Message, Filename, Line);
      end Neq;
   end Basic;

   package body Discrete is
      procedure Discrete_Assert is new Call_Assert (T, Image_Discrete);
      procedure Eq (T1 : in T; T2 : in T; Message : in String := ""; Filename : in String := Sinfo.File; Line : in Natural := Sinfo.Line) is
      begin
         Basic_Assert_P.Eq (T1, T2, Message, Filename, Line);
      end Eq;
      procedure Neq (T1 : in T; T2 : in T; Message : in String := ""; Filename : in String := Sinfo.File; Line : in Natural := Sinfo.Line) is
      begin
         Basic_Assert_P.Neq (T1, T2, Message, Filename, Line);
      end Neq;
      procedure Gt (T1 : in T; T2 : in T; Message : in String := ""; Filename : in String := Sinfo.File; Line : in Natural := Sinfo.Line) is
      begin
         Discrete_Assert (T1 > T2, T1, T2, ">", Message, Filename, Line);
      end Gt;
      procedure Ge (T1 : in T; T2 : in T; Message : in String := ""; Filename : in String := Sinfo.File; Line : in Natural := Sinfo.Line) is
      begin
         Discrete_Assert (T1 >= T2, T1, T2, ">=", Message, Filename, Line);
      end Ge;
      procedure Lt (T1 : in T; T2 : in T; Message : in String := ""; Filename : in String := Sinfo.File; Line : in Natural := Sinfo.Line) is
      begin
         Discrete_Assert (T1 < T2, T1, T2, "<", Message, Filename, Line);
      end Lt;
      procedure Le (T1 : in T; T2 : in T; Message : in String := ""; Filename : in String := Sinfo.File; Line : in Natural := Sinfo.Line) is
      begin
         Discrete_Assert (T1 <= T2, T1, T2, "<=", Message, Filename, Line);
      end Le;
   end Discrete;

   package body Float is
      procedure Float_Assert is new Call_Assert (T, Image_Float);
      procedure Eq (T1 : in T; T2 : in T; Epsilon : in T := T'Small; Message : in String := ""; Filename : in String := Sinfo.File; Line : in Natural := Sinfo.Line) is
         Condition : constant Boolean := ((T1 + Epsilon) >= T2) and then ((T1 - Epsilon) <= T2);
      begin
         Float_Assert (Condition, T1, T2, "= (with Epsilon => " & Image_Float (Epsilon) & ")", Message, Filename, Line);
      end Eq;
      procedure Neq (T1 : in T; T2 : in T; Epsilon : in T := T'Small; Message : in String := ""; Filename : in String := Sinfo.File; Line : in Natural := Sinfo.Line) is
         Condition : constant Boolean := ((T1 + Epsilon) < T2) or else ((T1 - Epsilon) > T2);
      begin
         Float_Assert (Condition, T1, T2, "/= (with Epsilon => " & Image_Float (Epsilon) & ")", Message, Filename, Line);
      end Neq;
      procedure Gt (T1 : in T; T2 : in T; Message : in String := ""; Filename : in String := Sinfo.File; Line : in Natural := Sinfo.Line) is
      begin
         Float_Assert (T1 > T2, T1, T2, ">", Message, Filename, Line);
      end Gt;
      procedure Ge (T1 : in T; T2 : in T; Message : in String := ""; Filename : in String := Sinfo.File; Line : in Natural := Sinfo.Line) is
      begin
         Float_Assert (T1 >= T2, T1, T2, ">=", Message, Filename, Line);
      end Ge;
      procedure Lt (T1 : in T; T2 : in T; Message : in String := ""; Filename : in String := Sinfo.File; Line : in Natural := Sinfo.Line) is
      begin
         Float_Assert (T1 < T2, T1, T2, "<", Message, Filename, Line);
      end Lt;
      procedure Le (T1 : in T; T2 : in T; Message : in String := ""; Filename : in String := Sinfo.File; Line : in Natural := Sinfo.Line) is
      begin
         Float_Assert (T1 <= T2, T1, T2, "<=", Message, Filename, Line);
      end Le;
   end Float;

end Smart_Assert;

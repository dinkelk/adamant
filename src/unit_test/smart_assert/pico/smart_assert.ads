with GNAT.Source_Info;

package Smart_Assert is
   package Sinfo renames GNAT.Source_Info;

   procedure Assert (Condition : in Boolean; Message : in String := ""; Filename : in String := Sinfo.File; Line : in Natural := Sinfo.Line);

   generic
      type T (<>) is private;
      with function Image_Basic (Item : in T) return String;
   package Basic is
      procedure Eq (T1 : in T; T2 : in T; Message : in String := ""; Filename : in String := Sinfo.File; Line : in Natural := Sinfo.Line);
      procedure Neq (T1 : in T; T2 : in T; Message : in String := ""; Filename : in String := Sinfo.File; Line : in Natural := Sinfo.Line);
   end Basic;

   generic
      type T is (<>);
      with function Image_Discrete (Item : in T) return String;
   package Discrete is
      package Basic_Assert_P is new Basic (T, Image_Discrete);
      procedure Eq (T1 : in T; T2 : in T; Message : in String := ""; Filename : in String := Sinfo.File; Line : in Natural := Sinfo.Line);
      procedure Neq (T1 : in T; T2 : in T; Message : in String := ""; Filename : in String := Sinfo.File; Line : in Natural := Sinfo.Line);
      procedure Gt (T1 : in T; T2 : in T; Message : in String := ""; Filename : in String := Sinfo.File; Line : in Natural := Sinfo.Line);
      procedure Ge (T1 : in T; T2 : in T; Message : in String := ""; Filename : in String := Sinfo.File; Line : in Natural := Sinfo.Line);
      procedure Lt (T1 : in T; T2 : in T; Message : in String := ""; Filename : in String := Sinfo.File; Line : in Natural := Sinfo.Line);
      procedure Le (T1 : in T; T2 : in T; Message : in String := ""; Filename : in String := Sinfo.File; Line : in Natural := Sinfo.Line);
   end Discrete;

   generic
      type T is digits <>;
      with function Image_Float (Item : in T) return String;
   package Float is
      package Basic_Assert_P is new Basic (T, Image_Float);
      procedure Eq (T1 : in T; T2 : in T; Epsilon : in T := T'Small; Message : in String := ""; Filename : in String := Sinfo.File; Line : in Natural := Sinfo.Line);
      procedure Neq (T1 : in T; T2 : in T; Epsilon : in T := T'Small; Message : in String := ""; Filename : in String := Sinfo.File; Line : in Natural := Sinfo.Line);
      procedure Gt (T1 : in T; T2 : in T; Message : in String := ""; Filename : in String := Sinfo.File; Line : in Natural := Sinfo.Line);
      procedure Ge (T1 : in T; T2 : in T; Message : in String := ""; Filename : in String := Sinfo.File; Line : in Natural := Sinfo.Line);
      procedure Lt (T1 : in T; T2 : in T; Message : in String := ""; Filename : in String := Sinfo.File; Line : in Natural := Sinfo.Line);
      procedure Le (T1 : in T; T2 : in T; Message : in String := ""; Filename : in String := Sinfo.File; Line : in Natural := Sinfo.Line);
   end Float;

   generic
      type T (<>) is private;
      with function Image (Item : in T) return String;
   procedure Call_Assert (Condition : in Boolean; T1 : in T; T2 : in T; Comparison : in String := "compared to"; Message : in String := ""; Filename : in String := Sinfo.File; Line : in Natural := Sinfo.Line);

end Smart_Assert;

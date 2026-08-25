-- See the note in the parent package specification. Everything here is for
-- proof only and is disabled at runtime. A ghost package cannot contain the
-- policy pragma, so it is given as a configuration pragma for this unit:
pragma Assertion_Policy
   (Pre => Ignore,
    Pre'Class => Ignore,
    Post => Ignore,
    Post'Class => Ignore,
    Contract_Cases => Ignore,
    Ghost => Ignore,
    Loop_Invariant => Ignore,
    Loop_Variant => Ignore,
    Assert_And_Cut => Ignore,
    Assume => Ignore,
    Subprogram_Variant => Ignore);

package body Binary_Tree.Lemmas with SPARK_Mode => On is

   ----------------------------------
   -- Ordering axioms:
   ----------------------------------

   procedure Lemma_Asymmetric (Left, Right : in Element_Type) is
   begin
      pragma Assume (not (Left < Right and then Right < Left), "The formal '<' is a strict weak ordering.");
   end Lemma_Asymmetric;

   procedure Lemma_Not_Less_Transitive (A, B, C : in Element_Type) is
   begin
      pragma Assume ((if not (B < A) and then not (C < B) then not (C < A)), "The formal '<' is a strict weak ordering.");
   end Lemma_Not_Less_Transitive;

   procedure Lemma_Greater_Is_Converse (Left, Right : in Element_Type) is
   begin
      pragma Assume ((Left > Right) = (Right < Left), "The formal '>' is the converse of the formal '<'.");
   end Lemma_Greater_Is_Converse;

   ----------------------------------
   -- Derived ordering lemmas:
   ----------------------------------

   procedure Lemma_Less_Not_Less_Transitive (X, Y, Z : in Element_Type) is
   begin
      -- Were Z <= X, then Y <= Z <= X would give Y <= X, contradicting X < Y.
      if not (X < Z) then
         Lemma_Not_Less_Transitive (Y, Z, X);
      end if;
   end Lemma_Less_Not_Less_Transitive;

   procedure Lemma_Not_Less_Less_Transitive (X, Y, Z : in Element_Type) is
   begin
      -- Were Z <= X, then Z <= X <= Y would give Z <= Y, contradicting Y < Z.
      if not (X < Z) then
         Lemma_Not_Less_Transitive (Z, X, Y);
      end if;
   end Lemma_Not_Less_Less_Transitive;

   procedure Lemma_Prefix_Not_Less (Sequence : in Element_Sequence; K : in Positive; Element : in Element_Type) is
   begin
      for I in Sequence'First .. K loop
         -- The element is not less than anything already visited.
         pragma Loop_Invariant (for all J in Sequence'First .. I - 1 => not (Element < Sequence (J)));
         if I < K then
            Lemma_Not_Less_Transitive (Sequence (I), Sequence (K), Element);
         end if;
      end loop;
   end Lemma_Prefix_Not_Less;

   procedure Lemma_Suffix_Not_Less (Sequence : in Element_Sequence; K : in Positive; Element : in Element_Type) is
   begin
      for I in K .. Sequence'Last loop
         -- Nothing already visited is less than the element.
         pragma Loop_Invariant (for all J in K .. I - 1 => not (Sequence (J) < Element));
         if I > K then
            Lemma_Not_Less_Transitive (Element, Sequence (K), Sequence (I));
         end if;
      end loop;
   end Lemma_Suffix_Not_Less;

   procedure Lemma_Prefix_Less (Sequence : in Element_Sequence; K : in Positive; Element : in Element_Type) is
   begin
      for I in Sequence'First .. K loop
         -- Everything already visited is less than the element.
         pragma Loop_Invariant (for all J in Sequence'First .. I - 1 => Sequence (J) < Element);
         if I < K then
            Lemma_Not_Less_Less_Transitive (Sequence (I), Sequence (K), Element);
         end if;
      end loop;
   end Lemma_Prefix_Less;

   procedure Lemma_Suffix_Greater (Sequence : in Element_Sequence; K : in Positive; Element : in Element_Type) is
   begin
      for I in K .. Sequence'Last loop
         -- The element is less than everything already visited.
         pragma Loop_Invariant (for all J in K .. I - 1 => Element < Sequence (J));
         if I > K then
            Lemma_Less_Not_Less_Transitive (Element, Sequence (K), Sequence (I));
         end if;
      end loop;
   end Lemma_Suffix_Greater;

   procedure Lemma_Insert_Suffix (Sequence : in Element_Sequence; K : in Positive; Element : in Element_Type) is
   begin
      if K <= Sequence'Last then
         Lemma_Asymmetric (Element, Sequence (K));
         Lemma_Suffix_Not_Less (Sequence, K, Element);
      end if;
   end Lemma_Insert_Suffix;

   procedure Lemma_Replace_Neighbors (Sequence : in Element_Sequence; K : in Positive; Element : in Element_Type) is
   begin
      if K > Sequence'First then
         Lemma_Prefix_Not_Less (Sequence, K - 1, Element);
      end if;
      if K < Sequence'Last then
         Lemma_Suffix_Not_Less (Sequence, K + 1, Element);
      end if;
   end Lemma_Replace_Neighbors;

end Binary_Tree.Lemmas;

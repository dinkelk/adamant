--
-- Proof scaffolding for Binary_Tree. Nothing in this package runs: it is
-- ghost code that exists only so that GNATprove can prove the sortedness
-- and search correctness contracts of the parent package. It is instantiated
-- once, inside the parent package body.
--
-- The package states the ordering assumptions about the parent's generic
-- formal operators as three axioms (see the parent specification for the
-- reasoning), and derives from them every ordering fact the parent's proof
-- needs: the mixed transitivity forms, and the quantified statements about
-- a sorted sequence that the binary search, the insertion and the
-- replacement proofs consume.
--

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

private generic
package Binary_Tree.Lemmas with SPARK_Mode => On, Ghost is

   ----------------------------------
   -- Ordering axioms:
   ----------------------------------
   -- Nothing is known about the generic formal operators, so these three
   -- properties are assumed in the package body. Every instantiation whose
   -- "<" is a strict weak ordering and whose ">" is its converse satisfies
   -- them.

   -- "<" is asymmetric:
   procedure Lemma_Asymmetric (Left, Right : in Element_Type)
      with
         Global => null,
         -- Two elements are never each less than the other.
         Post => not (Left < Right and then Right < Left);

   -- "not <" is transitive:
   procedure Lemma_Not_Less_Transitive (A, B, C : in Element_Type)
      with
         Global => null,
         -- A is not more than B, and B is not more than C.
         Pre => not (B < A) and then not (C < B),
         -- Then A is not more than C.
         Post => not (C < A);

   -- ">" is the converse of "<":
   procedure Lemma_Greater_Is_Converse (Left, Right : in Element_Type)
      with
         Global => null,
         -- Greater than in one direction is exactly less than in the other.
         Post => (Left > Right) = (Right < Left);

   ----------------------------------
   -- Derived ordering lemmas:
   ----------------------------------
   -- Everything below is proved from the axioms above.

   -- X < Y and Y <= Z implies X < Z:
   procedure Lemma_Less_Not_Less_Transitive (X, Y, Z : in Element_Type)
      with
         Global => null,
         -- X is less than Y, and Y is not more than Z.
         Pre => X < Y and then not (Z < Y),
         -- Then X is less than Z.
         Post => X < Z;

   -- X <= Y and Y < Z implies X < Z:
   procedure Lemma_Not_Less_Less_Transitive (X, Y, Z : in Element_Type)
      with
         Global => null,
         -- X is not more than Y, and Y is less than Z.
         Pre => not (Y < X) and then Y < Z,
         -- Then X is less than Z.
         Post => X < Z;

   -- In a sorted sequence, an element that is not less than the element at
   -- index K is not less than any element at or before K:
   procedure Lemma_Prefix_Not_Less (Sequence : in Element_Sequence; K : in Positive; Element : in Element_Type)
      with
         Global => null,
         -- The sequence is sorted, K is in it, and the element is not less than the one at K.
         Pre => Is_Sorted (Sequence) and then K in Sequence'Range and then not (Element < Sequence (K)),
         -- The element is not less than anything at or before K.
         Post => (for all I in Sequence'First .. K => not (Element < Sequence (I)));

   -- In a sorted sequence, an element that is not greater than the element at
   -- index K is not greater than any element at or after K:
   procedure Lemma_Suffix_Not_Less (Sequence : in Element_Sequence; K : in Positive; Element : in Element_Type)
      with
         Global => null,
         -- The sequence is sorted, K is in it, and the one at K is not less than the element.
         Pre => Is_Sorted (Sequence) and then K in Sequence'Range and then not (Sequence (K) < Element),
         -- Nothing at or after K is less than the element.
         Post => (for all I in K .. Sequence'Last => not (Sequence (I) < Element));

   -- In a sorted sequence, an element greater than the element at index K is
   -- greater than every element at or before K:
   procedure Lemma_Prefix_Less (Sequence : in Element_Sequence; K : in Positive; Element : in Element_Type)
      with
         Global => null,
         -- The sequence is sorted, K is in it, and the one at K is less than the element.
         Pre => Is_Sorted (Sequence) and then K in Sequence'Range and then Sequence (K) < Element,
         -- Everything at or before K is less than the element.
         Post => (for all I in Sequence'First .. K => Sequence (I) < Element);

   -- In a sorted sequence, an element less than the element at index K is
   -- less than every element at or after K:
   procedure Lemma_Suffix_Greater (Sequence : in Element_Sequence; K : in Positive; Element : in Element_Type)
      with
         Global => null,
         -- The sequence is sorted, K is in it, and the element is less than the one at K.
         Pre => Is_Sorted (Sequence) and then K in Sequence'Range and then Element < Sequence (K),
         -- The element is less than everything at or after K.
         Post => (for all I in K .. Sequence'Last => Element < Sequence (I));

   -- Inserting an element at index K of a sorted sequence keeps it sorted
   -- when the element is not less than anything before K and less than the
   -- element at K, if any. This lemma provides the facts about the elements
   -- from K on. Index K may be one past the end of the sequence:
   procedure Lemma_Insert_Suffix (Sequence : in Element_Sequence; K : in Positive; Element : in Element_Type)
      with
         Global => null,
         -- The sequence is sorted, K is in it or one past its end, and the element is less than the one at K if there is one.
         Pre => Is_Sorted (Sequence)
            and then Sequence'Last < Positive'Last
            and then K in Sequence'First .. Sequence'Last + 1
            and then (if K <= Sequence'Last then Element < Sequence (K)),
         -- Nothing at or after K is less than the element.
         Post => (for all I in K .. Sequence'Last => not (Sequence (I) < Element));

   -- Replacing the element at index K of a sorted sequence keeps it sorted
   -- when the new element is not less than its predecessor nor greater than
   -- its successor. This lemma provides the facts about all other elements:
   procedure Lemma_Replace_Neighbors (Sequence : in Element_Sequence; K : in Positive; Element : in Element_Type)
      with
         Global => null,
         -- The sequence is sorted, K is in it, and the element is not less than its predecessor nor greater than its successor.
         Pre => Is_Sorted (Sequence)
            and then Sequence'Last < Positive'Last
            and then K in Sequence'Range
            and then (K = Sequence'First or else not (Element < Sequence (K - 1)))
            and then (K = Sequence'Last or else not (Sequence (K + 1) < Element)),
         -- The element is not less than anything before K, and nothing after K is less than it.
         Post => (for all I in Sequence'First .. K - 1 => not (Element < Sequence (I)))
            and then (for all I in K + 1 .. Sequence'Last => not (Sequence (I) < Element));

end Binary_Tree.Lemmas;

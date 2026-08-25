with Safe_Deallocator;

package body Binary_Tree with SPARK_Mode => On is

   -- See the note in the package specification. All contracts and ghost code
   -- are for proof only and are disabled at runtime:
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

   ----------------------------------
   -- Ordering axioms:
   ----------------------------------
   -- Nothing is known about the generic formal operators, so the properties
   -- described at the top of the specification are assumed here. See the
   -- specification for the properties and the reasoning behind them.

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
   -- Everything below is proved from the axioms above.

   -- X < Y and Y <= Z implies X < Z:
   procedure Lemma_Less_Not_Less_Transitive (X, Y, Z : in Element_Type)
      with Ghost,
           Global => null,
           Pre => X < Y and then not (Z < Y),
           Post => X < Z;

   procedure Lemma_Less_Not_Less_Transitive (X, Y, Z : in Element_Type) is
   begin
      -- Were Z <= X, then Y <= Z <= X would give Y <= X, contradicting X < Y.
      if not (X < Z) then
         Lemma_Not_Less_Transitive (Y, Z, X);
      end if;
   end Lemma_Less_Not_Less_Transitive;

   -- X <= Y and Y < Z implies X < Z:
   procedure Lemma_Not_Less_Less_Transitive (X, Y, Z : in Element_Type)
      with Ghost,
           Global => null,
           Pre => not (Y < X) and then Y < Z,
           Post => X < Z;

   procedure Lemma_Not_Less_Less_Transitive (X, Y, Z : in Element_Type) is
   begin
      -- Were Z <= X, then Z <= X <= Y would give Z <= Y, contradicting Y < Z.
      if not (X < Z) then
         Lemma_Not_Less_Transitive (Z, X, Y);
      end if;
   end Lemma_Not_Less_Less_Transitive;

   -- In a sorted sequence, an element that is not less than the element at
   -- index K is not less than any element at or before K:
   procedure Lemma_Prefix_Not_Less (Sequence : in Element_Sequence; K : in Positive; Element : in Element_Type)
      with Ghost,
           Global => null,
           Pre => Is_Sorted (Sequence) and then K in Sequence'Range and then not (Element < Sequence (K)),
           Post => (for all I in Sequence'First .. K => not (Element < Sequence (I)));

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

   -- In a sorted sequence, an element that is not greater than the element at
   -- index K is not greater than any element at or after K:
   procedure Lemma_Suffix_Not_Less (Sequence : in Element_Sequence; K : in Positive; Element : in Element_Type)
      with Ghost,
           Global => null,
           Pre => Is_Sorted (Sequence) and then K in Sequence'Range and then not (Sequence (K) < Element),
           Post => (for all I in K .. Sequence'Last => not (Sequence (I) < Element));

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

   -- In a sorted sequence, an element greater than the element at index K is
   -- greater than every element at or before K:
   procedure Lemma_Prefix_Less (Sequence : in Element_Sequence; K : in Positive; Element : in Element_Type)
      with Ghost,
           Global => null,
           Pre => Is_Sorted (Sequence) and then K in Sequence'Range and then Sequence (K) < Element,
           Post => (for all I in Sequence'First .. K => Sequence (I) < Element);

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

   -- In a sorted sequence, an element less than the element at index K is
   -- less than every element at or after K:
   procedure Lemma_Suffix_Greater (Sequence : in Element_Sequence; K : in Positive; Element : in Element_Type)
      with Ghost,
           Global => null,
           Pre => Is_Sorted (Sequence) and then K in Sequence'Range and then Element < Sequence (K),
           Post => (for all I in K .. Sequence'Last => Element < Sequence (I));

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

   -- Inserting an element at index K of a sorted sequence keeps it sorted
   -- when the element is not less than anything before K and less than the
   -- element at K, if any. This lemma provides the facts about the elements
   -- from K on. Index K may be one past the end of the sequence:
   procedure Lemma_Insert_Suffix (Sequence : in Element_Sequence; K : in Positive; Element : in Element_Type)
      with Ghost,
           Global => null,
           Pre => Is_Sorted (Sequence)
              and then Sequence'Last < Positive'Last
              and then K in Sequence'First .. Sequence'Last + 1
              and then (if K <= Sequence'Last then Element < Sequence (K)),
           Post => (for all I in K .. Sequence'Last => not (Sequence (I) < Element));

   procedure Lemma_Insert_Suffix (Sequence : in Element_Sequence; K : in Positive; Element : in Element_Type) is
   begin
      if K <= Sequence'Last then
         Lemma_Asymmetric (Element, Sequence (K));
         Lemma_Suffix_Not_Less (Sequence, K, Element);
      end if;
   end Lemma_Insert_Suffix;

   -- Replacing the element at index K of a sorted sequence keeps it sorted
   -- when the new element is not less than its predecessor nor greater than
   -- its successor. This lemma provides the facts about all other elements:
   procedure Lemma_Replace_Neighbors (Sequence : in Element_Sequence; K : in Positive; Element : in Element_Type)
      with Ghost,
           Global => null,
           Pre => Is_Sorted (Sequence)
              and then Sequence'Last < Positive'Last
              and then K in Sequence'Range
              and then (K = Sequence'First or else not (Element < Sequence (K - 1)))
              and then (K = Sequence'Last or else not (Sequence (K + 1) < Element)),
           Post => (for all I in Sequence'First .. K - 1 => not (Element < Sequence (I)))
              and then (for all I in K + 1 .. Sequence'Last => not (Sequence (I) < Element));

   procedure Lemma_Replace_Neighbors (Sequence : in Element_Sequence; K : in Positive; Element : in Element_Type) is
   begin
      if K > Sequence'First then
         Lemma_Prefix_Not_Less (Sequence, K - 1, Element);
      end if;
      if K < Sequence'Last then
         Lemma_Suffix_Not_Less (Sequence, K + 1, Element);
      end if;
   end Lemma_Replace_Neighbors;

   ----------------------------------
   -- Public sub programs:
   ----------------------------------

   -- The body is not analyzed by SPARK since it performs the heap allocation
   -- that owns the element storage for the rest of the tree's life. The
   -- postcondition holds because the precondition provides an empty tree,
   -- which is trivially sorted, and the allocation below is indexed from 1
   -- with the requested positive size.
   procedure Init (Self : in out Instance; Maximum_Size : in Positive) with SPARK_Mode => Off is
   begin
      Self.Tree := new Element_Array (Positive'First .. Positive'First + Maximum_Size - 1);
   end Init;

   -- The body is not analyzed by SPARK since conditional deallocation is
   -- outside the SPARK ownership model. The postcondition holds because
   -- Clear sets the size to zero below.
   procedure Destroy (Self : in out Instance) with SPARK_Mode => Off is
      procedure Free_If_Testing is new Safe_Deallocator.Deallocate_If_Testing (Object => Element_Array, Name => Element_Array_Access);
   begin
      Free_If_Testing (Self.Tree);
      Self.Clear;
   end Destroy;

   -- Add element to tree. This is done in O(n) time where n is the current size of the tree.
   function Add (Self : in out Instance; Element : in Element_Type) return Boolean is
      Old_Model : constant Element_Sequence := Model (Self) with Ghost;
   begin
      -- Make sure tree is not full:
      if Self.Size >= Self.Tree'Last then
         return False;
      end if;

      declare
         Insert_Index : Positive := Self.Size + 1;
         This_Element : Element_Type := Element;
         Next_Element : Element_Type;
      begin
         -- Search linearly for appropriate place to put element:
         for Index in 1 .. Self.Size loop
            -- The element is not less than anything before the current index.
            pragma Loop_Invariant (for all I in 1 .. Index - 1 => not (Element < Old_Model (I)));
            if Element < Self.Tree (Index) then
               Insert_Index := Index;
               exit;
            end if;
         end loop;

         -- Ghost: the element is not less than anything before the insertion
         -- point, and everything from the insertion point on is not less
         -- than the element, so the tree stays sorted after the insertion:
         Lemma_Insert_Suffix (Old_Model, Insert_Index, Element);

         -- Insert the element and then move the remainder
         -- of the list up one index. If the found index is at
         -- the end then this loop will be skipped.
         for Index in Insert_Index .. Self.Size loop
            -- Everything before the insertion point is untouched, the inserted element sits at the
            -- insertion point, the elements already shifted are the old ones moved up by one, the
            -- element in hand is the next old one to move, and the rest is still untouched.
            pragma Loop_Invariant (for all I in 1 .. Insert_Index - 1 => Self.Tree (I) = Old_Model (I));
            pragma Loop_Invariant (if Index > Insert_Index then Self.Tree (Insert_Index) = Element);
            pragma Loop_Invariant (for all I in Insert_Index + 1 .. Index - 1 => Self.Tree (I) = Old_Model (I - 1));
            pragma Loop_Invariant (if Index > Insert_Index then This_Element = Old_Model (Index - 1) else This_Element = Element);
            pragma Loop_Invariant (for all I in Index .. Self.Size => Self.Tree (I) = Old_Model (I));
            Next_Element := Self.Tree (Index);
            Self.Tree (Index) := This_Element;
            This_Element := Next_Element;
         end loop;

         -- Increment size:
         Self.Size := @ + 1;

         -- Move the last element into the new last slot.
         pragma Assert (Self.Size >= Self.Tree'First);
         Self.Tree (Self.Size) := This_Element;
      end;

      return True;
   end Add;

   function Remove (Self : in out Instance; Element_Index : in Positive) return Boolean is
      Old_Model : constant Element_Sequence := Model (Self) with Ghost;
   begin
      -- Make sure index is in tree:
      if Element_Index > Self.Size then
         return False;
      end if;

      -- Starting with the given element index, start moving
      -- every element past this one a single entry to the left
      -- in the array. This will keep the list sorted and
      -- compact.
      for Index in Element_Index .. Self.Size - 1 loop
         -- Everything before the removed index is untouched, the elements already shifted are the
         -- old ones moved down by one, and the rest is still untouched.
         pragma Loop_Invariant (for all I in 1 .. Element_Index - 1 => Self.Tree (I) = Old_Model (I));
         pragma Loop_Invariant (for all I in Element_Index .. Index - 1 => Self.Tree (I) = Old_Model (I + 1));
         pragma Loop_Invariant (for all I in Index .. Self.Size => Self.Tree (I) = Old_Model (I));
         Self.Tree (Index) := Self.Tree (Index + 1);
      end loop;

      -- Decrement size:
      Self.Size := @ - 1;

      return True;
   end Remove;

   -- Search for element in tree. This is done in O(log n) where n is the current size of the tree.
   function Search (Self : in Instance; Element : in Element_Type; Element_Found : out Element_Type; Element_Index : out Positive) return Boolean is
      Low_Index : Natural := Self.Tree'First;
      High_Index : Natural := Self.Size;
   begin
      -- Ensure size is as expected
      pragma Assert (Self.Size <= Self.Tree'Last - Self.Tree'First + 1);

      -- Perform binary search on sorted list:
      while Low_Index <= High_Index loop
         -- The search range stays within the elements held, so every probed index is in range.
         pragma Loop_Invariant (Low_Index >= Self.Tree'First);
         pragma Loop_Invariant (High_Index <= Self.Size);
         -- Everything below the search range is less than the element and everything above it is
         -- greater, so a match can only be inside.
         pragma Loop_Invariant (for all I in 1 .. Low_Index - 1 => Self.Tree (I) < Element);
         pragma Loop_Invariant (for all I in High_Index + 1 .. Self.Size => Element < Self.Tree (I));
         -- The search range shrinks every iteration, so the loop terminates.
         pragma Loop_Variant (Decreases => High_Index - Low_Index);
         declare
            Mid_Index : constant Positive := Low_Index + ((High_Index - Low_Index) / 2);
            Current_Element : Element_Type renames Self.Tree (Mid_Index);
         begin
            Lemma_Greater_Is_Converse (Current_Element, Element);
            if Current_Element > Element then
               Lemma_Suffix_Greater (Model (Self), Mid_Index, Element);
               High_Index := Mid_Index - 1;
            elsif Current_Element < Element then
               Lemma_Prefix_Less (Model (Self), Mid_Index, Element);
               Low_Index := Mid_Index + 1;
            else
               Element_Found := Current_Element;
               Element_Index := Mid_Index;
               return True;
            end if;
         end;
      end loop;

      -- Initialize out parameters to sane values on failure to find match
      Element_Index := Self.Tree'First;
      Element_Found := Element;

      return False;
   end Search;

   function Get (Self : in Instance; Element_Index : in Positive) return Element_Type is
   begin
      return Self.Tree (Element_Index);
   end Get;

   procedure Set (Self : in out Instance; Element_Index : in Positive; Element : in Element_Type) is
   begin
      -- Ghost: the new element is not less than anything before its index
      -- and nothing after its index is less than it, so the tree stays
      -- sorted after the replacement:
      Lemma_Replace_Neighbors (Model (Self), Element_Index, Element);
      Self.Tree (Element_Index) := Element;
   end Set;

   procedure Clear (Self : in out Instance) is
   begin
      Self.Size := 0;
   end Clear;

   function Get_First_Index (Self : in Instance) return Positive is
   begin
      -- If empty, then return 1 as the first index. The last will return 0.
      if Self.Size = 0 then
         return 1;
      else
         return Self.Tree'First;
      end if;
   end Get_First_Index;

   function Get_Last_Index (Self : in Instance) return Natural is
   begin
      return Self.Size;
   end Get_Last_Index;

end Binary_Tree;

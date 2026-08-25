with Safe_Deallocator;
with Binary_Tree.Lemmas;

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

   -- The ordering axioms and the lemmas derived from them live in a ghost
   -- child package so that this body reads as the running code plus the
   -- proof annotations that refer to it:
   package Ordering is new Binary_Tree.Lemmas;

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
         Ordering.Lemma_Insert_Suffix (Old_Model, Insert_Index, Element);

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
            Ordering.Lemma_Greater_Is_Converse (Current_Element, Element);
            if Current_Element > Element then
               Ordering.Lemma_Suffix_Greater (Model (Self), Mid_Index, Element);
               High_Index := Mid_Index - 1;
            elsif Current_Element < Element then
               Ordering.Lemma_Prefix_Less (Model (Self), Mid_Index, Element);
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
      Ordering.Lemma_Replace_Neighbors (Model (Self), Element_Index, Element);
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

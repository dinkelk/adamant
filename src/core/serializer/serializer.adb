package body Serializer with SPARK_Mode => On is

   -- Byte arrays don't have a "scalar storage order" since they are an array of single byte
   -- items. So this warning doesn't apply. We can safely overlay a byte array with any type
   -- no matter the underlying scalar storage order.
   pragma Warnings (Off, "overlay changes scalar storage order");

   -- The bytes of a value. SPARK needs the overlaid object to be aliased so that
   -- its alignment is known, and a parameter is not, so the value is copied to
   -- an aliased local first.
   function Bytes_Of (Src : in T) return Byte_Array
      with Inline => True;

   function Bytes_Of (Src : in T) return Byte_Array is
      Copy : aliased constant T := Src;
      Overlay : constant Byte_Array with Import, Convention => Ada, Address => Copy'Address, Alignment => 1;
   begin
      return Overlay;
   end Bytes_Of;

   procedure To_Byte_Array (Dest : out Byte_Array; Src : in T) is
   begin
      Dest := Bytes_Of (Src);
   end To_Byte_Array;

   function To_Byte_Array (Src : in T) return Byte_Array is
   begin
      return Bytes_Of (Src);
   end To_Byte_Array;

   function To_Byte_Array_Unchecked (Dest : out Basic_Types.Byte_Array; Src : in T) return Natural is
   begin
      Dest := Bytes_Of (Src);
      return Serialized_Length;
   end To_Byte_Array_Unchecked;

   procedure To_Byte_Array_Unchecked (Dest : out Basic_Types.Byte_Array; Src : in T) is
   begin
      Dest := Bytes_Of (Src);
   end To_Byte_Array_Unchecked;

   function To_Byte_Array_Unchecked (Src : in T) return Basic_Types.Byte_Array is
   begin
      return Bytes_Of (Src);
   end To_Byte_Array_Unchecked;

   -- The deserialization bodies below are not analyzed, see the specification.

   procedure From_Byte_Array (Dest : out T; Src : in Byte_Array) with SPARK_Mode => Off is
      Overlay : Byte_Array with Import, Convention => Ada, Address => Dest'Address;
   begin
      Overlay := Src;
   end From_Byte_Array;

   function From_Byte_Array (Src : in Byte_Array) return T with SPARK_Mode => Off is
      pragma Annotate (GNATSAS, False_Positive, "validity check", "to_Return is initialized via overlay copy");
      -- The annotation below is not enough to remove the false positive for some
      -- reason, so just turn of analysis of this function.
      To_Return : T;
      Overlay : Byte_Array with Import, Convention => Ada, Address => To_Return'Address;
   begin
      Overlay := Src;
      return To_Return;
      pragma Annotate (GNATSAS, False_Positive, "validity check", "to_Return is initialized via overlay copy");
   end From_Byte_Array;

   function From_Byte_Array_Unchecked (Dest : out T; Src : in Basic_Types.Byte_Array) return Natural with SPARK_Mode => Off is
      Overlay : Byte_Array with Import, Convention => Ada, Address => Dest'Address;
   begin
      Overlay := Src (Src'First .. Src'First + Byte_Array'Length - 1);
      return Serialized_Length;
   end From_Byte_Array_Unchecked;

   procedure From_Byte_Array_Unchecked (Dest : out T; Src : in Basic_Types.Byte_Array) with SPARK_Mode => Off is
      Overlay : Byte_Array with Import, Convention => Ada, Address => Dest'Address;
   begin
      Overlay := Src (Src'First .. Src'First + Byte_Array'Length - 1);
   end From_Byte_Array_Unchecked;

   function From_Byte_Array_Unchecked (Src : in Basic_Types.Byte_Array) return T with SPARK_Mode => Off is
      pragma Annotate (GNATSAS, False_Positive, "validity check", "to_Return is initialized via overlay copy");
      -- The annotation below is not enough to remove the false positive for some
      -- reason, so just turn of analysis of this function.
      To_Return : T;
      Overlay : Byte_Array with Import, Convention => Ada, Address => To_Return'Address;
   begin
      Overlay := Src (Src'First .. Src'First + Byte_Array'Length - 1);
      return To_Return;
      pragma Annotate (GNATSAS, False_Positive, "validity check", "to_Return is initialized via overlay copy");
   end From_Byte_Array_Unchecked;

   pragma Warnings (On, "overlay changes scalar storage order");

end Serializer;

package body Serializer_Prover with SPARK_Mode => On is

   function Round_Trip (Value : in Example_Record) return Example_Record is
      Bytes : constant Example_Serializer.Byte_Array := Example_Serializer.To_Byte_Array (Value);
   begin
      return Example_Serializer.From_Byte_Array (Bytes);
   end Round_Trip;

   procedure Store (Value : in Example_Record; Dest : out Basic_Types.Byte_Array; Num_Bytes : out Natural) is
   begin
      Num_Bytes := Example_Serializer.To_Byte_Array_Unchecked (Dest, Value);
   end Store;

   function Example_Length (Src : in Example_Record; Num_Bytes_Serialized : out Natural) return Serializer_Types.Serialization_Status is
      pragma Unreferenced (Src);
   begin
      Num_Bytes_Serialized := Example_Record'Object_Size / Basic_Types.Byte'Object_Size;
      return Serializer_Types.Success;
   end Example_Length;

   function Example_Length (Src : in Basic_Types.Byte_Array; Num_Bytes_Serialized : out Natural) return Serializer_Types.Serialization_Status is
      pragma Unreferenced (Src);
   begin
      Num_Bytes_Serialized := Example_Record'Object_Size / Basic_Types.Byte'Object_Size;
      return Serializer_Types.Success;
   end Example_Length;

   function Variable_Store (Value : in Example_Record; Dest : out Basic_Types.Byte_Array; Num_Bytes : out Natural) return Serializer_Types.Serialization_Status is
      Status : Serializer_Types.Serialization_Status;
   begin
      Status := Example_Variable_Serializer.To_Byte_Array (Dest, Value, Num_Bytes);
      return Status;
   end Variable_Store;

   function Variable_Load (Bytes : in Basic_Types.Byte_Array; Value : out Example_Record; Num_Bytes : out Natural) return Serializer_Types.Serialization_Status is
      Status : Serializer_Types.Serialization_Status;
   begin
      Status := Example_Variable_Serializer.From_Byte_Array (Value, Bytes, Num_Bytes);
      return Status;
   end Variable_Load;

end Serializer_Prover;

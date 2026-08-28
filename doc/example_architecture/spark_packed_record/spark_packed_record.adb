package body Spark_Packed_Record with SPARK_Mode => On is

   procedure Set_Color (Item : in out Example_Record.T; Color : in Example_Record.My_Color) is
   begin
      Item.Value_3 := Color;
   end Set_Color;

   function To_Bytes (Item : in Example_Record.T) return Example_Record.Serialization.Byte_Array is
   begin
      return Example_Record.Serialization.To_Byte_Array (Item);
   end To_Bytes;

   procedure From_Bytes (Bytes : in Example_Record.Serialization.Byte_Array; Item : out Example_Record.T; Valid : out Boolean; Errant_Field : out Interfaces.Unsigned_32) is
   begin
      -- The validation function has an out parameter, so in SPARK it is
      -- called as the whole right hand side of an assignment:
      Valid := Example_Record.Validation.Valid (Bytes, Errant_Field);
      if Valid then
         Item := Example_Record.Serialization.From_Byte_Array (Bytes);
      else
         Item := (Value_1 => 0, Value_2 => 0, Value_3 => Example_Record.Red, Value_4 => 0.0);
      end if;
   end From_Bytes;

   procedure To_Bytes_Unchecked (Item : in Example_Record.T; Dest : out Basic_Types.Byte_Array; Num_Bytes : out Natural) is
   begin
      Num_Bytes := Example_Record.Serialization.To_Byte_Array_Unchecked (Dest, Item);
   end To_Bytes_Unchecked;

   function Serialized_Length (Item : in Example_Record.T) return Natural is
      Status : Serializer_Types.Serialization_Status;
      Num_Bytes : Natural;
   begin
      Status := Example_Record.Serialized_Length (Item, Num_Bytes);
      pragma Unreferenced (Status);
      return Num_Bytes;
   end Serialized_Length;

   function Variable_Serialized_Length (Item : in Example_Variable_Record.T; Num_Bytes : out Natural) return Serializer_Types.Serialization_Status is
      Status : Serializer_Types.Serialization_Status;
   begin
      Status := Example_Variable_Record.Serialized_Length (Item, Num_Bytes);
      return Status;
   end Variable_Serialized_Length;

   function Variable_To_Bytes (Item : in Example_Variable_Record.T; Dest : out Basic_Types.Byte_Array; Num_Bytes : out Natural) return Serializer_Types.Serialization_Status is
      Status : Serializer_Types.Serialization_Status;
   begin
      Status := Example_Variable_Record.Serialization.To_Byte_Array (Dest, Item, Num_Bytes);
      return Status;
   end Variable_To_Bytes;

   function Variable_From_Bytes (Bytes : in Basic_Types.Byte_Array; Item : out Example_Variable_Record.T; Num_Bytes : out Natural) return Serializer_Types.Serialization_Status is
      Status : Serializer_Types.Serialization_Status;
   begin
      Status := Example_Variable_Record.Serialization.From_Byte_Array (Item, Bytes, Num_Bytes);
      return Status;
   end Variable_From_Bytes;

end Spark_Packed_Record;

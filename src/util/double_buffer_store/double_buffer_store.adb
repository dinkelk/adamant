with Ada.Unchecked_Conversion;
with Basic_Types;
with Interfaces; use Interfaces;

package body Double_Buffer_Store with SPARK_Mode => On is

   use type Basic_Types.Byte_Array;

   -- Identifies one of the two copies:
   type Copy_Type is (Copy_A, Copy_B);
   function Other_Copy (Copy : in Copy_Type) return Copy_Type is
      (if Copy = Copy_A then Copy_B else Copy_A);

   -- The contents of one copy, read out of memory into an ordinary record:
   type Copy_Contents is record
      Crc : Crc_16.Crc_16_Type;
      Payload : Payload_Type;
   end record;

   -- The byte view of T for the CRC and the zero value. The unchecked conversions are
   -- legal in SPARK only because every bit pattern of T is a valid value, which
   -- GNATprove checks at each instantiation. Universal_Aliasing lets the compiler
   -- implement the conversions without a copy. GNATprove does not model the aspect
   -- and says so, which is harmless, so that message is silenced.
   pragma Warnings (GNATprove, Off, "*Universal_Aliasing*");
   type Data_Bytes is new Basic_Types.Byte_Array (0 .. T'Object_Size / Basic_Types.Byte'Object_Size - 1)
      with Universal_Aliasing;
   pragma Warnings (GNATprove, On, "*Universal_Aliasing*");
   function To_Bytes is new Ada.Unchecked_Conversion (Source => T, Target => Data_Bytes);
   function From_Bytes is new Ada.Unchecked_Conversion (Source => Data_Bytes, Target => T);

   -- The CRC covers the serialized save time followed by the bytes of the data:
   function Compute_Crc (Payload : in Payload_Type) return Crc_16.Crc_16_Type is
      (Crc_16.Compute_Crc_16 (Sys_Time.Serialization.To_Byte_Array (Payload.Save_Time) & Basic_Types.Byte_Array (To_Bytes (Payload.Data))))
      with Global => null;

   function Is_Valid (Contents : in Copy_Contents) return Boolean is
      (Contents.Crc = Compute_Crc (Contents.Payload))
      with Global => null;

   -- True if Time is later than Than:
   function Is_Later (Time : in Sys_Time.T; Than : in Sys_Time.T) return Boolean is
      (Time.Seconds > Than.Seconds or else (Time.Seconds = Than.Seconds and then Time.Subseconds > Than.Subseconds))
      with Global => null;

   -- Pick the copy to restore from: the valid one, or the one with the later save time
   -- if both are valid. Copy A wins a tie. Valid_Found is False if neither is valid.
   procedure Select_Copy (Current_A : in Copy_Contents; Current_B : in Copy_Contents; Valid_Found : out Boolean; Source : out Copy_Type)
      with Global => null
   is
      A_Valid : constant Boolean := Is_Valid (Current_A);
      B_Valid : constant Boolean := Is_Valid (Current_B);
   begin
      Valid_Found := A_Valid or else B_Valid;
      if A_Valid and then B_Valid then
         Source := (if Is_Later (Current_B.Payload.Save_Time, Than => Current_A.Payload.Save_Time) then Copy_B else Copy_A);
      elsif B_Valid then
         Source := Copy_B;
      else
         Source := Copy_A;
      end if;
   end Select_Copy;

   package body Bound with SPARK_Mode => On, Refined_State => (State => Target) is

      -- The copy the next save writes:
      Target : Copy_Type := Copy_A;

      ----------------------------------------------------------------------
      -- Memory access. These are the only subprograms that touch the regions.
      ----------------------------------------------------------------------

      -- Read a copy out of memory:
      function Read (Copy : in Copy_Type) return Copy_Contents is
         (case Copy is
            when Copy_A => (Crc => Region_A.Crc, Payload => Region_A.Payload),
            when Copy_B => (Crc => Region_B.Crc, Payload => Region_B.Payload))
         with Global => (Input => (Region_A, Region_B));

      -- Write a copy into memory. The payload and the CRC are written as two separate
      -- statements, payload first, so that the CRC reaches memory only after the data
      -- it covers. A single assignment of the whole record would let the compiler
      -- store the components in any order, and a reboot between the CRC and the data
      -- would leave a copy that validates with stale data.
      procedure Write (Copy : in Copy_Type; Contents : in Copy_Contents)
         with Global => (In_Out => (Region_A, Region_B))
      is
      begin
         case Copy is
            when Copy_A =>
               Region_A.Payload := Contents.Payload;
               Region_A.Crc := Contents.Crc;
            when Copy_B =>
               Region_B.Payload := Contents.Payload;
               Region_B.Crc := Contents.Crc;
         end case;
      end Write;

      -- Invalidate a copy by complementing its CRC. The stored CRC then differs from
      -- the CRC of the payload whatever the payload holds, so the copy can never read
      -- as valid until it is written again.
      procedure Invalidate (Copy : in Copy_Type)
         with Global => (In_Out => (Region_A, Region_B))
      is
      begin
         case Copy is
            when Copy_A =>
               Region_A.Crc := [not Region_A.Crc (0), not Region_A.Crc (1)];
            when Copy_B =>
               Region_B.Crc := [not Region_B.Crc (0), not Region_B.Crc (1)];
         end case;
      end Invalidate;

      ----------------------------------------------------------------------
      -- Public operations:
      ----------------------------------------------------------------------

      -- Restore, also reporting whether a valid copy was found and which:
      procedure Restore (Value : out T; Status : out Restore_Status; Valid_Found : out Boolean; Source : out Copy_Type)
         with Global => (Input => (Region_A, Region_B))
      is
         Current_A : constant Copy_Contents := Read (Copy_A);
         Current_B : constant Copy_Contents := Read (Copy_B);
      begin
         Select_Copy (Current_A, Current_B, Valid_Found, Source);
         if Valid_Found then
            Value := (case Source is
               when Copy_A => Current_A.Payload.Data,
               when Copy_B => Current_B.Payload.Data);
            Status := Restored;
         else
            Value := From_Bytes (Data_Bytes'[others => 0]);
            Status := No_Valid_Copy;
         end if;
      end Restore;

      procedure Restore (Value : out T; Status : out Restore_Status) is
         Ignore_Valid_Found : Boolean;
         Ignore_Source : Copy_Type;
      begin
         Restore (Value, Status, Ignore_Valid_Found, Ignore_Source);
      end Restore;

      procedure Init (Value : out T; Status : out Restore_Status)
         with Refined_Global => (In_Out => (Region_A, Region_B), Output => Target)
      is
         Valid_Found : Boolean;
         Source : Copy_Type;
      begin
         Restore (Value, Status, Valid_Found, Source);
         if Valid_Found then
            -- The other copy is stale. Invalidate it and write it next.
            Invalidate (Other_Copy (Source));
            Target := Other_Copy (Source);
         else
            -- Nothing is valid, so nothing is stale. Start with copy A.
            Target := Copy_A;
         end if;
      end Init;

      procedure Save (Value : in T; Save_Time : in Sys_Time.T)
         with Refined_Global => (In_Out => (Region_A, Region_B, Target))
      is
         Payload : constant Payload_Type := (Save_Time => Save_Time, Data => Value);
      begin
         Write (Target, (Crc => Compute_Crc (Payload), Payload => Payload));
         Target := Other_Copy (Target);
      end Save;

   end Bound;

end Double_Buffer_Store;

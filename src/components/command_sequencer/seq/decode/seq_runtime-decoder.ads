with Ada.Text_IO;
with Seq_Config;

package Seq_Runtime.Decoder is

   -- Decoder_Instance type:
   type Decoder_Instance is new Seq_Runtime.Instance with private;

   -- It takes the filename as an argument
   procedure Decode (Self : in out Decoder_Instance; Path : in String; Config_Path : in String := ""; Output : in Ada.Text_IO.File_Type := Ada.Text_IO.Standard_Output);

private

   type Decoder_Instance is new Seq_Runtime.Instance with record
      Config : Seq_Config.Instance;
   end record;

end Seq_Runtime.Decoder;

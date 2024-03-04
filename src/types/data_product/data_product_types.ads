with Basic_Types;
with Configuration;

-- Declaration of Data_Product id type. This ensures that
-- it is NOT just a naked natural, giving the compiler
-- more information to help find errors.
package Data_Product_Types is
   -- Id type:
   type Data_Product_Id is new Natural range 0 .. 65_535;
   subtype Data_Product_Id_Base is Data_Product_Id range 1 .. Data_Product_Id'Last;
   -- Length type:
   subtype Data_Product_Buffer_Length_Type is Natural range 0 .. Configuration.Data_Product_Buffer_Size;
   subtype Data_Product_Buffer_Index_Type is Data_Product_Buffer_Length_Type range 0 .. Data_Product_Buffer_Length_Type'Last - 1;
   -- Buffer type:
   subtype Data_Product_Buffer_Type is Basic_Types.Byte_Array (Data_Product_Buffer_Index_Type);
end Data_Product_Types;

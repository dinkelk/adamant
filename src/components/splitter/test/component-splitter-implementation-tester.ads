--------------------------------------------------------------------------------
-- Splitter Component Tester Spec
--------------------------------------------------------------------------------

-- Includes:
with Component.Splitter_Reciprocal;
with History;

-- This is a generic component that can be used to split a single connector of
-- any type into an arrayed connector of that type.
generic
package Component.Splitter.Implementation.Tester is

   package Splitter_Package is new Component.Splitter_Reciprocal (T);
   -- Invoker connector history packages:
   package T_Recv_Sync_History_Package is new History (T);

   -- Component class instance:
   type Instance is new Splitter_Package.Base_Instance with record
      -- The component instance under test:
      Component_Instance : aliased Component.Splitter.Implementation.Instance;
      -- Connector histories:
      T_Recv_Sync_History : T_Recv_Sync_History_Package.Instance;
   end record;
   type Instance_Access is access all Instance;

   ---------------------------------------
   -- Initialize component heap variables:
   ---------------------------------------
   procedure Init_Base (Self : in out Instance);
   procedure Final_Base (Self : in out Instance);

   ---------------------------------------
   -- Test initialization functions:
   ---------------------------------------
   procedure Connect (Self : in out Instance);
   procedure Disconnect_T_Recv_Sync (Self : in out Instance; Index : in Positive);

   ---------------------------------------
   -- Invokee connector primitives:
   ---------------------------------------
   -- The arrayed output connector that receives fanned-out data.
   overriding procedure T_Recv_Sync (Self : in out Instance; Arg : in T);

end Component.Splitter.Implementation.Tester;

--  Copyright 2026 The FreedomChat authors
--  SPDX-License-Identifier: Apache-2.0

with Unishox; use Unishox;

package body Unishox_C
  with SPARK_Mode => Off
is

   use type Interfaces.C.int;

   type Operation is access procedure
     (Input         : Byte_Array;
      Output        : out Byte_Array;
      Output_Length : out Natural;
      Success       : out Boolean);

   --  Overlay the C buffers with Byte_Arrays and call Op
   function Call
     (Op      : Operation;
      Inp     : System.Address;
      In_Len  : Interfaces.C.int;
      Outp    : System.Address;
      Out_Cap : Interfaces.C.int;
      Out_Len : out Interfaces.C.int) return Interfaces.C.int
   is
   begin
      Out_Len := 0;
      if In_Len not in 0 .. Max_Length or else Out_Cap not in 0 .. Max_Length
      then
         return -1;
      end if;
      declare
         Input  : Byte_Array (1 .. Natural (In_Len))
         with Import, Address => Inp;
         Output : Byte_Array (1 .. Natural (Out_Cap))
         with Import, Address => Outp;
         Len    : Natural;
         Ok     : Boolean;
      begin
         Op (Input, Output, Len, Ok);
         Out_Len := Interfaces.C.int (Len);
         return (if Ok then 1 else 0);
      end;
   end Call;

   function Compress
     (Inp     : System.Address;
      In_Len  : Interfaces.C.int;
      Outp    : System.Address;
      Out_Cap : Interfaces.C.int;
      Out_Len : out Interfaces.C.int) return Interfaces.C.int
   is (Call (Unishox.Compress'Access, Inp, In_Len, Outp, Out_Cap, Out_Len));

   function Decompress
     (Inp     : System.Address;
      In_Len  : Interfaces.C.int;
      Outp    : System.Address;
      Out_Cap : Interfaces.C.int;
      Out_Len : out Interfaces.C.int) return Interfaces.C.int
   is (Call (Unishox.Decompress'Access, Inp, In_Len, Outp, Out_Cap, Out_Len));

end Unishox_C;

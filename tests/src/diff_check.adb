--  Copyright 2026 The FreedomChat authors
--  SPDX-License-Identifier: Apache-2.0

with Ada.Text_IO; use Ada.Text_IO;

package body Diff_Check is

   C_Plain  : Big_Array (0 .. Big_Size - 1);   --  reference decompressed
   A_Comp   : Byte_Array (1 .. Max_Length);    --  Ada compressed
   A_Plain  : Byte_Array (1 .. Max_Length);    --  Ada decompressed
   Tmp      : Byte_Array (1 .. Max_Length);

   procedure Fail (Name, What : String) is
   begin
      Failures := Failures + 1;
      if Failures <= 20 then
         Put_Line ("FAIL [" & Name & "] " & What);
      end if;
   end Fail;

   function Same (A : Byte_Array; B : Big_Array) return Boolean is
     (A'Length = B'Length
      and then (for all K in 0 .. A'Length - 1 =>
                  A (A'First + K) = B (B'First + K)));


   procedure Check (Name : String; Input : Byte_Array) is
      C_Len, D_Len : Int;
      A_Len, P_Len : Natural;
      Ok           : Boolean;
   begin
      Checks := Checks + 1;
      C_Len := Ref_Compress (Input'Address, Int (Input'Length), C_Comp'Address);
      Compress (Input, A_Comp, A_Len, Ok);
      if Integer (C_Len) > Max_Length then
         Too_Big := Too_Big + 1;
         if Ok or else A_Len /= 0 then
            Fail (Name, "compress should report overflow, C length"
                  & C_Len'Image);
         end if;
         return;
      end if;
      if not Ok or else A_Len /= Natural (C_Len)
        or else not Same (A_Comp (1 .. A_Len), C_Comp (0 .. A_Len - 1))
      then
         Fail (Name, "compress differs: C" & C_Len'Image & " Ada"
               & A_Len'Image & " ok " & Ok'Image);
         return;
      end if;

      --  Output buffer of exactly the needed size, and one byte less
      Compress (Input, Tmp (1 .. A_Len), P_Len, Ok);
      if not Ok or else P_Len /= A_Len or else Tmp (1 .. A_Len) /= A_Comp (1 .. A_Len)
      then
         Fail (Name, "compress into an exact-size buffer failed");
      end if;
      if A_Len > 0 then
         Compress (Input, Tmp (1 .. A_Len - 1), P_Len, Ok);
         if Ok or else P_Len /= 0
           or else (for some B of Tmp (1 .. A_Len - 1) => B /= 0)
         then
            Fail (Name, "compress into a too small buffer did not fail cleanly");
         end if;
      end if;

      --  Ada decompress (C compressed) = input
      declare
         C_Bytes : Byte_Array (1 .. A_Len);
      begin
         for K in C_Bytes'Range loop
            C_Bytes (K) := C_Comp (K - 1);
         end loop;
         Decompress (C_Bytes, A_Plain, P_Len, Ok);
         if not Ok or else P_Len /= Input'Length
           or else A_Plain (1 .. P_Len) /= Input
         then
            Fail (Name, "Ada decompress of C output differs, length"
                  & P_Len'Image & " ok " & Ok'Image);
         end if;
         Decompress (C_Bytes, Tmp (1 .. Input'Length), P_Len, Ok);
         if not Ok or else P_Len /= Input'Length then
            Fail (Name, "decompress into an exact-size buffer failed");
         end if;
         if Input'Length > 0 then
            Decompress (C_Bytes, Tmp (1 .. Input'Length - 1), P_Len, Ok);
            if Ok or else P_Len /= 0 then
               Fail (Name, "decompress into a too small buffer did not fail");
            end if;
         end if;
      end;

      --  C decompress (Ada compressed) = input
      D_Len := Ref_Decompress_Simple
        (A_Comp'Address, Int (A_Len), C_Plain'Address, Big_Size);
      if Natural (D_Len) /= Input'Length
        or else not Same (Input, C_Plain (0 .. Input'Length - 1))
      then
         Fail (Name, "C decompress of Ada output differs");
      end if;
   end Check;

   procedure Check_Decoder (Name : String; Input : Byte_Array; Limit : Natural)
   is
      C_Len : Int;
      P_Len : Natural;
      Ok    : Boolean;
   begin
      Fuzz_Checks := Fuzz_Checks + 1;
      C_Len := Ref_Decompress_Bounded
        (Input'Address, Int (Input'Length), C_Plain'Address, Big_Size);
      Decompress (Input, A_Plain (1 .. Limit), P_Len, Ok);
      if Integer (C_Len) <= Limit then
         if not Ok or else P_Len /= Natural (C_Len)
           or else not Same (A_Plain (1 .. P_Len), C_Plain (0 .. P_Len - 1))
         then
            Fail (Name, "decoder differs: C" & C_Len'Image & " Ada"
                  & P_Len'Image & " ok " & Ok'Image);
         end if;
      elsif Ok or else P_Len /= 0 then
         Fail (Name, "decoder should report overflow, C length" & C_Len'Image
               & " limit" & Limit'Image);
      end if;
   end Check_Decoder;

end Diff_Check;

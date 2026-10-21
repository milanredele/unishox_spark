--  Copyright 2026 The FreedomChat authors
--  SPDX-License-Identifier: Apache-2.0
--
--  Differential test of the SPARK Unishox2 port against the C reference.
--  Usage: test_unishox <corpus.txt> [random round trips] [decoder fuzz cases]

with Ada.Command_Line;
with Ada.Text_IO;  use Ada.Text_IO;
with Interfaces;   use Interfaces;
with Interfaces.C;
with System;
with Unishox;      use Unishox;

procedure Test_Unishox is

   package CL renames Ada.Command_Line;
   subtype Int is Interfaces.C.int;

   function Ref_Compress
     (Inp : System.Address; Len : Int; Outp : System.Address) return Int
   with Import, Convention => C, External_Name => "ref_compress";

   function Ref_Decompress_Simple
     (Inp : System.Address; Len : Int; Outp : System.Address; Size : Int)
      return Int
   with Import, Convention => C, External_Name => "ref_decompress_simple";

   function Ref_Decompress_Bounded
     (Inp : System.Address; Len : Int; Outp : System.Address; Olen : Int)
      return Int
   with Import, Convention => C, External_Name => "ref_decompress_bounded";

   type Big_Array is array (Natural range <>) of Unsigned_8;

   Big_Size : constant := 65_536;
   C_Comp   : Big_Array (0 .. Big_Size - 1);   --  reference compressed
   C_Plain  : Big_Array (0 .. Big_Size - 1);   --  reference decompressed
   A_Comp   : Byte_Array (1 .. Max_Length);    --  Ada compressed
   A_Plain  : Byte_Array (1 .. Max_Length);    --  Ada decompressed
   Tmp      : Byte_Array (1 .. Max_Length);

   Failures : Natural := 0;
   Checks   : Natural := 0;
   Too_Big  : Natural := 0;

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

   --  Full differential check of one input
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

   --  Decoder check on arbitrary (usually malformed) input with an output
   --  limit: the Ada result must equal the reference whenever the
   --  reference output fits, and be a failure otherwise.
   Fuzz_Checks : Natural := 0;
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

   ---------------------------------------------------------------------
   --  Corpus
   ---------------------------------------------------------------------

   function Hex_Value (C : Character) return Unsigned_8 is
     (case C is
         when '0' .. '9' => Character'Pos (C) - Character'Pos ('0'),
         when 'a' .. 'f' => Character'Pos (C) - Character'Pos ('a') + 10,
         when others     => raise Constraint_Error with "bad hex");

   type Sizes is array (1 .. 5) of Natural;
   Sample_Sizes : Sizes := [others => 0];
   Samples_Seen : Natural := 0;

   procedure Run_Corpus (Path : String) is
      F    : File_Type;
      Line : String (1 .. 2 * Max_Length + 10);
      Last : Natural;
      Name : String (1 .. 200) := [others => ' '];
      NL   : Natural := 0;
      N    : Natural := 0;
      Buf  : Byte_Array (1 .. Max_Length);
      Len  : Natural;
      Ok   : Boolean;
   begin
      Open (F, In_File, Path);
      while not End_Of_File (F) loop
         Get_Line (F, Line, Last);
         if Last >= 2 and then Line (1 .. 2) = "# " then
            NL := Natural'Min (Last - 2, Name'Length);
            Name (1 .. NL) := Line (3 .. 2 + NL);
         else
            for K in 1 .. Last / 2 loop
               Buf (K) := Hex_Value (Line (2 * K - 1)) * 16
                          + Hex_Value (Line (2 * K));
            end loop;
            Check (Name (1 .. NL), Buf (1 .. Last / 2));
            N := N + 1;
            if NL > 7 and then Name (1 .. 7) = "sample " then
               Samples_Seen := Samples_Seen + 1;
               Compress (Buf (1 .. Last / 2), A_Comp, Len, Ok);
               Sample_Sizes (Samples_Seen) := Len;
               Put_Line ("  " & Name (1 .. NL) & ":" & Natural'Image (Last / 2)
                         & " ->" & Len'Image & " bytes");
            end if;
         end if;
      end loop;
      Close (F);
      Put_Line ("corpus:" & N'Image & " strings checked");
   end Run_Corpus;

   ---------------------------------------------------------------------
   --  Random inputs (fixed seed)
   ---------------------------------------------------------------------

   State : Unsigned_64 := 16#9E37_79B9_7F4A_7C15#;

   function Next return Unsigned_64 is
   begin
      State := State xor Shift_Right (State, 12);
      State := State xor Shift_Left (State, 25);
      State := State xor Shift_Right (State, 27);
      return State * 16#2545_F491_4F6C_DD1D#;
   end Next;

   function Rand (N : Positive) return Natural is
     (Natural (Shift_Right (Next, 11) mod Unsigned_64 (N)));

   type Word is access constant String;
   Words : constant array (Positive range <>) of Word :=
     [new String'("the"), new String'("of"), new String'("and"),
      new String'("to"), new String'("in"), new String'("is"),
      new String'("you"), new String'("that"), new String'("it"),
      new String'("meet"), new String'("bridge"), new String'("police"),
      new String'("station"), new String'("tomorrow"), new String'("water"),
      new String'("message"), new String'("north"), new String'("relay"),
      new String'("találkozzunk"), new String'("állomás"),
      new String'("holnap"), new String'("üzenet"), new String'("híd"),
      new String'("rendőrség"), new String'("víz"), new String'("őrző"),
      new String'("Привет"), new String'("你好"), new String'("😀"),
      new String'("👍🏽"), new String'("ÉÉÉ"), new String'("HELP"),
      new String'("URGENT"), new String'("ok"), new String'("Ok"),
      new String'("2026-10-21"), new String'("12:30:00"),
      new String'("2026-10-21T13:45:30.123Z"), new String'("(555) 123-4567"),
      new String'("deadbeef"), new String'("CAFEBABE"), new String'("0123456789"),
      new String'("https://"), new String'("""key"": ""value"""),
      new String'("</p>"), new String'("a=""b"""), new String'("://"),
      new String'("550e8400-e29b-41d4-a716-446655440000")];

   Buf : Byte_Array (1 .. Max_Length);
   Len : Natural;

   procedure Push (B : Unsigned_8; Max : Natural) is
   begin
      if Len < Max then
         Len := Len + 1;
         Buf (Len) := B;
      end if;
   end Push;

   procedure Push_Code_Point (Cp : Natural; Max : Natural) is
   begin
      if Cp < 16#80# then
         Push (Unsigned_8 (Cp), Max);
      elsif Cp < 16#800# then
         Push (Unsigned_8 (16#C0# + Cp / 64), Max);
         Push (Unsigned_8 (16#80# + Cp mod 64), Max);
      elsif Cp < 16#1_0000# then
         Push (Unsigned_8 (16#E0# + Cp / 4096), Max);
         Push (Unsigned_8 (16#80# + Cp / 64 mod 64), Max);
         Push (Unsigned_8 (16#80# + Cp mod 64), Max);
      else
         Push (Unsigned_8 (16#F0# + Cp / 262_144), Max);
         Push (Unsigned_8 (16#80# + Cp / 4096 mod 64), Max);
         Push (Unsigned_8 (16#80# + Cp / 64 mod 64), Max);
         Push (Unsigned_8 (16#80# + Cp mod 64), Max);
      end if;
   end Push_Code_Point;

   procedure Generate is
      Max  : Natural;
      Kind : constant Natural := Rand (8);
   begin
      Len := 0;
      case Rand (1000) is
         when 0 .. 4    => Max := Rand (Max_Length + 1);
         when 5 .. 99   => Max := Rand (1200);
         when others    => Max := Rand (200);
      end case;
      for Iter in 1 .. 10_000 loop
         exit when Len >= Max;
         case Kind is
            when 0 =>      --  printable ASCII
               Push (Unsigned_8 (32 + Rand (95)), Max);
            when 1 | 2 =>  --  words with case changes, numbers, punctuation
               declare
                  W : constant String := Words (1 + Rand (Words'Length)).all;
                  R : constant Natural := Rand (100);
               begin
                  for C of W loop
                     if R < 10 and then C in 'a' .. 'z' then
                        Push (Character'Pos (C) - 32, Max);
                     else
                        Push (Character'Pos (C), Max);
                     end if;
                  end loop;
                  if R in 10 .. 14 then
                     for D in 1 .. 1 + Rand (12) loop
                        Push (Unsigned_8 (48 + Rand (10)), Max);
                     end loop;
                  end if;
                  case Rand (12) is
                     when 0 => Push (Character'Pos (','), Max);
                     when 1 => Push (Character'Pos ('.'), Max);
                     when 2 => Push (10, Max);
                     when 3 => Push (13, Max); Push (10, Max);
                     when 4 => Push (9, Max);
                     when others => null;
                  end case;
                  Push (32, Max);
               end;
            when 3 =>      --  random code points from several scripts
               case Rand (7) is
                  when 0 => Push_Code_Point (32 + Rand (95), Max);
                  when 1 => Push_Code_Point (16#A0# + Rand (16#1B0#), Max);
                  when 2 => Push_Code_Point (16#370# + Rand (16#190#), Max);
                  when 3 => Push_Code_Point (16#4E00# + Rand (16#5200#), Max);
                  when 4 => Push_Code_Point (16#1F300# + Rand (16#800#), Max);
                  when 5 => Push_Code_Point (16#800# + Rand (16#D000#), Max);
                  when others =>
                     Push_Code_Point (16#1_0000# + Rand (16#10_0000#), Max);
               end case;
            when 4 =>      --  random bytes
               Push (Unsigned_8 (Rand (256)), Max);
            when 5 =>      --  small alphabet: many repeats and matches
               Push (Character'Pos (String'("ab .") (1 + Rand (4))), Max);
            when 6 =>      --  runs of one byte or character
               declare
                  B : constant Unsigned_8 := Unsigned_8 (Rand (256));
               begin
                  for K in 1 .. 1 + Rand (12) loop
                     if B < 128 then
                        Push (B, Max);
                     else
                        Push_Code_Point (16#E1# + Natural (B), Max);
                     end if;
                  end loop;
               end;
            when others => --  everything mixed
               case Rand (6) is
                  when 0 => Push (Unsigned_8 (Rand (256)), Max);
                  when 1 => Push_Code_Point (16#A0# + Rand (16#3000#), Max);
                  when 2 =>
                     for C of Words (1 + Rand (Words'Length)).all loop
                        Push (Character'Pos (C), Max);
                     end loop;
                  when 3 => Push (Unsigned_8 (Rand (32)), Max);
                  when 4 => Push_Code_Point (16#1F600# + Rand (80), Max);
                  when others => Push (Unsigned_8 (32 + Rand (95)), Max);
               end case;
         end case;
      end loop;
   end Generate;

   procedure Run_Random (Count : Natural) is
   begin
      for I in 1 .. Count loop
         Generate;
         Check ("random" & I'Image, Buf (1 .. Len));
      end loop;
      Put_Line ("random round trips:" & Count'Image);
   end Run_Random;

   procedure Run_Decoder_Fuzz (Count : Natural) is
      C_Len : Int;
      N     : Natural;
      Limit : Natural;
   begin
      for I in 1 .. Count loop
         if I mod 2 = 0 then
            --  a valid stream with a few bits flipped, or truncated
            Generate;
            C_Len := Ref_Compress (Buf'Address, Int (Len), C_Comp'Address);
            N := Natural'Min (Natural (C_Len), Max_Length);
            for K in 1 .. N loop
               Tmp (K) := C_Comp (K - 1);
            end loop;
            if N > 0 then
               for F in 1 .. 1 + Rand (3) loop
                  declare
                     P : constant Positive := 1 + Rand (N);
                  begin
                     Tmp (P) := Tmp (P) xor Shift_Left (1, Rand (8));
                  end;
               end loop;
               if Rand (4) = 0 then
                  N := Rand (N + 1);
               end if;
            end if;
         else
            --  random bytes
            N := (if Rand (100) = 0 then Rand (Max_Length + 1) else Rand (64));
            for K in 1 .. N loop
               Tmp (K) := Unsigned_8 (Rand (256));
            end loop;
         end if;
         Limit := (if Rand (4) = 0 then Rand (Max_Length + 1) else Max_Length);
         Check_Decoder ("fuzz" & I'Image, Tmp (1 .. N), Limit);
      end loop;
      Put_Line ("decoder fuzz cases:" & Count'Image);
   end Run_Decoder_Fuzz;

   Expected : constant Sizes := [57, 257, 70, 321, 474];
   N_Random : Natural := 100_000;
   N_Fuzz   : Natural := 100_000;
begin
   if CL.Argument_Count < 1 then
      Put_Line ("usage: test_unishox corpus.txt [round trips] [fuzz cases]");
      CL.Set_Exit_Status (CL.Failure);
      return;
   end if;
   if CL.Argument_Count >= 2 then
      N_Random := Natural'Value (CL.Argument (2));
   end if;
   if CL.Argument_Count >= 3 then
      N_Fuzz := Natural'Value (CL.Argument (3));
   end if;

   Run_Corpus (CL.Argument (1));
   if Samples_Seen /= 5 or else Sample_Sizes /= Expected then
      Fail ("samples", "sizes differ from the addendum table");
   end if;
   Run_Random (N_Random);
   Run_Decoder_Fuzz (N_Fuzz);

   Put_Line ("checks:" & Checks'Image & " (" & Too_Big'Image
             & " with output > 4096 bytes), decoder fuzz:"
             & Fuzz_Checks'Image & ", failures:" & Failures'Image);
   if Failures = 0 then
      Put_Line ("PASS");
   else
      Put_Line ("FAIL");
      CL.Set_Exit_Status (CL.Failure);
   end if;
end Test_Unishox;

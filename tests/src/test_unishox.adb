--  Copyright 2026 The FreedomChat authors
--  SPDX-License-Identifier: Apache-2.0
--
--  Differential test of the SPARK Unishox2 port against the C reference.
--  Usage: test_unishox <corpus.txt> [random round trips] [decoder fuzz cases]

with Ada.Command_Line;
with Ada.Text_IO;  use Ada.Text_IO;
with Diff_Check;   use Diff_Check;
with Interfaces;   use Interfaces;
with Unishox;      use Unishox;

procedure Test_Unishox is

   package CL renames Ada.Command_Line;

   A_Comp : Byte_Array (1 .. Max_Length);   --  Ada compressed (sample sizes)
   Tmp    : Byte_Array (1 .. Max_Length);   --  fuzz input

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

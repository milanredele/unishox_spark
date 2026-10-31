--  Copyright 2026 The FreedomChat authors
--  SPDX-License-Identifier: Apache-2.0
--
--  Bounded-exhaustive differential test against the C reference:
--   (a) the decoder on every input of 1, 2 and 3 bytes, at several output
--       limits (Diff_Check.Check_Decoder);
--   (b) the full check (Diff_Check.Check) on every input of at most 2 bytes
--       and every 3-byte string over a 40-character alphabet.
--  Usage: exhaustive_unishox

with Ada.Calendar; use Ada.Calendar;
with Ada.Command_Line;
with Ada.Text_IO;  use Ada.Text_IO;
with Diff_Check;   use Diff_Check;
with Unishox;      use Unishox;

procedure Exhaustive_Unishox is

   Limits : constant array (1 .. 5) of Natural := [0, 1, 7, 64, Max_Length];

   --  Letters of both cases, digits, space, CR, LF, punctuation, and the
   --  two bytes of U+00E9 in UTF-8
   Alphabet : constant Byte_Array :=
     [Character'Pos ('a'), Character'Pos ('e'), Character'Pos ('i'),
      Character'Pos ('o'), Character'Pos ('t'), Character'Pos ('n'),
      Character'Pos ('s'), Character'Pos ('r'), Character'Pos ('h'),
      Character'Pos ('l'), Character'Pos ('x'), Character'Pos ('z'),
      Character'Pos ('A'), Character'Pos ('E'), Character'Pos ('T'),
      Character'Pos ('O'), Character'Pos ('N'), Character'Pos ('Q'),
      Character'Pos ('X'), Character'Pos ('Z'),
      Character'Pos ('0'), Character'Pos ('1'), Character'Pos ('2'),
      Character'Pos ('5'), Character'Pos ('7'), Character'Pos ('9'),
      Character'Pos (' '), 13, 10,
      Character'Pos ('.'), Character'Pos (','), Character'Pos ('-'),
      Character'Pos (':'), Character'Pos ('/'), Character'Pos ('"'),
      Character'Pos ('('), Character'Pos ('@'), Character'Pos ('~'),
      16#C3#, 16#A9#];

   Hex_Digit : constant String := "0123456789abcdef";

   function Hex (Input : Byte_Array) return String is
      R : String (1 .. 2 * Input'Length);
   begin
      for K in Input'Range loop
         R (2 * (K - Input'First) + 1) := Hex_Digit (Natural (Input (K)) / 16 + 1);
         R (2 * (K - Input'First) + 2) := Hex_Digit (Natural (Input (K)) mod 16 + 1);
      end loop;
      return R;
   end Hex;

   --  Print the input of a check that failed (Fail prints only the name)
   procedure Report (Before : Natural; Input : Byte_Array; Limit : Integer) is
   begin
      if Failures > Before and then Failures <= 20 then
         Put_Line ("  input " & Hex (Input)
                   & (if Limit >= 0 then " limit" & Limit'Image else ""));
      end if;
   end Report;

   Inp    : Byte_Array (1 .. 3);
   Before : Natural;
   Cases  : Natural := 0;
   Start  : Time := Clock;

   procedure Decode_All (Len : Positive) is
   begin
      for Code in 0 .. 256 ** Len - 1 loop
         pragma Loop_Invariant (Code < 256 ** Len);
         for K in 1 .. Len loop
            Inp (K) := Byte (Code / 256 ** (K - 1) mod 256);
         end loop;
         Cases := Cases + 1;
         for L of Limits loop
            Before := Failures;
            Check_Decoder ("exhaustive decode", Inp (1 .. Len), L, L + 1);
            Report (Before, Inp (1 .. Len), L);
         end loop;
      end loop;
   end Decode_All;

   procedure Check_One (Input : Byte_Array) is
   begin
      Before := Failures;
      Check ("exhaustive", Input);
      Report (Before, Input, -1);
   end Check_One;

   procedure Lap (What : String) is
   begin
      Put_Line (What & " (" & Duration'Image (Clock - Start) & " s)");
      Start := Clock;
   end Lap;

begin
   for Len in 1 .. 3 loop
      Decode_All (Len);
   end loop;
   Lap ("decoder: every input of 1 to 3 bytes," & Cases'Image & " inputs at"
        & Limits'Length'Image & " output limits");

   Check_One (Inp (1 .. 0));
   for A in Byte loop
      Inp (1) := A;
      Check_One (Inp (1 .. 1));
      for B in Byte loop
         Inp (2) := B;
         Check_One (Inp (1 .. 2));
      end loop;
   end loop;
   Lap ("full check: every input of at most 2 bytes," & Checks'Image & " inputs");

   for A of Alphabet loop
      for B of Alphabet loop
         for C of Alphabet loop
            Inp := [A, B, C];
            Check_One (Inp);
         end loop;
      end loop;
   end loop;
   Lap ("full check: 3-byte strings over" & Alphabet'Length'Image
        & " characters, total" & Checks'Image & " inputs");

   Put_Line ("checks:" & Checks'Image & ", decoder:" & Fuzz_Checks'Image
             & ", failures:" & Failures'Image);
   if Failures = 0 then
      Put_Line ("PASS");
   else
      Put_Line ("FAIL");
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end if;
end Exhaustive_Unishox;

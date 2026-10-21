--  Copyright 2026 The FreedomChat authors
--  SPDX-License-Identifier: Apache-2.0
--
--  Throughput on 1 kB inputs: SPARK port (built -O2 -gnatp) and the C
--  reference (clang -O2), microseconds per call.
--  Usage: bench_unishox <tests/corpus.txt>

with Ada.Command_Line;
with Ada.Real_Time; use Ada.Real_Time;
with Ada.Text_IO;   use Ada.Text_IO;
with Interfaces;    use Interfaces;
with Interfaces.C;
with System;
with Unishox;       use Unishox;

procedure Bench_Unishox is

   subtype Int is Interfaces.C.int;

   function Ref_Compress
     (Inp : System.Address; Len : Int; Outp : System.Address) return Int
   with Import, Convention => C, External_Name => "ref_compress";

   function Ref_Decompress
     (Inp : System.Address; Len : Int; Outp : System.Address) return Int
   with Import, Convention => C, External_Name => "unishox2_decompress_simple";

   type Case_Kind is (En, Hu);

   Input  : Byte_Array (1 .. 1024);
   Comp   : Byte_Array (1 .. Max_Length);
   Plain  : Byte_Array (1 .. Max_Length);
   type Big_Array is array (Positive range <>) of Unsigned_8;
   C_Comp : Big_Array (1 .. 32_768);
   C_Out  : Big_Array (1 .. 32_768);

   --  Loads the corpus entry "# <Name>" (hex line) into Input
   procedure Fill (Path, Name : String) is
      F    : File_Type;
      Line : String (1 .. 2 * Max_Length + 10);
      Last : Natural;
      function Hex (C : Character) return Unsigned_8 is
        (if C in '0' .. '9' then Character'Pos (C) - Character'Pos ('0')
         else Character'Pos (C) - Character'Pos ('a') + 10);
   begin
      Open (F, In_File, Path);
      loop
         Get_Line (F, Line, Last);
         exit when Line (1 .. Last) = "# " & Name;
      end loop;
      Get_Line (F, Line, Last);
      Close (F);
      for K in Input'Range loop
         Input (K) := Hex (Line (2 * K - 1)) * 16 + Hex (Line (2 * K));
      end loop;
   end Fill;

   function Micros (Span : Time_Span; N : Positive) return String is
      Us : constant Long_Float := Long_Float (To_Duration (Span)) * 1.0E6
                                  / Long_Float (N);
      Hundredths : constant Natural := Natural (Us * 100.0);
   begin
      return Natural'Image (Hundredths / 100) & "."
        & (if Hundredths mod 100 < 10 then "0" else "")
        & Natural'Image (Hundredths mod 100) (2 .. Natural'Image (Hundredths mod 100)'Last);
   end Micros;

   N : constant := 20_000;
   Len, P_Len : Natural;
   Ok : Boolean;
   C_Len : Int;
   T0 : Time;
   Sink : Natural := 0;
begin
   for K in Case_Kind loop
      Fill (Ada.Command_Line.Argument (1),
            (if K = En then "english 1024" else "hungarian text 1k"));
      Compress (Input, Comp, Len, Ok);
      Decompress (Comp (1 .. Len), Plain, P_Len, Ok);
      if not Ok or else P_Len /= Input'Length or else Plain (1 .. P_Len) /= Input
      then
         Put_Line ("round trip failed");
         return;
      end if;

      T0 := Clock;
      for I in 1 .. N loop
         Compress (Input, Comp, Len, Ok);
         Sink := Sink + Len;
      end loop;
      Put_Line (K'Image & " 1024 B -> " & Len'Image & " B; SPARK compress  "
                & Micros (Clock - T0, N) & " us");
      T0 := Clock;
      for I in 1 .. N loop
         Decompress (Comp (1 .. Len), Plain, P_Len, Ok);
         Sink := Sink + P_Len;
      end loop;
      Put_Line (K'Image & "                 SPARK decompress"
                & Micros (Clock - T0, N) & " us");
      T0 := Clock;
      for I in 1 .. N loop
         C_Len := Ref_Compress (Input'Address, 1024, C_Comp'Address);
         Sink := Sink + Natural (C_Len);
      end loop;
      Put_Line (K'Image & "                 C compress      "
                & Micros (Clock - T0, N) & " us");
      T0 := Clock;
      for I in 1 .. N loop
         C_Len := Ref_Decompress (Comp'Address, Int (Len), C_Out'Address);
         Sink := Sink + Natural (C_Len);
      end loop;
      Put_Line (K'Image & "                 C decompress    "
                & Micros (Clock - T0, N) & " us");
   end loop;
   if Sink = 0 then
      Put_Line ("?");
   end if;
end Bench_Unishox;

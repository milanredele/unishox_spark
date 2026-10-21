--  Copyright 2026 The FreedomChat authors
--
--  Licensed under the Apache License, Version 2.0 (the "License");
--  you may not use this file except in compliance with the License.
--  You may obtain a copy of the License at
--
--      http://www.apache.org/licenses/LICENSE-2.0
--
--  Unless required by applicable law or agreed to in writing, software
--  distributed under the License is distributed on an "AS IS" BASIS,
--  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
--  See the License for the specific language governing permissions and
--  limitations under the License.
--
--  The code tables below are those of Unishox2 (unishox2.c / unishox2.h,
--  Copyright (C) 2020 Siara Logics (cc), Apache-2.0): the default preset
--  USX_HCODES_DFLT, USX_HCODE_LENS_DFLT, USX_FREQ_SEQ_DFLT and USX_TEMPLATES,
--  plus the fixed character sets, vertical codes, count and Unicode codes.

private package Unishox.Tables with SPARK_Mode, Pure is

   --  Horizontal sets / coder states (USX_ALPHA .. USX_DELTA)
   type Set_Kind is (Alpha, Sym, Num, Dict, Uni);
   subtype Char_Set is Set_Kind range Alpha .. Num;

   subtype Bit_Length is Natural range 0 .. 8;
   subtype Code_Length is Positive range 1 .. 8;
   subtype Num_Bits is Positive range 1 .. 21;
   subtype VCode_Index is Natural range 0 .. 27;

   --  USX_HCODES_DFLT / USX_HCODE_LENS_DFLT
   HCodes     : constant array (Set_Kind) of Byte :=
     (16#00#, 16#40#, 16#80#, 16#C0#, 16#E0#);
   HCode_Lens : constant array (Set_Kind) of Code_Length := (2, 2, 2, 3, 3);

   --  usx_sets: 0 where the character does not fit in a byte (special code)
   Sets : constant array (Char_Set, VCode_Index) of Byte :=
     (Alpha =>
        (0, 32, 101, 116, 97, 111, 105, 110, 115, 114, 108, 99, 100, 104,
         117, 112, 109, 98, 103, 119, 102, 121, 118, 107, 113, 106, 120,
         122),
      --   ' ' e   t   a   o   i   n   s   r   l   c  d   h
      --   u   p   m   b   g   w   f   y   v   k   q   j   x   z
      Sym =>
        (34, 123, 125, 95, 60, 62, 58, 10, 0, 91, 93, 92, 59, 39, 9, 64,
         42, 38, 63, 33, 94, 124, 13, 126, 96, 0, 0, 0),
      --   "  {  }  _  <  >  :  LF  -  [  ]  \  ;  '  TAB  @
      --   *  &  ?  !  ^  |  CR  ~  `
      Num =>
        (0, 44, 46, 48, 49, 57, 50, 53, 45, 47, 51, 52, 54, 55, 56, 40,
         41, 32, 61, 43, 36, 37, 35, 0, 0, 0, 0, 0));
      --   -  ,  .  0  1  9  2  5  -  /  3  4  6  7  8  (
      --   )  ' ' =  +  $  %  #

   --  usx_vcodes / usx_vcode_lens
   VCodes : constant array (VCode_Index) of Byte :=
     (16#00#, 16#40#, 16#60#, 16#80#, 16#90#, 16#A0#, 16#B0#,
      16#C0#, 16#D0#, 16#D8#, 16#E0#, 16#E4#, 16#E8#, 16#EC#,
      16#EE#, 16#F0#, 16#F2#, 16#F4#, 16#F6#, 16#F7#, 16#F8#,
      16#F9#, 16#FA#, 16#FB#, 16#FC#, 16#FD#, 16#FE#, 16#FF#);
   VCode_Lens : constant array (VCode_Index) of Bit_Length :=
     (2, 3, 3, 4, 4, 4, 4,
      4, 5, 5, 6, 6, 6, 7,
      7, 7, 7, 7, 8, 8, 8,
      8, 8, 8, 8, 8, 8, 8);

   --  A position in the sets: horizontal set and vertical code
   type Set_Code is record
      Set : Char_Set;
      V   : VCode_Index;
   end record;

   --  usx_code_94: printable ASCII 33 .. 126 (index = character - 33);
   --  upper-case letters share the code of their lower-case letter.
   Code_94 : constant array (0 .. 93) of Set_Code :=
     ((Sym, 19), (Sym, 0), (Num, 22), (Num, 20), (Num, 21), (Sym, 17),
      (Sym, 13), (Num, 15), (Num, 16), (Sym, 16), (Num, 19), (Num, 1),
      (Num, 8), (Num, 2), (Num, 9), (Num, 3), (Num, 4), (Num, 6),
      (Num, 10), (Num, 11), (Num, 7), (Num, 12), (Num, 13), (Num, 14),
      (Num, 5), (Sym, 6), (Sym, 12), (Sym, 4), (Num, 18), (Sym, 5),
      (Sym, 18), (Sym, 15), (Alpha, 4), (Alpha, 17), (Alpha, 11),
      (Alpha, 12), (Alpha, 2), (Alpha, 20), (Alpha, 18), (Alpha, 13),
      (Alpha, 6), (Alpha, 25), (Alpha, 23), (Alpha, 10), (Alpha, 16),
      (Alpha, 7), (Alpha, 5), (Alpha, 15), (Alpha, 24), (Alpha, 9),
      (Alpha, 8), (Alpha, 3), (Alpha, 14), (Alpha, 22), (Alpha, 19),
      (Alpha, 26), (Alpha, 21), (Alpha, 27), (Sym, 9), (Sym, 11),
      (Sym, 10), (Sym, 20), (Sym, 3), (Sym, 24), (Alpha, 4), (Alpha, 17),
      (Alpha, 11), (Alpha, 12), (Alpha, 2), (Alpha, 20), (Alpha, 18),
      (Alpha, 13), (Alpha, 6), (Alpha, 25), (Alpha, 23), (Alpha, 10),
      (Alpha, 16), (Alpha, 7), (Alpha, 5), (Alpha, 15), (Alpha, 24),
      (Alpha, 9), (Alpha, 8), (Alpha, 3), (Alpha, 14), (Alpha, 22),
      (Alpha, 19), (Alpha, 26), (Alpha, 21), (Alpha, 27), (Sym, 1),
      (Sym, 21), (Sym, 2), (Sym, 23));

   --  Special codes
   RPT_Code     : constant Set_Code := (Num, 26);
   Term_V       : constant VCode_Index := 27;    --  TERM_CODE (Num, 27)
   LF_Code      : constant Set_Code := (Sym, 7);
   CRLF_Code    : constant Set_Code := (Sym, 8);
   CR_Code      : constant Set_Code := (Sym, 22);
   Tab_Code     : constant Set_Code := (Sym, 14);
   Num_Spc_V    : constant VCode_Index := 17;    --  NUM_SPC_CODE (Num, 17)

   --  USX_FREQ_SEQ_DFLT and usx_freq_codes
   subtype Freq_Index is Natural range 0 .. 5;
   type Freq_Text is array (1 .. 4) of Byte;
   type Freq_Seq is record
      Len  : Positive range 1 .. 4;
      Text : Freq_Text;
   end record;
   --  {"\": \"", "\": ", "</", "=\"", "\":\"", "://"}
   Freq_Seqs : constant array (Freq_Index) of Freq_Seq :=
     ((4, (34, 58, 32, 34)),
      (3, (34, 58, 32, 0)),
      (2, (60, 47, 0, 0)),
      (2, (61, 34, 0, 0)),
      (4, (34, 58, 58, 34)),
      (3, (58, 47, 47, 0)));
   Freq_Codes : constant array (Freq_Index) of Set_Code :=
     ((Sym, 25), (Sym, 26), (Sym, 27), (Num, 23), (Num, 24), (Num, 25));

   --  USX_TEMPLATES (the fifth entry is NULL)
   subtype Template_Index is Natural range 0 .. 3;
   type Template is record
      Len  : Positive range 1 .. 24;
      Text : String (1 .. 24);
   end record;
   Templates : constant array (Template_Index) of Template :=
     ((24, "tfff-of-tfTtf:rf:rf.fffZ"),
      (10, "tfff-of-tf              "),
      (14, "(fff) fff-ffff          "),
      (8,  "tf:rf:rf                "));

   --  Counts: count_bit_lens, count_adder, count_codes (prefix part)
   subtype Level is Natural range 0 .. 4;
   Count_Bit_Lens : constant array (Level) of Num_Bits := (2, 4, 7, 11, 16);
   Count_Adder    : constant array (Level) of Positive range 1 .. 67732 :=
     (4, 20, 148, 2196, 67732);
   Count_Prefix     : constant array (Level) of Byte :=
     (16#00#, 16#80#, 16#C0#, 16#E0#, 16#F0#);
   Count_Prefix_Len : constant array (Level) of Bit_Length := (1, 2, 3, 4, 4);
   Max_Count : constant := 67731;

   --  Unicode deltas: uni_bit_len, uni_adder, codes (prefix part)
   Uni_Bit_Len    : constant array (Level) of Num_Bits := (6, 12, 14, 16, 21);
   Uni_Adder      : constant array (Level) of Natural range 0 .. 86080 :=
     (0, 64, 4160, 20544, 86080);
   Uni_Till       : constant array (Level) of Positive :=
     (64, 4160, 20544, 86080, 2183232);
   Uni_Prefix     : constant array (Level) of Byte :=
     (16#00#, 16#80#, 16#C0#, 16#E0#, 16#F0#);
   Uni_Prefix_Len : constant array (Level) of Bit_Length := (1, 2, 3, 4, 5);

   --  usx_vcode_lookup split into code length and vertical position
   type VCode_Entry is record
      Len : Positive range 1 .. 8;
      V   : VCode_Index;
   end record;
   VCode_Lookup : constant array (0 .. 35) of VCode_Entry :=
     ((2, 0), (2, 0), (3, 1), (3, 2),
      (4, 3), (4, 4), (4, 5), (4, 6),
      (4, 7), (4, 7), (5, 8), (5, 9),
      (6, 10), (6, 10), (6, 11), (6, 11),
      (6, 12), (6, 12), (7, 13), (7, 14),
      (7, 15), (7, 15), (7, 16), (7, 16),
      (7, 17), (7, 17), (8, 18), (8, 19),
      (8, 20), (8, 21), (8, 22), (8, 23),
      (8, 24), (8, 25), (8, 26), (8, 27));

   --  len_masks / usx_mask
   Masks : constant array (1 .. 8) of Byte :=
     (16#80#, 16#C0#, 16#E0#, 16#F0#, 16#F8#, 16#FC#, 16#FE#, 16#FF#);

end Unishox.Tables;

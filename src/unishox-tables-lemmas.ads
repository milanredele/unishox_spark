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
--  Static consistency facts of the code tables (Unishox.Tables), proved
--  by GNATprove: the facts a decoding-inverse argument rests on. Ghost
--  code only: nothing of this unit is compiled without -gnata.

package Unishox.Tables.Lemmas with Ghost, SPARK_Mode => On is

   --  2 ** N as a table of literals: the provers look up an entry where
   --  they would have to unfold a power with a non-static exponent (and
   --  powers in the aggregate would bring the power axioms everywhere)
   Pow2 : constant array (0 .. 24) of Positive :=
     (1, 2, 4, 8, 16, 32, 64, 128, 256, 512, 1024, 2048,
      4096, 8192, 16_384, 32_768, 65_536, 131_072, 262_144,
      524_288, 1_048_576, 2_097_152, 4_194_304, 8_388_608, 16_777_216);

   procedure Lemma_Pow2
   with Global => null,
        Post   => Pow2 (0) = 1
                  and then (for all N in 1 .. 24 => Pow2 (N) = 2 * Pow2 (N - 1));

   --  The masks keep the Len most significant bits
   procedure Lemma_Masks
   with Global => null,
        Post   => (for all I in Masks'Range =>
                     Natural (Masks (I)) = 256 - Pow2 (8 - I));

   --  Counts: level I codes Count in Base (I) .. Count_Adder (I) - 1 as
   --  Count - Base (I) in Count_Bit_Lens (I) bits after the unary prefix
   --  of I ones, then a zero (no zero after the four ones of the last
   --  level: getStepCodeIdx stops at its limit 4).
   function Count_Base (I : Level) return Natural is
     (if I = 0 then 0 else Count_Adder (I - 1));

   procedure Lemma_Count_Levels
   with Global => null,
        Post   =>
          (for all I in Level =>
             Count_Adder (I) - Count_Base (I) = Pow2 (Count_Bit_Lens (I))
             and then Natural (Count_Prefix (I)) = 256 - Pow2 (8 - I)
             and then Count_Prefix_Len (I) = Natural'Min (I + 1, 4))
          and then Count_Adder (Level'Last) = Max_Count + 1;

   --  Unicode deltas: level I codes Diff in Uni_Adder (I) .. Uni_Till (I)
   --  - 1 as Diff - Uni_Adder (I) in Uni_Bit_Len (I) bits after the unary
   --  prefix of I ones, then a zero (getStepCodeIdx with limit 5), and
   --  the levels cover every code point difference.
   procedure Lemma_Uni_Levels
   with Global => null,
        Post   =>
          Uni_Adder (0) = 0
          and then (for all I in Level =>
                      Uni_Till (I) - Uni_Adder (I) = Pow2 (Uni_Bit_Len (I))
                      and then (if I > 0 then Uni_Adder (I) = Uni_Till (I - 1))
                      and then Natural (Uni_Prefix (I)) = 256 - Pow2 (8 - I)
                      and then Uni_Prefix_Len (I) = I + 1)
          and then Uni_Till (Level'Last) > 16#1F_FFFF#;

   --  The horizontal codes are left-aligned and prefix-free
   procedure Lemma_HCodes
   with Global => null,
        Post   =>
          (for all P in Set_Kind =>
             (HCodes (P) and Masks (HCode_Lens (P))) = HCodes (P))
          and then
          (for all P in Set_Kind =>
             (for all Q in Set_Kind =>
                (if P /= Q and then HCode_Lens (P) <= HCode_Lens (Q)
                 then (HCodes (Q) and Masks (HCode_Lens (P))) /= HCodes (P))));

   --  The vertical codes are left-aligned and prefix-free
   function VCode_Prefix_Free (V, W : VCode_Index) return Boolean is
     (V = W or else VCode_Lens (V) > VCode_Lens (W)
      or else (VCodes (W) and Masks (VCode_Lens (V))) /= VCodes (V))
   with Pre => VCode_Lens (V) >= 1;

   procedure Lemma_VCodes
   with Global => null,
        Post   =>
          (for all V in VCode_Index =>
             VCode_Lens (V) >= 2
             and then (VCodes (V) and Masks (VCode_Lens (V))) = VCodes (V))
          and then
          (for all V in VCode_Index =>
             (for all W in VCode_Index => VCode_Prefix_Free (V, W)));

   --  readVCodeIdx: the entry of VCode_Lookup that the next 8 bits C select
   --  (usx_vsections / usx_vsection_pos / usx_vsection_mask)
   function VSection_Idx (C : Byte) return Natural is
     (if C <= 16#7F# then Natural (C) mod 128 / 32
      elsif C <= 16#BF# then 4 + Natural (C) mod 64 / 16
      elsif C <= 16#DF# then 8 + Natural (C) mod 32 / 8
      elsif C <= 16#EF# then 12 + Natural (C) mod 16 / 2
      else 20 + Natural (C) mod 16)
   with Post => VSection_Idx'Result in VCode_Lookup'Range;

   --  The entry selected by C is a vertical code that C starts with
   function Lookup_Sound (C : Byte) return Boolean is
     (VCode_Lookup (VSection_Idx (C)).Len
        = VCode_Lens (VCode_Lookup (VSection_Idx (C)).V)
      and then (C and Masks (VCode_Lookup (VSection_Idx (C)).Len))
                 = VCodes (VCode_Lookup (VSection_Idx (C)).V));

   procedure Lemma_VCode_Lookup
   with Global => null,
        Post   =>
          (for all C in Byte => Lookup_Sound (C))
          and then (for all V in VCode_Index =>
                      VCode_Lookup (VSection_Idx (VCodes (V))).V = V);

   --  usx_code_94 agrees with usx_sets: the code of printable ASCII
   --  character K + 33 is a position of that character, except for the
   --  upper-case letters, which share the code of their lower-case letter
   function Code_94_Char (K : Natural) return Byte is
     (if K + 33 in 65 .. 90 then Byte (K + 65) else Byte (K + 33))
   with Pre => K <= 93;

   function Code_94_Ok (K : Natural) return Boolean is
     (Sets (Code_94 (K).Set, Code_94 (K).V) = Code_94_Char (K))
   with Pre => K <= 93;

   procedure Lemma_Code_94
   with Global => null,
        Post   =>
          (for all K in Code_94'Range => Code_94_Ok (K))
          and then (for all K in 32 .. 57 => Code_94 (K) = Code_94 (K + 32));

   --  The special codes and the space codes
   procedure Lemma_Special_Codes
   with Global => null,
        Post   =>
          Sets (Alpha, 1) = 32 and then Sets (Num, Num_Spc_V) = 32
          and then Sets (LF_Code.Set, LF_Code.V) = 10
          and then Sets (CR_Code.Set, CR_Code.V) = 13
          and then Sets (Tab_Code.Set, Tab_Code.V) = 9
          and then Sets (CRLF_Code.Set, CRLF_Code.V) = 0
          and then Sets (RPT_Code.Set, RPT_Code.V) = 0
          and then Sets (Num, Term_V) = 0
          and then (for all I in Freq_Index =>
                      Sets (Freq_Codes (I).Set, Freq_Codes (I).V) = 0);

end Unishox.Tables.Lemmas;

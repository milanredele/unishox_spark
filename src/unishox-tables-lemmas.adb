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

package body Unishox.Tables.Lemmas with SPARK_Mode => On is

   procedure Lemma_Pow2 is null;

   procedure Lemma_Masks is null;

   --  The two loops below have no invariant on purpose: GNATprove unrolls
   --  them, so each level is proved with its table entries.

   procedure Lemma_Count_Levels is
   begin
      for I in Level loop
         pragma Assert
           (Count_Adder (I) - Count_Base (I) = Pow2 (Count_Bit_Lens (I)));
      end loop;
   end Lemma_Count_Levels;

   procedure Lemma_Uni_Levels is
   begin
      for I in Level loop
         pragma Assert (Uni_Till (I) >= Uni_Adder (I));
         pragma Assert (Uni_Till (I) - Uni_Adder (I) = Pow2 (Uni_Bit_Len (I)));
         pragma Assert (if I > 0 then Uni_Adder (I) = Uni_Till (I - 1));
      end loop;
   end Lemma_Uni_Levels;

   procedure Lemma_HCodes is null;

   procedure Lemma_VCodes is
   begin
      for V in VCode_Index loop
         for W in VCode_Index loop
            pragma Assert (VCode_Prefix_Free (V, W));
            pragma Loop_Invariant
              (for all X in VCode_Index'First .. W => VCode_Prefix_Free (V, X));
         end loop;
         pragma Loop_Invariant
           (for all U in VCode_Index'First .. V =>
              (for all X in VCode_Index => VCode_Prefix_Free (U, X)));
      end loop;
   end Lemma_VCodes;

   procedure Lemma_VCode_Lookup is
   begin
      for C in Byte loop
         pragma Assert (Lookup_Sound (C));
         pragma Loop_Invariant
           (for all D in Byte'First .. C => Lookup_Sound (D));
      end loop;
   end Lemma_VCode_Lookup;

   procedure Lemma_Code_94 is
   begin
      for K in Code_94'Range loop
         pragma Assert (Code_94_Ok (K));
         pragma Loop_Invariant
           (for all J in Code_94'First .. K => Code_94_Ok (J));
      end loop;
   end Lemma_Code_94;

   procedure Lemma_Special_Codes is null;

end Unishox.Tables.Lemmas;

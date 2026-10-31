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
--  Port of unishox2.c (Copyright (C) 2020 Siara Logics (cc), Apache-2.0).
--  The structure follows the reference function by function; comments
--  name the C function or macro each part corresponds to.

with Unishox.Tables; use Unishox.Tables;

package body Unishox with SPARK_Mode is

   use type Interfaces.Unsigned_32;

   subtype U32 is Interfaces.Unsigned_32;

   Nice_Len : constant := 5;                    --  NICE_LEN
   Max_Bits : constant := 8 * Max_Length;

   subtype Code_Point is Natural range 0 .. 16#1F_FFFF#;

   function Ch (C : Character) return Byte is (Character'Pos (C));

   ---------------------------------------------------------------------
   --  Input access (0-based offsets)
   ---------------------------------------------------------------------

   function Get (Input : Byte_Array; K : Natural) return Byte is
     (Input (Input'First + K))
   with Pre => K < Input'Length;

   --  in[k] where k may be len: the reference reads the C string
   --  terminator there, so a position past the end reads as 0.
   function Get_Or_Zero (Input : Byte_Array; K : Natural) return Byte is
     (if K < Input'Length then Input (Input'First + K) else 0);

   function Is_Upper_Letter (B : Byte) return Boolean is
     (B in Ch ('A') .. Ch ('Z'));

   ---------------------------------------------------------------------
   --  Bit writer (append_bits)
   ---------------------------------------------------------------------

   type Bit_Writer is record
      Pos    : Natural := 0;     --  bits written
      Failed : Boolean := False;  --  output limit reached
   end record;

   --  The bytes from the first one not yet started by W are zero.
   --  Zero_Tail and the frame functions below cost a pass over Output
   --  (and Output'Old a copy of it) at every check, so the contracts that
   --  use them are stated as Contract_Cases and loop invariants with the
   --  policy Ignore: proved by GNATprove, not executed in the checks build.
   pragma Assertion_Policy (Contract_Cases => Ignore);

   function Zero_Tail (Output : Byte_Array; W : Bit_Writer) return Boolean is
     (for all I in Output'Range =>
        (if I - Output'First >= (W.Pos + 7) / 8 then Output (I) = 0))
   with Ghost, Pre => W.Pos <= Max_Bits;

   --  Output equals Old at the offsets below Upto
   function Same_Below (Old, Output : Byte_Array; Upto : Natural)
     return Boolean
   is (for all I in Output'Range =>
         (if I - Output'First < Upto then Output (I) = Old (I)))
   with Ghost, Pre => Old'First = Output'First and then Old'Last = Output'Last;

   --  Output equals Old at the offsets from From on
   function Same_From (Old, Output : Byte_Array; From : Natural)
     return Boolean
   is (for all I in Output'Range =>
         (if I - Output'First >= From then Output (I) = Old (I)))
   with Ghost, Pre => Old'First = Output'First and then Old'Last = Output'Last;

   --  W advanced from Old by at most Bits bits within the limit of Limit
   --  bytes: nothing changes once failed, and a failure means that the
   --  bits did not fit (the exact counterpart is in the Post of
   --  Append_Bits and Append_Value).
   function Wrote (Old, W : Bit_Writer; Bits, Limit : Natural) return Boolean
   is (W.Pos <= 8 * Limit and then Old.Pos <= W.Pos
       and then W.Pos <= Old.Pos + Bits
       and then (if Old.Failed then W = Old)
       and then (if W.Failed and then not Old.Failed
                 then Old.Pos + Bits > 8 * Limit))
   with Ghost, Pre => Bits <= 256 * Max_Length and then Limit <= Max_Length;

   --  Expansion bound: an encoding step that consumes K input bytes writes
   --  at most Byte_Bits * K bits
   Byte_Bits : constant := 32;

   --  append_bits: appends the Len most significant bits of Code at bit
   --  W.Pos, without writing at or beyond byte Limit. Once a write would
   --  pass the limit, W.Failed is set and further calls do nothing (the
   --  reference returns -1 and its callers stop).
   procedure Append_Bits
     (Output : in out Byte_Array;
      Limit  : Natural;
      W      : in out Bit_Writer;
      Code   : Byte;
      Len    : Bit_Length)
   with
     Pre  => Limit <= Output'Length and then Output'Length <= Max_Length
       and then W.Pos <= 8 * Limit,
     Post => W.Pos <= 8 * Limit and then W.Pos >= W.Pos'Old
       and then (if W.Failed'Old then W = W'Old)
       and then (if not W.Failed'Old
                 then W.Failed = (W.Pos'Old + Len > 8 * Limit))
       and then (if not W.Failed then W.Pos = W.Pos'Old + Len)
       and then Wrote (W'Old, W, Len, Limit),
     Contract_Cases =>
       (others => Same_Below (Output'Old, Output, W.Pos'Old / 8)
                    and then Same_From (Output'Old, Output, Limit)
                    and then (if Zero_Tail (Output'Old, W'Old)
                              then Zero_Tail (Output, W)))
   is
      Cur   : Natural;
      Idx   : Natural;
      A     : Byte;
      First : Natural;
   begin
      if W.Failed or else Len = 0 then
         return;
      end if;
      Cur := W.Pos mod 8;
      Idx := W.Pos / 8;
      if Idx >= Limit then
         W.Failed := True;
         return;
      end if;
      A := Interfaces.Shift_Right (Code and Masks (Len), Cur);
      if Cur = 0 then
         Output (Output'First + Idx) := A;
      else
         Output (Output'First + Idx) := Output (Output'First + Idx) or A;
      end if;
      if Len + Cur > 8 then
         First := 8 - Cur;
         W.Pos := W.Pos + First;
         Idx := Idx + 1;
         if Idx >= Limit then
            W.Failed := True;
            return;
         end if;
         Output (Output'First + Idx) :=
           Interfaces.Shift_Left (Code, First) and Masks (Len - First);
         W.Pos := W.Pos + (Len - First);
      else
         W.Pos := W.Pos + Len;
      end if;
   end Append_Bits;

   --  2 ** N as a table of literals (as Pow2 of Unishox.Tables.Lemmas,
   --  which this Pure unit cannot depend on): the provers look up an entry
   --  where they would have to unfold a power with a non-static exponent
   Pow2 : constant array (0 .. 24) of Positive :=
     (1, 2, 4, 8, 16, 32, 64, 128, 256, 512, 1024, 2048,
      4096, 8192, 16_384, 32_768, 65_536, 131_072, 262_144,
      524_288, 1_048_576, 2_097_152, 4_194_304, 8_388_608, 16_777_216)
   with Ghost;

   --  Value fits in N bits (Value < 2 ** N)
   function Fits (Value, N : Natural) return Boolean is
     (N in 1 .. 24 and then Value < Pow2 (N))
   with Ghost;

   --  Appends the N low-order bits of Value, most significant first
   --  (the multi-call sequences of encodeCount and encodeUnicode). Value
   --  must fit in N bits, so no wrong table entry can drop bits silently.
   procedure Append_Value
     (Output : in out Byte_Array;
      W      : in out Bit_Writer;
      Value  : Natural;
      N      : Natural)
   with
     Pre  => Output'Length <= Max_Length and then W.Pos <= 8 * Output'Length
       and then Fits (Value, N),
     Post => W.Pos <= 8 * Output'Length and then W.Pos >= W.Pos'Old
       and then (if W.Failed'Old then W = W'Old)
       and then (if not W.Failed'Old
                 then W.Failed = (W.Pos'Old + N > 8 * Output'Length))
       and then (if not W.Failed then W.Pos = W.Pos'Old + N)
       and then Wrote (W'Old, W, N, Output'Length),
     Contract_Cases =>
       (others => (if Zero_Tail (Output'Old, W'Old) then Zero_Tail (Output, W)))
   is
      pragma Assertion_Policy (Loop_Invariant => Ignore);   --  see Zero_Tail
      Left : Natural := N;
      Take : Natural;
      B    : Byte;
   begin
      for Chunk in 1 .. 3 loop
         pragma Loop_Invariant
           (Left <= N and then Left <= 8 * (4 - Chunk)
            and then W.Pos <= 8 * Output'Length
            and then W.Pos >= W.Pos'Loop_Entry
            and then (if W.Failed'Loop_Entry then W = W'Loop_Entry)
            and then (if not W.Failed
                      then W.Pos = W.Pos'Loop_Entry + (N - Left))
            and then (if W.Failed and then not W.Failed'Loop_Entry
                      then W.Pos'Loop_Entry + N > 8 * Output'Length)
            and then (if Zero_Tail (Output'Loop_Entry, W'Loop_Entry)
                      then Zero_Tail (Output, W)));
         exit when Left = 0;
         Take := Natural'Min (8, Left);
         B := Byte (Interfaces.Shift_Right (U32 (Value), Left - Take) mod 256);
         Append_Bits (Output, Output'Length, W,
                      Interfaces.Shift_Left (B, 8 - Take), Take);
         Left := Left - Take;
      end loop;
   end Append_Value;

   ---------------------------------------------------------------------
   --  Encoder
   ---------------------------------------------------------------------

   type Encoder is record
      W            : Bit_Writer;
      State        : Set_Kind := Alpha;
      Is_All_Upper : Boolean := False;
      Prev_Uni     : Code_Point := 0;
   end record;

   function Valid_Pos (Output : Byte_Array; E : Encoder) return Boolean is
     (Output'Length <= Max_Length and then E.W.Pos <= 8 * Output'Length);

   procedure Put_Bits
     (Output : in out Byte_Array; E : in out Encoder; Code : Byte;
      Len : Bit_Length)
   with Pre  => Valid_Pos (Output, E),
        Post => Valid_Pos (Output, E) and E.State = E.State'Old
                and E.Is_All_Upper = E.Is_All_Upper'Old
                and E.Prev_Uni = E.Prev_Uni'Old
                and Wrote (E.W'Old, E.W, Len, Output'Length),
        Contract_Cases =>
          (others => (if Zero_Tail (Output'Old, E.W'Old)
                      then Zero_Tail (Output, E.W)))
   is
   begin
      Append_Bits (Output, Output'Length, E.W, Code, Len);
   end Put_Bits;

   --  Length of the switch code from State
   function Switch_Bits (State : Set_Kind) return Natural is
     (if State = Uni then 7 else 2)
   with Ghost;

   --  append_switch_code
   procedure Append_Switch_Code
     (Output : in out Byte_Array; Limit : Natural; W : in out Bit_Writer;
      State : Set_Kind)
   with Pre  => Limit <= Output'Length and then Output'Length <= Max_Length
                and then W.Pos <= 8 * Limit,
        Post => W.Pos <= 8 * Limit
                and then Wrote (W'Old, W, Switch_Bits (State), Limit),
        Contract_Cases =>
          (others => Same_From (Output'Old, Output, Limit)
                       and then (if Zero_Tail (Output'Old, W'Old)
                                 then Zero_Tail (Output, W)))
   is
   begin
      if State = Uni then
         Append_Bits (Output, Limit, W, 16#F8#, 5);   --  UNI_STATE_SPL_CODE
         Append_Bits (Output, Limit, W, 16#80#, 2);   --  UNI_STATE_SW_CODE
      else
         Append_Bits (Output, Limit, W, 16#00#, 2);   --  SW_CODE
      end if;
   end Append_Switch_Code;

   --  append_switch_code followed by the horizontal code of Set
   procedure Switch_To
     (Output : in out Byte_Array; E : in out Encoder; Set : Set_Kind)
   with Pre  => Valid_Pos (Output, E),
        Post => Valid_Pos (Output, E) and E.State = E.State'Old
                and E.Is_All_Upper = E.Is_All_Upper'Old
                and E.Prev_Uni = E.Prev_Uni'Old
                and Wrote (E.W'Old, E.W, Switch_Bits (E.State) + HCode_Lens (Set),
                           Output'Length),
        Contract_Cases =>
          (others => (if Zero_Tail (Output'Old, E.W'Old)
                      then Zero_Tail (Output, E.W)))
   is
   begin
      Append_Switch_Code (Output, Output'Length, E.W, E.State);
      Append_Bits (Output, Output'Length, E.W, HCodes (Set), HCode_Lens (Set));
   end Switch_To;

   --  Bits that append_code writes for Code from State
   function Code_Bits (State : Set_Kind; Code : Set_Code) return Natural is
     ((if (Code.Set = Alpha and then State = Alpha)
         or else (Code.Set = Num and then State = Num)
       then 0
       else Switch_Bits (State) + HCode_Lens (Code.Set))
      + VCode_Lens (Code.V))
   with Ghost;

   --  append_code
   procedure Append_Code
     (Output : in out Byte_Array; E : in out Encoder; Code : Set_Code)
   with Pre  => Valid_Pos (Output, E),
        Post => Valid_Pos (Output, E)
                and E.Is_All_Upper = E.Is_All_Upper'Old
                and E.Prev_Uni = E.Prev_Uni'Old
                and Wrote (E.W'Old, E.W, Code_Bits (E.State'Old, Code),
                           Output'Length),
        Contract_Cases =>
          (others => (if Zero_Tail (Output'Old, E.W'Old)
                      then Zero_Tail (Output, E.W)))
   is
   begin
      case Code.Set is
         when Alpha =>
            if E.State /= Alpha then
               Switch_To (Output, E, Alpha);
               E.State := Alpha;
            end if;
         when Sym =>
            Switch_To (Output, E, Sym);
         when Num =>
            if E.State /= Num then
               Switch_To (Output, E, Num);
               if Sets (Num, Code.V) in Ch ('0') .. Ch ('9') then
                  E.State := Num;
               end if;
            end if;
      end case;
      Put_Bits (Output, E, VCodes (Code.V), VCode_Lens (Code.V));
   end Append_Code;

   --  Bits that encodeCount writes for Count (prefix and value)
   function Count_Bits (Count : Natural) return Natural is
     (if Count < 4 then 3 elsif Count < 20 then 6 elsif Count < 148 then 10
      elsif Count < 2196 then 15 else 20)
   with Ghost;

   --  encodeCount
   procedure Encode_Count
     (Output : in out Byte_Array; E : in out Encoder; Count : Natural)
   with Pre  => Valid_Pos (Output, E) and then Count <= Max_Count,
        Post => Valid_Pos (Output, E) and E.State = E.State'Old
                and E.Is_All_Upper = E.Is_All_Upper'Old
                and E.Prev_Uni = E.Prev_Uni'Old
                and Wrote (E.W'Old, E.W, Count_Bits (Count), Output'Length),
        Contract_Cases =>
          (others => (if Zero_Tail (Output'Old, E.W'Old)
                      then Zero_Tail (Output, E.W)))
   is
   begin
      for I in Level loop
         if Count < Count_Adder (I) then
            Put_Bits (Output, E, Count_Prefix (I), Count_Prefix_Len (I));
            Append_Value
              (Output, E.W,
               Count - (if I = 0 then 0 else Count_Adder (I - 1)),
               Count_Bit_Lens (I));
            return;
         end if;
      end loop;
   end Encode_Count;

   --  encodeUnicode
   procedure Encode_Unicode
     (Output : in out Byte_Array; E : in out Encoder;
      Code, Prev : Code_Point)
   with Pre  => Valid_Pos (Output, E),
        Post => Valid_Pos (Output, E) and E.State = E.State'Old
                and E.Is_All_Upper = E.Is_All_Upper'Old
                and E.Prev_Uni = E.Prev_Uni'Old
                and Wrote (E.W'Old, E.W, 27, Output'Length),
        Contract_Cases =>
          (others => (if Zero_Tail (Output'Old, E.W'Old)
                      then Zero_Tail (Output, E.W)))
   is
      Diff : constant Natural := abs (Code - Prev);
   begin
      for I in Level loop
         if Diff < Uni_Till (I) then
            Put_Bits (Output, E, Uni_Prefix (I), Uni_Prefix_Len (I));
            Put_Bits (Output, E, (if Prev > Code then 16#80# else 0), 1);
            Append_Value
              (Output, E.W, Diff - Uni_Adder (I), Uni_Bit_Len (I));
            return;
         end if;
      end loop;
   end Encode_Unicode;

   --  append_nibble_escape
   procedure Append_Nibble_Escape
     (Output : in out Byte_Array; E : in out Encoder)
   with Pre  => Valid_Pos (Output, E),
        Post => Valid_Pos (Output, E) and E.State = E.State'Old
                and E.Is_All_Upper = E.Is_All_Upper'Old
                and E.Prev_Uni = E.Prev_Uni'Old
                and Wrote (E.W'Old, E.W, Switch_Bits (E.State) + 4,
                           Output'Length),
        Contract_Cases =>
          (others => (if Zero_Tail (Output'Old, E.W'Old)
                      then Zero_Tail (Output, E.W)))
   is
   begin
      Switch_To (Output, E, Num);
      Put_Bits (Output, E, 0, 2);
   end Append_Nibble_Escape;

   --  Number of bytes of the UTF-8 sequence of a code point read by UTF8_At
   function UTF8_Length (Code : Code_Point) return Natural is
     (if Code < 16#800# then 2 elsif Code < 16#1_0000# then 3 else 4);

   --  readUTF8: the code point at K (0 if none, overlong or truncated).
   --  Like the reference, surrogates and values up to 16#1F_FFFF# pass.
   function UTF8_At (Input : Byte_Array; K : Natural) return Code_Point
   with Pre  => K <= Input'Length,
        Post => UTF8_At'Result = 0
                or else K + UTF8_Length (UTF8_At'Result) <= Input'Length
   is
      N  : constant Natural := Input'Length;
      B0 : Byte;
      V  : Natural;
   begin
      if K >= N then
         return 0;
      end if;
      B0 := Get (Input, K);
      if K + 1 < N and then B0 / 32 = 6
        and then Get (Input, K + 1) / 64 = 2
      then
         V := Natural (B0 mod 32) * 64 + Natural (Get (Input, K + 1) mod 64);
         return (if V >= 16#80# then V else 0);
      elsif K + 2 < N and then B0 / 16 = 14
        and then Get (Input, K + 1) / 64 = 2
        and then Get (Input, K + 2) / 64 = 2
      then
         V := (Natural (B0 mod 16) * 64 + Natural (Get (Input, K + 1) mod 64))
                * 64 + Natural (Get (Input, K + 2) mod 64);
         return (if V >= 16#800# then V else 0);
      elsif K + 3 < N and then B0 / 8 = 30
        and then Get (Input, K + 1) / 64 = 2
        and then Get (Input, K + 2) / 64 = 2
        and then Get (Input, K + 3) / 64 = 2
      then
         V := ((Natural (B0 mod 8) * 64 + Natural (Get (Input, K + 1) mod 64))
                 * 64 + Natural (Get (Input, K + 2) mod 64))
                * 64 + Natural (Get (Input, K + 3) mod 64);
         return (if V >= 16#1_0000# then V else 0);
      end if;
      return 0;
   end UTF8_At;

   type Nibble_Kind is (Nib_Num, Nib_Hex_Lower, Nib_Hex_Upper, Nib_Not);

   --  getNibbleType
   function Nibble_Type (B : Byte) return Nibble_Kind is
     (if B in Ch ('0') .. Ch ('9') then Nib_Num
      elsif B in Ch ('a') .. Ch ('f') then Nib_Hex_Lower
      elsif B in Ch ('A') .. Ch ('F') then Nib_Hex_Upper
      else Nib_Not);

   --  getBaseCode
   function Base_Code (B : Byte) return Byte is
     (if B in Ch ('0') .. Ch ('9') then (B - Ch ('0')) * 16
      elsif B in Ch ('A') .. Ch ('F') then (B - Ch ('A') + 10) * 16
      elsif B in Ch ('a') .. Ch ('f') then (B - Ch ('a') + 10) * 16
      else 0);

   --  Contract shared by the encoding steps: L is the reference's l, the
   --  index of the current input byte; a step that handles input leaves L
   --  on the last byte it consumed (the main loop then adds one).
   --  matchOccurance
   procedure Match_Occurrence
     (Input   : Byte_Array;
      L       : in out Natural;
      Output  : in out Byte_Array;
      E       : in out Encoder;
      Handled : out Boolean)
   with Pre  => Input'Length <= Max_Length
                and then L < Input'Length
                and then L + Nice_Len <= Input'Length
                and then Valid_Pos (Output, E),
        Post => Valid_Pos (Output, E) and then L >= L'Old
                and then L < Input'Length
                and then E.Is_All_Upper = E.Is_All_Upper'Old
                and then E.Prev_Uni = E.Prev_Uni'Old
                and then (if Handled
                          then Wrote (E.W'Old, E.W, Byte_Bits * (L - L'Old + 1),
                                      Output'Length)
                          else L = L'Old and then E.W = E.W'Old),
        Contract_Cases =>
          (others => (if Zero_Tail (Output'Old, E.W'Old)
                      then Zero_Tail (Output, E.W)))
   is
      Len          : constant Natural := Input'Length;
      K            : Natural;
      Longest_Len  : Natural := 0;
      Longest_Dist : Natural := 0;
      Need         : Natural;
   begin
      Handled := False;
      if L < Nice_Len then
         return;
      end if;
      for J in reverse 0 .. L - Nice_Len loop
         pragma Loop_Invariant (L + Longest_Len + Nice_Len <= Len
                                and Longest_Dist <= L);
         Need := Longest_Len + Nice_Len;
         --  Shortcut, not in the reference but exact: a candidate can only
         --  replace the longest match if the bytes at offsets 0 and Need
         --  match (and are in range); otherwise the reference computes a
         --  match length it then discards.
         if L + Need < Len and then J + Need < L
           and then Get (Input, L) = Get (Input, J)
           and then Get (Input, L + Need) = Get (Input, J + Need)
         then
            K := L;
            while K < Len and then J + (K - L) < L
              and then Get (Input, K) = Get (Input, J + (K - L))
            loop
               pragma Loop_Invariant (K >= L and K < Len);
               pragma Loop_Variant (Increases => K);
               K := K + 1;
            end loop;
            --  Skip partial UTF-8 matches. Stopping at L + Nice_Len - 1
            --  gives the same outcome as the reference's unbounded loop:
            --  below that point no match is possible either way.
            while K >= L + Nice_Len and then Get_Or_Zero (Input, K) / 64 = 2
            loop
               pragma Loop_Invariant (K <= Len);
               pragma Loop_Variant (Decreases => K);
               K := K - 1;
            end loop;
            if K - L > Nice_Len - 1 and then K - L - Nice_Len > Longest_Len
            then
               Longest_Len := K - L - Nice_Len;
               Longest_Dist := L - J - Nice_Len + 1;
            end if;
         end if;
      end loop;
      if Longest_Len > 0 then
         Switch_To (Output, E, Dict);
         Encode_Count (Output, E, Longest_Len);
         Encode_Count (Output, E, Longest_Dist);
         L := L + Longest_Len + Nice_Len - 1;
         Handled := True;
      end if;
   end Match_Occurrence;

   --  Runs of five or more equal bytes (RPT_CODE)
   procedure Try_Repeat
     (Input   : Byte_Array;
      L       : in out Natural;
      Output  : in out Byte_Array;
      E       : in out Encoder;
      Handled : out Boolean)
   with Pre  => L < Input'Length and then Input'Length <= Max_Length
                and then Valid_Pos (Output, E),
        Post => Valid_Pos (Output, E) and then L >= L'Old
                and then L < Input'Length
                and then E.Is_All_Upper = E.Is_All_Upper'Old
                and then E.Prev_Uni = E.Prev_Uni'Old
                and then (if Handled
                          then Wrote (E.W'Old, E.W, Byte_Bits * (L - L'Old + 1),
                                      Output'Length)
                          else L = L'Old and then E.W = E.W'Old),
        Contract_Cases =>
          (others => (if Zero_Tail (Output'Old, E.W'Old)
                      then Zero_Tail (Output, E.W)))
   is
      Len : constant Natural := Input'Length;
      C   : Byte;
      R   : Natural;
   begin
      Handled := False;
      if L = 0 or else L + 4 >= Len then
         return;
      end if;
      C := Get (Input, L);
      if C = Get (Input, L - 1) and then C = Get (Input, L + 1)
        and then C = Get (Input, L + 2) and then C = Get (Input, L + 3)
      then
         R := L + 4;
         while R < Len and then Get (Input, R) = C loop
            pragma Loop_Invariant (R >= L + 4 and R < Len);
            pragma Loop_Variant (Increases => R);
            R := R + 1;
         end loop;
         Append_Code (Output, E, RPT_Code);
         Encode_Count (Output, E, R - L - 4);
         L := R - 1;
         Handled := True;
      end if;
   end Try_Repeat;

   --  UUIDs. As in the reference, the dash positions are compared with
   --  absolute offsets 8, 13, 18 and 23, so only a UUID at the start of
   --  the input is recognised.
   procedure Try_Uuid
     (Input   : Byte_Array;
      L       : in out Natural;
      Output  : in out Byte_Array;
      E       : in out Encoder;
      Handled : out Boolean)
   with Pre  => L < Input'Length and then Input'Length <= Max_Length
                and then Valid_Pos (Output, E),
        Post => Valid_Pos (Output, E) and then L >= L'Old
                and then L < Input'Length
                and then E.Is_All_Upper = E.Is_All_Upper'Old
                and then E.Prev_Uni = E.Prev_Uni'Old
                and then (if Handled
                          then Wrote (E.W'Old, E.W, Byte_Bits * (L - L'Old + 1),
                                      Output'Length)
                          else L = L'Old and then E.W = E.W'Old),
        Contract_Cases =>
          (others => (if Zero_Tail (Output'Old, E.W'Old)
                      then Zero_Tail (Output, E.W)))
   is
      pragma Assertion_Policy (Loop_Invariant => Ignore);   --  see Zero_Tail
      Len      : constant Natural := Input'Length;
      Hex_Type : Nibble_Kind := Nib_Num;
      Nib      : Nibble_Kind;
      C        : Byte;
      Uid_Pos  : Natural;
   begin
      Handled := False;
      if L + 36 > Len then
         return;
      end if;
      if Get (Input, L + 8) /= Ch ('-') or else Get (Input, L + 13) /= Ch ('-')
        or else Get (Input, L + 18) /= Ch ('-')
        or else Get (Input, L + 23) /= Ch ('-')
      then
         return;
      end if;
      Uid_Pos := L;
      while Uid_Pos < L + 36 loop
         pragma Loop_Invariant (Uid_Pos >= L and Uid_Pos < L + 36
                                and Hex_Type /= Nib_Not);
         pragma Loop_Variant (Increases => Uid_Pos);
         C := Get (Input, Uid_Pos);
         if not (C = Ch ('-') and then Uid_Pos in 8 | 13 | 18 | 23) then
            Nib := Nibble_Type (C);
            exit when Nib = Nib_Not;
            if Nib /= Nib_Num then
               exit when Hex_Type /= Nib_Num and then Hex_Type /= Nib;
               Hex_Type := Nib;
            end if;
         end if;
         Uid_Pos := Uid_Pos + 1;
      end loop;
      if Uid_Pos /= L + 36 then
         return;
      end if;
      Append_Nibble_Escape (Output, E);
      if Hex_Type = Nib_Hex_Lower then
         Put_Bits (Output, E, 16#C0#, 3);
      else
         Put_Bits (Output, E, 16#F0#, 5);
      end if;
      for P in L .. L + 35 loop
         pragma Loop_Invariant (Valid_Pos (Output, E)
                                and E.Is_All_Upper = E.Is_All_Upper'Loop_Entry
                                and E.Prev_Uni = E.Prev_Uni'Loop_Entry
                                and (if Zero_Tail (Output'Loop_Entry, E.W'Loop_Entry)
                                     then Zero_Tail (Output, E.W)));
         pragma Loop_Invariant
           (Wrote (E.W'Loop_Entry, E.W, 4 * (P - L), Output'Length));
         if Get (Input, P) /= Ch ('-') then
            Put_Bits (Output, E, Base_Code (Get (Input, P)), 4);
         end if;
      end loop;
      L := L + 35;
      Handled := True;
   end Try_Uuid;

   --  Hexadecimal runs and long decimal runs
   procedure Try_Hex
     (Input   : Byte_Array;
      L       : in out Natural;
      Output  : in out Byte_Array;
      E       : in out Encoder;
      Handled : out Boolean)
   with Pre  => L < Input'Length and then Input'Length <= Max_Length
                and then Valid_Pos (Output, E),
        Post => Valid_Pos (Output, E) and then L >= L'Old
                and then L < Input'Length
                and then E.Is_All_Upper = E.Is_All_Upper'Old
                and then E.Prev_Uni = E.Prev_Uni'Old
                and then (if Handled
                          then Wrote (E.W'Old, E.W, Byte_Bits * (L - L'Old + 1),
                                      Output'Length)
                          else L = L'Old and then E.W = E.W'Old),
        Contract_Cases =>
          (others => (if Zero_Tail (Output'Old, E.W'Old)
                      then Zero_Tail (Output, E.W)))
   is
      pragma Assertion_Policy (Loop_Invariant => Ignore);   --  see Zero_Tail
      Len      : constant Natural := Input'Length;
      Hex_Type : Nibble_Kind := Nib_Num;
      Hex_Len  : Natural := 0;
      Nib      : Nibble_Kind;
   begin
      Handled := False;
      if L + 5 >= Len then
         return;
      end if;
      while L + Hex_Len < Len loop
         pragma Loop_Invariant (L + Hex_Len < Len and Hex_Type /= Nib_Not);
         pragma Loop_Variant (Increases => Hex_Len);
         Nib := Nibble_Type (Get (Input, L + Hex_Len));
         exit when Nib = Nib_Not;
         if Nib /= Nib_Num then
            exit when Hex_Type /= Nib_Num and then Hex_Type /= Nib;
            Hex_Type := Nib;
         end if;
         Hex_Len := Hex_Len + 1;
      end loop;
      if Hex_Len > 10 and then Hex_Type = Nib_Num then
         Hex_Type := Nib_Hex_Lower;
      end if;
      if Hex_Type in Nib_Hex_Lower | Nib_Hex_Upper and then Hex_Len > 3 then
         Append_Nibble_Escape (Output, E);
         if Hex_Type = Nib_Hex_Lower then
            Put_Bits (Output, E, 16#80#, 2);
         else
            Put_Bits (Output, E, 16#E0#, 4);
         end if;
         Encode_Count (Output, E, Hex_Len);
         for P in L .. L + Hex_Len - 1 loop
            pragma Loop_Invariant (Valid_Pos (Output, E)
                                   and E.Is_All_Upper = E.Is_All_Upper'Loop_Entry
                                   and E.Prev_Uni = E.Prev_Uni'Loop_Entry
                                   and (if Zero_Tail (Output'Loop_Entry, E.W'Loop_Entry)
                                        then Zero_Tail (Output, E.W)));
            pragma Loop_Invariant
              (Wrote (E.W'Loop_Entry, E.W, 4 * (P - L), Output'Length));
            Put_Bits (Output, E, Base_Code (Get (Input, P)), 4);
         end loop;
         L := L + Hex_Len - 1;
         Handled := True;
      end if;
   end Try_Hex;

   --  Does template character T accept input byte B?
   function Template_Accepts (T : Character; B : Byte) return Boolean is
     (case T is
         when 'f' => Nibble_Type (B) in Nib_Hex_Lower | Nib_Num,
         when 'F' => Nibble_Type (B) in Nib_Hex_Upper | Nib_Num,
         when 'r' => B in Ch ('0') .. Ch ('7'),
         when 't' => B in Ch ('0') .. Ch ('3'),
         when 'o' => B in Ch ('0') .. Ch ('1'),
         when others => B = Ch (T));

   --  USX_TEMPLATES (ISO date/time, ISO date, US phone number, ISO time)
   procedure Try_Template
     (Input   : Byte_Array;
      L       : in out Natural;
      Output  : in out Byte_Array;
      E       : in out Encoder;
      Handled : out Boolean)
   with Pre  => L < Input'Length and then Input'Length <= Max_Length
                and then Valid_Pos (Output, E),
        Post => Valid_Pos (Output, E) and then L >= L'Old
                and then L < Input'Length
                and then E.Is_All_Upper = E.Is_All_Upper'Old
                and then E.Prev_Uni = E.Prev_Uni'Old
                and then (if Handled
                          then Wrote (E.W'Old, E.W, Byte_Bits * (L - L'Old + 1),
                                      Output'Length)
                          else L = L'Old and then E.W = E.W'Old),
        Contract_Cases =>
          (others => (if Zero_Tail (Output'Old, E.W'Old)
                      then Zero_Tail (Output, E.W)))
   is
      pragma Assertion_Policy (Loop_Invariant => Ignore);   --  see Zero_Tail
      Len  : constant Natural := Input'Length;
      Tlen : Positive;
      J    : Natural;
      T    : Character;
   begin
      Handled := False;
      for I in Template_Index loop
         pragma Loop_Invariant
           (E = E'Loop_Entry and then L = L'Loop_Entry
            and then Output = Output'Loop_Entry and then not Handled);
         Tlen := Templates (I).Len;
         pragma Assert (Tlen >= 8);   --  so a match covers at least 6 bytes
         J := 0;
         while J < Tlen and then L + J < Len
           and then Template_Accepts (Templates (I).Text (J + 1),
                                      Get (Input, L + J))
         loop
            pragma Loop_Invariant (J < Tlen and L + J < Len);
            pragma Loop_Variant (Increases => J);
            J := J + 1;
         end loop;
         --  (float) j / rem > 0.66; exact for the template lengths 24, 10,
         --  14 and 8, where no j / rem lies within 1/100 of 0.66.
         if J * 50 > Tlen * 33 then
            Append_Nibble_Escape (Output, E);
            Put_Bits (Output, E, 0, 1);
            Put_Bits (Output, E, Count_Prefix (I), Count_Prefix_Len (I));
            Encode_Count (Output, E, Tlen - J);
            for K in 0 .. J - 1 loop
               pragma Loop_Invariant (Valid_Pos (Output, E)
                                      and E.Is_All_Upper = E.Is_All_Upper'Loop_Entry
                                      and E.Prev_Uni = E.Prev_Uni'Loop_Entry
                                      and (if Zero_Tail (Output'Loop_Entry, E.W'Loop_Entry)
                                           then Zero_Tail (Output, E.W)));
               pragma Loop_Invariant
                 (Wrote (E.W'Loop_Entry, E.W, 4 * K, Output'Length));
               T := Templates (I).Text (K + 1);
               case T is
                  when 'f' | 'F' =>
                     Put_Bits (Output, E, Base_Code (Get (Input, L + K)), 4);
                  when 'r' =>
                     Put_Bits (Output, E,
                               (Get (Input, L + K) - Ch ('0')) * 32, 3);
                  when 't' =>
                     Put_Bits (Output, E,
                               (Get (Input, L + K) - Ch ('0')) * 64, 2);
                  when 'o' =>
                     Put_Bits (Output, E,
                               (Get (Input, L + K) - Ch ('0')) * 128, 1);
                  when others =>
                     null;
               end case;
            end loop;
            L := L + J - 1;
            Handled := True;
            return;
         end if;
      end loop;
   end Try_Template;

   --  USX_FREQ_SEQ_DFLT
   procedure Try_Freq_Seq
     (Input   : Byte_Array;
      L       : in out Natural;
      Output  : in out Byte_Array;
      E       : in out Encoder;
      Handled : out Boolean)
   with Pre  => L < Input'Length and then Input'Length <= Max_Length
                and then Valid_Pos (Output, E),
        Post => Valid_Pos (Output, E) and then L >= L'Old
                and then L < Input'Length
                and then E.Is_All_Upper = E.Is_All_Upper'Old
                and then E.Prev_Uni = E.Prev_Uni'Old
                and then (if Handled
                          then Wrote (E.W'Old, E.W, Byte_Bits * (L - L'Old + 1),
                                      Output'Length)
                          else L = L'Old and then E.W = E.W'Old),
        Contract_Cases =>
          (others => (if Zero_Tail (Output'Old, E.W'Old)
                      then Zero_Tail (Output, E.W)))
   is
      Len : constant Natural := Input'Length;
      N   : Positive;
   begin
      Handled := False;
      for I in Freq_Index loop
         N := Freq_Seqs (I).Len;
         if L + N <= Len
           and then (for all K in 0 .. N - 1 =>
                       Get (Input, L + K) = Freq_Seqs (I).Text (K + 1))
         then
            Append_Code (Output, E, Freq_Codes (I));
            L := L + N - 1;
            Handled := True;
            return;
         end if;
      end loop;
   end Try_Freq_Seq;

   --  The per-character part of the main loop of unishox2_compress_lines
   procedure Encode_Char
     (Input  : Byte_Array;
      L      : in out Natural;
      Output : in out Byte_Array;
      E      : in out Encoder)
   with Pre  => L < Input'Length and then Input'Length <= Max_Length
                and then Valid_Pos (Output, E),
        Post => Valid_Pos (Output, E) and then L >= L'Old
                and then L < Input'Length
                and then Wrote (E.W'Old, E.W, Byte_Bits * (L - L'Old + 1),
                                Output'Length),
        Contract_Cases =>
          (others => (if Zero_Tail (Output'Old, E.W'Old)
                      then Zero_Tail (Output, E.W)))
   is
      pragma Assertion_Policy (Loop_Invariant => Ignore);   --  see Zero_Tail
      Len       : constant Natural := Input'Length;
      C_In      : constant Byte := Get (Input, L);
      C_Next    : Byte := 0;
      Is_Upper  : constant Boolean := Is_Upper_Letter (C_In);
      Cp        : Code_Point;
      Bin_Count : Natural;
      Idx       : Natural;
   begin
      if not Is_Upper and then E.Is_All_Upper then
         E.Is_All_Upper := False;
         Switch_To (Output, E, Alpha);
         E.State := Alpha;
      end if;
      if Is_Upper and then not E.Is_All_Upper then
         if E.State = Num then
            Switch_To (Output, E, Alpha);
            E.State := Alpha;
         end if;
         Switch_To (Output, E, Alpha);
         if E.State = Uni then
            E.State := Alpha;
            Switch_To (Output, E, Alpha);
         end if;
      end if;
      if L + 1 < Len then
         C_Next := Get (Input, L + 1);
      end if;

      if C_In in 32 .. 126 then
         if Is_Upper and then not E.Is_All_Upper and then L + 4 < Len
           and then (for all K in L .. L + 4 =>
                       Is_Upper_Letter (Get (Input, K)))
         then
            Switch_To (Output, E, Alpha);
            E.State := Alpha;
            E.Is_All_Upper := True;
         end if;
         if E.State = Uni and then C_In in Ch (' ') | Ch ('.') | Ch (',') then
            Put_Bits (Output, E, 16#F8#, 5);         --  UNI_STATE_SPL_CODE
            if C_In = Ch (',') then
               Put_Bits (Output, E, 16#C0#, 3);
            elsif C_In = Ch ('.') then
               Put_Bits (Output, E, 16#E0#, 4);
            else
               Put_Bits (Output, E, 16#00#, 1);
            end if;
            return;
         end if;
         if C_In = 32 then
            if E.State = Num then
               Put_Bits (Output, E, VCodes (Num_Spc_V), VCode_Lens (Num_Spc_V));
            else
               Put_Bits (Output, E, VCodes (1), VCode_Lens (1));
            end if;
         else
            if E.Is_All_Upper and then Is_Upper then
               Idx := Natural (C_In) - 1;
            else
               Idx := Natural (C_In) - 33;
            end if;
            --  A letter is coded in the Alpha set (expansion bound)
            pragma Assert (if Is_Upper then Code_94 (Idx).Set = Alpha);
            Append_Code (Output, E, Code_94 (Idx));
         end if;
      elsif C_In = 13 and then C_Next = 10 then
         Append_Code (Output, E, CRLF_Code);
         L := L + 1;
      elsif C_In = 10 then
         if E.State = Uni then
            Put_Bits (Output, E, 16#F8#, 5);
            Put_Bits (Output, E, 16#F0#, 4);
         else
            Append_Code (Output, E, LF_Code);
         end if;
      elsif C_In = 13 then
         Append_Code (Output, E, CR_Code);
      elsif C_In = 9 then
         Append_Code (Output, E, Tab_Code);
      else
         Cp := UTF8_At (Input, L);
         if Cp /= 0 then
            if E.State /= Uni then
               if UTF8_At (Input, L + UTF8_Length (Cp)) /= 0 then
                  if E.State /= Alpha then
                     Switch_To (Output, E, Alpha);
                  end if;
                  Switch_To (Output, E, Alpha);
                  Put_Bits (Output, E, VCodes (1), VCode_Lens (1));
                  E.State := Uni;
               else
                  Switch_To (Output, E, Uni);
               end if;
            end if;
            Encode_Unicode (Output, E, Cp, E.Prev_Uni);
            E.Prev_Uni := Cp;
            L := L + UTF8_Length (Cp) - 1;
         else
            Bin_Count := 1;
            for Bi in L + 1 .. Len - 1 loop
               pragma Loop_Invariant (Bin_Count = Bi - L);
               exit when UTF8_At (Input, Bi) /= 0;
               exit when Bi + 4 < Len
                 and then Get (Input, Bi) = Get (Input, Bi - 1)
                 and then Get (Input, Bi) = Get (Input, Bi + 1)
                 and then Get (Input, Bi) = Get (Input, Bi + 2)
                 and then Get (Input, Bi) = Get (Input, Bi + 3);
               Bin_Count := Bin_Count + 1;
            end loop;
            Append_Nibble_Escape (Output, E);
            Put_Bits (Output, E, 16#F8#, 5);
            Encode_Count (Output, E, Bin_Count);
            for P in L .. L + Bin_Count - 1 loop
               pragma Loop_Invariant
                 (Valid_Pos (Output, E)
                  and (if Zero_Tail (Output'Loop_Entry, E.W'Loop_Entry)
                       then Zero_Tail (Output, E.W)));
               pragma Loop_Invariant
                 (Wrote (E.W'Loop_Entry, E.W, 8 * (P - L), Output'Length));
               Put_Bits (Output, E, Get (Input, P), 8);
            end loop;
            L := L + Bin_Count - 1;
         end if;
      end if;
   end Encode_Char;

   --------------
   -- Compress --
   --------------

   procedure Compress
     (Input         : Byte_Array;
      Output        : out Byte_Array;
      Output_Length : out Natural;
      Success       : out Boolean)
   is
      pragma Assertion_Policy (Loop_Invariant => Ignore);   --  see Zero_Tail
      Len     : constant Natural := Input'Length;
      E       : Encoder;
      Init    : constant Bit_Writer := (Pos => 0, Failed => False)
      with Ghost;
      L       : Natural := 0;
      Handled : Boolean;
      Rst     : Natural;
   begin
      Output := (others => 0);
      Put_Bits (Output, E, 16#FF#, 1);              --  UNISHOX_MAGIC_BITS
      while L < Len and then not E.W.Failed loop
         pragma Loop_Invariant (Valid_Pos (Output, E) and Zero_Tail (Output, E.W));
         pragma Loop_Invariant
           (L < Len and then Wrote (Init, E.W, 1 + Byte_Bits * L, Output'Length));
         pragma Loop_Variant (Increases => L);
         Handled := False;
         if L + Nice_Len <= Len then
            Match_Occurrence (Input, L, Output, E, Handled);
         end if;
         if not Handled then
            Try_Repeat (Input, L, Output, E, Handled);
         end if;
         if not Handled then
            Try_Uuid (Input, L, Output, E, Handled);
         end if;
         if not Handled then
            Try_Hex (Input, L, Output, E, Handled);
         end if;
         if not Handled then
            Try_Template (Input, L, Output, E, Handled);
         end if;
         if not Handled then
            Try_Freq_Seq (Input, L, Output, E, Handled);
         end if;
         if not Handled then
            Encode_Char (Input, L, Output, E);
         end if;
         L := L + 1;
      end loop;

      if E.W.Failed then
         Output := (others => 0);
         Output_Length := 0;
         Success := False;
         return;
      end if;

      --  append_final_bits, limited to the bytes already started: the
      --  terminator (at least 8 bits) is cut off at the end of the last
      --  byte, and the "fill with the last bit" step is never reached.
      Rst := (E.W.Pos + 7) / 8;
      if E.State /= Num then
         Append_Switch_Code (Output, Rst, E.W, E.State);
         Append_Bits (Output, Rst, E.W, HCodes (Num), HCode_Lens (Num));
      end if;
      pragma Warnings (GNATprove, Off, """E.W"" is set by ""Append_Bits""",
                       Reason => "the writer is not needed after the terminator");
      Append_Bits (Output, Rst, E.W, VCodes (Term_V), VCode_Lens (Term_V));
      pragma Warnings (GNATprove, On, """E.W"" is set by ""Append_Bits""");
      Output_Length := Rst;
      Success := True;
   end Compress;

   ---------------------------------------------------------------------
   --  Decoder
   ---------------------------------------------------------------------

   --  Bit positions: readers may step up to 8 bits past the end of the
   --  input before they notice it, as the reference does.
   function Valid_Bits (Input : Byte_Array; Bit_No : Natural) return Boolean
   is (Input'Length <= Max_Length and then Bit_No <= 8 * Input'Length + 8);

   --  readBit
   function Read_Bit (Input : Byte_Array; Bit_No : Natural) return Boolean is
     ((Input (Input'First + Bit_No / 8)
         and Interfaces.Shift_Right (Byte'(16#80#), Bit_No mod 8)) /= 0)
   with Pre => Input'Length <= Max_Length and then Bit_No < 8 * Input'Length;

   --  read8bitCode: the next 8 bits, padded with ones past the end
   function Read_8bit_Code (Input : Byte_Array; Bit_No : Natural) return Byte
   with Pre => Input'Length <= Max_Length and then Bit_No < 8 * Input'Length
   is
      Shift    : constant Natural := Bit_No mod 8;
      Char_Pos : constant Natural := Bit_No / 8;
      Code     : Byte :=
        Interfaces.Shift_Left (Input (Input'First + Char_Pos), Shift);
   begin
      if Char_Pos + 1 < Input'Length then
         Code := Code or Interfaces.Shift_Right
           (Input (Input'First + Char_Pos + 1), 8 - Shift);
      else
         Code := Code or Interfaces.Shift_Right (Byte'(16#FF#), 8 - Shift);
      end if;
      return Code;
   end Read_8bit_Code;

   --  readVCodeIdx (usx_vsections / usx_vcode_lookup)
   procedure Read_VCode
     (Input  : Byte_Array;
      Bit_No : in out Natural;
      V      : out VCode_Index;
      Valid  : out Boolean)
   with Pre  => Valid_Bits (Input, Bit_No),
        Post => Valid_Bits (Input, Bit_No)
                and then (if Valid then Bit_No > Bit_No'Old
                                    and then Bit_No <= 8 * Input'Length)
   is
      Code : Byte;
      Idx  : Natural;
      Ent  : VCode_Entry;
   begin
      V := 0;
      Valid := False;
      if Bit_No >= 8 * Input'Length then
         return;
      end if;
      Code := Read_8bit_Code (Input, Bit_No);
      if Code <= 16#7F# then
         Idx := Natural (Code) mod 128 / 32;
      elsif Code <= 16#BF# then
         Idx := 4 + Natural (Code) mod 64 / 16;
      elsif Code <= 16#DF# then
         Idx := 8 + Natural (Code) mod 32 / 8;
      elsif Code <= 16#EF# then
         Idx := 12 + Natural (Code) mod 16 / 2;
      else
         Idx := 20 + Natural (Code) mod 16;
      end if;
      Ent := VCode_Lookup (Idx);
      Bit_No := Bit_No + Ent.Len;
      if Bit_No > 8 * Input'Length then
         return;
      end if;
      V := Ent.V;
      Valid := True;
   end Read_VCode;

   --  readHCodeIdx
   procedure Read_HCode
     (Input  : Byte_Array;
      Bit_No : in out Natural;
      H      : out Set_Kind;
      Valid  : out Boolean)
   with Pre  => Valid_Bits (Input, Bit_No),
        Post => Valid_Bits (Input, Bit_No)
                and then (if Valid then Bit_No > Bit_No'Old)
   is
      Code : Byte;
   begin
      H := Alpha;
      Valid := False;
      if Bit_No >= 8 * Input'Length then
         return;
      end if;
      Code := Read_8bit_Code (Input, Bit_No);
      for P in Set_Kind loop
         if (Code and Masks (HCode_Lens (P))) = HCodes (P) then
            Bit_No := Bit_No + HCode_Lens (P);
            H := P;
            Valid := True;
            return;
         end if;
      end loop;
   end Read_HCode;

   --  getStepCodeIdx
   procedure Get_Step_Code_Idx
     (Input  : Byte_Array;
      Bit_No : in out Natural;
      Limit  : Positive;
      Idx    : out Natural;
      Valid  : out Boolean)
   with Pre  => Valid_Bits (Input, Bit_No) and then Limit <= 5,
        Post => Valid_Bits (Input, Bit_No) and then Idx <= Limit
                and then (if Valid then Bit_No > Bit_No'Old
                                    and then Bit_No <= 8 * Input'Length)
   is
   begin
      Idx := 0;
      Valid := False;
      while Bit_No < 8 * Input'Length and then Read_Bit (Input, Bit_No) loop
         pragma Loop_Invariant (Idx < Limit
                                and then Bit_No < 8 * Input'Length
                                and then Bit_No = Bit_No'Loop_Entry + Idx);
         pragma Loop_Variant (Increases => Bit_No);
         Idx := Idx + 1;
         Bit_No := Bit_No + 1;
         if Idx = Limit then
            Valid := True;
            return;
         end if;
      end loop;
      if Bit_No >= 8 * Input'Length then
         return;
      end if;
      Bit_No := Bit_No + 1;
      Valid := True;
   end Get_Step_Code_Idx;

   --  getNumFromBits: Count bits from Bit_No, most significant first; not
   --  Valid if the input ends first. Bit_No is not advanced.
   procedure Get_Num_From_Bits
     (Input  : Byte_Array;
      Bit_No : Natural;
      Count  : Natural;
      Value  : out Natural;
      Valid  : out Boolean)
   with Pre  => Valid_Bits (Input, Bit_No) and then Count <= 21,
        Post => Value <= 16#1F_FFFF#
                and then (if Valid then Bit_No + Count <= 8 * Input'Length)
   is
      W : U32 := 0;
      P : Natural;
   begin
      Value := 0;
      Valid := False;
      if Bit_No + Count > 8 * Input'Length then
         return;
      end if;
      Valid := True;
      if Count = 0 then
         return;
      end if;
      for K in 0 .. 3 loop
         P := Bit_No / 8 + K;
         W := Interfaces.Shift_Left (W, 8);
         if P < Input'Length then
            W := W or U32 (Input (Input'First + P));
         end if;
      end loop;
      Value := Natural
        (Interfaces.Shift_Right (Interfaces.Shift_Left (W, Bit_No mod 8),
                                 32 - Count) and 16#1F_FFFF#);
   end Get_Num_From_Bits;

   Max_Read_Count : constant := 16#1F_FFFF# + Max_Count + 1;

   --  readCount
   procedure Read_Count
     (Input  : Byte_Array;
      Bit_No : in out Natural;
      Count  : out Natural;
      Valid  : out Boolean)
   with Pre  => Valid_Bits (Input, Bit_No),
        Post => Valid_Bits (Input, Bit_No) and then Count <= Max_Read_Count
                and then (if Valid then Bit_No > Bit_No'Old
                                    and then Bit_No <= 8 * Input'Length)
   is
      Idx : Natural;
      V   : Natural;
      Ok  : Boolean;
   begin
      Count := 0;
      Valid := False;
      Get_Step_Code_Idx (Input, Bit_No, 4, Idx, Ok);
      if not Ok then
         return;
      end if;
      if Bit_No + Count_Bit_Lens (Idx) > 8 * Input'Length then
         return;
      end if;
      Get_Num_From_Bits (Input, Bit_No, Count_Bit_Lens (Idx), V, Ok);
      if not Ok then
         return;
      end if;
      Count := V + (if Idx = 0 then 0 else Count_Adder (Idx - 1));
      Bit_No := Bit_No + Count_Bit_Lens (Idx);
      Valid := True;
   end Read_Count;

   type Uni_Kind is (U_Invalid, U_Special, U_Delta);

   --  readUnicode: a special code (Spl 0 .. 4) or a signed delta
   procedure Read_Unicode
     (Input    : Byte_Array;
      Bit_No   : in out Natural;
      Kind     : out Uni_Kind;
      Spl      : out Natural;
      Negative : out Boolean;
      Mag      : out Natural)
   with Pre  => Valid_Bits (Input, Bit_No),
        Post => Valid_Bits (Input, Bit_No) and then Spl <= 4
                and then Mag <= 16#1F_FFFF# + 86080
                and then (if Kind /= U_Invalid then Bit_No > Bit_No'Old)
   is
      Idx : Natural;
      V   : Natural;
      Ok  : Boolean;
   begin
      Kind := U_Invalid;
      Spl := 0;
      Negative := False;
      Mag := 0;
      Get_Step_Code_Idx (Input, Bit_No, 5, Idx, Ok);
      if not Ok then
         return;
      end if;
      if Idx = 5 then
         Get_Step_Code_Idx (Input, Bit_No, 4, Idx, Ok);
         if Ok then
            Kind := U_Special;
            Spl := Idx;
         end if;
         return;
      end if;
      if Bit_No < 8 * Input'Length then
         Negative := Read_Bit (Input, Bit_No);
      end if;
      Bit_No := Bit_No + 1;
      if Bit_No + Uni_Bit_Len (Idx) > 8 * Input'Length then
         return;
      end if;
      Get_Num_From_Bits (Input, Bit_No, Uni_Bit_Len (Idx), V, Ok);
      if not Ok then
         return;
      end if;
      Mag := V + Uni_Adder (Idx);
      Bit_No := Bit_No + Uni_Bit_Len (Idx);
      Kind := U_Delta;
   end Read_Unicode;

   --  The bytes from offset OL on are zero (a pass over Output, so used
   --  in Contract_Cases and ignored loop invariants only, as Zero_Tail)
   function Dec_Zero_Tail (Output : Byte_Array; OL : Natural) return Boolean
   is (for all I in Output'Range =>
         (if I - Output'First >= OL then Output (I) = 0))
   with Ghost;

   --  Output is Old with bytes appended at offset Old_OL: OL did not go
   --  back, the bytes below Old_OL are unchanged and a zero tail stays
   function Appended
     (Old, Output : Byte_Array; Old_OL, OL : Natural) return Boolean
   is (OL >= Old_OL
       and then Same_Below (Old, Output, Old_OL)
       and then (if Dec_Zero_Tail (Old, Old_OL)
                 then Dec_Zero_Tail (Output, OL)))
   with Ghost, Pre => Old'First = Output'First and then Old'Last = Output'Last;

   --  DEC_OUTPUT_CHAR: Overflow is sticky; the caller reports failure
   procedure Put
     (Output   : in out Byte_Array;
      OL       : in out Natural;
      B        : Byte;
      Overflow : in out Boolean)
   with Pre  => OL <= Output'Length,
        Post => OL <= Output'Length
                and then (if Overflow'Old then Overflow)
                and then (if Overflow
                          then OL = OL'Old and then Output = Output'Old)
                and then (if Overflow and then not Overflow'Old
                          then OL'Old = Output'Length)
                and then (if not Overflow
                          then OL = OL'Old + 1
                            and then Output (Output'First + OL'Old) = B
                            and then (for all I in Output'Range =>
                                        (if I /= Output'First + OL'Old
                                         then Output (I) = Output'Old (I)))),
        Contract_Cases => (others => Appended (Output'Old, Output, OL'Old, OL))
   is
   begin
      if Overflow then
         return;
      end if;
      if OL >= Output'Length then
         Overflow := True;
         return;
      end if;
      Output (Output'First + OL) := B;
      OL := OL + 1;
   end Put;

   --  writeUTF8, for any 32-bit value (two's complement, as the int of
   --  the reference, which malformed input can make negative or large)
   procedure Write_UTF8
     (Output   : in out Byte_Array;
      OL       : in out Natural;
      Uni      : U32;
      Overflow : in out Boolean)
   with Pre  => OL <= Output'Length,
        Post => OL <= Output'Length,
        Contract_Cases => (others => Appended (Output'Old, Output, OL'Old, OL))
   is
      use Interfaces;
   begin
      if Uni >= 2 ** 31 or else Uni < 2 ** 11 then
         Put (Output, OL,
              Byte ((16#C0# + Shift_Right_Arithmetic (Uni, 6)) mod 256),
              Overflow);
         Put (Output, OL, Byte (16#80# + Uni mod 64), Overflow);
      elsif Uni < 2 ** 16 then
         Put (Output, OL, Byte ((16#E0# + Shift_Right (Uni, 12)) mod 256),
              Overflow);
         Put (Output, OL, Byte (16#80# + Shift_Right (Uni, 6) mod 64),
              Overflow);
         Put (Output, OL, Byte (16#80# + Uni mod 64), Overflow);
      else
         Put (Output, OL, Byte ((16#F0# + Shift_Right (Uni, 18)) mod 256),
              Overflow);
         Put (Output, OL, Byte (16#80# + Shift_Right (Uni, 12) mod 64),
              Overflow);
         Put (Output, OL, Byte (16#80# + Shift_Right (Uni, 6) mod 64),
              Overflow);
         Put (Output, OL, Byte (16#80# + Uni mod 64), Overflow);
      end if;
   end Write_UTF8;

   --  getHexChar
   function Hex_Char (Value : Natural; Upper : Boolean) return Byte is
     (if Value <= 9 then Ch ('0') + Byte (Value)
      elsif Upper then Byte ((Value - 10 + Character'Pos ('A')) mod 256)
      else Byte ((Value - 10 + Character'Pos ('a')) mod 256))
   with Pre => Value <= 16#1F_FFFF#;

   type Decoder is record
      Bit_No       : Natural := 1;     --  after UNISHOX_MAGIC_BIT_LEN
      OL           : Natural := 0;     --  bytes written
      DState       : Set_Kind := Alpha;
      H            : Set_Kind := Alpha;
      Is_All_Upper : Boolean := False;
      Prev_Uni     : U32 := 0;
      Overflow     : Boolean := False;  --  output did not fit
   end record;

   function Valid_Dec
     (Input, Output : Byte_Array; D : Decoder) return Boolean
   is (Valid_Bits (Input, D.Bit_No) and then D.OL <= Output'Length);

   type Rep_Status is (Rep_Ok, Rep_Invalid);

   --  decodeRepeat (without prev_lines). The copy has memmove semantics,
   --  as in the reference, also for malformed input where the source
   --  overlaps the bytes not yet written.
   procedure Decode_Repeat
     (Input  : Byte_Array;
      Output : in out Byte_Array;
      D      : in out Decoder;
      Status : out Rep_Status)
   with Pre  => Valid_Dec (Input, Output, D),
        Post => Valid_Dec (Input, Output, D)
                and then (if Status = Rep_Ok then D.Bit_No > D.Bit_No'Old),
        Contract_Cases =>
          (others => Appended (Output'Old, Output, D.OL'Old, D.OL))
   is
      pragma Assertion_Policy (Loop_Invariant => Ignore);   --  see Zero_Tail
      Count    : Natural;
      Dict_Len : Natural;
      Dist     : Natural;
      Ok       : Boolean;
      Dst      : Natural;
      Src      : Natural;
   begin
      Status := Rep_Invalid;
      Read_Count (Input, D.Bit_No, Count, Ok);
      if not Ok then
         return;
      end if;
      Dict_Len := Count + Nice_Len;
      Read_Count (Input, D.Bit_No, Count, Ok);
      if not Ok then
         return;
      end if;
      Dist := Count + Nice_Len - 1;
      if D.OL < Dist then
         return;
      end if;
      Status := Rep_Ok;
      if Dict_Len > Output'Length - D.OL then
         D.Overflow := True;
         return;
      end if;
      Dst := Output'First + D.OL;
      Src := Dst - Dist;
      --  Source before destination: copying backwards is a memmove
      for K in reverse 0 .. Dict_Len - 1 loop
         pragma Loop_Invariant
           (Same_Below (Output'Loop_Entry, Output, D.OL)
            and then Same_From (Output'Loop_Entry, Output, D.OL + Dict_Len));
         Output (Dst + K) := Output (Src + K);
      end loop;
      D.OL := D.OL + Dict_Len;
   end Decode_Repeat;

   type Step_Result is (Go_On, Stop);

   --  The nibble / template / binary escapes (h == USX_NUM && v == 0)
   procedure Decode_Num_Escape
     (Input  : Byte_Array;
      Output : in out Byte_Array;
      D      : in out Decoder;
      Result : out Step_Result)
   with Pre  => Valid_Dec (Input, Output, D),
        Post => Valid_Dec (Input, Output, D)
                and then (if Result = Go_On then D.Bit_No > D.Bit_No'Old),
        Contract_Cases =>
          (others => Appended (Output'Old, Output, D.OL'Old, D.OL))
   is
      pragma Assertion_Policy (Loop_Invariant => Ignore);   --  see Zero_Tail
      Idx    : Natural;
      T      : Natural;
      Ok     : Boolean;
      Count  : Natural;
      Tlen   : Positive;
      CT     : Character;
      N      : Natural;
      Raw    : Natural;
      Start  : constant Natural := D.Bit_No;
   begin
      Result := Stop;
      Get_Step_Code_Idx (Input, D.Bit_No, 5, Idx, Ok);
      if not Ok then
         return;
      end if;
      if Idx = 0 then
         --  Template
         Get_Step_Code_Idx (Input, D.Bit_No, 4, T, Ok);
         if not Ok then
            return;
         end if;
         Read_Count (Input, D.Bit_No, Count, Ok);
         if not Ok or else T = 4 then
            return;
         end if;
         Tlen := Templates (T).Len;
         if Count > Tlen then
            return;
         end if;
         for J in 1 .. Tlen - Count loop
            pragma Loop_Invariant (Valid_Dec (Input, Output, D)
                                   and then D.Bit_No > Start
                                   and then D.Bit_No <= 8 * Input'Length);
            pragma Loop_Invariant
              (Appended (Output'Loop_Entry, Output, D.OL'Loop_Entry, D.OL));
            CT := Templates (T).Text (J);
            if CT in 'f' | 'r' | 't' | 'o' | 'F' then
               N := (case CT is
                        when 'f' | 'F' => 4,
                        when 'r'       => 3,
                        when 't'       => 2,
                        when others    => 1);
               Get_Num_From_Bits (Input, D.Bit_No, N, Raw, Ok);
               if not Ok then
                  return;
               end if;
               Put (Output, D.OL, Hex_Char (Raw, Upper => CT /= 'f'),
                    D.Overflow);
               D.Bit_No := D.Bit_No + N;
            else
               Put (Output, D.OL, Ch (CT), D.Overflow);
            end if;
            exit when D.Overflow;
         end loop;
      elsif Idx = 5 then
         --  Binary bytes
         Read_Count (Input, D.Bit_No, Count, Ok);
         if not Ok or else Count = 0 then
            return;
         end if;
         for K in 1 .. Count loop
            pragma Loop_Invariant (Valid_Dec (Input, Output, D)
                                   and then D.Bit_No > Start
                                   and then D.Bit_No <= 8 * Input'Length);
            pragma Loop_Invariant
              (Appended (Output'Loop_Entry, Output, D.OL'Loop_Entry, D.OL));
            Get_Num_From_Bits (Input, D.Bit_No, 8, Raw, Ok);
            if not Ok then
               return;
            end if;
            Put (Output, D.OL, Byte (Raw mod 256), D.Overflow);
            D.Bit_No := D.Bit_No + 8;
            exit when D.Overflow;
         end loop;
      else
         --  Hexadecimal nibbles (1, 3) or UUID (2, 4); lower case below 3
         if Idx = 2 or else Idx = 4 then
            Count := 32;
         else
            Read_Count (Input, D.Bit_No, Count, Ok);
            if not Ok or else Count = 0 then
               return;
            end if;
         end if;
         for K in reverse 1 .. Count loop
            pragma Loop_Invariant (Valid_Dec (Input, Output, D)
                                   and then D.Bit_No > Start
                                   and then D.Bit_No <= 8 * Input'Length);
            pragma Loop_Invariant
              (Appended (Output'Loop_Entry, Output, D.OL'Loop_Entry, D.OL));
            Get_Num_From_Bits (Input, D.Bit_No, 4, Raw, Ok);
            if not Ok then
               return;
            end if;
            Put (Output, D.OL, Hex_Char (Raw, Upper => Idx >= 3), D.Overflow);
            if (Idx = 2 or else Idx = 4) and then K in 25 | 21 | 17 | 13 then
               Put (Output, D.OL, Ch ('-'), D.Overflow);
            end if;
            D.Bit_No := D.Bit_No + 4;
            exit when D.Overflow;
         end loop;
      end if;
      if D.DState = Uni then
         D.H := Uni;
      end if;
      Result := Go_On;
   end Decode_Num_Escape;

   --  Appends a USX_FREQ_SEQ_DFLT entry
   procedure Put_Freq_Seq
     (Output : in out Byte_Array; D : in out Decoder; I : Freq_Index)
   with Pre  => D.OL <= Output'Length,
        Post => D.OL <= Output'Length and then D.Bit_No = D.Bit_No'Old,
        Contract_Cases =>
          (others => Appended (Output'Old, Output, D.OL'Old, D.OL))
   is
      pragma Assertion_Policy (Loop_Invariant => Ignore);   --  see Zero_Tail
   begin
      for K in 1 .. Freq_Seqs (I).Len loop
         pragma Loop_Invariant (D.OL <= Output'Length
                                and then D.Bit_No = D.Bit_No'Loop_Entry);
         pragma Loop_Invariant
           (Appended (Output'Loop_Entry, Output, D.OL'Loop_Entry, D.OL));
         Put (Output, D.OL, Freq_Seqs (I).Text (K), D.Overflow);
      end loop;
   end Put_Freq_Seq;

   --  One iteration of the main loop of unishox2_decompress_lines.
   --  Go_On is the reference's "continue", Stop its "break".
   procedure Decode_Step
     (Input  : Byte_Array;
      Output : in out Byte_Array;
      D      : in out Decoder;
      Result : out Step_Result)
   with Pre  => Valid_Dec (Input, Output, D)
                and then D.Bit_No < 8 * Input'Length,
        Post => Valid_Dec (Input, Output, D)
                and then (if Result = Go_On then D.Bit_No > D.Bit_No'Old),
        Contract_Cases =>
          (others => Appended (Output'Old, Output, D.OL'Old, D.OL))
   is
      pragma Assertion_Policy (Loop_Invariant => Ignore);   --  see Zero_Tail
      V        : VCode_Index;
      H2       : Set_Kind;
      Ok       : Boolean;
      Is_Upper : Boolean;
      C        : Byte := 0;
      Kind     : Uni_Kind;
      Spl      : Natural;
      Neg      : Boolean;
      Mag      : Natural;
      Status   : Rep_Status;
      Count    : Natural;
      Rpt      : Byte;
   begin
      Result := Stop;
      if D.DState = Uni or else D.H = Uni then
         if D.DState /= Uni then
            D.H := D.DState;
         end if;
         Read_Unicode (Input, D.Bit_No, Kind, Spl, Neg, Mag);
         if Kind = U_Invalid then
            return;
         end if;
         if Kind = U_Special then
            case Spl is
               when 0 =>
                  Put (Output, D.OL, Ch (' '), D.Overflow);
                  Result := Go_On;
                  return;
               when 1 =>
                  Read_HCode (Input, D.Bit_No, H2, Ok);
                  if not Ok then
                     return;
                  end if;
                  D.H := H2;
                  if H2 = Uni or else H2 = Alpha then
                     D.DState := H2;
                     Result := Go_On;
                     return;
                  end if;
                  if H2 = Dict then
                     Decode_Repeat (Input, Output, D, Status);
                     if Status = Rep_Invalid then
                        return;
                     end if;
                     D.H := D.DState;
                     Result := Go_On;
                     return;
                  end if;
               when 2 =>
                  Put (Output, D.OL, Ch (','), D.Overflow);
                  Result := Go_On;
                  return;
               when 3 =>
                  Put (Output, D.OL, Ch ('.'), D.Overflow);
                  Result := Go_On;
                  return;
               when others =>
                  Put (Output, D.OL, 10, D.Overflow);
                  Result := Go_On;
                  return;
            end case;
         else
            if Neg then
               D.Prev_Uni := D.Prev_Uni - U32 (Mag);
            else
               D.Prev_Uni := D.Prev_Uni + U32 (Mag);
            end if;
            Write_UTF8 (Output, D.OL, D.Prev_Uni, D.Overflow);
         end if;
         if D.DState = Uni and then D.H = Uni then
            Result := Go_On;
            return;
         end if;
      else
         D.H := D.DState;
      end if;

      Is_Upper := D.Is_All_Upper;
      Read_VCode (Input, D.Bit_No, V, Ok);
      if not Ok then
         return;
      end if;
      if V = 0 and then D.H /= Sym then
         if D.Bit_No >= 8 * Input'Length then
            return;
         end if;
         if D.H /= Num or else D.DState /= Uni then
            Read_HCode (Input, D.Bit_No, D.H, Ok);
            if not Ok or else D.Bit_No >= 8 * Input'Length then
               return;
            end if;
         end if;
         if D.H = Alpha then
            if D.DState = Alpha then
               if D.Is_All_Upper then
                  D.Is_All_Upper := False;
                  Result := Go_On;
                  return;
               end if;
               Read_VCode (Input, D.Bit_No, V, Ok);
               if not Ok then
                  return;
               end if;
               if V = 0 then
                  Read_HCode (Input, D.Bit_No, D.H, Ok);
                  if not Ok then
                     return;
                  end if;
                  if D.H = Alpha then
                     D.Is_All_Upper := True;
                     Result := Go_On;
                     return;
                  end if;
               end if;
               Is_Upper := True;
            else
               D.DState := Alpha;
               Result := Go_On;
               return;
            end if;
         elsif D.H = Dict then
            Decode_Repeat (Input, Output, D, Status);
            if Status = Rep_Ok then
               Result := Go_On;
            end if;
            return;
         elsif D.H = Uni then
            Result := Go_On;
            return;
         else
            if D.H /= Num or else D.DState /= Uni then
               Read_VCode (Input, D.Bit_No, V, Ok);
               if not Ok then
                  return;
               end if;
            end if;
            if D.H = Num and then V = 0 then
               Decode_Num_Escape (Input, Output, D, Result);
               return;
            end if;
         end if;
      end if;

      if Is_Upper and then V = 1 then
         D.H := Uni;                 --  continuous delta coding
         D.DState := Uni;
         Result := Go_On;
         return;
      end if;
      if D.H in Char_Set then
         C := Sets (D.H, V);
      end if;
      if C in Ch ('a') .. Ch ('z') then
         D.DState := Alpha;
         if Is_Upper then
            C := C - 32;
         end if;
      elsif C in Ch ('0') .. Ch ('9') then
         D.DState := Num;
      elsif C = 0 then
         if V = 8 then
            Put (Output, D.OL, 13, D.Overflow);
            Put (Output, D.OL, 10, D.Overflow);
         elsif D.H = Num and then V = 26 then
            Read_Count (Input, D.Bit_No, Count, Ok);
            if not Ok or else D.OL = 0 then
               return;
            end if;
            Rpt := Output (Output'First + D.OL - 1);
            for K in 1 .. Count + 4 loop
               pragma Loop_Invariant (Valid_Dec (Input, Output, D)
                                      and then D.Bit_No = D.Bit_No'Loop_Entry);
               pragma Loop_Invariant
                 (Appended (Output'Loop_Entry, Output, D.OL'Loop_Entry, D.OL));
               Put (Output, D.OL, Rpt, D.Overflow);
               exit when D.Overflow;
            end loop;
         elsif D.H = Sym and then V > 24 then
            Put_Freq_Seq (Output, D, V - 25);
         elsif D.H = Num and then V in 23 .. 25 then
            Put_Freq_Seq (Output, D, V - 20);
         else
            return;                  --  terminator
         end if;
         if D.DState = Uni then
            D.H := Uni;
         end if;
         Result := Go_On;
         return;
      end if;
      if D.DState = Uni then
         D.H := Uni;
      end if;
      Put (Output, D.OL, C, D.Overflow);
      Result := Go_On;
   end Decode_Step;

   ----------------
   -- Decompress --
   ----------------

   procedure Decompress
     (Input         : Byte_Array;
      Output        : out Byte_Array;
      Output_Length : out Natural;
      Success       : out Boolean)
   is
      pragma Assertion_Policy (Loop_Invariant => Ignore);   --  see Zero_Tail
      D      : Decoder;
      Result : Step_Result := Go_On;
   begin
      Output := (others => 0);
      --  Every step that goes on consumes at least one bit, so the bound
      --  never ends the loop: it ends as "while (bit_no < len)" does.
      for Iter in 1 .. Max_Bits loop
         pragma Loop_Invariant (Valid_Dec (Input, Output, D)
                                and then D.Bit_No >= Iter
                                and then Result = Go_On);
         pragma Loop_Invariant (Dec_Zero_Tail (Output, D.OL));
         exit when D.Bit_No >= 8 * Input'Length;
         Decode_Step (Input, Output, D, Result);
         exit when Result = Stop or else D.Overflow;
      end loop;
      pragma Assert (D.Bit_No >= 8 * Input'Length or else Result = Stop
                     or else D.Overflow);
      if D.Overflow then
         Output := (others => 0);
         Output_Length := 0;
         Success := False;
      else
         Output_Length := D.OL;
         Success := True;
      end if;
   end Decompress;

end Unishox;

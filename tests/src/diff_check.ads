--  Copyright 2026 The FreedomChat authors
--  SPDX-License-Identifier: Apache-2.0
--
--  The differential checks of the SPARK Unishox2 port against the C
--  reference (tests/c/ref_wrap.c), shared by the test programs.

with Interfaces;   use Interfaces;
with Interfaces.C;
with System;
with Unishox;      use Unishox;

package Diff_Check is

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

   Failures    : Natural := 0;
   Checks      : Natural := 0;   --  calls of Check
   Too_Big     : Natural := 0;   --  of which with output > Max_Length
   Fuzz_Checks : Natural := 0;   --  calls of Check_Decoder

   --  Count a failure and print the first 20
   procedure Fail (Name, What : String);

   --  Full differential check of one input: Ada compress = C compress;
   --  Ada decompress (C output) = input; C decompress (Ada output) = input;
   --  exact-size buffers succeed and one byte less fails cleanly; an output
   --  over Max_Length makes Compress fail. Leaves the reference output in
   --  C_Comp.
   procedure Check (Name : String; Input : Byte_Array);

   --  Decoder check on arbitrary (usually malformed) input with an output
   --  limit: the Ada result must equal the reference whenever the
   --  reference output fits, and be a failure otherwise. C_Size is the
   --  output buffer of the reference (its bounded decoder stops beyond
   --  it): more than Limit, smaller than the default only to save time.
   procedure Check_Decoder
     (Name   : String;
      Input  : Byte_Array;
      Limit  : Natural;
      C_Size : Positive := Big_Size)
   with Pre => Limit <= Max_Length and then C_Size > Limit
               and then C_Size <= Big_Size;

end Diff_Check;

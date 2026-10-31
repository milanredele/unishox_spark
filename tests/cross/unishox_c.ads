--  Copyright 2026 The FreedomChat authors
--  SPDX-License-Identifier: Apache-2.0
--
--  C interface to Unishox.Compress and Unishox.Decompress, for the
--  cross-target differential test (cross_test.c, run-target.sh). Test code:
--  compiled with the library's cross flags, it needs no Ada runtime and no
--  elaboration.
--
--  int unishox_compress   (const uint8_t *in, int in_len,
--                          uint8_t *out, int out_cap, int *out_len);
--  int unishox_decompress (same)
--  return 1 on success, 0 if the result does not fit in out_cap bytes
--  (*out_len is then 0), -1 if a length is negative or above 4096.

with Interfaces.C;
with System;

package Unishox_C
  with SPARK_Mode => Off, Preelaborate
is

   function Compress
     (Inp     : System.Address;
      In_Len  : Interfaces.C.int;
      Outp    : System.Address;
      Out_Cap : Interfaces.C.int;
      Out_Len : out Interfaces.C.int) return Interfaces.C.int
   with Export, Convention => C, External_Name => "unishox_compress";

   function Decompress
     (Inp     : System.Address;
      In_Len  : Interfaces.C.int;
      Outp    : System.Address;
      Out_Cap : Interfaces.C.int;
      Out_Len : out Interfaces.C.int) return Interfaces.C.int
   with Export, Convention => C, External_Name => "unishox_decompress";

end Unishox_C;

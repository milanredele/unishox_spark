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
--  Unishox2 short-string compression in SPARK, bit-compatible with
--  unishox2_compress_simple / unishox2_decompress_simple of the reference
--  implementation (Copyright (C) 2020 Siara Logics (cc), Apache-2.0) with
--  its default preset (USX_PSET_DFLT).
--
--  Light-runtime discipline: no heap, no secondary stack, no exceptions,
--  no tasking; all buffers are provided by the caller and every loop is
--  bounded by the buffer sizes.

with Interfaces;

package Unishox with SPARK_Mode, Pure is

   subtype Byte is Interfaces.Unsigned_8;
   use type Interfaces.Unsigned_8;

   --  Inputs and outputs are limited to 4 KiB by the index subtype
   Max_Length : constant := 4_096;
   subtype Buffer_Index is Positive range 1 .. Max_Length;
   type Byte_Array is array (Buffer_Index range <>) of Byte;
   subtype Buffer_Length is Natural range 0 .. Max_Length;

   procedure Compress
     (Input         : Byte_Array;
      Output        : out Byte_Array;
      Output_Length : out Natural;
      Success       : out Boolean)
   with
     Pre  => Input'Length <= Max_Length and then Output'Length <= Max_Length,
     Post => Output_Length <= Output'Length
       and then (if not Success
                 then Output_Length = 0
                   and then (for all B of Output => B = 0))
       and then (for all I in Output'First + Output_Length .. Output'Last =>
                   Output (I) = 0)
       and then (if Output'Length >= 8 * Input'Length + 1 then Success);
   --  Compresses Input (UTF-8 text, any bytes allowed) into
   --  Output (Output'First .. Output'First + Output_Length - 1), exactly as
   --  unishox2_compress_simple does. Success is False, Output_Length is 0
   --  and Output is all zero if the result does not fit in Output. The
   --  bytes after the result are zero, and the result always fits in
   --  8 * Input'Length + 1 bytes.

   procedure Decompress
     (Input         : Byte_Array;
      Output        : out Byte_Array;
      Output_Length : out Natural;
      Success       : out Boolean)
   with
     Pre  => Input'Length <= Max_Length and then Output'Length <= Max_Length,
     Post => Output_Length <= Output'Length
       and then (if not Success
                 then Output_Length = 0
                   and then (for all B of Output => B = 0));
   --  Decompresses Input into Output exactly as unishox2_decompress_simple
   --  does (also for malformed input, which decodes to whatever the
   --  reference produces and never reads or writes out of bounds).
   --  Success is False, Output_Length is 0 and Output is all zero if the
   --  result does not fit in Output.

end Unishox;

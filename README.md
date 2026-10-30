# unishox_spark

Unishox2 short-string compression in SPARK 2014 / Ada 2022, proved free of run-time errors.
Written for the [FreedomChat](https://github.com/milanredele/FreedomChat) core, an offline mesh
messenger whose messages must fit a 1024-byte envelope, and published on its own because
nothing else in the Alire ecosystem compresses short strings. It reproduces `unishox2_compress_simple` and `unishox2_decompress_simple` of the reference C
implementation ([Unishox2](https://github.com/siara-cc/Unishox2), Siara Logics, Apache-2.0)
bit for bit, with the reference's default tables (`USX_HCODES_DFLT`, `USX_HCODE_LENS_DFLT`,
`USX_FREQ_SEQ_DFLT`, `USX_TEMPLATES`). The output format is the reference's, so either side
can decode the other's output.

Light-runtime discipline: no heap, no secondary stack, no exceptions, no tasking, no I/O
(`unishox.adc`); every buffer is the caller's and at most 4096 bytes; every loop is
bounded. GNATprove proves the absence of run-time errors (795 of 795 checks, see
[PROOF.md](PROOF.md)), so the release build runs with checks off.

## API

```ada
package Unishox is
   subtype Byte is Interfaces.Unsigned_8;
   Max_Length : constant := 4_096;
   subtype Buffer_Index is Positive range 1 .. Max_Length;
   type Byte_Array is array (Buffer_Index range <>) of Byte;   --  at most 4096 bytes

   procedure Compress   (Input : Byte_Array; Output : out Byte_Array;
                         Output_Length : out Natural; Success : out Boolean);
   procedure Decompress (Input : Byte_Array; Output : out Byte_Array;
                         Output_Length : out Natural; Success : out Boolean);
   --  Pre:  Input'Length <= 4096 and Output'Length <= 4096
   --  Post: Output_Length <= Output'Length; if not Success, Output_Length = 0
   --        and Output is all zero
end Unishox;
```

The result is `Output (Output'First .. Output'First + Output_Length - 1)`. `Success` is
False only when the result does not fit in `Output`: a compressed text larger than the
buffer, or a decompressed text larger than the buffer (the bound that rules out
decompression bombs). Malformed compressed input is not an error: like the reference, the
decoder stops where the stream stops making sense and returns what it has decoded, so the
caller must authenticate before decompressing (addendum section 5).

## Files

| path | what |
|---|---|
| `src/unishox.ads`, `src/unishox.adb` | the library; the body follows `unishox2.c` function by function |
| `src/unishox-tables.ads` | the reference's code tables |
| `unishox_spark.gpr`, `alire.toml`, `unishox.adc` | project (modes `release`, `debug`, `checks`, `bench`), crate, restrictions |
| `prove.sh`, `PROOF.md` | GNATprove at level 2 and its results |
| `tests/run.sh` | differential tests against the C reference |
| `bench/bench.sh` | object size and throughput |
| `build-target.sh` | GNAT-LLVM cross build for iOS and Android (the toolchain of [ada-mobile](https://github.com/milanredele/ada-mobile)) |
| `tools/prove.sh` | the proof runner shared with the FreedomChat core: all proved, no warning, a margin to the prover limits |
| `reference/` | unmodified `unishox2.c/h` (commit `4981d94`), used only by the tests and benchmark |

`./build.sh [release|debug|checks]` builds the static library with the Alire GNAT
(`env.sh` finds it under `~/.local/share/alire/toolchains`; set `GNAT_BIN`/`GPR_BIN` to
override). `GNATPROVE=<path>/bin/gnatprove ./prove.sh` runs the proof.

## Tests

`tests/run.sh` builds the reference with clang (`-fwrapv`, and `UNISHOX_API_WITH_OUTPUT_LEN`
for the bounded decoder used in fuzzing; the `*_simple` functions are unchanged by it), the
library with all checks and contracts on, and runs:

1. **Corpus** (`tests/corpus.txt`, written by `tests/gen_corpus.py`, 547 strings): the five
   samples of FreedomChat's compression benchmark (`experiments/compression-bench/samples.py`
   there); the empty string and all 256
   one-byte strings; ASCII prose, JSON, HTML, URLs, CRLF/tab/control text, upper-case runs;
   numbers, dates, times, phone numbers, hexadecimal and UUIDs (the template and nibble
   codes); Hungarian, other accented Latin, Greek, Cyrillic, Hebrew, Arabic, CJK, Indic, Thai;
   emoji including ZWJ sequences, flags and skin tones; invalid UTF-8 (lone continuation
   bytes, truncated, overlong, surrogates, above U+10FFFF); repeated characters; texts of 900
   to 4096 bytes around the 1024 and 4096 limits; random bytes of 1 to 4096 bytes.
2. **100,000 random round trips** (fixed seed): printable ASCII, words with case changes,
   numbers and punctuation, code points from several scripts, random bytes, small alphabets,
   runs, and mixtures, of 0 to 4096 bytes.
3. **100,000 decoder fuzz cases**: random bytes and reference streams with flipped bits or
   truncated, decoded into output buffers of random size.

For every corpus and random input: Ada compress = C compress byte for byte; Ada decompress
(C output) = input; C decompress (Ada output) = input; compressing into a buffer of exactly
the needed size succeeds and into one byte less fails cleanly; decompressing into exactly
the input length succeeds and into one byte less fails. Inputs whose compressed form is
larger than 4096 bytes (random bytes expand) must make `Compress` fail. For every fuzz
case, the Ada decoder must produce exactly the reference's output when it fits, and fail
otherwise.

Result: `checks: 100547 (13 with output > 4096 bytes), decoder fuzz: 100000, failures: 0`,
about 18 s.

## Compression ratios

The five samples of FreedomChat's compression study, identical to the C reference:

| sample | bytes | unishox_spark | C reference |
|---|---|---|---|
| English, 1 sentence | 94 | 57 | 57 |
| English, 1 paragraph | 442 | 257 | 257 |
| Hungarian, 1 sentence | 98 | 70 | 70 |
| Hungarian, 1 paragraph | 466 | 321 | 321 |
| English, 834 bytes | 834 | 474 | 474 |

## Size and speed

Native GNAT 15.1.2 (Alire), `-O2 -gnatp -gnatn`, aarch64 macOS; `bench/bench.sh`:

| object | text | stripped file |
|---|---|---|
| `unishox.o` | 16,424 B | 22,288 B |
| `unishox-tables.o` | 2,152 B | 4,976 B |
| total | **18.6 KB** | |
| reference `unishox2.o` (clang -O2), for comparison | 23,509 B + 613 B data | 33,201 B |

GNAT-LLVM (`build-target.sh`, `-O2 -gnatp -gnatn`): 23.6 KB + 1.9 KB text for
`arm64-apple-ios15.0` and for `aarch64-linux-android29` (LLVM inlines more).

Throughput on 1 kB inputs, Apple M5, microseconds per call (20,000 calls each):

| input | compressed | SPARK compress | C compress | SPARK decompress | C decompress |
|---|---|---|---|---|---|
| English, 1024 B | 571 B | 200 to 225 | 435 to 440 | 6.0 to 6.3 | 4.3 |
| Hungarian, 1024 B | 654 B | 240 | 425 to 435 | 6.0 to 6.2 | 5.5 to 5.7 |

Compression time is dominated by the reference's quadratic search for repeated
substrings; the port skips candidates that cannot become the longest match, which gives
the same output in about half the reference's time. Decompression is about 1.1 to 1.5
times the reference's time.

## Cross targets

`./build-target.sh [triple...]` compiles the sources with the project GNAT-LLVM toolchain
(`$FC_TOOLS/gnat-llvm`, see `toolchain/`) for the four supported triples by default, exactly as
`experiments/ada-cross-poc/build-llvm.sh` does (the installed `lp64.atp` via `-gnateT`, the light runtime from `$FC_TOOLS/rts/<triple>`,
`-O2 -gnatp -gnatn -fPIC`),
with the restrictions of `unishox.adc`. The only undefined symbol is `memset` (Android) or
`_bzero` (iOS: LLVM's AArch64 back end turns a zero memset of variable size into `bzero`,
which libSystem provides). No GNAT runtime symbol, no secondary stack, no exception
handling.

## Deviations from the reference

None in the output: for every input of up to 4096 bytes the compressed bytes, and for
every compressed input the decompressed bytes, are the reference's (tested as above).
Differences in behaviour and scope:

- **Bounded buffers.** The `*_simple` reference functions have no output limit and write
  past the caller's buffer if it is too small; this port fails instead (`Success = False`,
  zeroed output). Inputs and outputs are limited to 4096 bytes.
- **Reads outside the input.** The reference reads `in[len]` (the C string terminator) in
  its repeated-substring search, and `in[-1]` when an input starts with UTF-8
  continuation bytes. The port treats `in[len]` as 0, which is what the reference sees for
  a C string, and never reads before the input (stopping that backward scan early cannot
  change the result).
- **Malformed compressed input.** The port decodes it exactly as the reference does,
  including its overlapping back-reference copy (`memmove`), which for a malformed stream
  can copy bytes beyond the decoded text: those read as 0 here because the output buffer
  is zeroed first (the test harness zeroes the reference's buffer too). The running Unicode
  code point wraps around in 32 bits where the reference's `int` would overflow (the tests
  build the reference with `-fwrapv`).
- **Not ported:** the string-array API (`unishox2_compress_lines` with `prev_lines`), the
  other presets and their tables, the variant of the API that returns full terminator
  codes (negative `olen`), and the preset-1 terminator. The last step of
  `append_final_bits` ("fill the byte with the last bit") is unreachable from the simple
  API: the terminator is always cut at the end of the last started byte.
- **Two exact shortcuts:** the repeated-substring search skips a candidate position
  when its first byte, or the byte at the length that would beat the current longest
  match, differs (the reference measures such matches and then discards them); the
  template threshold
  `(float) j / rem > 0.66` is computed as `50 * j > 33 * rem`, which is exact for the four
  template lengths (24, 10, 14, 8).

## Licence

Apache License 2.0 ([LICENSE](LICENSE)). The algorithm and its tables are Unishox2 by
Siara Logics, also Apache-2.0; see [NOTICE](NOTICE).

# Proof results

`./prove.sh` runs GNATprove (FSF 16.1.0: CVC5 1.3.2, Z3 4.15.4, Alt-Ergo 2.6.1) on the
release configuration (with the light-runtime restrictions of `unishox.adc`):

    gnatprove -P unishox_spark.gpr --level=2 --mode=all --checks-as-errors=on

Result on 2026-10-31: **all 1,120 checks proved, none unproved, none justified** (no
`pragma Annotate`, no `Assume`); the largest proof takes 14,181 of the 100,000 steps allowed
and under a second; no check has 16 or more verification conditions. Seven short loops of at
most 20 iterations (over the five count and Unicode levels, the sets of the horizontal codes,
the sections of the vertical codes, and in the lemma unit) are unrolled by GNATprove and
proved per iteration. About 45 s wall-clock on an Apple M5
(`-j0`). GNATprove 15.1.0 proves the same 1,120 checks (largest proof 27,977 steps, 2.8 s), so
16.1 is the version reported here, not a requirement. A local run replays the result cache of
`prove.sh`, so its prover shares say nothing;
the CI run (`.github/workflows/ci.yml`) has no cache and is the authoritative proof.

| category | checks | how |
|---|---|---|
| Initialization | 92 | flow analysis |
| Non-aliasing | 17 | flow analysis |
| Data dependencies | 9 | flow analysis |
| Run-time checks (index, overflow, range, division) | 532 | provers |
| Assertions (loop invariants, lemmas, assertions) | 86 | provers |
| Functional contracts (pre/postconditions, contract cases) | 345 | provers |
| Termination (loop variants, subprogram termination) | 39 | flow 31, provers 8 |
| **Total** | **1,120** | |

What is proved:

- **Absence of run-time errors** in `Compress` and `Decompress` for every input of up to
  4096 bytes and every output buffer of up to 4096 bytes: no out-of-bounds read of the
  input, no write outside the output buffer, no integer overflow, no range violation. This
  is what allows the release and cross builds to use `-gnatp` (checks off).
- **The public contracts** (`src/unishox.ads`): `Output_Length <= Output'Length`; on failure
  `Output_Length = 0` with the whole output buffer zero (never partial output); the bytes after
  `Output_Length` are zero in every case (the caller's buffer holds no stale bytes); and for
  `Compress` a **size bound**: `Output'Length >= 4 * Input'Length + 1` implies `Success`. The
  constant comes from the worst path of the encoder, a binary byte right after an all-upper
  run, which costs 31 bits; an empty input costs the one terminator bit.
- **The bit writer and the byte writer are exact.** `Append_Bits` and `Append_Value` advance
  `Pos` by exactly the bits appended, change nothing once failed, and fail exactly when the
  bits do not fit (`Pos'Old + Len > 8 * Limit`); they change no byte below the one being
  written and keep every byte not yet started zero. Every encoder step carries a proved bound
  on the bits it appends (`Wrote`). The decoder's `Put` appends exactly one byte at `OL`,
  changes no other byte, and overflows exactly when `OL = Output'Length`; every decoder step
  only appends (`Appended`: the bytes below the old `OL` are unchanged, the bytes from the
  new `OL` on stay zero), which is what makes the zero tail of `Decompress` hold.
- **The tables are consistent** (`src/unishox-tables-lemmas.adb`, a ghost unit with no code
  in the release build): the count and Unicode levels tile their ranges with powers of two,
  so the writer never drops a bit of a count or a code point (`Append_Value` requires
  `Value < 2 ** N`, and `Encode_Count` and `Encode_Unicode` prove it); the unary prefixes are
  the ones `Get_Step_Code_Idx` reads; the horizontal and vertical codes are prefix-free;
  `VCode_Lookup` is the inverse of `VCodes`/`VCode_Lens` for all 256 bytes; `Code_94` maps
  every printable character to the set and position whose `Sets` entry is that character.
  Agreement of the tables with the C reference remains a matter of review and tests.
- **Termination:** every loop is a bounded `for` loop or a `while` loop with a proved
  `Loop_Variant`. The main decoder loop is a `for` loop bounded by the number of input bits;
  the postcondition of `Decode_Step` ("a step that goes on consumes at least one input bit"),
  the invariant `Bit_No >= Iter` and the assertion after the loop prove that the bound is
  never what stops it, so the bounded loop decodes exactly what the reference's
  `while (bit_no < len)` loop decodes.
- **Determinism**, by flow analysis: the package is `Pure`, the output is fully assigned
  first, every local is initialized before use.

The "functional contracts" row counts the call-site preconditions that carry the bounds
from caller to callee (`Valid_Pos`, `Valid_Bits`, `OL <= Output'Length`, `Fits`), the
bound, frame and progress postconditions of the internal procedures, and the public contracts
above. No proved contract describes the **content** of the compressed bytes beyond the frame
and the size bound: which code each character becomes, and that the decoder reads back what
the encoder wrote, is what the differential tests cover.

What is not proved (it is tested instead, see `tests/`): functional equivalence with the C
reference, the round-trip property `Decompress (Compress (X)) = X`, and the other half of
"`Success` is False only when the result does not fit" (the exact writer postconditions say
it for every single write; it is not carried up to `Compress` as a contract, and the tests
check exact-size success and one-byte-less failure for every input). The equivalence and the
round trip are checked differentially on 547 corpus strings, 100,000 random round trips and
100,000 decoder fuzz cases, on the checks build and on the release code, on every run of
`tests/run.sh`; `tests/exhaustive.sh` decodes every input of up to 3 bytes; `tests/run-target.sh`
runs the suite on the GNAT-LLVM objects for macOS, the iOS simulator and the Android emulator.
The time bound of the decoder (work linear in the input bits plus the output length) holds by
inspection, as every inner loop stops on input exhaustion or output overflow; termination is
proved, the cost is not.

Proof-relevant design choices:

- The bit writer is a record (`Pos`, `Failed`) with the invariant `Pos <= 8 * Limit`; a write
  that would cross the limit sets `Failed` instead of writing (the reference's
  `append_bits` returning -1).
- Every reader of the compressed stream keeps `Bit_No <= 8 * Input'Length + 8`, the most the
  reference ever steps past the end before it notices.
- Byte fields are decoded with `mod` and `/` instead of `and`/shift masks where a bound is
  needed (`B / 32 = 6` for `(b & 0xE0) == 0xC0`, the vertical-code section lookup written
  as five explicit ranges), which keeps the proofs in linear integer arithmetic.
- The frame contracts (`Zero_Tail`, `Dec_Zero_Tail`, `Appended`, `Same_Below`, `Same_From`,
  the element-wise frame of `Put`) quantify over the 4096-byte buffer and would cost a pass over it, plus a copy for
  `'Old`, at every call in the checks build. They are stated as `Contract_Cases` and loop
  invariants under `pragma Assertion_Policy (Contract_Cases => Ignore)` and local
  `(Loop_Invariant => Ignore)`: GNATprove proves them, the checks build does not execute them.
  Powers of two are a ghost table of literals (`Pow2`), as GNATprove does not evaluate
  `2 ** E` for a table-valued `E`.
- The table component subtypes carry the bounds most proofs need (for example code lengths
  `1 .. 8`, bit counts `1 .. 21`). The unrolled loops (above) are proved from the concrete
  table values, among them the loops over `Level` in `Encode_Count` and `Encode_Unicode`;
  the facts those proofs use are the ones the lemma unit asserts, so a table edit that breaks
  them fails the proof twice. The tables are constants, so this is sound.

What the proof assumes of the caller:

- `Input` and `Output` do not overlap. SPARK forbids the aliasing and checks it in SPARK
  callers; an Ada caller may legally pass the same array as both (`Compress (X, X, ...)`),
  which the proof does not cover: `Output` is zeroed first, so the result is garbage.
- The parameters are within their subtypes (`Byte` is modular, so every bit pattern is valid;
  the `out` parameters need no valid value on entry).

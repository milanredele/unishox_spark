# Proof results

`./prove.sh` runs GNATprove (FSF 16.1.0: CVC5 1.3.2, Z3 4.15.4, Alt-Ergo 2.6.1) on the
release configuration (with the light-runtime restrictions of `unishox.adc`):

    gnatprove -P unishox_spark.gpr --level=2 --mode=all --checks-as-errors=on

Result on 2026-10-21: **all 795 checks proved, none unproved, none justified**
(no `pragma Annotate`, no `Assume`). About 40 s wall-clock on an Apple M5 (`-j0`).

| category | checks | how |
|---|---|---|
| Initialization | 92 | flow analysis |
| Non-aliasing | 17 | flow analysis |
| Run-time checks (index, overflow, range, division) | 396 | CVC5 99 %, Z3 1 % |
| Assertions (loop invariants, one assertion) | 43 | CVC5 98 %, Z3 2 % |
| Functional contracts (pre/postconditions) | 224 | CVC5 94 %, Z3 3 %, trivial 2 % |
| Termination (loop variants, subprogram termination) | 23 | flow 15, CVC5 8 |
| **Total** | **795** | |

What is proved:

- **Absence of run-time errors** in `Compress` and `Decompress` for every input of up to
  4096 bytes and every output buffer of up to 4096 bytes: no out-of-bounds read of the
  input, no write outside the output buffer, no integer overflow, no range violation. This
  is what allows the release and cross builds to use `-gnatp` (checks off).
- The public contracts: `Output_Length <= Output'Length`, and on failure
  `Output_Length = 0` with the whole output buffer zero (never partial output).
- Termination: every loop is a bounded `for` loop or a `while` loop with a proved
  `Loop_Variant`. The main decoder loop is a `for` loop bounded by the number of input bits;
  the postcondition of `Decode_Step` ("a step that goes on consumes at least one input bit"),
  the invariant `Bit_No >= Iter` and the assertion after the loop prove that the bound is
  never what stops it, so the bounded loop decodes exactly what the reference's
  `while (bit_no < len)` loop decodes.

What is not proved (it is tested instead, see `tests/`): functional equivalence with the C
reference and the round-trip property `Decompress (Compress (X)) = X`. Both are checked
differentially on 547 corpus strings, 100,000 random round trips and 100,000 decoder fuzz
cases on every run of `tests/run.sh`.

Proof-relevant design choices:

- The bit writer is a record (`Pos`, `Failed`) with the invariant `Pos <= 8 * Limit`; a write
  that would cross the limit sets `Failed` instead of writing (the reference's
  `append_bits` returning -1).
- Every reader of the compressed stream keeps `Bit_No <= 8 * Input'Length + 8`, the most the
  reference ever steps past the end before it notices.
- Byte fields are decoded with `mod` and `/` instead of `and`/shift masks where a bound is
  needed (`B / 32 = 6` for `(b & 0xE0) == 0xC0`, the vertical-code section lookup written
  as five explicit ranges), which keeps the proofs in linear integer arithmetic.
- The table component subtypes carry the bounds the proofs need (for example code lengths
  `1 .. 8`, bit counts `1 .. 21`), so no proof depends on reading individual table entries.

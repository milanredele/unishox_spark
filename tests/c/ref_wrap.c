/*
 * Copyright 2026 The FreedomChat authors
 * SPDX-License-Identifier: Apache-2.0
 *
 * Thin wrappers around the Unishox2 reference (reference/unishox2.c, built with
 * UNISHOX_API_WITH_OUTPUT_LEN=1 so that the bounded decompressor exists too; the
 * *_simple functions behave the same in both builds).
 */
#include <string.h>
#include "unishox2.h"

#define REF_MAX_IN 4096

/* unishox2_compress_simple on a copy of the input that has a 0 byte before and after
   it: the reference reads in[len] (the C string terminator) and, for inputs that start
   with UTF-8 continuation bytes, in[-1]. */
int ref_compress(const unsigned char *in, int len, unsigned char *out) {
  static char buf[REF_MAX_IN + 2];
  if (len < 0 || len > REF_MAX_IN) return -1;
  buf[0] = 0;
  memcpy(buf + 1, in, (size_t)len);
  buf[len + 1] = 0;
  return unishox2_compress_simple(buf + 1, len, (char *)out);
}

/* unishox2_decompress_simple into a zeroed buffer, which must be large enough */
int ref_decompress_simple(const unsigned char *in, int len, unsigned char *out, int out_size) {
  memset(out, 0, (size_t)out_size);
  return unishox2_decompress_simple((const char *)in, len, (char *)out);
}

/* Bounded decompression (returns olen + 1 if the output does not fit), into a zeroed
   buffer: used to fuzz the decoder with malformed input, whose unbounded output can be
   very large. */
int ref_decompress_bounded(const unsigned char *in, int len, unsigned char *out, int olen) {
  memset(out, 0, (size_t)olen);
  return unishox2_decompress((const char *)in, len, (char *)out, olen, USX_PSET_DFLT);
}

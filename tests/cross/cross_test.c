/*
 * Copyright 2026 The FreedomChat authors
 * SPDX-License-Identifier: Apache-2.0
 *
 * Differential test of the cross-compiled SPARK Unishox2 port (through unishox_c.ads)
 * against the C reference compiled for the same target (with tests/c/ref_wrap.c): the
 * checks of tests/src/diff_check.adb, in C, for run-target.sh.
 * Usage: cross_test [corpus.txt|-] [random round trips (100000)] [decoder fuzz cases (100000)]
 */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int unishox_compress(const uint8_t *in, int in_len, uint8_t *out, int out_cap, int *out_len);
int unishox_decompress(const uint8_t *in, int in_len, uint8_t *out, int out_cap, int *out_len);
int ref_compress(const unsigned char *in, int len, unsigned char *out);
int ref_decompress_simple(const unsigned char *in, int len, unsigned char *out, int out_size);
int ref_decompress_bounded(const unsigned char *in, int len, unsigned char *out, int olen);

#define MAXL 4096
#define BIG 65536

static uint8_t c_comp[BIG], c_plain[BIG], a_comp[MAXL], a_plain[MAXL], tmp[MAXL];
static long failures, checks, too_big, fuzz_checks;
static uint64_t digest = 0xcbf29ce484222325ULL;   /* FNV-1a of every Ada output */

static void hash(const uint8_t *p, int len, int ok) {
  digest = (digest ^ (uint64_t)(ok + 2)) * 0x100000001b3ULL;
  for (int k = 0; k < len; k++) digest = (digest ^ p[k]) * 0x100000001b3ULL;
}

static void fail(const char *name, const char *what, const uint8_t *in, int len) {
  if (++failures <= 20) {
    printf("FAIL [%s] %s, input (%d bytes) ", name, what, len);
    for (int k = 0; k < len && k < 64; k++) printf("%02x", in[k]);
    printf("%s\n", len > 64 ? "..." : "");
  }
}

/* The full differential check of one input (Diff_Check.Check) */
static void check(const char *name, const uint8_t *in, int len) {
  int alen, plen, ok;
  checks++;
  int clen = ref_compress(in, len, c_comp);
  ok = unishox_compress(in, len, a_comp, MAXL, &alen);
  hash(a_comp, alen, ok);
  if (clen > MAXL) {
    too_big++;
    if (ok != 0 || alen != 0) fail(name, "compress should report overflow", in, len);
    return;
  }
  if (ok != 1 || alen != clen || memcmp(a_comp, c_comp, (size_t)clen) != 0) {
    fail(name, "compress differs", in, len);
    return;
  }
  /* output buffer of exactly the needed size, and one byte less */
  ok = unishox_compress(in, len, tmp, alen, &plen);
  if (ok != 1 || plen != alen || memcmp(tmp, a_comp, (size_t)alen) != 0)
    fail(name, "compress into an exact-size buffer failed", in, len);
  if (alen > 0) {
    memset(tmp, 0x55, (size_t)alen);
    ok = unishox_compress(in, len, tmp, alen - 1, &plen);
    int clean = ok == 0 && plen == 0;
    for (int k = 0; k < alen - 1; k++) clean = clean && tmp[k] == 0;
    if (!clean) fail(name, "compress into a too small buffer did not fail cleanly", in, len);
  }
  /* Ada decompress (C compressed) = input */
  ok = unishox_decompress(c_comp, clen, a_plain, MAXL, &plen);
  if (ok != 1 || plen != len || memcmp(a_plain, in, (size_t)len) != 0)
    fail(name, "Ada decompress of C output differs", in, len);
  ok = unishox_decompress(c_comp, clen, tmp, len, &plen);
  if (ok != 1 || plen != len) fail(name, "decompress into an exact-size buffer failed", in, len);
  if (len > 0) {
    ok = unishox_decompress(c_comp, clen, tmp, len - 1, &plen);
    if (ok != 0 || plen != 0) fail(name, "decompress into a too small buffer did not fail", in, len);
  }
  /* C decompress (Ada compressed) = input */
  int dlen = ref_decompress_simple(a_comp, alen, c_plain, BIG);
  if (dlen != len || memcmp(c_plain, in, (size_t)len) != 0)
    fail(name, "C decompress of Ada output differs", in, len);
}

/* Decoder check on arbitrary input with an output limit (Diff_Check.Check_Decoder) */
static void check_decoder(const char *name, const uint8_t *in, int len, int limit) {
  int plen;
  fuzz_checks++;
  int clen = ref_decompress_bounded(in, len, c_plain, BIG);
  int ok = unishox_decompress(in, len, a_plain, limit, &plen);
  hash(a_plain, plen, ok);
  if (clen <= limit) {
    if (ok != 1 || plen != clen || memcmp(a_plain, c_plain, (size_t)clen) != 0)
      fail(name, "decoder differs", in, len);
  } else if (ok != 0 || plen != 0) {
    fail(name, "decoder should report overflow", in, len);
  }
}

/* Corpus: '# name' lines, each followed by one hex-encoded input line */
static long run_corpus(const char *path) {
  static char line[2 * MAXL + 16];
  static const int expected[5] = {57, 257, 70, 321, 474};
  char name[200] = "";
  uint8_t buf[MAXL];
  long n = 0;
  int samples = 0;
  FILE *f = fopen(path, "r");
  if (!f) { perror(path); exit(2); }
  while (fgets(line, sizeof line, f)) {
    size_t l = strcspn(line, "\r\n");
    line[l] = 0;
    if (line[0] == '#' && line[1] == ' ') {
      snprintf(name, sizeof name, "%s", line + 2);
      continue;
    }
    int len = (int)(l / 2);
    for (int k = 0; k < len; k++) {
      unsigned v;
      sscanf(line + 2 * k, "%2x", &v);
      buf[k] = (uint8_t)v;
    }
    check(name, buf, len);
    n++;
    if (strncmp(name, "sample ", 7) == 0) {
      int alen;
      unishox_compress(buf, len, a_comp, MAXL, &alen);
      if (samples >= 5 || alen != expected[samples])
        fail(name, "sample size differs from the addendum table", buf, len);
      samples++;
    }
  }
  fclose(f);
  if (samples != 5) fail("samples", "not 5 samples in the corpus", NULL, 0);
  printf("corpus: %ld strings checked\n", n);
  return n;
}

/* xorshift64* with the seed of test_unishox */
static uint64_t state = 0x9E3779B97F4A7C15ULL;
static uint64_t next(void) {
  state ^= state >> 12; state ^= state << 25; state ^= state >> 27;
  return state * 0x2545F4914F6CDD1DULL;
}
static int rnd(int n) { return (int)((next() >> 11) % (uint64_t)n); }

static uint8_t gbuf[MAXL];
static int glen;
static void push(int b, int max) { if (glen < max) gbuf[glen++] = (uint8_t)b; }
static void push_cp(int cp, int max) {
  if (cp < 0x80) push(cp, max);
  else if (cp < 0x800) { push(0xC0 + cp / 64, max); push(0x80 + cp % 64, max); }
  else if (cp < 0x10000) {
    push(0xE0 + cp / 4096, max); push(0x80 + cp / 64 % 64, max); push(0x80 + cp % 64, max);
  } else {
    push(0xF0 + cp / 262144, max); push(0x80 + cp / 4096 % 64, max);
    push(0x80 + cp / 64 % 64, max); push(0x80 + cp % 64, max);
  }
}
static void push_str(const char *s, int max) { while (*s) push((uint8_t)*s++, max); }

static const char *words[] = {
  "the", "of", "and", "to", "in", "is", "you", "that", "meet", "bridge", "police",
  "station", "tomorrow", "message", "relay", "tal\xc3\xa1lkozzunk", "\xc3\xa1llom\xc3\xa1s",
  "\xc3\xbczenet", "h\xc3\xad" "d", "\xc5\x91rz\xc5\x91", "\xd0\x9f\xd1\x80\xd0\xb8\xd0\xb2\xd0\xb5\xd1\x82",
  "\xe4\xbd\xa0\xe5\xa5\xbd", "\xf0\x9f\x98\x80", "HELP", "URGENT", "ok", "Ok", "2026-10-21",
  "12:30:00", "2026-10-21T13:45:30.123Z", "(555) 123-4567", "deadbeef", "CAFEBABE",
  "0123456789", "https://", "\"key\": \"value\"", "</p>", "://",
  "550e8400-e29b-41d4-a716-446655440000"};
#define NWORDS ((int)(sizeof words / sizeof words[0]))

/* A random input of one of 8 kinds, as test_unishox's Generate */
static void generate(void) {
  int kind = rnd(8), r = rnd(1000), max;
  max = r < 5 ? rnd(MAXL + 1) : r < 100 ? rnd(1200) : rnd(200);
  glen = 0;
  for (int iter = 0; iter < 10000 && glen < max; iter++) {
    switch (kind) {
    case 0: push(32 + rnd(95), max); break;                 /* printable ASCII */
    case 1: case 2: {                                       /* words, case, numbers */
      const char *w = words[rnd(NWORDS)];
      int c = rnd(100);
      for (; *w; w++) push(c < 10 && *w >= 'a' && *w <= 'z' ? *w - 32 : (uint8_t)*w, max);
      if (c >= 10 && c < 15) for (int d = 1 + rnd(12); d > 0; d--) push('0' + rnd(10), max);
      switch (rnd(12)) {
      case 0: push(',', max); break;
      case 1: push('.', max); break;
      case 2: push(10, max); break;
      case 3: push(13, max); push(10, max); break;
      case 4: push(9, max); break;
      }
      push(' ', max);
      break;
    }
    case 3:                                                 /* code points */
      switch (rnd(7)) {
      case 0: push_cp(32 + rnd(95), max); break;
      case 1: push_cp(0xA0 + rnd(0x1B0), max); break;
      case 2: push_cp(0x370 + rnd(0x190), max); break;
      case 3: push_cp(0x4E00 + rnd(0x5200), max); break;
      case 4: push_cp(0x1F300 + rnd(0x800), max); break;
      case 5: push_cp(0x800 + rnd(0xD000), max); break;
      default: push_cp(0x10000 + rnd(0x100000), max); break;
      }
      break;
    case 4: push(rnd(256), max); break;                     /* random bytes */
    case 5: push("ab ."[rnd(4)], max); break;               /* small alphabet */
    case 6: {                                               /* runs */
      int b = rnd(256);
      for (int k = 1 + rnd(12); k > 0; k--) if (b < 128) push(b, max); else push_cp(0xE1 + b, max);
      break;
    }
    default:                                                /* mixed */
      switch (rnd(6)) {
      case 0: push(rnd(256), max); break;
      case 1: push_cp(0xA0 + rnd(0x3000), max); break;
      case 2: push_str(words[rnd(NWORDS)], max); break;
      case 3: push(rnd(32), max); break;
      case 4: push_cp(0x1F600 + rnd(80), max); break;
      default: push(32 + rnd(95), max); break;
      }
    }
  }
}

int main(int argc, char **argv) {
  long n_random = argc > 2 ? atol(argv[2]) : 100000, n_fuzz = argc > 3 ? atol(argv[3]) : 100000;
  char name[32];
  if (argc > 1 && strcmp(argv[1], "-") != 0) run_corpus(argv[1]);
  for (long i = 1; i <= n_random; i++) {
    generate();
    snprintf(name, sizeof name, "random %ld", i);
    check(name, gbuf, glen);
  }
  printf("random round trips: %ld\n", n_random);
  for (long i = 1; i <= n_fuzz; i++) {
    int n;
    if (i % 2 == 0) {        /* a valid stream with a few bits flipped, or truncated */
      generate();
      int clen = ref_compress(gbuf, glen, c_comp);
      n = clen < MAXL ? clen : MAXL;
      memcpy(tmp, c_comp, (size_t)n);
      if (n > 0) {
        for (int f = 1 + rnd(3); f > 0; f--) { int p = rnd(n); tmp[p] ^= (uint8_t)(1 << rnd(8)); }
        if (rnd(4) == 0) n = rnd(n + 1);
      }
    } else {                 /* random bytes */
      n = rnd(100) == 0 ? rnd(MAXL + 1) : rnd(64);
      for (int k = 0; k < n; k++) tmp[k] = (uint8_t)rnd(256);
    }
    int limit = rnd(4) == 0 ? rnd(MAXL + 1) : MAXL;
    snprintf(name, sizeof name, "fuzz %ld", i);
    check_decoder(name, tmp, n, limit);
  }
  printf("decoder fuzz cases: %ld\n", n_fuzz);
  printf("checks: %ld (%ld with output > 4096 bytes), decoder fuzz: %ld, failures: %ld\n",
         checks, too_big, fuzz_checks, failures);
  printf("digest of the Ada outputs: %016llx\n", (unsigned long long)digest);
  puts(failures == 0 ? "PASS" : "FAIL");
  return failures == 0 ? 0 : 1;
}

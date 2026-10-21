#!/usr/bin/env python3
# Copyright 2026 The FreedomChat authors
# SPDX-License-Identifier: Apache-2.0
"""Writes the fixed differential-test corpus: one hex-encoded byte string per line,
preceded by a '# name' comment line. Deterministic (fixed seed).
Usage: python3 -I gen_corpus.py > corpus.txt"""
import random
import sys

R = random.Random(20261021)
OUT = []


def add(name, data):
    if isinstance(data, str):
        data = data.encode("utf-8")
    assert len(data) <= 4096, (name, len(data))
    OUT.append((name, data))


# The five samples of experiments/compression-bench/samples.py (addendum section 5)
SAMPLES = {
    "en_short": "Meet me at the north entrance of the station at 6, bring the documents. Don't call, just come.",
    "en_med": "The road to the bridge is blocked by police since noon. People are being turned back at the roundabout near the hospital. If you need to get across, the footpath along the river is still open but crowded. Bring water, it is hot and there is no shade. Tell everyone to keep phones charged and to avoid the main square after dark. We will try to meet at the usual place tomorrow morning around nine, if that changes I will send another message.",
    "hu_short": "Találkozzunk az állomás északi bejáratánál hatkor, hozd a papírokat. Ne hívj, csak gyere.",
    "hu_med": "A hídhoz vezető utat dél óta lezárta a rendőrség. Az embereket a kórház melletti körforgalomnál visszafordítják. Ha át kell jutnod, a folyó menti gyalogút még nyitva van, de zsúfolt. Hozz vizet, nagy a hőség és nincs árnyék. Szólj mindenkinek, hogy tartsa töltve a telefonját, és sötétedés után kerülje a főteret. Holnap reggel kilenc körül megpróbálunk a szokott helyen találkozni, ha ez változik, küldök még egy üzenetet.",
    "en_long": "Status update from the east side, afternoon. Water distribution is working at the school and the church, both open until seven. The pharmacy on the corner has reopened but only takes cash. Buses are not running; a few private cars are taking people to the edge of town for a fee. Network is still down for everyone we spoke to. Please relay to anyone heading north: the second bridge is passable on foot, the first is not. Families with children should go to the community centre, they have mattresses and some food. If you can carry messages back towards the centre, come by the school before dark and we will hand you the batch. Keep this short message moving, do not add to it. Thanks to everyone carrying these around, it is working better than we expected. Next update tomorrow noon from the same place unless something changes. ",
}
for k, v in SAMPLES.items():
    add("sample " + k, v)

add("empty", b"")
for b in range(256):
    add("byte %02x" % b, bytes([b]))
for a, b in [(0x41, 0x42), (0x20, 0x20), (0x0d, 0x0a), (0xc3, 0xa1), (0x80, 0x80), (0xff, 0x00)]:
    add("two bytes %02x %02x" % (a, b), bytes([a, b]))

ASCII = [
    "Hello, World!", "hello world", "HELLO WORLD", "Hello WORLD this IS mixed CASE",
    "The quick brown fox jumps over the lazy dog.", "THE QUICK BROWN FOX JUMPS OVER THE LAZY DOG",
    "camelCaseIdentifier and snake_case_identifier", "a", "ab", "abc", "abcd", "abcde", "abcdef",
    "I", "OK", "ok.", "Yes!", "No?", "e-mail: someone@example.org", "https://www.example.com/path?q=1&r=2#frag",
    '{"name": "Alice", "age": 30, "tags": ["a", "b"], "nested": {"k":"v"}}',
    "<html><body><p class=\"x\">Hi</p></body></html>", "x = (a + b) * c / d - e % f;",
    "Line one\nLine two\nLine three", "Windows\r\nline\r\nendings\r\n", "Tabs\tseparated\tvalues\t1\t2",
    "Lonely CR\rhere", "Mixed\n\r\n\r\tcontrol", "~!@#$%^&*()_+`-={}|[]\\:\";'<>?,./",
    "Meet at 10:30, gate 7. Bring 2 bottles of water and 1 torch.", "Call +1 (555) 123-4567 now",
    "Phone: (555) 123-4567", "(555) 123-4567", "2026-10-21", "2026-10-21T13:45:30.123Z",
    "Date 2026-10-21T13:45:30.123Z end", "12:34:56", "Time 23:59:59 sharp", "1999-12-31",
    "0123456789", "3.14159265358979323846", "1,000,000.00", "-42", "+7", "100%", "$5", "#1",
    "deadbeef", "DEADBEEF", "DeadBeef", "0xdeadbeefcafebabe", "a1b2c3d4e5f6", "A1B2C3D4E5F6",
    "12345678901234567890", "123456789012", "99999999999", "1234567890",
    "550e8400-e29b-41d4-a716-446655440000", "550E8400-E29B-41D4-A716-446655440000",
    "550e8400-e29b-41d4-a716-446655440000 is a UUID", "uuid: 550e8400-e29b-41d4-a716-446655440000",
    "12345678-1234-1234-1234-123456789012", "550e8400-e29b-41d4-A716-446655440000",
    "the the the the the the the the", "abcabcabcabcabcabcabcabcabcabc", "to be or not to be, that is the question",
    "ACAB", "NATO and the UN", "An URGENT MESSAGE for EVERYONE: STAY INSIDE", "ABCDEFGHIJKLMNOPQRSTUVWXYZ",
    "aBcDeFgHiJkLmNoPqRsTuVwXyZ", "x" * 5, "x" * 6, "x" * 20, " " * 10, "\n" * 7, "." * 9, "-=" * 12,
    "\": \"", "\": ", "</", "=\"", "\":\"", "://", "a\": \"b\": c</d=\"e\":\"f://g",
    "space at end ", " space at start", "  two  spaces  ", "tab\tand space ", "A", "Z", "AB", "ABCDE", "ABCD",
    "Hello\x00World", "\x01\x02\x03\x04\x05 binary", "bell\x07 and del\x7f",
]
for i, s in enumerate(ASCII):
    add("ascii %d" % i, s)

ACCENTED = [
    "árvíztűrő tükörfúrógép", "ÁRVÍZTŰRŐ TÜKÖRFÚRÓGÉP", "Árvíztűrő Tükörfúrógép",
    "Köszönöm szépen, minden rendben van.", "Ő is jön? Igen, ő is.", "ő", "Ű", "éééééééé", "ááá",
    "Grüße aus München, schöne Straße!", "Ça va? Très bien, merci. Où est la gare?",
    "Zażółć gęślą jaźń", "Příliš žluťoučký kůň úpěl ďábelské ódy", "Înțeleg, mulțumesc frumos",
    "Çok güzel, teşekkür ederim. İstanbul", "Tiếng Việt có dấu rất nhiều", "¿Dónde está el baño? ¡Gracias!",
    "Ελληνικά: Καλημέρα κόσμε", "Русский текст: Привет, как дела?", "Українська: Слава Україні",
    "עברית: שלום עולם", "العربية: مرحبا بالعالم", "中文：你好，世界！", "日本語：こんにちは世界、カタカナ",
    "한국어: 안녕하세요 세계", "हिन्दी: नमस्ते दुनिया", "ไทย: สวัสดีชาวโลก", "Ελληνικά and English mixed ok",
    "naïve café résumé coöperate", "Ångström Øresund Æsir", "€100 and £50 and ¥1000",
    "§ 12 ¶ 3 © 2026 ® ™", "„Idézőjel” «guillemets» ‘single’ “double”", "em—dash en–dash ellipsis…",
    "\u00a0non-breaking\u00a0space", "zero\u200bwidth", "combining e\u0301 a\u0300", "Ｆｕｌｌｗｉｄｔｈ",
    "Mixed: Hello Szia Привет 你好 مرحبا", "é", "ü ö ő", "Ő" * 6,
]
for i, s in enumerate(ACCENTED):
    add("accented %d" % i, s)

EMOJI = [
    "😀", "😀😀😀😀😀😀", "Hi 👋 there", "🔥🔥🔥 fire", "👍🏽 thumbs", "👨‍👩‍👧‍👦 family",
    "🇭🇺🇬🇧🇺🇸 flags", "❤️ heart", "☕ coffee ☀️ sun", "Meet at 🏫 at 6 ⏰", "𝔘𝔫𝔦𝔠𝔬𝔡𝔢 math",
    "🙂🙃🙂🙃🙂🙃🙂🙃", "Emoji at end 🎉", "🎉 Emoji at start", "a😀b😀c😀d",
    "😀 ő 你 x", "\U0010FFFF max", "\U00010000 min astral",
]
for i, s in enumerate(EMOJI):
    add("emoji %d" % i, s)

INVALID = [
    b"\x80", b"\x80\x80\x80\x80\x80\x80\x80\x80", b"\xc3", b"\xc3(", b"\xe2\x82", b"\xf0\x9f\x98",
    b"\xc0\xaf overlong", b"\xe0\x80\xaf", b"\xed\xa0\x80 surrogate", b"\xf4\x90\x80\x80 too big",
    b"\xf7\xbf\xbf\xbf lead f7", b"\xf8\x88\x80\x80\x80", b"\xff\xfe\xfd", b"abc\x80def\x80ghi",
    b"\x80\x80\x80\x80\x80\x80hello", b"hello\x80\x80\x80\x80\x80\x80", b"\xc3\xa9\x80\x80\xc3\xa9",
    b"text\xc3\xa9\xc3\xa9\xc3\xa9\xc3\xa9\xc3\xa9\xc3\xa9 more", b"\x00" * 10, b"\x01" * 3 + b"\x02" * 6,
]
for i, s in enumerate(INVALID):
    add("invalid utf8 %d" % i, s)

# Repeats
for ch, n in [("a", 5), ("a", 6), ("a", 100), ("a", 4096), ("ő", 50), ("😀", 40), (" ", 300), ("\n", 64),
              ("ab", 200), ("abc ", 300), ("Hello, World! ", 100), ("\x00", 100), ("\xff", 1)]:
    data = (ch * n).encode("utf-8") if ch != "\xff" else b"\xff" * 4096
    add("repeat %r x %d" % (ch, n), data[:4096])

# Sizes around 1024 and 4096 bytes, from the English and Hungarian samples
EN = (SAMPLES["en_long"] + SAMPLES["en_med"]) * 6
HU = (SAMPLES["hu_med"] + SAMPLES["hu_short"]) * 10
for n in (900, 1000, 1023, 1024, 1025, 1100, 2048, 4000, 4095, 4096):
    add("english %d" % n, EN.encode()[:n])
    hb = HU.encode()[:n]
    add("hungarian %d" % n, hb)

# Random printable text, words and numbers
WORDS = ("the of and to in is you that it he was for on are as with his they at be this have from "
         "or one had by word but not what all were we when your can said there use an each which she "
         "do how their if will up other about out many then them these so some her would make like "
         "water bridge police station north entrance meet tomorrow morning message relay "
         "találkozzunk állomás holnap reggel üzenet híd rendőrség víz út gyere").split()
for i in range(30):
    n = R.choice([3, 10, 40, 120, 400])
    words = []
    for _ in range(n):
        w = R.choice(WORDS)
        r = R.random()
        if r < 0.1:
            w = w.capitalize()
        elif r < 0.13:
            w = w.upper()
        elif r < 0.18:
            w = str(R.randint(0, 100000))
        words.append(w + R.choice(["", "", "", ",", ".", "!", "?", ":", ";", "\n"]))
    add("random words %d" % i, " ".join(words).encode()[:4096])

# Random bytes (must round-trip even if they expand)
for i, n in enumerate([1, 2, 3, 5, 8, 16, 31, 64, 100, 255, 256, 500, 1000, 1024, 2000, 3000, 4095, 4096]):
    add("random bytes %d" % n, bytes(R.getrandbits(8) for _ in range(n)))
for i in range(10):
    n = R.randint(1, 300)
    add("random ascii controls %d" % i, bytes(R.randint(0, 127) for _ in range(n)))

# Random code points
for i in range(10):
    cps = []
    for _ in range(R.randint(1, 200)):
        rng = R.choice([(0x20, 0x7E), (0xA0, 0x24F), (0x370, 0x4FF), (0x4E00, 0x9FFF), (0x1F300, 0x1FAFF),
                        (0x800, 0xD7FF), (0x10000, 0x10FFFF)])
        cps.append(chr(R.randint(*rng)))
    add("random code points %d" % i, "".join(cps).encode("utf-8", "surrogatepass")[:4096])

for name, data in OUT:
    sys.stdout.write("# %s\n%s\n" % (name.replace("\n", "\\n").encode("unicode_escape").decode("ascii"),
                                       data.hex()))
sys.stderr.write("%d corpus entries\n" % len(OUT))

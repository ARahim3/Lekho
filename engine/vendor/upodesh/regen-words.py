#!/usr/bin/env python3
"""Rebuild the word list behind Lekho's src/words.fst.

    regen-words.py <upstream data/source-words.txt> <output source-words.txt>

Then compile it with upstream's generate tool (see PATCHES.md).
"""
import sys
import unicodedata
from pathlib import Path

# Mis-encoded entries left out instead of repaired: যেকোন would outrank the
# standard যেকোনো, and the other three are misspellings.
DROP = {"যেকোন", "পৌছে", "পৌছাতো", "কোনধরণ"}


def encode(word):
    """The dictionary's encoding: ো and ৌ as single code points (NFC), and
    য় ড় ঢ় precomposed (NFC would split them)."""
    word = unicodedata.normalize("NFC", word)
    return (word.replace("য়", "য়")
                .replace("ড়", "ড়")
                .replace("ঢ়", "ঢ়"))


def main(source, output):
    words = set()
    for line in open(source, encoding="utf-8"):
        word = line.strip()
        if not word:
            continue
        fixed = encode(word)
        if fixed != word and fixed in DROP:
            continue
        words.add(fixed)
    extra = Path(__file__).parent / "data" / "lekho-extra-words.txt"
    words |= {encode(line.strip()) for line in open(extra, encoding="utf-8") if line.strip()}
    Path(output).write_text("\n".join(sorted(words)) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])

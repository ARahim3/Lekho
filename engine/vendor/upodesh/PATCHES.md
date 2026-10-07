# Lekho's patches to upodesh 0.4.0

upodesh is the dictionary-search crate riti uses for phonetic suggestions. This
is the published 0.4.0 crate (upstream commit `2aee9a5`) with the fixes below;
every file not listed is byte-identical to it. `engine/Cargo.toml` swaps it in
with `[patch.crates-io]`. Remove both once upstream ships fixes 1–5 (the word
list in 6 would then need a new home).

riti switched from a regex search (okkhor's `REGEX_PATTERNS`) to upodesh in
June 2025. Typing each of the 159k dictionary words the plain way (~202k inputs),
1,143 words the regex search found were unreachable with 0.4.0, and nothing
was gained. With these patches there are no regressions left.

## What was wrong

1. **`ddh` and `dhm` patterns.** Their `dh` part had been replaced by `dg`'s
   `([দড](্?)(গ|(জ্ঞ)))`, so no দ্ধ or ধ্ম word could match: মুক্তিযোদ্ধা, যুদ্ধ,
   বুদ্ধি, শ্রদ্ধা, সিদ্ধান্ত, উদ্ধার… Fixed by putting the `dh` pattern back.
2. **`bbh` was missing.** `sobbho` no longer found সভ্য. Added, same shape as `ddh`.
3. **Word-initial `oi`, `ou`, `oo`.** `fix_string` capitalizes a word-initial
   `o`, and only a plain `O` pattern exists, so ঐ/ঔ words (ঐতিহ্য, ঐক্য, ঔষধ)
   were unreachable. Added `Oi`, `Ou`, `Oo`: the `oi`/`ou`/`oo` alternatives with
   the o part non-optional, like `O`.
4. **First block of the input.** `suggest()` didn't back off when the input
   starts with a prefix of a longer pattern that isn't a pattern itself (`jn…`
   is a prefix of `jng`), and returned nothing (জ্ঞান for `jnan`). It now backs
   off like the later blocks already did.

5. **Mis-encoded dictionary entries.** 54 words were stored with ো or ৌ as two
   code points (ে + া, ে + ৗ) while the patterns use the single code point, so no
   input could ever reach them. Among them were কোনো, ছিলো, আরো, অনুরোধ and
   আয়োজন; 39 of the 54 also had a correctly encoded copy. 50 are now stored in
   the dictionary's normal encoding. Four are left out instead:
   - যেকোন, because it would outrank the standard যেকোনো for `jekono`;
   - the misspellings পৌছে, পৌছাতো and কোনধরণ.

   The regex search had the same blind spot, so this is a fix, not a
   regression.
6. **Added words.** `data/lekho-extra-words.txt` holds 62 frequent standard
   words that plain typing couldn't reach before:
   - কী, হঠাৎ, স্যার, আরেকটু, পুরোনো…
   - modern ো-forms such as হলো, বলো, করছো, বলেছো.

   They were picked from the most frequent words of a Bengali usage list
   (OpenSubtitles-based FrequencyWords); misspellings, names, joined negations
   (পারোনা) and slang were left out.

The effect of 5 and 6, typing every dictionary word the plain way (~186k inputs):
- Phonetic-first's default changed 0 times.
- Smart's default changed twice: `paroni` gives পারোনি instead of পারণই, and a rare compound typed with a trailing o.
- No suggestion list lost a word.

## Files changed

- `data/source-regex-patterns.json`: the six patterns above (the source of truth).
- `data/preprocessed-patterns.json`: those six keys re-exploded with upstream's
  generator; all other keys untouched.
- `src/avro/patterns.fst`: regenerated with upstream's generator (new keys).
- `src/avro/suggest.rs`:
  - first-block back-off;
  - `test_lekho_patches` and `test_lekho_words`;
  - upstream's `sar` expectation now includes the added স্যার.
- `src/words.fst`: regenerated from upstream's word list with fixes 5 and 6.
- `data/lekho-extra-words.txt`: the added words.
- `regen-words.py`: rebuilds that word list from upstream's.
- `Cargo.toml`: trimmed to what building needs; `publish = false`.
- Not copied: `data/dictionary.json`, `data/source-words.txt` (`src/words.fst`
  is compiled from the latter), benches, examples.

## Regenerating

Use upstream's `generate` tool from a clone of github.com/OpenBangla/upodesh at
`2aee9a5` (`cd generate && cargo build --release`):

```sh
# Exploded patterns: copy only the keys you changed into data/preprocessed-patterns.json
generate explode data/source-regex-patterns.json /tmp/exploded.json

# patterns.fst and words.fst (word list = upstream's, run through regen-words.py):
mkdir -p /tmp/t/generate /tmp/t/data /tmp/t/src/avro
./regen-words.py <upstream>/data/source-words.txt /tmp/t/data/source-words.txt
cp data/preprocessed-patterns.json /tmp/t/data/
CARGO_MANIFEST_DIR=/tmp/t/generate generate
cp /tmp/t/src/avro/patterns.fst src/avro/
cp /tmp/t/src/words.fst src/
```

To add a word, append it to `data/lekho-extra-words.txt` and regenerate. Watch
the encoding: য়, ড়, ঢ় must be single code points (U+09DF, U+09DC, U+09DD) and
ো, ৌ single code points too; `regen-words.py` normalizes this.

Run `make test` afterwards (it runs this crate's tests too).

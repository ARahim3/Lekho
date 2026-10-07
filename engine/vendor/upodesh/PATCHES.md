# Lekho's patches to upodesh 0.4.0

upodesh is the dictionary-search crate riti uses for phonetic suggestions. This
is the published 0.4.0 crate (upstream commit `2aee9a5`) with the fixes below;
every file not listed is byte-identical to it. `engine/Cargo.toml` swaps it in
with `[patch.crates-io]`. Remove both once upstream ships these fixes.

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

## Files changed

- `data/source-regex-patterns.json`: the six patterns above (the source of truth).
- `data/preprocessed-patterns.json`: those six keys re-exploded with upstream's
  generator; all other keys untouched.
- `src/avro/patterns.fst`: regenerated with upstream's generator (new keys).
- `src/avro/suggest.rs`: first-block back-off, plus `test_lekho_patches`.
- `Cargo.toml`: trimmed to what building needs; `publish = false`.
- Not copied: `data/dictionary.json`, `data/source-words.txt` (`src/words.fst`
  is their compiled form), benches, examples.

## Regenerating

Use upstream's `generate` tool from a clone of github.com/OpenBangla/upodesh at
`2aee9a5` (`cd generate && cargo build --release`):

```sh
# Exploded patterns: copy only the keys you changed into data/preprocessed-patterns.json
generate explode data/source-regex-patterns.json /tmp/exploded.json

# patterns.fst (it also rebuilds words.fst, which must come out unchanged):
mkdir -p /tmp/t/generate /tmp/t/data /tmp/t/src/avro
cp <upstream>/data/source-words.txt data/preprocessed-patterns.json /tmp/t/data/
CARGO_MANIFEST_DIR=/tmp/t/generate generate
cp /tmp/t/src/avro/patterns.fst src/avro/
```

Run `make test` afterwards (it runs this crate's tests too).

# upodesh
`upodesh` (In Bangla, `উপদেশ` is a synonym of the word `পরামর্শ` which means `suggestion`) is a Bangla word suggestion library.

This implementation uses an approach based on the Finite State Transducer (FST) data structure which is substantially faster than the Regular Expression based approach. This approach is inspired by the Go project [`libavrophonetic`](https://github.com/mugli/libavrophonetic/) of Mehdi Hasan Khan which used Trie data structure.

## Benchmarks
`upodesh` is significantly faster than the previously used heavily optimized regex-based search approach in OpenBangla Keyboard. Based on recent benchmarks, it is approximately ~21× to ~58× faster, depending on the input. This demonstrates a substantial performance gain over regex, especially in cases where large patterns previously caused bottlenecks.
### 📊 Summary of the Benchmark
This benchmark was performed on a Apple MacBook Air M1:

| Word   | `upodesh` Time | `regex` Time | Speedup         |
| --------- | -------------- | ------------ | --------------- |
| `a`       | ~3.341 µs      | ~194.34 µs    | **\~58× faster**  |
| `arO`     | ~11.840 µs      | ~246.53 µs    | **\~20.8× faster**  |
| `bistari` | ~9.734 µs      | ~353.74 µs    | **\~36.3× faster** |



## Acknowledgement
* [Mehdi Hasan Khan](https://github.com/mugli) and [Tahmid Sadik](https://github.com/tahmidsadik/) for their [`libavrophonetic`](https://github.com/mugli/libavrophonetic/) project.
* [Andrew Gallant](https://github.com/BurntSushi) for his amazing [`fst`](https://github.com/BurntSushi/fst) crate and [Index 1,600,000,000 Keys with Automata and Rust](https://burntsushi.net/transducers/) blog post!

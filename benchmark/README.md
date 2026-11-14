# Benchmarks

CRC throughput benchmark for the Dart VM.

```sh
dart run benchmark/crc_benchmark.dart
```

Runs `computeArV1` and `computeArV2` against ~10 MiB of synthetic
44.1 kHz 16-bit stereo PCM (one minute of CD audio), reports best /
median wall-clock time and MiB/s.

Each CRC is run on an aligned buffer and on the same bytes viewed 2
bytes into a larger buffer — the layout `extractPcmFromWav` returns
when chunks before `data` leave the payload misaligned. Misaligned
input is copied before checksumming, so the difference between the
two rows is the cost of that copy.

The benchmark is VM-only — the web (dart2js / dart2wasm) CRC path
uses a separate split 16-bit multiply implementation and is
exercised for correctness by
`test/accuraterip_crc_differential_test.dart`.

# Benchmarks

CRC throughput benchmark for the Dart VM.

```sh
dart run benchmark/crc_benchmark.dart
```

Runs `computeArV1` and `computeArV2` against ~10 MiB of synthetic
44.1 kHz 16-bit stereo PCM (one minute of CD audio), reports best /
median wall-clock time and MiB/s.

The benchmark is VM-only — the web (dart2js / dart2wasm) CRC path
uses a separate split 16-bit multiply implementation and is
exercised for correctness by
`test/accuraterip_crc_differential_test.dart`.

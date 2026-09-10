# Portable SDK study results

The completed Clang 23 ARM64 comparison retains native SDK libraries: the best
matched SDK improves balanced latency by about 8.6%, below the required 10%.
Windows compatibility passes on both architectures. Linux Clang 22 and macOS
hosted trials remain in progress; their results can change their own platform
recommendations. No production SDK release or setup default has changed.

## Linux ARM64 reference comparison

The screen includes 16 native-SDK configurations and six matched-SDK
configurations, using GCC 14 and Clang 23. Native means that the SDK archives
contain native objects; these builds retain portable CPU targets. Both finalists
use Clang 23, full LTO for Core, benchmark-only compiler PGO for Core and its
SDK dependencies, and BOLT. SDK PGO covers the 165 archive targets in Core's
dependency closure, not every SDK library.

Two twelve-round screens collected 528 samples. The second screen had timing
spikes, so two additional twelve-round comparisons measured only the finalists.
All 576 samples are retained. The best native configuration was
`M-PGO-native-clang-bench-both-bolt`; the matched finalist was
`M-PGO-clang-bench-both-bolt`.

| Finalist comparison | Matched/native latency |    95% interval | Matched gain | Runtime gate |
| ------------------- | ---------------------: | --------------: | -----------: | ------------ |
| Repeat 1            |                0.91425 | 0.91088–0.91728 |        8.57% | Fail         |
| Repeat 2            |                0.91342 | 0.90992–0.91699 |        8.66% | Fail         |

Neither repeat has a confirmed individual workload regression above 3%. Both
upper latency bounds exceed 0.90, so the matched SDK fails the adoption rule.
The native finalist wheel is 38,498,907 bytes; the matched wheel is 40,979,706
bytes, 6.4% larger. Complete hosted SDK and wheel costs remain a separate gate.

These are DGX Spark ARM64 measurements of the Clang 23 reference, using Core
`706fd8f95e38c29451d97e88cfdf6022a55020fe`, LLVM 23.1.0, CPython 3.14.7, and
held-out benchmark SHA-256
`fcf65d90f27cd14f636ca99291b1ba46ab1701ef2fb769d1acb70fc73d09adc6`. Both cohorts
use the same repaired wheel hashes, one pinned CPU, fresh processes, and equal
family weights. They do not substitute for Clang 22, x86-64, or macOS
measurements.

The [raw samples and decisions](results/linux-arm64-native-pgo.tar.gz) include
both screens and both finalist repeats. The
[archive manifest](results/linux-arm64-native-pgo.json) records each file's
SHA-256. Extract the archive into `build/` to replay the final gate:

```console
tar -xzf experiments/results/linux-arm64-native-pgo.tar.gz -C build
python3 experiments/decide_optimization.py \
  build/native-finalists/cohort-1/evaluation/comparison-20260910-224326.json \
  build/native-finalists/cohort-2/evaluation/comparison-20260910-224448.json \
  --native M-PGO-native-clang-bench-both-bolt \
  --matched M-PGO-clang-bench-both-bolt \
  --output build/native-finalists/replayed-decision.json
```

## Windows compatibility

[Native SDK compatibility](https://github.com/munich-quantum-software/portable-mlir-toolchain/actions/runs/34538055244)
passes for x64 and ARM64 using the original repaired wheels from
[the build run](https://github.com/munich-quantum-software/portable-mlir-toolchain/actions/runs/34535339421).
Both original jobs passed wheel construction, repair, C++ tests, and installed
checks. Their test consumer exceeded Windows' default stack size; allocating its
DD package on the heap fixed the consumer. The retry verified the original wheel
hashes and passed fresh installed checks and consumer configure/build/execution.

| Platform      | Wheel bytes | Installed Python checks                  | Consumer |
| ------------- | ----------: | ---------------------------------------- | -------- |
| Windows x64   |  30,837,035 | 1,183 passed, two skipped                | Pass     |
| Windows ARM64 |  26,292,256 | Numerical, compiler, QIR, and CLI checks | Pass     |

ARM64 retains the existing release dependency limit instead of running the full
Python test group. This is compatibility evidence; Windows optimization settings
remain unchanged. Full provenance and per-stage timings are in the two workflow
artifacts.

## Remaining platform gates

The SDK repository schedules all remaining work. Completed Linux ARM64 full-LTO
and macOS ARM64 ThinLTO SDK archives were transferred into
[SDK-owned artifacts](https://github.com/munich-quantum-software/portable-mlir-toolchain/actions/runs/34535339411).
The Linux SDK pipeline took 48.5 minutes with an 11.7 GiB container peak and no
swap. The macOS SDK pipeline took 60.7 minutes with a 3.2 GiB sampled
process-tree peak. These timings exclude artifact transfer and are not complete
wheel costs.

The remaining work is the hosted LTO screen, Core-only and combined PGO for
native and matched finalists, paired runtime evaluation, full cold/warm costs,
and recipe selection for each platform. The macOS producer and consumers use
Xcode 26.6, SDK deployment target 11.0, and Core deployment target 13.3. Linux
uses the pinned manylinux 2.28 image and prebuilt Clang 22.1.8.1.

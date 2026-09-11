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

## Hosted SDK screen

All nine SDK library variants built and were uploaded. The
[SDK measurements](results/sdk-screen.json) record source jobs, artifact
digests, download/upload times, and resource usage. Job work includes setup and
artifact transfer, and excludes queue time. Every Linux container used four CPUs
and a 16 GiB memory limit with no swap; macOS used three build workers on its
standard runner.

| Platform    | SDK LTO | Job work (min) | Trial artifact (MiB) | Peak memory (GiB) |
| ----------- | ------- | -------------: | -------------------: | ----------------: |
| linux-arm64 | OFF     |           54.0 |                779.7 |              11.6 |
| linux-arm64 | Thin    |           48.5 |                886.6 |              11.8 |
| linux-arm64 | Full    |           48.9 |                885.8 |              11.7 |
| linux-x64   | OFF     |           48.5 |                816.1 |              12.0 |
| linux-x64   | Thin    |           60.3 |                923.5 |              12.0 |
| linux-x64   | Full    |           59.6 |                922.9 |              11.8 |
| macos-arm64 | OFF     |           48.4 |                559.7 |               3.3 |
| macos-arm64 | Thin    |           61.3 |                672.5 |               3.2 |
| macos-arm64 | Full    |           67.3 |                665.8 |               3.1 |

Linux memory is the container peak, including filesystem cache. macOS memory is
the sampled process-tree RSS; macOS swap was not measured. These are individual
hosted observations, not build-time confidence intervals. Trial archives use
Python's default zstd compression; production packaging uses `-19 --long=31`.
The listed artifact sizes are not production release size estimates. Finalist
packaging must use the production settings before making that comparison.

The macOS ThinLTO job completed every recorded step, including build, packaging,
and upload, before the migration cancellation marked its job cancelled. The
archive was verified and transferred to the SDK repository. Its earlier harness
did not run the standalone SDK consumer; the Core build and installed-package
checks remain required. All eight other SDK variants passed that consumer.

## Remaining platform gates

All six native-SDK Linux recipes passed their C++ tests, plain/BOLT
repaired-wheel checks, and producer-Clang/GCC consumers. Complete job work took
15.4–31.9 minutes on ARM64 and 19.9–35.3 minutes on x86-64, with container peaks
below 13.6 GiB and no swap. Both paired cohorts on each architecture selected
full Core LTO with BOLT. Their Core-only and combined PGO trials also measure a
clean warm-cache rebuild, avoiding another cold pipeline solely to obtain cache
measurements.

The first four Linux ThinLTO-SDK wheel jobs crashed in the static, musl-linked
LLD shipped by manylinux's Clang package. An LLVM-only reproducer also crashed:
the faulting instruction writes into a worker thread's stack guard. Setting the
linker's `PT_GNU_STACK` size to 8 MiB made that same link and runtime check
pass. The study records the original/configured linker hashes and changes no
executable code or stack permissions. The
[reproducer and evidence](results/linux-thin-linker-stack.tar.gz) have a
[hash manifest](results/linux-thin-linker-stack.json). Full hosted wheel retries
remain required. The static musl build is documented in the
[compiler package recipe](https://github.com/mayeut/static-clang-images/blob/v22.1.8.1/Dockerfile).

The macOS native-SDK screen exposed a separate Core build issue: its MLIR helper
disables RTTI after the QDMI adapter explicitly requests it. The unknown-device
exception then becomes `unknown exception`. A recorded study CMake override
restores the adapter's requested RTTI setting while preserving the pinned Core
source. Corrected package validation remains required; the superseded macOS LTO
jobs were cancelled.

The remaining work is repaired-wheel validation, Core-only and combined PGO for
native and matched finalists, paired runtime evaluation, full cold/warm costs,
production-setting archive measurements, and recipe selection for each platform.
The macOS producer and consumers use Xcode 26.6, SDK deployment target 11.0, and
Core deployment target 13.3. Linux uses the pinned manylinux 2.28 image and
prebuilt Clang 22.1.8.1.

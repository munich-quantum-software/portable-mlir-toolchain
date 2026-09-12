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

## Linux Clang 22 screen

All twelve Linux screening recipes passed their C++ tests, plain/BOLT
repaired-wheel checks, and producer-Clang/GCC consumers. The
[wheel measurements](results/linux-wheel-screen.json) retain complete job work,
per-stage times, compiler identity, memory, and cache statistics. Job work
includes setup and artifact transfer, and excludes queue time. All containers
used four CPUs, at most 16 GiB of memory, and no swap.

| SDK LTO | Core LTO | ARM64 job work (min) | x86-64 job work (min) |
| ------- | -------- | -------------------: | --------------------: |
| OFF     | OFF      |                 15.5 |                  20.0 |
| OFF     | Thin     |                 31.9 |                  35.4 |
| OFF     | Full     |                 28.0 |                  31.7 |
| Thin    | Thin     |                132.7 |                 146.4 |
| Thin    | Full     |                128.9 |                 124.9 |
| Full    | Full     |                 99.9 |                  80.3 |

All four native-SDK PGO trials also passed. Each uses full Core LTO and produces
both plain and BOLT wheels. Peak container memory across the sixteen recipes was
13.8 GiB; no swap was used.

| Platform | PGO scope | Job work including warm probe (min) | Cold pipeline (min) | Warm rebuild and checks (min) |
| -------- | --------- | ----------------------------------: | ------------------: | ----------------------------: |
| ARM64    | Core      |                                44.3 |                40.9 |                           3.0 |
| ARM64    | SDK/Core  |                               124.6 |               119.8 |                           4.3 |
| x86-64   | Core      |                                41.3 |                37.5 |                           2.4 |
| x86-64   | SDK/Core  |                               190.2 |               185.1 |                           4.1 |

Cold pipelines include provisioning, profile generation and use, C++ tests,
BOLT, wheel repair, and installed checks. SDK/Core PGO rebuilds the dependency
archive closure: 163 targets on ARM64 and 162 on x86-64. Warm probes clean and
rebuild those archives and the Core wheel with the existing profile, then run
staged Python checks. They exclude C++ test builds, fresh training, BOLT,
repair, and transfer. The warm probes recorded 113 cache hits for Core-only
builds and 2,257/2,263 hits for the combined ARM64/x86-64 builds, with no misses
or errors.

Two independent twelve-round cohorts per architecture evaluated sixteen wheel
variants, for 768 fresh-process samples. All four cohorts selected full Core
LTO, combined SDK/Core PGO, and BOLT as the native-SDK finalist. All four
selected full SDK/Core LTO with BOLT as the matched recipe to advance to PGO.
These are screening choices, not adoption decisions: the matched Core-only and
combined PGO builds are still running. The
[raw screens](results/linux-clang22-screen.tar.gz) and
[manifest](results/linux-clang22-screen.json) retain samples, artifact hashes,
host records, rankings, and finalist selections.

The first four Linux ThinLTO-SDK wheel jobs crashed in the static, musl-linked
LLD shipped by manylinux's Clang package. An LLVM-only reproducer also crashed:
the faulting instruction writes into a worker thread's stack guard. Setting the
linker's `PT_GNU_STACK` size to 8 MiB made that same link and runtime check
pass. The study records the original/configured linker hashes and changes no
executable code or stack permissions. The
[reproducer and evidence](results/linux-thin-linker-stack.tar.gz) have a
[hash manifest](results/linux-thin-linker-stack.json). All four hosted wheel
retries passed. Their complete measured pipelines took 124.3–145.0 minutes. The
static musl build is documented in the
[compiler package recipe](https://github.com/mayeut/static-clang-images/blob/v22.1.8.1/Dockerfile).

## Remaining platform gates

The original macOS native-SDK screen failed the unknown-device exception check:
the original error became `unknown exception`. A
[minimal reproducer](results/macos-exception-reproducer.tar.gz), with a
[hash manifest](results/macos-exception-reproducer.json), shows that linking a
translation unit which catches `std::exception` without RTTI can prevent an
otherwise RTTI-enabled handler from matching a standard exception thrown by a
shared library. Enabling RTTI only in the QDMI adapter was therefore
insufficient.

macOS trials now use Core `8d520eb04fc301b5dba85a8e4c2587ba410fb533`, which
honors explicit RTTI requirements for the adapter and its tests and separates
the benchmark exception handler from LLVM command-line types. Ordinary benchmark
file and argument errors return diagnostics directly, and the QDMI adapter no
longer catches and rethrows an exception merely to translate it. The complete
local Linux C++ suite passes with mold 2.42.1: 3,226 passed and one skipped.
macOS wheel validation remains pending. Linux measurements retain their frozen
Core revision; no previous macOS wheel is accepted.

The remaining work is repaired-wheel validation, Core-only and combined PGO for
native and matched finalists, paired runtime evaluation, full cold/warm costs,
production-setting archive measurements, and recipe selection for each platform.
The macOS producer and consumers use Xcode 26.6, SDK deployment target 11.0, and
Core deployment target 13.3. Linux uses the pinned manylinux 2.28 image and
prebuilt Clang 22.1.8.1.

## Released mold qualification

[mold 2.42.1](https://github.com/rui314/mold/releases/tag/v2.42.1) includes the
emitted-relocation fix used in the earlier patched 2.42.0 experiment. Its
unmodified ARM64 release passes the local-symbol relocation reproducer and both
Core QIR links previously rejected for duplicate symbols in mixed native/LTO
archives. The linked programs execute successfully with their expected results.
Neither the patch nor `--no-relax` or `--no-fork` was used.

Relinking the earlier full-LTO `mlir-tblgen` also passes relocation inspection
and execution. BOLT still rejects an ADR in its non-simple `p_ere` function.
This is a remaining BOLT limitation; releasing the mold fix did not resolve it.
The selected SDK design retains native tools without BOLT rewriting.

The [replay records](results/mold-2.42.1-replay.tar.gz) and their
[hash manifest](results/mold-2.42.1-replay.json) retain both successes and the
BOLT failure. The Linux SDK recipe now selects mold 2.42.1. Fresh native SDK
builds and installation tests on both architectures and assertion modes are
running in the
[Linux qualification workflow](https://github.com/munich-quantum-software/portable-mlir-toolchain/actions/runs/34683842047).
Existing runtime samples continue to identify their original linker binaries.

# Portable SDK study results

Both ARM64 comparisons retain native SDK libraries. The matched SDK improves
balanced latency by about 8.6% with the Clang 23 reference and 3.3% in the
hosted Clang 22 study, below the required 10%. Windows compatibility passes on
both architectures. The x86-64 and macOS PGO trials remain in progress. No
production SDK release or setup default has changed.

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

[Fresh native-SDK compatibility builds](https://github.com/munich-quantum-software/portable-mlir-toolchain/actions/runs/34688341748)
pass for x64 and ARM64 at Core `9e776ddb4bd1d9eede04a08cb814394367a84884`,
including its error-handling fixes. Both jobs passed wheel construction, repair,
C++ tests, installed checks, and consumer configure/build/execution.

| Platform      | Wheel bytes | Installed Python checks                  | Consumer |
| ------------- | ----------: | ---------------------------------------- | -------- |
| Windows x64   |  30,839,022 | 1,183 passed, two skipped                | Pass     |
| Windows ARM64 |  26,293,892 | Numerical, compiler, QIR, and CLI checks | Pass     |

ARM64 retains the existing release dependency limit instead of running the full
Python test group. This is compatibility evidence; Windows optimization settings
remain unchanged. The [retained records](results/windows-compatibility.tar.gz)
and [manifest](results/windows-compatibility.json) preserve wheel hashes,
compiler identity, per-stage commands, timings, and validation logs. The
consumer allocates its DD package on the heap to fit Windows' default stack
size.

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
The listed artifact sizes are not production release size estimates. Linux and
macOS production-compression measurements follow below.

The macOS ThinLTO job completed every recorded step, including build, packaging,
and upload, before the migration cancellation marked its job cancelled. The
archive was verified and transferred to the SDK repository. Its earlier harness
did not run the standalone SDK consumer; the Core build and installed-package
checks remain required. All eight other SDK variants passed that consumer.

## Production SDK compression

[Recompression](https://github.com/munich-quantum-software/portable-mlir-toolchain/actions/runs/34686211289)
of the verified Linux OFF/Full trial SDKs passed using the release zstd 1.5.7
executables and the production `-19 --long=31 --threads=0` settings. Each
archive passed checksum validation after compression. The jobs retained the
resulting archives, updated manifests, input hashes, and resource measurements.
The [retained records](results/linux-sdk-packaging.tar.gz) and
[summary manifest](results/linux-sdk-packaging.json) preserve these
measurements.

| Platform | SDK LTO | Production archive (MiB) | Compression (min) |
| -------- | ------- | -----------------------: | ----------------: |
| ARM64    | OFF     |                    297.2 |               6.5 |
| ARM64    | Full    |                    386.0 |               6.2 |
| x86-64   | OFF     |                    299.9 |              12.1 |
| x86-64   | Full    |                    392.0 |              10.4 |

Full-LTO archives are about 30% larger than the corresponding native archives
with these settings. Compression used four CPUs, peaked below 4.1 GiB, and used
no swap. These measurements reuse the completed SDK builds; compression time is
reported separately from the original cold-build jobs. They qualify packaging of
the Clang 22 study libraries, not a change to the public SDK's compiler.

The
[macOS recompression](https://github.com/munich-quantum-software/portable-mlir-toolchain/actions/runs/34695314027)
also passed all three variants on the standard three-CPU runner. The
[records](results/macos-sdk-packaging.tar.gz) and
[manifest](results/macos-sdk-packaging.json) retain input and output identities.

| macOS SDK LTO | Production archive (MiB) | Compression (min) |
| ------------- | -----------------------: | ----------------: |
| OFF           |                    227.7 |               5.8 |
| Thin          |                    331.4 |               9.4 |
| Full          |                    327.0 |               6.2 |

LTO archives are 44-46% larger. Sampled process-tree RSS stayed below 3 GiB;
swap was not measured. These jobs reused the Xcode 26.6 SDK libraries and did
not rebuild them.

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
These are screening choices, not adoption decisions. The
[raw screens](results/linux-clang22-screen.tar.gz) and
[manifest](results/linux-clang22-screen.json) retain samples, artifact hashes,
host records, rankings, and finalist selections.

The ARM64 matched-SDK combined-PGO trial failed during the instrumented Core
build. LLD was killed while linking `libmqt-core-qdmi-ddsim-device.so`, with
14.8 GiB recorded container memory and no swap. The job already used one
concurrent link and one LTO partition. Its pipeline stopped after 84.7 minutes,
before producing a validated wheel, so this recipe fails hosted feasibility. The
[failure records](results/linux-matched-pgo-failures.tar.gz) and
[manifest](results/linux-matched-pgo-failures.json) retain commands, resource
measurements, and diagnostics. The kill is consistent with memory pressure;
kernel OOM events were not retained. Both matched Core-only trials passed. Their
complete pipelines, including warm rebuild probes, took 156.7 minutes on ARM64
and 97.5 minutes on x86-64. The x86-64 combined-PGO trial continues.

The final ARM64 comparison evaluated all eighteen feasible variants in two
twelve-round cohorts, collecting 432 samples. Both select the native SDK with
full Core LTO, combined SDK/Core PGO, and BOLT. The best admissible matched
recipe uses full SDK/Core LTO, Core-only PGO, and BOLT.

| Cohort | Matched/native latency |    95% interval | Matched gain | Runtime gate |
| ------ | ---------------------: | --------------: | -----------: | ------------ |
| 1      |                0.96745 | 0.96236–0.97054 |        3.26% | Fail         |
| 2      |                0.96697 | 0.96393–0.97233 |        3.30% | Fail         |

Neither cohort has a confirmed individual workload regression above 3%. Both
upper bounds exceed 0.90, so native SDK libraries remain the recommendation. The
[raw final evaluations](results/linux-arm64-clang22-final.tar.gz) and
[hash manifest](results/linux-arm64-clang22-final.json) retain all samples,
original rankings, host records, and the separate decision calculation. This
Clang 22 result and the earlier Clang 23 result use different hosts and Core
revisions; a neutral compiler comparison remains outstanding.

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

## macOS screen

The original macOS native-SDK screen failed the unknown-device exception check:
the original error became `unknown exception`. A
[minimal reproducer](results/macos-exception-reproducer.tar.gz), with a
[hash manifest](results/macos-exception-reproducer.json), shows that linking a
translation unit which catches `std::exception` without RTTI can prevent an
otherwise RTTI-enabled handler from matching a standard exception thrown by a
shared library. Enabling RTTI only in the QDMI adapter was therefore
insufficient.

macOS trials now use Core `9e776ddb4bd1d9eede04a08cb814394367a84884`. The
[diagnostic run](https://github.com/munich-quantum-software/portable-mlir-toolchain/actions/runs/34686608949)
retains object symbols and a link map showing that the no-RTTI CLI translation
unit emitted private standard-exception typeinfo through inline library code.
That typeinfo prevented its RTTI-enabled handler from matching exceptions thrown
by the benchmark shared library.

The frozen study revision uses a separate RTTI-enabled CLI handler. All six
recipes now pass C++ and CLI tests, wheel repair, 1,184 installed Python tests
(one skipped), and the installed CMake consumer. The
[retained wheel records](results/macos-wheel-screen.tar.gz) and
[summary manifest](results/macos-wheel-screen.json) record each complete
pipeline and its validation commands.

| SDK LTO | Core LTO | Pipeline (min) | Peak process-tree RSS (GiB) |
| ------- | -------- | -------------: | --------------------------: |
| OFF     | OFF      |           10.0 |                         2.3 |
| OFF     | Thin     |           23.5 |                         2.1 |
| OFF     | Full     |           15.3 |                         2.4 |
| Thin    | Thin     |          105.7 |                         2.6 |
| Thin    | Full     |           90.5 |                         2.6 |
| Full    | Full     |           67.3 |                         4.4 |

Two twelve-round cohorts evaluated all six variants, collecting 144 samples.
Both select native SDK libraries with ThinLTO for Core. The first selects full
SDK/Core LTO among the matched variants; the second selects ThinLTO SDK
libraries with full Core LTO. Both matched candidates advance because their
ranking is not stable across cohorts. The
[raw screen](results/macos-lto-screen.tar.gz) and
[hash manifest](results/macos-lto-screen.json) preserve the results, including
their wide confidence intervals.

The initial native-SDK Core PGO trial failed when importing `dd.abi3.so`: its
profile data referenced the unresolved private alias `l_PyInit_dd.local`.
Disabling symbol stripping reproduced the same failure. A small instrumented
module fails with LLVM's `-flat_namespace` and loads when two-level namespaces
are restored.
[Upstream MLIR](https://github.com/llvm/llvm-project/blob/llvmorg-23.1.0/mlir/cmake/modules/AddMLIRPython.cmake)
applies that namespace restoration to its Python modules. The
[full Core diagnostic](https://github.com/munich-quantum-software/portable-mlir-toolchain/actions/runs/34695260514)
passes with that policy: profile generation, training, profile use, C++ tests,
wheel repair, installed Python checks, and the CMake consumer. It took 12.7
minutes and peaked at 2.3 GiB. The
[reproducer and Core records](results/macos-profile-namespace.tar.gz) have a
[hash manifest](results/macos-profile-namespace.json).

Core `cc3f08f5` applies the namespace restoration to all Python modules. The six
ordinary recipes are being rebuilt with this revision so that the final PGO
comparison uses identical source and link policies. Core-only and combined
SDK/Core PGO advance on native/Thin, Thin/Full, and Full/Full. The earlier
screening records remain unchanged.

The current-main repair in
[PR #2545](https://github.com/munich-quantum-toolkit/core/pull/2545) returns
QDMI and benchmark diagnostics before entering MLIR. Its adapter, generator, and
CLI compile without exceptions or RTTI; the earlier split CLI and platform
overrides have been removed. Local validation passed 3,544 C++ tests, with one
existing test skipped, and all 43 Python QDMI compilation tests. Hosted CI also
passes on Linux, macOS, and Windows at `bb0ae8208`. These changes do not alter
the frozen sources of the retained timing samples.

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

The native SDK integration consumer also passes mold linking, BOLT rewriting,
execution, and byte-for-byte recovery after failed training on ARM64. The SDK
installation check now uses mold instead of its BFD workaround.
[Updated hosted installation checks](https://github.com/munich-quantum-software/portable-mlir-toolchain/actions/runs/34690021713)
pass on both Linux architectures and assertion modes using the fresh SDK
archives. The assertion-free consumers also pass BOLT rewriting and
byte-for-byte recovery after failed training.

Relinking the earlier full-LTO `mlir-tblgen` also passes relocation inspection
and execution. BOLT still rejects an ADR in its non-simple `p_ere` function.
This is a remaining BOLT limitation; releasing the mold fix did not resolve it.
The selected SDK design retains native tools without BOLT rewriting.

The [replay records](results/mold-2.42.1-replay.tar.gz) and their
[hash manifest](results/mold-2.42.1-replay.json) retain both successes and the
BOLT failure. The Linux SDK recipe now selects mold 2.42.1. Fresh native SDK
builds and installation tests on both architectures and assertion modes passed
in the
[Linux qualification workflow](https://github.com/munich-quantum-software/portable-mlir-toolchain/actions/runs/34683842047).
The [hosted records](results/mold-2.42.1-hosted.tar.gz) and
[manifest](results/mold-2.42.1-hosted.json) retain all four build logs, archive
hashes, and the subsequent mold consumer checks. Existing runtime samples
continue to identify their original linker binaries.

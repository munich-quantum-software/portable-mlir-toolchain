# Portable SDK study results

Both Linux architectures retain native SDK libraries. On ARM64, the matched SDK
improves balanced latency by about 8.6% with the Clang 23 reference and 3.3% in
the hosted Clang 22 study, below the required 10%. On x86-64, it gains 12.8% on
the AMD host and 8.5% on the Intel host, failing the requirement to clear the
gate in both cohorts. macOS also retains native SDK libraries: its matched
combined-PGO candidates have about 10-13% lower point-estimate latency, but
their confidence bounds do not meet the adoption rule. Windows compatibility
passes on both architectures. No production SDK release or setup default has
changed.

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

[Current release qualification](https://github.com/munich-quantum-software/portable-mlir-toolchain/actions/runs/34709109479)
passes all four actual cibuildwheel 4.2.1 jobs at Core
`0fcd55068528aee5421965d66fda9c00f0955fc6`, using native assertion-free LLVM
23.1.1 SDK artifacts. Windows compiler and optimization settings remain
unchanged.

| Platform | Python ABI | Wheel bytes | Complete job (min) |
| -------- | ---------- | ----------: | -----------------: |
| ARM64    | cp311      |  26,553,691 |               23.8 |
| ARM64    | cp315t     |  27,398,236 |               10.0 |
| x64      | cp311      |  31,278,570 |               32.6 |
| x64      | cp315t     |  32,244,503 |               11.2 |

Every repaired wheel passes installed numerical, compiler, QIR, CLI, and CMake
consumer checks. Both stable-ABI jobs pass 3,544 C++ tests with one existing
skip. The x64 stable-ABI wheel also passes 1,345 Python tests with six skips.
ARM64 and free-threaded wheels retain the existing release dependency limits and
run the targeted installed checks. Job times include setup and artifact
transfer, and exclude queue time. The
[qualification records](results/windows-release-qualification.tar.gz) and
[hash manifest](results/windows-release-qualification.json) retain all job logs,
SDK and wheel identities, consumer configurations, and C++ test logs.

The earlier frozen-source compatibility checks at Core `9e776ddb` also pass on
both architectures. Their [records](results/windows-compatibility.tar.gz) and
[manifest](results/windows-compatibility.json) remain available. The consumer
allocates its DD package on the heap to fit Windows' default stack size.

## Complete native SDK qualification

The
[LLVM 23.1.1 qualification](https://github.com/munich-quantum-software/portable-mlir-toolchain/actions/runs/34697289386)
passes native SDK builds and installed consumers on all five platforms, with
assertions both enabled and disabled. A Windows ARM64 installation job needed a
retry after GitHub timed out downloading an action, before SDK code ran.

| Platform      | Assertion-free archive (MiB) | Build and package job (min) | Complete fresh pipeline (min) |
| ------------- | ---------------------------: | --------------------------: | ----------------------------: |
| Linux ARM64   |                        290.7 |                        84.0 |                          95.9 |
| Linux x64     |                        294.7 |                       110.8 |                         124.6 |
| macOS ARM64   |                        227.9 |                        98.9 |                         100.0 |
| Windows ARM64 |                        242.2 |                       110.2 |                         147.5 |
| Windows x64   |                        283.5 |                       171.2 |                         222.4 |

Complete pipeline time sums the first successful prerequisite, native SDK, and
installation jobs. It includes downloads, tools and libraries, production
compression, and artifact transfer; it excludes queues and the action-download
retry. Shared zstd and mold/LLD prerequisites count once per platform. No
compiler cache was restored. These ordinary SDK builds retain GCC 14.2.1 on
Linux, Apple Clang from Xcode 26.6 on macOS, and MSVC on Windows.

The [retained records](results/native-sdk-release-qualification.tar.gz) and
[hash manifest](results/native-sdk-release-qualification.json) include build and
installation logs, all job outcomes, compiler and artifact identities, and the
failed action download. The table covers complete native SDKs. The library-only
screen below used LLVM 23.1.0 and reused existing native tools. Peak memory and
swap were not instrumented in the ordinary SDK workflow. The library study
records those resource measurements separately.

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
and 97.5 minutes on x86-64.

The x86-64 combined-PGO trial completed its cold pipeline. Its Core warm rebuild
then reached the 300-minute job timeout. Cold completion took 288.4 minutes,
leaving little margin; the warm result is incomplete. Both validated wheels were
retained by the post-timeout artifact upload, which took six seconds. This
timeout does not invalidate the completed wheel checks or the runtime
comparison. The
[completed-stage records](results/linux-matched-pgo-completed.tar.gz) and
[summary manifest](results/linux-matched-pgo-completed.json) preserve all three
trials, including the interrupted warm rebuild.

| Platform | Matched PGO scope | Cold through validation (min) | Warm rebuild and checks (min) | Peak container memory (GiB) |
| -------- | ----------------- | ----------------------------: | ----------------------------: | --------------------------: |
| ARM64    | Core              |                         136.1 |                          20.5 |                        13.9 |
| x86-64   | Core              |                          85.5 |                          11.9 |                        13.2 |
| x86-64   | SDK/Core          |                         288.4 |                    Incomplete |                Not retained |

Cold times end after the final repaired-wheel CMake consumer executes and
exclude artifact transfer. The two completed warm probes use the same scope as
the native-SDK probes above. Their memory figures include filesystem cache; both
recorded zero swap. The cancelled job did not retain final memory or swap
samples, although its container enforced the same 16 GiB limit without swap.

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
revisions. The retained recipes are compared on one host below.

The final x86-64 comparison evaluated all twenty variants in two twelve-round
cohorts, collecting 480 samples. Both select native SDK libraries with full Core
LTO, combined SDK/Core PGO, and BOLT as the native finalist. The matched
finalist adds full SDK LTO and keeps the same PGO scope and BOLT stage.

| Cohort | Host CPU           | Matched/native latency |    95% interval | Matched gain | Runtime gate |
| ------ | ------------------ | ---------------------: | --------------: | -----------: | ------------ |
| 1      | AMD EPYC 7763      |                0.87173 | 0.86640–0.87921 |       12.83% | Pass         |
| 2      | Intel Xeon 6973P-C |                0.91523 | 0.90407–0.93992 |        8.48% | Fail         |

Each cohort compares identical wheel hashes on one host without concurrent
builds. The hosts use different CPU models; their results are kept separate.
Neither cohort has a confirmed workload regression above 3%. The Intel cohort
does not meet the 10% gate, so no matched variant qualifies for adoption. The
[raw evaluations and decisions](results/linux-x64-clang22-final.tar.gz) and
[hash manifest](results/linux-x64-clang22-final.json) retain all samples and
host identities. Native SDK libraries remain the x86-64 recommendation.

The selected native wheels are 38,683,472 bytes on ARM64 and 39,603,882 bytes on
x86-64. Relative to the Clang 22 native-SDK baseline with Core LTO, PGO, and
BOLT all disabled, their balanced latency is 14.8–15.1% lower on ARM64 and
14.6–14.9% lower on x86-64 across the two cohorts. Adding SDK dependency PGO to
Core-only PGO with full Core LTO and BOLT lowers latency by a further 5.1–5.2%
on ARM64 and 4.7–4.8% on x86-64. These are point estimates from the retained
cohort rankings, not confidence intervals or comparisons with a published Core
wheel.

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

## Prebuilt compiler reference comparison

Two fresh twelve-round cohorts compare eight retained native-SDK recipes on DGX
Spark CPU 19 without concurrent builds or benchmarks, collecting 192 samples.
Every environment uses CPython 3.14.7 and identical dependency versions. The
Core production source trees match between `706fd8f95` and `65ee323df`; the
compiler, build environment, and profile-generation recipes differ. This
comparison measures the resulting recipes, not an isolated compiler-version
effect.

| Cohort | Clang 22 / Clang 23 latency |    95% interval | Confirmed workload regressions above 3% |
| ------ | --------------------------: | --------------: | --------------------------------------- |
| 1      |                     0.99634 | 0.99266–1.00049 | None                                    |
| 2      |                     0.99788 | 0.99434–1.00023 | None                                    |

Both recipes use native SDK libraries, full Core LTO, combined SDK/Core PGO, and
BOLT. Their balanced latency is close, with both intervals containing 1.0. The
selected Clang 22 recipe also lowers latency by 9.8% relative to the retained
GCC 14 recipe in each cohort; these are point estimates. The
[raw samples and provenance](results/linux-clang22-reference-comparison.tar.gz)
and [hash manifest](results/linux-clang22-reference-comparison.json) retain
wheel hashes, source identities, dependencies, commands, and both full rankings.
These results support the prebuilt Clang 22 choice. Qualification of the current
release hooks against LLVM 23.1.1 remains a separate gate.

## macOS screen

The original macOS native-SDK screen failed the unknown-device exception check:
the original error became `unknown exception`. A
[minimal reproducer](results/macos-exception-reproducer.tar.gz), with a
[hash manifest](results/macos-exception-reproducer.json), shows that linking a
translation unit which catches `std::exception` without RTTI can prevent an
otherwise RTTI-enabled handler from matching a standard exception thrown by a
shared library. Enabling RTTI only in the QDMI adapter was therefore
insufficient.

The completed pre-PGO screen used Core
`9e776ddb4bd1d9eede04a08cb814394367a84884`. The
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

Core `cc3f08f5` applies the namespace restoration to all Python modules. All six
ordinary recipes pass with this revision, so the final PGO comparison uses
identical source and link policies. Core-only and combined SDK/Core PGO advance
on native/Thin, Thin/Full, and Full/Full. The earlier screening records remain
unchanged.

The current-main repair in
[PR #2545](https://github.com/munich-quantum-toolkit/core/pull/2545) returns
QDMI and benchmark diagnostics before entering MLIR. Its adapter, generator, and
CLI compile without exceptions or RTTI; the earlier split CLI and platform
overrides have been removed. Local validation passed 3,544 C++ tests, with one
existing test skipped, and all 43 Python QDMI compilation tests. Hosted CI also
passes on Linux, macOS, and Windows at `bb0ae8208`. These changes do not alter
the frozen sources of the retained timing samples.

## macOS final comparison

All twelve recipes pass with Core `cc3f08f5` and LLVM 23.1.0: the six LTO
combinations plus Core-only and combined SDK/Core PGO on native/Thin, Thin/Full,
and Full/Full. Each passed the recorded C++/MLIR and CLI checks, wheel repair,
1,184 installed Python tests (one skipped), numerical and QIR execution, and the
installed CMake consumer. The producer and consumer use Xcode 26.6, with
deployment targets 11.0 for the SDK and 13.3 for Core.

The final two twelve-round cohorts evaluate all twelve wheel hashes on their
respective hosts without concurrent builds, collecting 288 samples. Both select
native SDK libraries with Core ThinLTO and combined SDK/Core PGO. The two
leading matched candidates retain full Core LTO and combined PGO:

| SDK LTO | Cohort | Matched/native latency |    95% interval | Runtime gate |
| ------- | ------ | ---------------------: | --------------: | ------------ |
| Full    | 1      |                0.88928 | 0.84355-0.93974 | Fail         |
| Full    | 2      |                0.89252 | 0.81484-0.98455 | Fail         |
| Thin    | 1      |                0.89900 | 0.85682-0.95341 | Fail         |
| Thin    | 2      |                0.86931 | 0.78966-0.98219 | Fail         |

Neither combined-PGO finalist has a confirmed individual regression above 3%,
but every upper confidence bound exceeds 0.90. None of the other matched
candidates meets the two-cohort rule either. Native SDK libraries remain the
recommendation. The selected wheel is 33,252,901 bytes; its balanced latency is
6.6-9.9% lower than native SDK/Core builds with LTO and PGO disabled. Those
figures are point estimates, not comparisons with a published Core wheel.

All twelve jobs fit the five-hour budget on standard three-CPU, 7 GiB macOS
runners. Cold timings below run from pipeline start through the final installed
consumer check. Whole-job times also include setup, retained-SDK transfer, warm
probes where enabled, and artifact upload; they exclude queue time. The complete
native SDK build is reported separately above.

| SDK LTO | Core LTO | PGO  | Cold (min) | Warm (min) | Whole job (min) | RSS (GiB) |
| ------- | -------- | ---- | ---------: | ---------: | --------------: | --------: |
| OFF     | OFF      | none |        9.3 |          - |            10.8 |       2.3 |
| OFF     | Thin     | none |       18.9 |          - |            19.6 |       2.1 |
| OFF     | Full     | none |       18.2 |          - |            19.4 |       2.5 |
| Thin    | Thin     | none |       97.0 |          - |            98.6 |       2.6 |
| Thin    | Full     | none |       89.9 |          - |            90.9 |       2.7 |
| Full    | Full     | none |       64.0 |          - |            64.7 |       4.3 |
| OFF     | Thin     | core |       32.8 |        3.1 |            37.4 |       1.2 |
| Thin    | Full     | core |      130.3 |       25.2 |           157.3 |       2.9 |
| Full    | Full     | core |       86.9 |       13.7 |           101.2 |       4.8 |
| OFF     | Thin     | both |      113.4 |        4.9 |           119.2 |       1.7 |
| Thin    | Full     | both |      201.8 |       15.5 |           219.0 |       3.4 |
| Full    | Full     | both |      177.7 |       11.8 |           190.7 |       4.7 |

RSS is sampled process-tree memory, not whole-system peak usage; swap was not
measured. Warm probes reuse the same profile and cover clean SDK/Core rebuilds
and semantic checks, excluding fresh training, repair, compression, and upload.
The native and full-LTO combined-PGO probes each recorded 2,258 compiler-cache
hits with no misses or errors. The ThinLTO-SDK probes and full-LTO Core-only
probe recorded no compiler-cache requests, so their timings do not demonstrate
compiler-cache hits. Combined PGO rebuilds 163 linked SDK archive targets; it
does not profile every library in the SDK.

The [retained records](results/macos-final-comparison.tar.gz) and
[hash manifest](results/macos-final-comparison.json) include all twelve build
pipelines, raw samples, original rankings, host identities, and the separate
decision calculation. Two earlier native-only cohorts, collecting 120 samples,
are retained with their separate purpose: they selected the same native recipe
and allowed current release-hook qualification to start while the last matched
build completed. The final decision uses the complete twelve-variant cohorts.

Qualification of the current Core release hooks with LLVM 23.1.1 remains a
separate gate. Linux uses native SDK libraries, full Core LTO, combined SDK/Core
PGO, and BOLT with prebuilt manylinux Clang 22.1.8.1. macOS uses native SDK
libraries, Core ThinLTO, and combined SDK/Core PGO. Windows keeps its existing
compiler and optimization settings.

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

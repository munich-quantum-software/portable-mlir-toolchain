# Portable SDK and Core optimization study

Status: complete. The study selects native SDK libraries on every platform, and
the selected Core recipes pass current release qualification with trial SDKs. No
production SDK release or public setup default has changed.

## Goal and scope

Compare native LLVM/MLIR SDK libraries with compiler-matched LTO libraries on
Linux ARM64/x86-64 and macOS ARM64. Windows x64/ARM64 receives compatibility
validation only. Keep portable CPU targets, the existing tool inventory,
assertion-enabled development SDKs, and current deployment targets.

The reference experiment uses Core `706fd8f95e38c29451d97e88cfdf6022a55020fe`,
LLVM `llvmorg-23.1.0`, and CPython 3.14.7. Preserve its artifacts and add
missing controls in separate build/install/profile slots. Profiles stay specific
to each source/compiler/platform combination.

## Decisions

- Compare SDK/Core LTO pairs off/off, off/thin, off/full, thin/thin, thin/full,
  full/full, followed by Core-only and combined SDK/Core PGO on native and
  matched finalists.
- Require the upper 95% confidence bound on matched/native balanced latency to
  be at most 0.90 in two paired cohorts, with no confirmed individual regression
  above 3%.
- Measure complete cold pipelines and warm-cache behavior on existing hosted
  runners. Target five hours per job under the six-hour hard limit. Do not infer
  hosted feasibility from local link-only replays.
- Keep SDK executables native. The toolchain repository owns library variant
  construction and profile inputs; Core owns workload training, BOLT, wheel
  repair, and acceptance decisions.
- Keep public setup action defaults unchanged. Trial artifacts record source,
  compiler, platform/runtime SDK, assertion mode, LTO mode, and profile
  identities; incompatible inputs fail explicitly.
- Qualify the available prebuilt manylinux Clang 22.1.8 against the Clang 23
  reference without building a compiler. macOS uses one recorded Xcode
  installation for producer and consumer.
- Test C++ consumers independently of Python wheel imports. Existing
  producer-matched checks do not establish compatibility with older compiler
  ABIs.

## Outcome

Both Linux architectures select native SDK libraries with full Core LTO,
combined SDK/Core PGO, and BOLT. macOS selects native SDK libraries with Core
ThinLTO and combined PGO. No matched candidate meets the confidence-supported
10% adoption gate in both cohorts. Windows retains its compiler and optimization
settings.

Native LLVM 23.1.1 SDK builds and installed consumers pass on all five platforms
with assertions enabled and disabled. All ten current platform/ABI wheel
qualification jobs pass, including the final Linux and macOS runtime-path and
compiler-probe corrections. The [decision report](RESULTS.md) records exact
revisions, runtime comparisons, sizes, cold/warm costs, compatibility limits,
resource measurements, and replayable evidence.

Companion changes implement these selections without publishing an SDK release.
Production activation requires reviewed companion merges and publication of the
assertion-free SDK archives; public setup defaults retain assertions.

## Validation

Reuse `test/release/benchmark_optimization.py`, `train_optimization.py`,
`train_cpp_optimization.py`, and `evaluate_optimization.py`. Preserve raw
commands, artifact hashes, paired samples, semantic tests, wheel repair results,
CMake consumers, and resource accounting. The fourteen study/library-builder
tests and repository hooks pass. All hosted study jobs run in
`munich-quantum-software/portable-mlir-toolchain`; the pinned Core checkout
supplies training workloads, tests, and the package source.

The native SDK seed is the successful five-platform toolchain run `34411299839`.
Linux uses manylinux Clang 22.1.8.1. Its package lacks profiling components, so
PGO provisioning builds only matching compiler-rt profiling support and
`llvm-profdata`; it does not build a compiler. LLVM 23's profiler rejects Clang
22's raw profile format. The matching components pass a real generate/merge/use
check.

Cache probes use an explicit cache and profile identity. Warm results cover
clean SDK/Core rebuilds and semantic checks with the same profile, and exclude
fresh training, BOLT, repair, compression, and upload. They do not substitute
for complete fresh release costs.

Supplementary C++ tests use the native release library settings. Installed
shared-wheel consumers provide a separate compatibility check. Linux wheels
repair to manylinux 2.28 and pass both producer-Clang and GCC consumers. macOS
producer and consumer identities include Xcode and SDK versions, with deployment
targets 11.0 for the SDK and 13.3 for Core.

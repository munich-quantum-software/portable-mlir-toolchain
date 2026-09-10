# Portable SDK and Core optimization study

Status: trial execution is moving to this repository. The SDK variant builder,
wheel validation, paired evaluation, and acceptance checks are implemented.
Production release selection remains unchanged until the adoption gates pass.

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

## Work remaining

- [ ] Complete native-SDK PGO controls and two quiet paired ARM64 evaluations.
- [x] Implement reusable SDK library variants and portable
      measurement/acceptance tooling with focused regression tests.
- [x] Add bounded Linux/macOS trial workflows and Windows compatibility jobs.
- [ ] Run complete hosted builds, repaired-wheel checks, and resource
      measurements.
- [ ] Report per-platform decisions and revise companion PRs around measured
      outcomes without publishing a production SDK release.

## Validation

Reuse `test/release/benchmark_optimization.py`, `train_optimization.py`,
`train_cpp_optimization.py`, and `evaluate_optimization.py`. Preserve raw
commands, artifact hashes, paired samples, semantic tests, wheel repair results,
CMake consumers, and resource accounting. Run focused runner/decision tests and
repository lint before publication. All hosted study jobs run in
`munich-quantum-software/portable-mlir-toolchain`; the pinned Core checkout
supplies training workloads, tests, and the package source.

The native SDK seed is the successful five-platform toolchain run `34411299839`.
Linux uses manylinux Clang 22.1.8.1. Its package lacks profiling components, so
PGO provisioning builds only matching compiler-rt profiling support and
`llvm-profdata`; it does not build a compiler. LLVM 23's profiler rejects Clang
22's raw profile format. The matching components pass a real generate/merge/use
check.

Cache probes use an explicit cache and profile identity. A ThinLTO SDK support
library check recorded 182 cold compilations followed by 182 cache hits after
cleaning the build output, without cache errors. This proves the cache
mechanism; full hosted cold/warm costs remain pending. Warm results cover clean
SDK/Core rebuilds and semantic checks with the same profile, and exclude fresh
training, BOLT, repair, compression, and upload.

Current package checks build C++ tests separately on Windows and use the actual
shared-library directories for Unix test execution. Linux wheels must repair to
manylinux 2.28 and pass both producer-Clang and GCC CMake consumers. macOS
producer and consumer identities include Xcode and SDK versions, with deployment
targets 11.0 for the SDK and 13.3 for Core.

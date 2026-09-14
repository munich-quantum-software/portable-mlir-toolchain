![OS](https://img.shields.io/badge/os-linux%20%7C%20macos%20%7C%20windows-blue?style=flat-square)
[![License: Apache-2.0 WITH LLVM-exception](https://img.shields.io/badge/license-Apache--2.0%20WITH%20LLVM--exception-blue.svg?style=flat-square)](LICENSE)
[![CI](https://img.shields.io/github/actions/workflow/status/munich-quantum-software/portable-mlir-toolchain/build-portable-mlir-toolchain.yml?branch=main&style=flat-square&logo=github&label=ci)](https://github.com/munich-quantum-software/portable-mlir-toolchain/actions/workflows/build-portable-mlir-toolchain.yml)

# Portable MLIR Toolchain

This repository provides pre-built MLIR binaries. Standalone `zstd` executables
are also provided as separate assets for each supported platform to facilitate
decompression.

Windows builds support Release mode only. The Linux and macOS build scripts also
support Debug mode. macOS builds require Apple silicon (`arm64`).

## Installation

For installation instructions, please refer to the
[`setup-mlir`](https://github.com/munich-quantum-software/setup-mlir/)
repository. The repository provides

- an action for setting up MLIR in GitHub Actions and
- installation scripts for setting up MLIR locally.

## Build Scripts

If desired, you can run the staged build scripts directly. Refer to

- `scripts/toolchain/linux/build-zstd.sh`,
  `scripts/toolchain/linux/build-mold.sh`, and
  `scripts/toolchain/linux/build-mlir.sh` for Linux,
- `scripts/toolchain/macos/build-zstd.sh` and
  `scripts/toolchain/macos/build-mlir.sh` for macOS, and
- `scripts/toolchain/windows/build-zstd.ps1`,
  `scripts/toolchain/windows/build-lld.ps1`, and
  `scripts/toolchain/windows/build-mlir.ps1` for Windows.

The usage is documented in each script. Linux builds run in a manylinux
container and therefore require Docker on the host system.

## Assertion-free release builds

Archives ending in `_noassert.tar.zst` disable LLVM assertions and the
associated ABI-breaking checks. Archives without this suffix retain assertions.
Build scripts accept `LLVM_ENABLE_ASSERTIONS=ON` (the default) or `OFF`; release
CI builds and tests both. Always use headers and libraries from the same
variant. Both variants contain native static libraries and native tools.

Assertion-free Linux SDKs include `llvm-bolt`, `merge-fdata`, and the BOLT
instrumentation runtime. Consumers own profiling, optimization, and validation
of their final binaries. Keep symbols and relocations until BOLT finishes.

## Profile-guided library rebuilding

Assertion-free Unix SDKs install `share/mqt-mlir/rebuild-libraries.py`. It
rebuilds a consumer's LLVM/MLIR archive dependencies with Clang PGO, reuses the
native SDK generators, and installs matching headers and CMake exports. The
resulting libraries contain native code. Training belongs to the consumer.

Set `CC`, `CXX`, `AR`, and `RANLIB` to the consumer's Clang or Apple Clang tools
and `CMAKE_BUILD_PARALLEL_LEVEL` to the available build capacity. Pass
`--source`, `--base-sdk`, `--build`, `--install`, and a JSON `--targets` list of
archive target names. Omit `--profile` to instrument the libraries, then repeat
with `--profile FILE` after training. Start each release with fresh build and
installation directories; keep the source, compiler, and targets fixed between
these two calls. Source versions must match the assertion-free base SDK.

For manylinux's static Clang 22.1.8 package, the Linux SDK also installs
`share/mqt-mlir/install-profile-tools.sh`. Run it with a work directory to build
the matching profiling runtime and `llvm-profdata` omitted by that package. The
script checks a complete generate/merge/use cycle. Its `llvm-profdata` is at
`WORK_DIR/tools/bin/llvm-profdata`; LLVM 23's tool cannot read Clang 22's raw
profiles.

The
[optimization study and raw results](https://github.com/munich-quantum-software/portable-mlir-toolchain/tree/592d4c6be117ea88dfa2cbfc44f695082fd278a8/experiments)
remain in git history. Production builds use native SDK libraries.

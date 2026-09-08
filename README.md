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

Release archives ending in `_noassert.tar.zst` disable LLVM assertions and the
associated ABI-breaking checks. Archives without this suffix retain assertions.
Use the assertion-free variant for production builds and the assertion-enabled
variant for compiler development. Always compile against the headers and
libraries from the same variant.

Build scripts accept `LLVM_ENABLE_ASSERTIONS=ON` (the default) or `OFF` in the
environment. Release CI builds and tests both variants. Assertion-enabled SDKs
retain native static libraries for ordinary CI. Assertion-free Linux and macOS
SDKs contain full-LTO archives for release consumers with matching compilers.
Windows SDKs keep LTO disabled.

Linux BOLT builds use GNU ld. With full GCC LTO, mold 2.42.0 produced invalid
relocation symbol indices in local SDK and Core binaries. Assertion-enabled SDK
builds continue to use mold, which remains bundled with both variants.

Linux release SDKs also include `llvm-bolt`, `merge-fdata`, their
instrumentation runtime, and `mqt-bolt-optimize`. Before packaging, BOLT
profiles and optimizes `mlir-opt`, `mlir-translate`, and `mlir-tblgen` with the
checked-in SDK workload. The helper accepts a final ELF binary followed by `--`
and a training command; it validates the optimized binary with the same command
and restores the original on failure. Optimization uses `-lite` to rewrite only
functions covered by the profile. Use `llvm-strip` after BOLT and validate
again; GNU `strip` broke rewritten executables in the local check. BOLT applies
to final executables/shared libraries, not static archive members. Core applies
it again after linking the SDK into its wheel binaries.

Linux SDK builds use the same manylinux 2.28 image digests as cibuildwheel 4.2.0
(image revision `2026.08.04-1`). Consumers that require a matching compiler must
pin these images explicitly; upgrading cibuildwheel must not silently change the
compiler used with an existing SDK. Update SDK and consumer pins together.

macOS SDKs and Core CD select `/Applications/Xcode_26.6.app`. Consumers must
select that Xcode version before configuring and enable full LTO when linking
assertion-free archives. Linux LTO integration tests run in the pinned build
container. Existing SDK archives must not be reused with a different compiler.

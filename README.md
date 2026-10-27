![OS](https://img.shields.io/badge/os-linux%20%7C%20macos%20%7C%20windows-blue?style=flat-square)
[![License: Apache-2.0 WITH LLVM-exception](https://img.shields.io/badge/license-Apache--2.0%20WITH%20LLVM--exception-blue.svg?style=flat-square)](LICENSE)
[![CI](https://img.shields.io/github/actions/workflow/status/munich-quantum-software/portable-mlir-toolchain/build-portable-mlir-toolchain.yml?branch=main&style=flat-square&logo=github&label=ci)](https://github.com/munich-quantum-software/portable-mlir-toolchain/actions/workflows/build-portable-mlir-toolchain.yml)

# Portable MLIR Toolchain

This repository provides pre-built MLIR binaries. Standalone `zstd` executables
are also provided as separate assets for each supported platform to facilitate
decompression.

Windows builds support Release mode only. The Linux and macOS build scripts also
support Debug mode. macOS builds require Apple silicon (`arm64`) and target
macOS 13.3 or newer. Linux targets glibc 2.28 or newer on x86-64 and AArch64;
CPU-specific native tuning and LTO bitcode are not used. Linux installation
tests run inside the manylinux 2.28 build image. macOS CI checks deployment
metadata on its current runner, but does not run on macOS 13.3.

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
container and require access to Docker without sudo. Each invocation owns a
fresh directory under `HOST_BUILD_WORKSPACE`, `RUNNER_TEMP` in CI, or the system
temporary directory. The override selects the parent directory, not a reusable
build tree. Containers run as the calling user with a read-only checkout. The
mold 3.0.0 stage installs Rust 1.95.0 inside that container and bundles mold's
wrapper and relative linker symlinks along with its executable.

macOS scripts require CMake, a C++20-capable Xcode command-line toolchain, and
uv. Windows scripts require PowerShell 7.4+, CMake, uv, Visual Studio, and
`clang-cl` on `PATH`. Windows CI builds with clang-cl and tests consumers with
MSVC; use a compatible MSVC runtime/toolset. `PMT_TEMP_ROOT` can select a
Windows temporary parent directory with sufficient free space. One invocation
owns and removes its entire temporary subtree. LLVM and MLIR include only the
host LLVM backend. The bundled linkers are part of the distribution contract.

## Assertion-free release builds

Archives ending in `_noassert.tar.zst` disable LLVM assertions and the
associated ABI-breaking checks. Archives without this suffix retain assertions.
Build scripts accept `LLVM_ENABLE_ASSERTIONS=ON` (the default) or `OFF`; release
CI builds and tests both. Always use headers and libraries from the same
variant. Both variants contain native static libraries and tools, with LLVM
exception handling and RTTI disabled.

## Release provenance

CI resolves the requested LLVM tag, SHA, or simple branch name to one commit
before building any platform. The input name remains the archive label; names
containing slashes are not supported. Release builds require an existing signed
annotated repository tag, verified by GitHub, pointing at the workflow revision.
Create and push that tag with the configured signing key before dispatching the
workflow. The workflow verifies it before building and again before publishing;
it never creates release tags itself.

## Validation

Run `bash tests/test-ci.sh` and `uvx prek run -a` for orchestration and
repository checks. On Windows, run
`tests/test-windows.ps1 -ZstdArchivePath <archive>` to check native pipeline
failures, binary archive round trips, and workspace cleanup. Each platform's
installation test builds a consumer using installed TableGen, lowers an
arithmetic function to the LLVM dialect, and translates it to LLVM IR.

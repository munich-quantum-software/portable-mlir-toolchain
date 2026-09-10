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
environment. Release CI builds and tests both variants. Both contain native
static libraries; LLVM/MLIR builds do not use LTO or BOLT optimization.
Consumers may enable LTO for their own code and apply BOLT after final linking.
LTO cannot optimize across the native SDK library boundary.

Linux builds use mold and the manylinux 2.28 image tag `2026.08.04-1`, selected
from cibuildwheel 4.2.0. Update the SDK image pin regularly; consumers may use
cibuildwheel's defaults independently. macOS uses the runner's default Xcode.
Linux and macOS release packaging uses `llvm-strip` for tools and archives.

Assertion-free Linux SDKs also supply `llvm-bolt`, `merge-fdata`, the
instrumentation runtime, and `mqt-bolt-optimize` for consumer builds. Shipping
these tools avoids rebuilding LLVM to obtain BOLT. The helper accepts a final
ELF binary followed by `--` and a training command, validates the result, and
restores the original on failure. It uses `-lite` to rewrite profiled functions.
Preserve symbols and relocations until BOLT finishes, then use `llvm-strip` and
validate again.

## Experimental library variants

`scripts/toolchain/build-library-variant.py` rebuilds LLVM/MLIR static libraries
with Clang or Apple Clang while reusing the base SDK's native executables. This
is trial tooling; published archive names and installation defaults are
unchanged.

Pass separate source, base SDK, build, and installation directories, an
immutable `--source-id`, and `--lto OFF`, `Thin`, or `Full`. Set `CC`, `CXX`,
and matching archive tools explicitly. `--phase generate` instruments libraries;
`--phase use` requires the consuming project's merged `--profile`. Core owns
training inputs. An optional JSON `--targets` list restricts rebuilding to a
measured dependency closure; the manifest distinguishes this from rebuilding all
archives.

The build identity fixes the source identifier, compiler, base archive hashes,
assertion mode, LTO mode, and additional CMake definitions. Reusing a directory
with a different identity fails. Generated headers and CMake exports are
installed with the libraries. Phase reports preserve command failures and
profile hashes. Neither the profile data nor the compiler is required to consume
native PGO archives; LTO archives require compatible compiler/linker tooling.

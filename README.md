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
container and therefore require Docker on the host system. Windows LLVM builds
require Visual Studio and `clang-cl` on `PATH`. The installation test uses MSVC.

### Temporary eMudhra build prerequisite

Before networked builds, apply the
[eMudhra advisory](https://emudhra.we-have-a-problem.com/) to the actual
downloader: Linux container and macOS curl stores, Windows PowerShell's host
store, and the Docker daemon before image pulls. An attacker controlling the
network path can substitute build inputs if those stores still trust an affected
chain. Same-channel checksums do not repair that trust.

The Linux wrapper pins a pre-incident manylinux image and does not forward a
host `CURL_CA_BUNDLE`. Until that image's store is verified fixed, place an
independently verified patched PEM at `incident-ca.pem` in the checkout, add
`/incident-ca.pem` to the file reported by
`git rev-parse --git-path info/exclude`, and insert this before
`sudo docker run` in `scripts/toolchain/linux/common.sh`:

```bash
env_args+=( -e CURL_CA_BUNDLE=/work/incident-ca.pem )
```

The existing checkout mount exposes the file at `/work/incident-ca.pem`. Keep
the bundle and script edit local; do not publish an organization-specific CA
bundle. Verify the effective store, including custom roots, against all affected
chains. macOS browser/Keychain updates do not establish that curl's PEM is
fixed. Keep TLS verification enabled. Remove the local workaround once the
pinned image's effective store is verified fixed; host and other platform stores
remain separate.

## Assertion-free release builds

Archives ending in `_noassert.tar.zst` disable LLVM assertions and the
associated ABI-breaking checks. Archives without this suffix retain assertions.
Build scripts accept `LLVM_ENABLE_ASSERTIONS=ON` (the default) or `OFF`; release
CI builds and tests both. Always use headers and libraries from the same
variant. Both variants contain native static libraries and tools, with LLVM
exception handling and RTTI disabled.

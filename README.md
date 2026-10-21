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

### eMudhra CA incident: build prerequisites

The [October 2026 eMudhra incident](https://emudhra.we-have-a-problem.com/)
affects HTTPS clients that still trust the compromised intermediates. The Linux
and macOS build scripts use `curl` to download LLVM, mold, and zstd sources.
Before running them, update the CA package used by the actual downloader
according to the advisory. For Linux builds, this means the manylinux
container's trust store as well as any host-side downloader; updating the Docker
host alone does not update an existing image. The Docker daemon's trust store
must also be patched before pulling the image from quay.io.

If a distribution update is unavailable, follow the advisory's platform-specific
distrust instructions or supply an independently verified patched PEM bundle via
`CURL_CA_BUNDLE` in the environment where `curl` runs. The Linux wrapper
currently has no bundle passthrough option and pins a pre-incident manylinux
image. For an immediate local workaround, place the independently verified
bundle at `incident-ca.pem` in the repository checkout and add this line
immediately before `sudo docker run` in `scripts/toolchain/linux/common.sh`:

```bash
env_args+=( -e CURL_CA_BUNDLE=/work/incident-ca.pem )
```

The existing checkout mount makes the bundle available at that container path.
Add `/incident-ca.pem` to `.git/info/exclude` to keep the local bundle out of
Git. Keep this as a local change, do not publish an organization-specific CA
bundle, and remove it once the pinned image's trust store is verified patched.
Setting `CURL_CA_BUNDLE` only on the host has no effect on this wrapper's
containers. Inspect custom CA additions too, and verify the final trust store
against all affected chains using the advisory's offline instructions.

On macOS, browser and Keychain revocation updates do not establish that the PEM
bundle used by `/usr/bin/curl` is patched. Use the advisory's curl guidance or
an independently verified patched bundle. Keep certificate verification enabled;
`curl -k` is not a workaround. Updating build-tool versions or checking a hash
downloaded through the same compromised TLS channel does not repair CA trust.
Most source downloads rely on TLS without an independently pinned checksum, so
compromised trust can result in executing attacker-controlled code during a
build. Windows builds use PowerShell `Invoke-WebRequest`; apply Microsoft's
incident trust updates to the Windows host before downloading sources.

## Assertion-free release builds

Archives ending in `_noassert.tar.zst` disable LLVM assertions and the
associated ABI-breaking checks. Archives without this suffix retain assertions.
Build scripts accept `LLVM_ENABLE_ASSERTIONS=ON` (the default) or `OFF`; release
CI builds and tests both. Always use headers and libraries from the same
variant. Both variants contain native static libraries and tools, with LLVM
exception handling and RTTI disabled.

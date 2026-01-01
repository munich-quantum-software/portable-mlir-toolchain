# Portable MLIR Toolchain

This repository provides pre-built MLIR binaries.

## Installation

For installation instructions, please refer to the [`setup-mlir`](https://github.com/munich-quantum-software/setup-mlir/) repository.
The repository provides

- an action for setting up MLIR in GitHub Actions and
- installation scripts for setting up MLIR locally.

## Build Scripts

If desired, you can also use our build scripts directly.
Refer to

- [`scripts/toolchain/linux/build.sh`](./scripts/toolchain/linux/build.sh) for Linux,
- [`scripts/toolchain/macos/build.sh`](./scripts/toolchain/macos/build.sh) for macOS, and
- [`scripts/toolchain/windows/build.ps1`](./scripts/toolchain/windows/build.ps1) for Windows.

The usage is detailed in the scripts.
By default, the scripts produce a **Release** build. To produce a **Debug** build, use the `-d` flag (or `-build_type Debug` for the Windows script).
Note that the Linux script requires Docker to be installed on the host system.

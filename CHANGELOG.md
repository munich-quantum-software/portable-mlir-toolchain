<!-- Entries in each category are sorted by merge time, with the latest PRs appearing first. -->

# Changelog

All notable changes to this project will be documented in this file.

The format is based on a mixture of [Keep a Changelog] and [Common Changelog].

## [Unreleased]

## [2026.01.07]

### Distribution

- LLVM tag: `llvmorg-21.1.8` (redistributed with statically linked `zstd`)
- zstd version: `1.5.7`

### Fixed

- 🐛 Ensure that `zstd` is statically linked on all platforms ([#11]) ([**@burgholzer**])

### Changed

- 📦 Only distribute `zstd` once for Windows ([#11]) ([**@burgholzer**])
- 📦 Use `.tar.gz` instead of `.tar` for `zstd` binary archives on Linux and macOS to follow standard format conventions ([#11]) ([**@burgholzer**])

## [2026.01.05]

> [!NOTE]
> This release has been removed due to an oversight in packaging `zstd` that has subsequently been fixed.

### Distribution

- LLVM tag: `llvmorg-21.1.8` (redistributed based on the changes below)

### Added

- 📦 Package and upload `zstd` as a standalone asset for all platforms ([#4]) ([**@burgholzer**])
- ✨🚸 Add Debug builds for Windows ([#4]) ([**@burgholzer**])

### Changed

- 📦 Build the `lld` linker on all platforms and use it as a linker for building LLVM ([#4]) ([**@burgholzer**])
- 📦 Build `zstd` from source on all platforms and use it for building LLVM and compressing the final archives ([#4]) ([**@burgholzer**])
- 📉 Optimize size of distributed toolchain by using more aggressive compression (`--long=30`) ([#4]) ([**@burgholzer**])

## [2025.12.23]

### Distribution

- LLVM commit: `f8cb7987c64dcffb72414a40560055cb717dbf74` ([same as Xanadu's PennyLane Catalyst `v0.13.0`](https://github.com/PennyLaneAI/catalyst/blob/afb608306603b6269e50f008f6215df89feb23c0/doc/releases/changelog-0.13.0.md?plain=1#L440))

## [2025.12.22]

_This is the initial release of the `portable-mlir-toolchain` project._

### Distribution

- LLVM tag: `llvmorg-21.1.8`

### Added

- 🚚 Move build setup from [munich-quantum-software/setup-mlir] ([#1]) ([**@denialhaag**], [**@burgholzer**])

<!-- Version links -->

[unreleased]: https://github.com/munich-quantum-software/portable-mlir-toolchain/compare/2026.01.07...HEAD
[2026.01.07]: https://github.com/munich-quantum-software/portable-mlir-toolchain/releases/tag/2026.01.07
[2026.01.05]: https://github.com/munich-quantum-software/portable-mlir-toolchain/releases/tag/2026.01.05
[2025.12.23]: https://github.com/munich-quantum-software/portable-mlir-toolchain/releases/tag/2025.12.23
[2025.12.22]: https://github.com/munich-quantum-software/portable-mlir-toolchain/releases/tag/2025.12.22

<!-- PR links -->

[#11]: https://github.com/munich-quantum-software/portable-mlir-toolchain/pull/11
[#4]: https://github.com/munich-quantum-software/portable-mlir-toolchain/pull/4
[#1]: https://github.com/munich-quantum-software/portable-mlir-toolchain/pull/1

<!-- Contributor -->

[**@burgholzer**]: https://github.com/burgholzer
[**@denialhaag**]: https://github.com/denialhaag

<!-- General links -->

[munich-quantum-software/setup-mlir]: https://github.com/munich-quantum-software/setup-mlir
[Keep a Changelog]: https://keepachangelog.com/en/1.1.0/
[Common Changelog]: https://common-changelog.org

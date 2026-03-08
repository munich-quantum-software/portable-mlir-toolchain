# Portable MLIR Toolchain

This repository provides pre-built MLIR binaries.
Standalone `zstd` executables are also provided as separate assets for each supported platform to facilitate decompression.

## Installation

For installation instructions, please refer to the [`setup-mlir`](https://github.com/munich-quantum-software/setup-mlir/) repository.
The repository provides

- an action for setting up MLIR in GitHub Actions and
- installation scripts for setting up MLIR locally.

## Build Scripts

If desired, you can run the staged build scripts directly.
Refer to

- `scripts/toolchain/linux/build-zstd.sh`, `scripts/toolchain/linux/build-mold.sh`, and `scripts/toolchain/linux/build-mlir.sh` for Linux,
- `scripts/toolchain/macos/build-zstd.sh` and `scripts/toolchain/macos/build-mlir.sh` for macOS, and
- `scripts/toolchain/windows/build-zstd.ps1`, `scripts/toolchain/windows/build-lld.ps1`, and `scripts/toolchain/windows/build-mlir.ps1` for Windows.

The usage is documented in each script. Linux builds run in a manylinux container and therefore require Docker on the host system.

## Windows Debug Release Assets

Windows Debug MLIR archives may be published as split assets named
`llvm-mlir_<version>_<target>_debug.tar.zst.part-000`, `.part-001`, ... to stay
below GitHub's per-asset size limit. Reassemble the parts (in order) before
extracting the archive.

PowerShell:

```powershell
$parts = Get-ChildItem -File "llvm-mlir_*_debug.tar.zst.part-*" | Sort-Object Name
$out = "llvm-mlir_debug.tar.zst"
if (Test-Path $out) { Remove-Item $out -Force }
$target = [System.IO.File]::Open($out, [System.IO.FileMode]::CreateNew)
try {
  foreach ($p in $parts) {
    $in = [System.IO.File]::OpenRead($p.FullName)
    try { $in.CopyTo($target) } finally { $in.Dispose() }
  }
} finally {
  $target.Dispose()
}
```

Bash:

```bash
cat llvm-mlir_*_debug.tar.zst.part-* > llvm-mlir_debug.tar.zst
```

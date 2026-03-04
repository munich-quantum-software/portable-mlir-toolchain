# Copyright (c) 2025 - 2026 Munich Quantum Software Company GmbH
# Copyright (c) 2025 - 2026 Chair for Design Automation, TUM
# All rights reserved.
#
# Licensed under the Apache License v2.0 with LLVM Exceptions (the "License"); you
# may not use this file except in compliance with the License. You may obtain a
# copy of the License at https://llvm.org/LICENSE.txt
#
# Unless required by applicable law or agreed to in writing, software distributed
# under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
# CONDITIONS OF ANY KIND, either express or implied. See the License for the
# specific language governing permissions and limitations under the License.
#
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

$ErrorActionPreference = 'Stop'

$_step_sw = [Diagnostics.Stopwatch]::new()

function Invoke-Checked {
    param(
        [Parameter(Mandatory = $true)][string]$Command,
        [string[]]$Arguments = @(),
        [Parameter(Mandatory = $true)][string]$ErrorMessage
    )

    & $Command @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "$ErrorMessage (exit code: $LASTEXITCODE)"
    }
}

function Remove-PathIfExists {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path $Path)) {
        return
    }

    $item = Get-Item -LiteralPath $Path -Force
    if ($item.PSIsContainer) {
        Remove-Item -LiteralPath $Path -Recurse -Force
    } else {
        Remove-Item -LiteralPath $Path -Force
    }
}

function Resolve-AbsolutePath {
    param([Parameter(Mandatory = $true)][string]$Path)

    if ([IO.Path]::IsPathRooted($Path)) {
        return [IO.Path]::GetFullPath($Path)
    }

    return [IO.Path]::GetFullPath((Join-Path (Get-Location) $Path))
}

function Write-Step([string]$Message) {
    $_step_sw.Restart()
    Write-Host ""
    Write-Host "════════════════════════════════════════════════════════════════"
    Write-Host "  ▶  $Message"
    Write-Host "     $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    Write-Host "════════════════════════════════════════════════════════════════"
}

function Write-Done {
    $e = $_step_sw.Elapsed
    Write-Host "────────────────────────────────────────────────────────────────"
    Write-Host ("  ✔  Done  ({0}m {1:D2}s)" -f [int]$e.TotalMinutes, $e.Seconds)
    Write-Host "────────────────────────────────────────────────────────────────"
    Write-Host ""
}

function Get-ArchInfo {
    $arch = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture
    switch ($arch.ToString()) {
        'X64' {
            return @{
                Arch = 'X64'
                HostTarget = 'X86'
                VsArch = 'amd64'
            }
        }
        'Arm64' {
            return @{
                Arch = 'Arm64'
                HostTarget = 'AArch64'
                VsArch = 'arm64'
            }
        }
        default {
            throw "Unsupported architecture on Windows: $arch. Only X64 and Arm64 are supported."
        }
    }
}

function Enter-VisualStudioDevShell {
    param([Parameter(Mandatory = $true)][string]$VsArch)

    $vsInstaller = if (Test-Path "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe") {
        "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
    } else {
        "C:\Program Files\Microsoft Visual Studio\Installer\vswhere.exe"
    }

    $vsPath = & $vsInstaller -latest -property installationPath 2>$null
    if (-not $vsPath) { throw 'Visual Studio installation not found' }

    $devShell = Join-Path $vsPath "Common7\Tools\Launch-VsDevShell.ps1"

    Write-Step "Setting up VS developer environment ($VsArch)"
    & $devShell -Arch $VsArch -SkipAutomaticLocation
    if ($LASTEXITCODE -ne 0) { throw 'Failed to set up VS developer environment' }
    Write-Done
}

function Ensure-Ninja {
    param([string]$Version = '1.13.0')

    # Ensure uv-installed tools are reachable in this session.
    $env:PATH = "$env:USERPROFILE\.local\bin;$env:PATH"

    $ninja = Get-Command ninja -ErrorAction SilentlyContinue
    if ($ninja) {
        $currentVersion = ''
        try {
            $currentVersion = (& $ninja.Source --version 2>$null | Select-Object -First 1).Trim()
        } catch {
            $currentVersion = ''
        }

        if ($currentVersion -eq $Version) {
            return
        }
    }

    Write-Step "Installing build tools (Ninja $Version)"
    Invoke-Checked -Command 'uv' -Arguments @('tool', 'install', "ninja==$Version") -ErrorMessage 'Failed to install Ninja via uv'
    Write-Done
}

function Get-RepoRootFromScript([string]$ScriptPath) {
    return (Resolve-Path (Join-Path (Split-Path -Parent $ScriptPath) '..\..\..')).Path
}

function Compress-DirectoryToArchive {
    param(
        [Parameter(Mandatory = $true)][string]$SourceDir,
        [Parameter(Mandatory = $true)][string]$ArchivePath,
        [Parameter(Mandatory = $true)][string]$ZstdExePath,
        [int]$CompressionLevel = 19,
        [long]$LongWindow = 30
    )

    if (-not (Test-Path $ZstdExePath)) {
        throw "zstd executable not found: $ZstdExePath"
    }
    if (-not (Test-Path $SourceDir)) {
        throw "source directory not found: $SourceDir"
    }

    $ArchivePath = Resolve-AbsolutePath -Path $ArchivePath
    $sourceFullPath = Resolve-AbsolutePath -Path $SourceDir
    $archiveParent = Split-Path -Parent $ArchivePath
    if ($archiveParent -and -not (Test-Path $archiveParent)) {
        New-Item -ItemType Directory -Path $archiveParent -Force | Out-Null
    }

    Remove-Item -Path $ArchivePath -Force -ErrorAction SilentlyContinue

    Write-Step "Compressing directory $SourceDir to archive $ArchivePath with zstd (level $CompressionLevel, long window $LongWindow)"
    pushd $sourceFullPath > $null
    try {
        tar -cf - . | & $ZstdExePath "-$CompressionLevel" "--long=$LongWindow" '--threads=0' '-f' '-o' $ArchivePath '-'
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to compress directory with zstd: $ZstdExePath"
        }
    } finally {
        popd > $null
    }
    Write-Done
}

function Decompress-ArchiveToDirectory {
    param(
        [Parameter(Mandatory = $true)][string]$ArchivePath,
        [Parameter(Mandatory = $true)][string]$DestinationDir,
        [Parameter(Mandatory = $true)][string]$ZstdExePath,
        [int]$LongWindow = 30
    )

    if (-not (Test-Path $ArchivePath)) {
        throw "archive not found: $ArchivePath"
    }
    if (-not (Test-Path $ZstdExePath)) {
        throw "zstd executable not found: $ZstdExePath"
    }

    if (Test-Path $DestinationDir) {
        Remove-Item -Path $DestinationDir -Recurse -Force
    }
    New-Item -ItemType Directory -Path $DestinationDir -Force | Out-Null

    Write-Step "Decompressing tar.zst archive $ArchivePath to directory $DestinationDir"
    # Stream: zstd decompression -> tar extraction.
    & $ZstdExePath '-d' "--long=$LongWindow" $ArchivePath '-c' | tar '-xf' '-' '-C' $DestinationDir
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to extract tar stream from archive: $ArchivePath"
    }
    Write-Done
}

function Initialize-LlvmSourceTree {
    param(
        [Parameter(Mandatory = $true)][string]$LlvmProjectRef,
        [string]$RepoDir = (Join-Path $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath('.') 'llvm-project')
    )

    $archiveUrl = "https://github.com/llvm/llvm-project/archive/$LlvmProjectRef.tar.gz"
    $tempArchive = Join-Path ([IO.Path]::GetTempPath()) ("llvm-project-$LlvmProjectRef.tar.gz")

    Write-Step "Downloading LLVM/MLIR source ($LlvmProjectRef)"
    Remove-PathIfExists -Path $RepoDir
    New-Item -ItemType Directory -Path $RepoDir -Force | Out-Null

    try {
        Invoke-WebRequest -Uri $archiveUrl -OutFile $tempArchive

        $excludeArgs = @(
            '-xzf', $tempArchive,
            '--strip-components=1',
            '-C', $RepoDir,
            '--exclude=clang',
            '--exclude=lldb',
            '--exclude=polly',
            '--exclude=flang',
            '--exclude=openmp',
            '--exclude=libclc',
            '--exclude=libc',
            '--exclude=llvm/test',
            '--exclude=llvm/unittests',
            '--exclude=mlir/test',
            '--exclude=mlir/unittests'
        )
        Invoke-Checked -Command 'tar' -Arguments $excludeArgs -ErrorMessage 'Failed to extract llvm-project archive'
    } finally {
        Remove-Item -Path $tempArchive -Force -ErrorAction SilentlyContinue
    }

    Write-Done
    return $RepoDir
}

function Get-LlvmCommonCMakeArgs {
    param(
        [Parameter(Mandatory = $true)][string]$BuildDir,
        [Parameter(Mandatory = $true)][ValidateSet('Release', 'Debug')][string]$BuildType,
        [Parameter(Mandatory = $true)][string]$InstallPrefix,
        [Parameter(Mandatory = $true)][string]$HostTarget,
        [Parameter(Mandatory = $true)][string]$Projects,
        [string]$PrefixPath,
    )

    $cmakeArgs = @(
        '-S', 'llvm',
        '-B', $BuildDir,
        '-G', 'Ninja',
        "-DCMAKE_BUILD_TYPE=$BuildType",
        "-DCMAKE_INSTALL_PREFIX=$InstallPrefix",
        "-DLLVM_TARGETS_TO_BUILD=$HostTarget",
        "-DLLVM_ENABLE_PROJECTS=$Projects",
        '-DLLVM_BUILD_EXAMPLES=OFF',
        '-DLLVM_INCLUDE_EXAMPLES=OFF',
        '-DLLVM_BUILD_TESTS=OFF',
        '-DLLVM_INCLUDE_TESTS=OFF',
        '-DLLVM_INCLUDE_BENCHMARKS=OFF',
        '-DLLVM_ENABLE_ASSERTIONS=ON',
        '-DLLVM_ENABLE_LTO=OFF',
        '-DLLVM_ENABLE_RTTI=ON',
        '-DLLVM_ENABLE_LIBXML2=OFF',
        '-DLLVM_ENABLE_LIBEDIT=OFF',
        '-DLLVM_ENABLE_LIBPFM=OFF',
        '-DLLVM_INSTALL_UTILS=ON',
        '-DLLVM_OPTIMIZED_TABLEGEN=ON',
        '-DLLVM_ENABLE_WARNINGS=OFF',
        '-DLLVM_ENABLE_ZSTD=FORCE_ON',
        '-DLLVM_USE_STATIC_ZSTD=ON',
        '-DLLVM_USE_LINKER=mold'
    )

    if ($BuildType -eq 'Debug') {
        $cmakeArgs += @(
            '-DCMAKE_MSVC_DEBUG_INFORMATION_FORMAT=Embedded',
            '-DCMAKE_POLICY_DEFAULT_CMP0141=NEW'
        )
    }

    if ($PrefixPath) {
        $cmakeArgs += "-DCMAKE_PREFIX_PATH=$PrefixPath"
    }

    return $cmakeArgs
}

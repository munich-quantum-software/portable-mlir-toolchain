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

function Enter-VsDevShell {
    param([string]$VsArch)

    $vsInstaller = if (Test-Path "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe") {
        "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
    } else {
        "C:\Program Files\Microsoft Visual Studio\Installer\vswhere.exe"
    }

    $vsPath = & $vsInstaller -latest -property installationPath 2>$null
    if (-not $vsPath) { throw 'Visual Studio installation not found' }

    $devShell = Join-Path $vsPath "Common7\Tools\Launch-VsDevShell.ps1"

    Write-Step "Setting up VS developer environment ($vsArch)"
    & $devShell -Arch $vsArch -SkipAutomaticLocation
    if (-not $?) { throw "Failed to set up VS developer environment" }
    Write-Done
}

function Ensure-Ninja {
    param([string]$Version = '1.13.0')

    # Ensure uv-installed tools are reachable in this session.
    $env:PATH = "$env:USERPROFILE\.local\bin;$env:PATH"

    if (Get-Command ninja -ErrorAction SilentlyContinue) {
        return
    }

    Write-Step "Installing build tools (Ninja $Version)"
    Invoke-Checked -Command 'uv' -Arguments @('tool', 'install', "ninja==$Version") -ErrorMessage 'Failed to install Ninja via uv'
    Write-Done
}

function Get-RepoRootFromScript([string]$ScriptPath) {
    return (Resolve-Path (Join-Path (Split-Path -Parent $ScriptPath) '..\..\..')).Path
}

function Initialize-LlvmSourceTree {
    param(
        [Parameter(Mandatory = $true)][string]$llvm_project_ref,
        [string]$RepoDir = (Join-Path $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath('.') 'llvm-project'),
        [switch]$ExcludeMlirTests
    )

    $archiveUrl = "https://github.com/llvm/llvm-project/archive/$llvm_project_ref.tar.gz"
    $tempArchive = Join-Path ([IO.Path]::GetTempPath()) ("llvm-project-$llvm_project_ref.tar.gz")

    Write-Step "Downloading LLVM/MLIR source ($llvm_project_ref)"
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
            '--exclude=llvm/unittests'
        )
        if ($ExcludeMlirTests) {
            $excludeArgs += @(
                '--exclude=mlir/test',
                '--exclude=mlir/unittests'
            )
        }

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
        [switch]$EnableLld
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
        '-DLLVM_USE_STATIC_ZSTD=ON'
    )

    if ($BuildType -eq 'Debug') {
        $cmakeArgs += @(
            '-DCMAKE_MSVC_DEBUG_INFORMATION_FORMAT=Embedded',
            '-DCMAKE_POLICY_DEFAULT_CMP0141=NEW'
        )
    }

    if ($EnableLld) {
        $cmakeArgs += '-DLLVM_ENABLE_LLD=ON'
    }
    if ($PrefixPath) {
        $cmakeArgs += "-DCMAKE_PREFIX_PATH=$PrefixPath"
    }

    return $cmakeArgs
}

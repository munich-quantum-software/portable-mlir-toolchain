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

param(
    [Parameter(Mandatory)][string]$ArchivePath,
    [Parameter(Mandatory)][string]$ZstdInstallPrefix,
    [ValidateSet("Release", "Debug")]
    [string]$BuildType = "Release"
)

$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Logging helpers
# ---------------------------------------------------------------------------
$_step_sw = [Diagnostics.Stopwatch]::new()
function Write-Step([string]$msg) {
    $_step_sw.Restart()
    Write-Host ""
    Write-Host "════════════════════════════════════════════════════════════════"
    Write-Host "  ▶  $msg"
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
# ---------------------------------------------------------------------------

# Detect architecture
$arch = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture

# Find and enter VS developer shell to set up MSVC environment for Ninja
$vsInstaller = if (Test-Path "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe") {
    "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
} else {
    "C:\Program Files\Microsoft Visual Studio\Installer\vswhere.exe"
}
$vsPath = & $vsInstaller -latest -property installationPath 2>$null
if (-not $vsPath) { throw "Visual Studio installation not found" }
$devShell = Join-Path $vsPath "Common7\Tools\Launch-VsDevShell.ps1"
$vsArch = switch ($arch) {
    'X64'   { 'amd64' }
    'Arm64' { 'arm64' }
    default { throw "Unsupported architecture: $arch" }
}
Write-Step "Setting up VS developer environment ($vsArch)"
& $devShell -Arch $vsArch -SkipAutomaticLocation
if (-not $?) { throw "Failed to set up VS developer environment" }
Write-Done

# Ensure Ninja is available for fast, parallel builds
Write-Step "Installing build tools (Ninja)"
uv tool install ninja
if ($LASTEXITCODE -ne 0) { throw "Failed to install Ninja via uv" }
# Ensure uv-installed tools are on the PATH
$env:PATH = "$env:USERPROFILE\.local\bin;$env:PATH"
Write-Done

$ZstdExe = Join-Path $ZstdInstallPrefix "zstd.exe"
if (-not (Test-Path $ZstdExe)) {
    throw "zstd.exe not found at '$ZstdExe'"
}

Write-Host "Testing installation from $ArchivePath..."

$TestInstallDir = Join-Path ([System.IO.Path]::GetTempPath()) ([System.IO.Path]::GetRandomFileName())
$TestBuildDir   = Join-Path ([System.IO.Path]::GetTempPath()) ([System.IO.Path]::GetRandomFileName())
New-Item -ItemType Directory -Force -Path $TestInstallDir | Out-Null
New-Item -ItemType Directory -Force -Path $TestBuildDir   | Out-Null

try {
    Write-Step "Extracting archive"
    # Extract the archive using the bundled zstd
    & $ZstdExe -d --long=30 $ArchivePath -c | tar -xf - -C $TestInstallDir
    if ($LASTEXITCODE -ne 0) { throw "Extraction failed" }
    Write-Done

    Write-Step "Verifying archive structure"
    # Verify basic structure
    foreach ($d in @("bin", "include")) {
        $p = Join-Path $TestInstallDir $d
        if (-not (Test-Path $p)) {
            throw "Error: $d not found in installation"
        }
    }

    # Find cmake config directories
    $MLIRCMakeDir = Get-ChildItem -Recurse -Directory -Path $TestInstallDir |
            Where-Object { $_.Name -eq "mlir" -and $_.FullName -match "cmake" } |
            Select-Object -First 1 -ExpandProperty FullName
    $LLVMCMakeDir = Get-ChildItem -Recurse -Directory -Path $TestInstallDir |
            Where-Object { $_.Name -eq "llvm" -and $_.FullName -match "cmake" } |
            Select-Object -First 1 -ExpandProperty FullName

    if (-not $MLIRCMakeDir) { throw "Error: MLIR cmake directory not found in installation" }
    if (-not $LLVMCMakeDir) { throw "Error: LLVM cmake directory not found in installation" }

    Write-Host "Found MLIR cmake dir: $MLIRCMakeDir"
    Write-Host "Found LLVM cmake dir: $LLVMCMakeDir"
    Write-Done

    Write-Step "Verifying key binaries"
    $env:PATH = "$TestInstallDir\bin;$env:PATH"
    & "$TestInstallDir\bin\mlir-opt.exe" --version
    if ($LASTEXITCODE -ne 0) { throw "mlir-opt --version failed" }
    & "$TestInstallDir\bin\mlir-translate.exe" --version
    if ($LASTEXITCODE -ne 0) { throw "mlir-translate --version failed" }
    Write-Done

    # Locate integration test sources relative to this script
    $ScriptDir  = Split-Path -Parent $MyInvocation.MyCommand.Path
    $RepoRoot   = (Resolve-Path (Join-Path $ScriptDir "..\..\..")).Path
    $IntegrationSrc = Join-Path $RepoRoot "tests\integration"

    if (-not (Test-Path $IntegrationSrc)) {
        throw "Error: integration test sources not found at $IntegrationSrc"
    }

    Write-Step "CMake configure – integration test"
    cmake -G Ninja `
    -S $IntegrationSrc `
    -B $TestBuildDir `
    "-DCMAKE_BUILD_TYPE=$BuildType" `
    "-DCMAKE_PREFIX_PATH=$TestInstallDir" `
    "-DMLIR_DIR=$MLIRCMakeDir" `
    "-DLLVM_DIR=$LLVMCMakeDir" `
    "-DLLVM_ENABLE_LLD=ON"
    if ($LASTEXITCODE -ne 0) { throw "cmake configure failed" }
    Write-Done

    Write-Step "CMake build – integration test"
    cmake --build $TestBuildDir --config $BuildType
    if ($LASTEXITCODE -ne 0) { throw "cmake build failed" }
    Write-Done

    Write-Step "Running integration test binary"
    & "$TestBuildDir\hello_mlir.exe"
    if ($LASTEXITCODE -ne 0) { throw "hello_mlir failed" }
    Write-Done

    Write-Host "Integration test passed!"
} finally {
    Remove-Item -Recurse -Force $TestInstallDir -ErrorAction SilentlyContinue
    Remove-Item -Recurse -Force $TestBuildDir   -ErrorAction SilentlyContinue
}

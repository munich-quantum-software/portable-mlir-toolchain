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
    [Parameter(Mandatory = $true)][string]$ZstdExePath,
    [Parameter(Mandatory = $true)][string]$LldArchivePath,
    [Parameter(Mandatory = $true)][string]$ZstdArchivePath,
    [Parameter(Mandatory = $true)][string]$MlirArchivePath,
    [string]$NinjaVersion = '1.13.0',
    [ValidateSet('Release', 'Debug')][string]$BuildType = 'Release'
)

$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'common.ps1')

$archInfo = Get-ArchInfo
Enter-VisualStudioDevShell -VsArch $archInfo.VsArch
Ensure-Ninja -Version $NinjaVersion

$ZstdExePath = Resolve-AbsolutePath -Path $ZstdExePath
if (-not (Test-Path $ZstdExePath)) {
    throw "zstd executable not found: $ZstdExePath"
}

$ZstdArchivePath = Resolve-AbsolutePath -Path $ZstdArchivePath
if (-not (Test-Path $ZstdArchivePath)) {
    throw "zstd archive not found: $ZstdArchivePath"
}
$tempZstdExtractDir = Join-Path ([System.IO.Path]::GetTempPath()) ([System.IO.Path]::GetRandomFileName())
New-Item -ItemType Directory -Force -Path $tempZstdExtractDir | Out-Null
try {
    Decompress-ArchiveToDirectory -ArchivePath $ZstdArchivePath -DestinationDir $tempZstdExtractDir -ZstdExePath $ZstdExePath
} catch {
    throw "Failed to extract zstd archive: $($_.Exception.Message)"
}

$LldArchivePath = Resolve-AbsolutePath -Path $LldArchivePath
if (-not (Test-Path $LldArchivePath)) {
    throw "lld archive not found: $LldArchivePath"
}
$tempLldExtractDir = Join-Path ([System.IO.Path]::GetTempPath()) ([System.IO.Path]::GetRandomFileName())
New-Item -ItemType Directory -Force -Path $tempLldExtractDir | Out-Null
try {
    Decompress-ArchiveToDirectory -ArchivePath $LldArchivePath -DestinationDir $tempLldExtractDir -ZstdExePath $ZstdExePath
} catch {
    throw "Failed to extract lld archive: $($_.Exception.Message)"
}
$lldExe = Join-Path $tempLldExtractDir 'bin\ldd-link.exe'
if (-not (Test-Path $lldExe)) {
    throw "lld executable not found: $lldExe"
}

$MlirArchivePath = Resolve-AbsolutePath -Path $MlirArchivePath
if (-not (Test-Path $MlirArchivePath)) {
    throw "MLIR archive not found: $MlirArchivePath"
}
$tempMlirExtractDir = Join-Path ([System.IO.Path]::GetTempPath()) ([System.IO.Path]::GetRandomFileName())
New-Item -ItemType Directory -Force -Path $tempMlirExtractDir | Out-Null
try {
    Decompress-ArchiveToDirectory -ArchivePath $MlirArchivePath -DestinationDir $tempMlirExtractDir -ZstdExePath $ZstdExePath
} catch {
    throw "Failed to extract MLIR archive: $($_.Exception.Message)"
}


Write-Host "Testing installation from $MlirArchivePath..."

$TestBuildDir = Join-Path ([System.IO.Path]::GetTempPath()) ([System.IO.Path]::GetRandomFileName())
New-Item -ItemType Directory -Force -Path $TestBuildDir   | Out-Null

try {
    # Find cmake config directories
    $MLIRCMakeDir = Get-ChildItem -Recurse -Directory -Path $tempMlirExtractDir |
            Where-Object { $_.Name -eq "mlir" -and $_.FullName -match "cmake" } |
            Select-Object -First 1 -ExpandProperty FullName
    $LLVMCMakeDir = Get-ChildItem -Recurse -Directory -Path $tempMlirExtractDir |
            Where-Object { $_.Name -eq "llvm" -and $_.FullName -match "cmake" } |
            Select-Object -First 1 -ExpandProperty FullName

    if (-not $MLIRCMakeDir) { throw "Error: MLIR cmake directory not found in installation" }
    if (-not $LLVMCMakeDir) { throw "Error: LLVM cmake directory not found in installation" }

    Write-Host "Found MLIR cmake dir: $MLIRCMakeDir"
    Write-Host "Found LLVM cmake dir: $LLVMCMakeDir"
    Write-Done

    Write-Step "Verifying key binaries"
    $env:PATH = "$tempMlirExtractDir\bin;$tempLldExtractDir\bin;$env:PATH"
    & "$tempMlirExtractDir\bin\mlir-opt.exe" --version
    if ($LASTEXITCODE -ne 0) { throw "mlir-opt --version failed" }
    & "$tempMlirExtractDir\bin\mlir-translate.exe" --version
    if ($LASTEXITCODE -ne 0) { throw "mlir-translate --version failed" }
    & $lldExe --version
    if ($LASTEXITCODE -ne 0) { throw "ldd-link --version failed" }
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
        "-DCMAKE_PREFIX_PATH=$tempZstdExtractDir;$tempMlirExtractDir" `
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
    Remove-Item -Recurse -Force $tempMlirExtractDir -ErrorAction SilentlyContinue
    Remove-Item -Recurse -Force $tempLldExtractDir -ErrorAction SilentlyContinue
    Remove-Item -Recurse -Force $TestBuildDir   -ErrorAction SilentlyContinue
}

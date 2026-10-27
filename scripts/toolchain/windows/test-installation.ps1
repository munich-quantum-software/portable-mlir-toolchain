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
    [Parameter(Mandatory = $true)][string]$ZstdArchivePath,
    [Parameter(Mandatory = $true)][string]$MlirArchivePath,
    [string]$NinjaVersion = '1.13.0'
)

$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'common.ps1')

$archInfo = Get-ArchInfo
Enter-VisualStudioDevShell -VsArch $archInfo.VsArch
Ensure-Ninja -Version $NinjaVersion

Invoke-WithTempSession -ScriptBlock {
    param($tempRoot)

    $resolvedZstdArchivePath = Resolve-ExistingPath -Path $ZstdArchivePath -Description 'zstd archive'
    $resolvedMlirArchivePath = Resolve-ExistingPath -Path $MlirArchivePath -Description 'MLIR archive'

    $tempZstdDir = New-ScopedTempDir -RootPath $tempRoot
    $resolvedZstdExePath = Expand-ZstdExecutableFromTarGz -ArchivePath $resolvedZstdArchivePath -DestinationDir $tempZstdDir

    $tempMlirExtractDir = New-ScopedTempDir -RootPath $tempRoot
    Decompress-ArchiveToDirectory -ArchivePath $resolvedMlirArchivePath -DestinationDir $tempMlirExtractDir -ZstdExePath $resolvedZstdExePath

    Write-Host "Testing installation from $resolvedMlirArchivePath..."

    $testBuildDir = New-ScopedTempDir -RootPath $tempRoot

    Write-Step 'Verifying key binaries'
    $env:PATH = "$tempMlirExtractDir\bin;$env:PATH"
    & "$tempMlirExtractDir\bin\mlir-opt.exe" --version

    & "$tempMlirExtractDir\bin\mlir-translate.exe" --version

    Write-Done

    $repoRoot = Get-RepoRootFromScript -ScriptPath $PSCommandPath
    $integrationSrc = Join-Path $repoRoot 'tests\integration'

    if (-not (Test-Path $integrationSrc)) {
        throw "Error: integration test sources not found at $integrationSrc"
    }

    Write-Step 'CMake configure - integration test'
    cmake -G Ninja `
        -S $integrationSrc `
        -B $testBuildDir `
        '-DCMAKE_BUILD_TYPE=Release' `
        "-DEXPECTED_LLVM_ASSERTIONS=$(if ($env:LLVM_ENABLE_ASSERTIONS) { $env:LLVM_ENABLE_ASSERTIONS } else { 'ON' })" `
        "-DCMAKE_PREFIX_PATH=$tempMlirExtractDir" `
        '-DLLVM_ENABLE_LLD=ON'

    Write-Done

    Write-Step 'CMake build - integration test'
    cmake --build $testBuildDir --config Release

    Write-Done

    Write-Step 'Running integration test binary'
    & "$testBuildDir\hello_mlir.exe"

    Write-Done

    Write-Host 'Integration test passed!'
}

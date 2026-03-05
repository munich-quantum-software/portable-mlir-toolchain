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

Invoke-WithTempSession -ReferencePath (Get-Location).Path -ScriptBlock {
    param($tempRoot)

    $cleanupPaths = @()
    try {
        $resolvedZstdExePath = Resolve-ExistingPath -Path $ZstdExePath -Description 'zstd executable'
        $resolvedZstdArchivePath = Resolve-ExistingPath -Path $ZstdArchivePath -Description 'zstd archive'
        $resolvedLldArchivePath = Resolve-ExistingPath -Path $LldArchivePath -Description 'lld archive'
        $resolvedMlirArchivePath = Resolve-ExistingPath -Path $MlirArchivePath -Description 'MLIR archive'

        $tempZstdExtractDir = New-ScopedTempDir -RootPath $tempRoot
        $cleanupPaths += $tempZstdExtractDir
        Decompress-ArchiveToDirectory -ArchivePath $resolvedZstdArchivePath -DestinationDir $tempZstdExtractDir -ZstdExePath $resolvedZstdExePath

        $tempLldExtractDir = New-ScopedTempDir -RootPath $tempRoot
        $cleanupPaths += $tempLldExtractDir
        Decompress-ArchiveToDirectory -ArchivePath $resolvedLldArchivePath -DestinationDir $tempLldExtractDir -ZstdExePath $resolvedZstdExePath

        $null = Resolve-ExistingPath -Path (Join-Path $tempLldExtractDir 'bin\lld.exe') -Description 'lld executable'

        $tempMlirExtractDir = New-ScopedTempDir -RootPath $tempRoot
        $cleanupPaths += $tempMlirExtractDir
        Decompress-ArchiveToDirectory -ArchivePath $resolvedMlirArchivePath -DestinationDir $tempMlirExtractDir -ZstdExePath $resolvedZstdExePath

        Write-Host "Testing installation from $resolvedMlirArchivePath..."

        $testBuildDir = New-ScopedTempDir -RootPath $tempRoot
        $cleanupPaths += $testBuildDir

        $MLIRCMakeDir = Get-ChildItem -Recurse -Directory -Path $tempMlirExtractDir |
            Where-Object { $_.Name -eq 'mlir' -and $_.FullName -match 'cmake' } |
            Select-Object -First 1 -ExpandProperty FullName
        $LLVMCMakeDir = Get-ChildItem -Recurse -Directory -Path $tempMlirExtractDir |
            Where-Object { $_.Name -eq 'llvm' -and $_.FullName -match 'cmake' } |
            Select-Object -First 1 -ExpandProperty FullName

        if (-not $MLIRCMakeDir) { throw 'Error: MLIR cmake directory not found in installation' }
        if (-not $LLVMCMakeDir) { throw 'Error: LLVM cmake directory not found in installation' }

        Write-Host "Found MLIR cmake dir: $MLIRCMakeDir"
        Write-Host "Found LLVM cmake dir: $LLVMCMakeDir"
        Write-Done

        Write-Step 'Verifying key binaries'
        $env:PATH = "$tempMlirExtractDir\bin;$tempLldExtractDir\bin;$env:PATH"
        & "$tempMlirExtractDir\bin\mlir-opt.exe" --version
        if ($LASTEXITCODE -ne 0) { throw 'mlir-opt --version failed' }
        & "$tempMlirExtractDir\bin\mlir-translate.exe" --version
        if ($LASTEXITCODE -ne 0) { throw 'mlir-translate --version failed' }
        Write-Done

        $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
        $repoRoot = (Resolve-Path (Join-Path $scriptDir '..\..\..')).Path
        $integrationSrc = Join-Path $repoRoot 'tests\integration'

        if (-not (Test-Path $integrationSrc)) {
            throw "Error: integration test sources not found at $integrationSrc"
        }

        Write-Step 'CMake configure - integration test'
        cmake -G Ninja `
            -S $integrationSrc `
            -B $testBuildDir `
            "-DCMAKE_BUILD_TYPE=$BuildType" `
            "-DCMAKE_PREFIX_PATH=$tempZstdExtractDir;$tempMlirExtractDir" `
            "-DMLIR_DIR=$MLIRCMakeDir" `
            "-DLLVM_DIR=$LLVMCMakeDir" `
            '-DLLVM_ENABLE_LLD=ON'
        if ($LASTEXITCODE -ne 0) { throw 'cmake configure failed' }
        Write-Done

        Write-Step 'CMake build - integration test'
        cmake --build $testBuildDir --config $BuildType
        if ($LASTEXITCODE -ne 0) { throw 'cmake build failed' }
        Write-Done

        Write-Step 'Running integration test binary'
        & "$testBuildDir\hello_mlir.exe"
        if ($LASTEXITCODE -ne 0) { throw 'hello_mlir failed' }
        Write-Done

        Write-Host 'Integration test passed!'
    } finally {
        Remove-PathsIfExists -Paths $cleanupPaths
    }
}

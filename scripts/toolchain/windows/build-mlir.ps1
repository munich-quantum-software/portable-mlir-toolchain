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
    [Parameter(Mandatory = $true)][string]$LlvmProjectRef,
    [Parameter(Mandatory = $true)][string]$ZstdExePath,
    [Parameter(Mandatory = $true)][string]$ZstdArchivePath,
    [Parameter(Mandatory = $true)][string]$LldArchivePath,
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

$lldExe = Join-Path $tempLldExtractDir 'bin\ldd.exe'
if (-not (Test-Path $lldExe)) {
    throw "lld executable not found: $lldExe"
}
try {
    $lldVersionOutput = & $lldExe --version 2>&1
    Write-Host "LLD version output: $lldVersionOutput"
} catch {
    throw "Failed to execute lld to get version information: $($_.Exception.Message)"
}
$env:PATH = "$($tempLldExtractDir)\bin;$env:PATH"

$tempInstallDir = Join-Path ([System.IO.Path]::GetTempPath()) ([System.IO.Path]::GetRandomFileName())
New-Item -ItemType Directory -Path $tempInstallDir -Force | Out-Null

$tempBuildDir = Join-Path ([System.IO.Path]::GetTempPath()) ([System.IO.Path]::GetRandomFileName())
New-Item -ItemType Directory -Path $tempBuildDir -Force | Out-Null

try {
    $repoDir = Initialize-LlvmSourceTree -LlvmProjectRef $LlvmProjectRef

    pushd $repoDir > $null
    $cmakeArgs = Get-LlvmCommonCMakeArgs `
        -BuildDir $tempBuildDir `
        -BuildType $BuildType `
        -InstallPrefix $tempInstallDir `
        -HostTarget $archInfo.HostTarget `
        -Projects 'mlir' `
        -PrefixPath $tempZstdExtractDir

    Write-Step "CMake configure MLIR ($BuildType)"
    Invoke-Checked -Command 'cmake' -Arguments $cmakeArgs -ErrorMessage 'MLIR cmake configure failed'
    Write-Done

    Write-Step "Build and install MLIR ($BuildType)"
    Invoke-Checked -Command 'cmake' -Arguments @('--build', $tempBuildDir, '--target', 'install', '--config', $BuildType) -ErrorMessage 'MLIR build/install failed'
    Write-Done
} finally {
    popd > $null
    Remove-PathIfExists -Path $repoDir
    Remove-PathIfExists -Path $tempZstdExtractDir
    Remove-PathIfExists -Path $tempLldExtractDir
    Remove-PathIfExists -Path $tempBuildDir
}

try {
    Compress-DirectoryToArchive -SourceDir $tempInstallDir -ArchivePath $MlirArchivePath -ZstdExePath $ZstdExePath
} finally {
    Remove-PathIfExists -Path $tempInstallDir
}

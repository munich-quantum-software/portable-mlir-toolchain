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
    [Parameter(Mandatory = $true)][string]$ZstdArchivePath,
    [Parameter(Mandatory = $true)][string]$MoldArchivePath,
    [string]$MoldVersion = '2.40.4',
    [string]$NinjaVersion = '1.13.0'
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
$tempExtractDir = Join-Path ([System.IO.Path]::GetTempPath()) ([System.IO.Path]::GetRandomFileName())
New-Item -ItemType Directory -Force -Path $tempExtractDir | Out-Null
try {
    Decompress-ArchiveToDirectory -ArchivePath $ZstdArchivePath -DestinationDir $tempExtractDir -ZstdExePath $ZstdExePath
} catch {
    throw "Failed to extract zstd archive: $($_.Exception.Message)"
}

$rootDir = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath('.')
$moldDir = Join-Path $rootDir "mold-$MoldVersion"
Remove-PathIfExists -Path $moldDir

$tempInstallDir = Join-Path ([System.IO.Path]::GetTempPath()) ("mold-install-$MoldVersion-$([Guid]::NewGuid().ToString('N'))")
New-Item -ItemType Directory -Path $tempInstallDir -Force | Out-Null

$tempBuildDir = Join-Path ([IO.Path]::GetTempPath()) ("mold-$MoldVersion-$([Guid]::NewGuid().ToString('N'))")
New-Item -ItemType Directory -Path $tempBuildDir -Force | Out-Null

$moldTarball = Join-Path $tempBuildDir "mold-$MoldVersion.tar.gz"
$moldUrl = "https://github.com/rui314/mold/archive/refs/tags/v$MoldVersion.tar.gz"

Write-Step "Building mold v$MoldVersion"
try {
    Invoke-WebRequest -Uri $moldUrl -OutFile $moldTarball
    Invoke-Checked -Command 'tar' -Arguments @('-xzf', $moldTarball, '-C', $rootDir) -ErrorMessage 'Failed to extract mold source archive'

    pushd $moldDir > $null
    try {
        Invoke-Checked -Command 'cmake' -Arguments @(
            '-S', '.',
            '-B', 'build',
            '-G', 'Ninja',
            '-DCMAKE_C_COMPILER=clang-cl',
            '-DCMAKE_CXX_COMPILER=clang-cl',
            "-DCMAKE_BUILD_TYPE=Release",
            "-DCMAKE_INSTALL_PREFIX=$tempInstallDir",
            "-DZSTD_ROOT=$tempExtractDir",
            '-DMOLD_LTO=ON',
            '-DMOLD_USE_SYSTEM_TBB=OFF',
            '-DMOLD_USE_SYSTEM_MIMALLOC=OFF',
            '-DMOLD_USE_MIMALLOC=ON'
        ) -ErrorMessage 'Failed to configure mold build with CMake'

        Invoke-Checked -Command 'cmake' -Arguments @('--build', 'build', '--target', 'install') -ErrorMessage 'Failed to build and install mold'
    } finally {
        popd > $null
    }
    $moldExe = Join-Path $tempInstallDir 'bin\mold.exe'
    if (-not (Test-Path $moldExe)) {
        throw "mold.exe was not found at expected path: $moldExe"
    }
} finally {
    Remove-PathIfExists -Path $tempExtractDir
    Remove-PathIfExists -Path $moldDir
    Remove-PathIfExists -Path $tempBuildDir
}
Write-Done

try {
    Compress-DirectoryToArchive -SourceDir $tempInstallDir -ArchivePath $MoldArchivePath -ZstdExePath $ZstdExePath
} finally {
    Remove-PathIfExists -Path $tempInstallDir
}

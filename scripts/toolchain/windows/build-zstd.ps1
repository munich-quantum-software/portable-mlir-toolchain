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
    [Parameter(Mandatory = $true)][string]$InstallPrefix,
    [string]$ZstdVersion = '1.5.7',
    [string]$NinjaVersion = '1.13.0'
)

$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'common.ps1')

$InstallPrefix = Resolve-AbsolutePath -Path $InstallPrefix
$archInfo = Get-ArchInfo
Enter-VsDevShell -VsArch $archInfo.VsArch
Ensure-Ninja -Version $NinjaVersion

$rootDir = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath('.')
$zstdDir = Join-Path $rootDir "zstd-$ZstdVersion"
$tempDir = Join-Path ([IO.Path]::GetTempPath()) ("zstd-$ZstdVersion-$([Guid]::NewGuid().ToString('N'))")
New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

$zstdTarball = Join-Path $tempDir "zstd-$ZstdVersion.tar.gz"
$zstdChecksumFile = "$zstdTarball.sha256"
$zstdUrl = "https://github.com/facebook/zstd/releases/download/v$ZstdVersion/$(Split-Path -Leaf $zstdTarball)"
$zstdChecksumUrl = "https://github.com/facebook/zstd/releases/download/v$ZstdVersion/$(Split-Path -Leaf $zstdChecksumFile)"

Write-Step "Building zstd v$ZstdVersion"
Remove-PathIfExists -Path $InstallPrefix
Remove-PathIfExists -Path $zstdDir

try {
    Invoke-WebRequest -Uri $zstdUrl -OutFile $zstdTarball
    Invoke-WebRequest -Uri $zstdChecksumUrl -OutFile $zstdChecksumFile

    $expectedHashLine = Get-Content $zstdChecksumFile | Select-Object -First 1
    $expectedHash = ($expectedHashLine -split ' ')[0]
    $actualHash = (Get-FileHash $zstdTarball -Algorithm SHA256).Hash
    if ($actualHash.ToLowerInvariant() -ne $expectedHash.ToLowerInvariant()) {
        throw "Checksum verification failed for $zstdTarball. Expected: $expectedHash, Actual: $actualHash"
    }

    Invoke-Checked -Command 'tar' -Arguments @('-xzf', $zstdTarball, '-C', $rootDir) -ErrorMessage 'Failed to extract zstd source archive'

    pushd (Join-Path $zstdDir 'build\cmake') > $null
    try {
        Invoke-Checked -Command 'cmake' -Arguments @(
            '-S', '.',
            '-B', 'build',
            '-G', 'Ninja',
            '-DCMAKE_BUILD_TYPE=Release',
            "-DCMAKE_INSTALL_PREFIX=$InstallPrefix",
            '-DZSTD_BUILD_STATIC=ON',
            '-DZSTD_BUILD_SHARED=OFF'
        ) -ErrorMessage 'zstd cmake configure failed'

        Invoke-Checked -Command 'cmake' -Arguments @(
            '--build', 'build',
            '--target', 'install',
            '--config', 'Release'
        ) -ErrorMessage 'zstd build/install failed'
    } finally {
        popd > $null
    }
} finally {
    Remove-PathIfExists -Path $zstdDir
    Remove-PathIfExists -Path $tempDir
}

$zstdExe = Join-Path $InstallPrefix 'bin\zstd.exe'
if (-not (Test-Path $zstdExe)) {
    throw "zstd.exe was not found at expected path: $zstdExe"
}
Write-Done

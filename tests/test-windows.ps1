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

param([string]$ZstdArchivePath = $env:ZSTD_ARCHIVE_PATH)

. (Join-Path $PSScriptRoot '../scripts/toolchain/windows/common.ps1')

# Both upstream and downstream native failures must terminate binary pipelines.
foreach ($pipeline in @(
    { cmd.exe /c 'exit 7' | cmd.exe /c 'exit 0' },
    { cmd.exe /c 'exit 0' | cmd.exe /c 'exit 7' }
)) {
    $failed = $false
    try { & $pipeline } catch { $failed = $true }
    if (-not $failed) { throw 'Native pipeline failure was ignored' }
}

$originalTemp = $env:TEMP
$originalPath = $env:PATH
$session = $null
try {
    Invoke-WithTempSession {
        param($root)
        $script:session = $root
        $sentinel = Join-Path $root 'sentinel'
        Set-Content $sentinel 'outer session'
        Invoke-WithTempSession {
            param($inner)
            if ($inner -eq $root) { throw 'Temporary sessions overlap' }
        }
        if (-not (Test-Path $sentinel)) { throw 'Nested session removed its parent' }

        $zstd = Expand-ZstdExecutableFromTarGz -ArchivePath $ZstdArchivePath -DestinationDir (Join-Path $root 'zstd')
        $source = New-ScopedTempDir $root
        $data = Join-Path $source 'bytes.bin'
        [IO.File]::WriteAllBytes($data, [byte[]](0..255))
        $archive = Join-Path $root 'payload.tar.zst'
        Compress-DirectoryToArchive $source $archive $zstd
        $extracted = Join-Path $root 'extracted'
        Decompress-ArchiveToDirectory $archive $extracted $zstd
        if ((Get-FileHash $data).Hash -ne (Get-FileHash (Join-Path $extracted 'bytes.bin')).Hash) {
            throw 'Binary archive round trip changed the payload'
        }
        $env:PATH = 'changed by test'
        throw 'deliberate session failure'
    }
} catch {
    if ($_.Exception.Message -ne 'deliberate session failure') { throw }
}
if ((Test-Path $session) -or $env:TEMP -ne $originalTemp -or $env:PATH -ne $originalPath) {
    throw 'Session cleanup did not restore the caller'
}
Write-Host 'Windows helper tests passed'

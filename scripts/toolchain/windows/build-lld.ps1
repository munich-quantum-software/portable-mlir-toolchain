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
    [string]$NinjaVersion = '1.13.0'
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

        $tempExtractDir = New-ScopedTempDir -RootPath $tempRoot
        $cleanupPaths += $tempExtractDir
        Decompress-ArchiveToDirectory -ArchivePath $resolvedZstdArchivePath -DestinationDir $tempExtractDir -ZstdExePath $resolvedZstdExePath

        $tempInstallDir = New-ScopedTempDir -RootPath $tempRoot
        $cleanupPaths += $tempInstallDir

        $tempBuildDir = New-ScopedTempDir -RootPath $tempRoot
        $cleanupPaths += $tempBuildDir

        $repoDir = Initialize-LlvmSourceTree -LlvmProjectRef $LlvmProjectRef
        $cleanupPaths += $repoDir

        Invoke-InDirectory -Path $repoDir -ScriptBlock {
            $cmakeArgs = Get-LlvmCommonCMakeArgs `
                -BuildDir $tempBuildDir `
                -BuildType 'Release' `
                -InstallPrefix $tempInstallDir `
                -HostTarget $archInfo.HostTarget `
                -Projects 'lld' `
                -PrefixPath $tempExtractDir

            Write-Step 'CMake configure (lld only, Release)'
            Invoke-Checked -Command 'cmake' -Arguments $cmakeArgs -ErrorMessage 'lld cmake configure failed'
            Write-Done

            Write-Step 'Build and install lld (Release)'
            Invoke-Checked -Command 'cmake' -Arguments @('--build', $tempBuildDir, '--target', 'install-lld', '--config', 'Release') -ErrorMessage 'lld build/install failed'
            Write-Done
        }

        Compress-DirectoryToArchive -SourceDir $tempInstallDir -ArchivePath $LldArchivePath -ZstdExePath $resolvedZstdExePath
    } finally {
        Remove-PathsIfExists -Paths $cleanupPaths
    }
}

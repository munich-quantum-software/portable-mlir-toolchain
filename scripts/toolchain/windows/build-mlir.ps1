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
    [Parameter(Mandatory = $true)][string]$ZstdArchivePath,
    [Parameter(Mandatory = $true)][string]$LldArchivePath,
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
    $resolvedLldArchivePath = Resolve-ExistingPath -Path $LldArchivePath -Description 'lld archive'

    $tempZstdDir = New-ScopedTempDir -RootPath $tempRoot
    $resolvedZstdExePath = Expand-ZstdExecutableFromTarGz -ArchivePath $resolvedZstdArchivePath -DestinationDir $tempZstdDir

    $tempLldExtractDir = New-ScopedTempDir -RootPath $tempRoot
    Decompress-ArchiveToDirectory -ArchivePath $resolvedLldArchivePath -DestinationDir $tempLldExtractDir -ZstdExePath $resolvedZstdExePath

    $env:PATH = "$($tempLldExtractDir)\bin;$env:PATH"

    $tempInstallDir = New-ScopedTempDir -RootPath $tempRoot

    $tempBuildDir = New-ScopedTempDir -RootPath $tempRoot

    $repoDir = Initialize-LlvmSourceTree -LlvmProjectRef $LlvmProjectRef -RepoDir (Join-Path $tempRoot 'llvm-project')

    Invoke-InDirectory -Path $repoDir -ScriptBlock {
        $cmakeArgs = Get-LlvmCommonCMakeArgs `
            -BuildDir $tempBuildDir `
            -InstallPrefix $tempInstallDir `
            -HostTarget $archInfo.HostTarget `
            -Projects 'mlir' `
            -EnableLld

        Write-Step 'CMake configure MLIR (Release)'
        & cmake @cmakeArgs
        Write-Done

        Write-Step 'Build and install MLIR (Release)'
        cmake '--build' $tempBuildDir '--target' 'install' '--config' 'Release'
        Write-Done
    }

    # Vendor the lld installation into the MLIR archive to ensure lld is available in the test environment without needing to set up additional PATH entries.
    Copy-Item -Path (Join-Path $tempLldExtractDir 'bin\*') -Destination (Join-Path $tempInstallDir 'bin') -Recurse -Force

    Compress-DirectoryToArchive -SourceDir $tempInstallDir -ArchivePath $MlirArchivePath -ZstdExePath $resolvedZstdExePath
}

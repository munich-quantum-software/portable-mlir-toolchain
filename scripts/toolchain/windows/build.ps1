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
    [Parameter(Mandatory = $true)]
    [string]$llvm_project_ref,
    [Parameter(Mandatory = $true)]
    [string]$install_prefix,
    [ValidateSet('Release', 'Debug')]
    [string]$build_type = 'Release'
)

$ErrorActionPreference = 'Stop'

$rootDir = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath('.')
$windowsScripts = Join-Path $rootDir 'scripts\toolchain\windows'

. (Join-Path $windowsScripts 'common.ps1')

$install_prefix = Resolve-AbsolutePath -Path $install_prefix
$zstdInstallPrefix = Join-Path $rootDir 'zstd-install'
$lldInstallPrefix = Join-Path $rootDir 'lld-install'

Remove-PathIfExists -Path $zstdInstallPrefix
Remove-PathIfExists -Path $lldInstallPrefix
Remove-PathIfExists -Path $install_prefix

Write-Host "Building MLIR $llvm_project_ref into $install_prefix..."

try {
    try {
        & (Join-Path $windowsScripts 'build-zstd.ps1') -InstallPrefix $zstdInstallPrefix
        if (-not $?) { throw 'build-zstd.ps1 failed' }
    } catch {
        throw "build-zstd.ps1 failed: $($_.Exception.Message)"
    }

    try {
        & (Join-Path $windowsScripts 'build-lld.ps1') `
            -llvm_project_ref $llvm_project_ref `
            -install_prefix $lldInstallPrefix `
            -zstd_prefix $zstdInstallPrefix
        if (-not $?) { throw 'build-lld.ps1 failed' }
    } catch {
        throw "build-lld.ps1 failed: $($_.Exception.Message)"
    }

    try {
        & (Join-Path $windowsScripts 'build-mlir.ps1') `
            -llvm_project_ref $llvm_project_ref `
            -install_prefix $install_prefix `
            -lld_install_prefix $lldInstallPrefix `
            -build_type $build_type
        if (-not $?) { throw 'build-mlir.ps1 failed' }
    } catch {
        throw "build-mlir.ps1 failed: $($_.Exception.Message)"
    }

    $zstdExe = Join-Path $zstdInstallPrefix 'bin\zstd.exe'
    try {
        & (Join-Path $windowsScripts 'package-mlir.ps1') `
            -llvm_project_ref $llvm_project_ref `
            -install_prefix $install_prefix `
            -zstd_exe $zstdExe `
            -build_type $build_type `
            -output_dir $rootDir
        if (-not $?) { throw 'package-mlir.ps1 failed' }
    } catch {
        throw "package-mlir.ps1 failed: $($_.Exception.Message)"
    }

    # Keep publishing zstd.exe as a portable standalone payload.
    $zstdArchiveName = 'zstd-windows.zip'
    $zstdArchivePath = Join-Path $rootDir $zstdArchiveName
    Remove-PathIfExists -Path $zstdArchivePath
    Compress-Archive -Path $zstdExe -DestinationPath $zstdArchivePath
} finally {
    Remove-PathIfExists -Path $zstdInstallPrefix
    Remove-PathIfExists -Path $lldInstallPrefix
}

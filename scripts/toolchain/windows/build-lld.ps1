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
    [Parameter(Mandatory = $true)][string]$llvm_project_ref,
    [Parameter(Mandatory = $true)][string]$install_prefix,
    [Parameter(Mandatory = $true)][string]$zstd_prefix,
    [string]$NinjaVersion = '1.13.0'
)

$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'common.ps1')

$install_prefix = Resolve-AbsolutePath -Path $install_prefix
$zstd_prefix = Resolve-AbsolutePath -Path $zstd_prefix

$archInfo = Get-ArchInfo
Enter-VsDevShell
Ensure-Ninja -Version $NinjaVersion

if (-not (Test-Path (Join-Path $zstd_prefix 'lib'))) {
    throw "zstd install prefix does not look valid: $zstd_prefix"
}

Remove-PathIfExists -Path $install_prefix
$repoDir = Initialize-LlvmSourceTree -llvm_project_ref $llvm_project_ref

pushd $repoDir > $null
try {
    $buildDir = 'build_lld_release'
    $cmakeArgs = Get-LlvmCommonCMakeArgs `
        -BuildDir $buildDir `
        -BuildType 'Release' `
        -InstallPrefix $install_prefix `
        -HostTarget $archInfo.HostTarget `
        -Projects 'lld' `
        -PrefixPath $zstd_prefix

    Write-Step 'CMake configure (lld only, Release)'
    Invoke-Checked -Command 'cmake' -Arguments $cmakeArgs -ErrorMessage 'lld cmake configure failed'
    Write-Done

    Write-Step 'Build and install lld (Release)'
    Invoke-Checked -Command 'cmake' -Arguments @('--build', $buildDir, '--target', 'install-lld', '--config', 'Release') -ErrorMessage 'lld build/install failed'
    Write-Done
} finally {
    popd > $null
    Remove-PathIfExists -Path $repoDir
}

Write-Step 'Vendoring zstd installation into lld installation'
if (-not (Test-Path $install_prefix)) {
    throw "lld install prefix does not exist: $install_prefix"
}
Copy-Item -Path (Join-Path $zstd_prefix '*') -Destination $install_prefix -Recurse -Force
Write-Done

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
    [Parameter(Mandatory = $true)][string]$lld_install_prefix,
    [ValidateSet('Release', 'Debug')][string]$build_type = 'Release',
    [string]$NinjaVersion = '1.13.0'
)

$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'common.ps1')

$install_prefix = Resolve-AbsolutePath -Path $install_prefix
$lld_install_prefix = Resolve-AbsolutePath -Path $lld_install_prefix

$archInfo = Get-ArchInfo

Enter-VsDevShell
Ensure-Ninja -Version $NinjaVersion

$lldLink = Join-Path $lld_install_prefix 'bin\lld-link.exe'
if (-not (Test-Path $lldLink)) {
    throw "lld-link.exe not found in lld install prefix: $lld_install_prefix"
}
$env:PATH = "$(Join-Path $lld_install_prefix 'bin');$env:PATH"

$repoDir = Initialize-LlvmSourceTree -llvm_project_ref $llvm_project_ref -ExcludeMlirTests

Remove-PathIfExists -Path $install_prefix

pushd $repoDir > $null
try {
    $buildDir = 'build_mlir'
    $cmakeArgs = Get-LlvmCommonCMakeArgs `
        -BuildDir $buildDir `
        -BuildType $build_type `
        -InstallPrefix $install_prefix `
        -HostTarget $archInfo.HostTarget `
        -Projects 'mlir' `
        -PrefixPath $lld_install_prefix `
        -EnableLld

    Write-Step "CMake configure MLIR ($build_type)"
    Invoke-Checked -Command 'cmake' -Arguments $cmakeArgs -ErrorMessage 'MLIR cmake configure failed'
    Write-Done

    Write-Step "Build and install MLIR ($build_type)"
    Invoke-Checked -Command 'cmake' -Arguments @('--build', $buildDir, '--target', 'install', '--config', $build_type) -ErrorMessage 'MLIR build/install failed'
    Write-Done
} finally {
    popd > $null
    Remove-PathIfExists -Path $repoDir
}

Write-Step 'Bundling lld+zstd into the MLIR installation'
Copy-Item -Path (Join-Path $lld_install_prefix '*') -Destination $install_prefix -Recurse -Force
Write-Done

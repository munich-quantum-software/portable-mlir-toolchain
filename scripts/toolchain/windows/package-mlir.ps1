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
    [Parameter(Mandatory = $true)][string]$zstd_exe,
    [ValidateSet('Release', 'Debug')][string]$build_type = 'Release',
    [string]$output_dir = '.'
)

$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'common.ps1')

$install_prefix = Resolve-AbsolutePath -Path $install_prefix
$zstd_exe = Resolve-AbsolutePath -Path $zstd_exe
$output_dir = Resolve-AbsolutePath -Path $output_dir

if (-not (Test-Path $zstd_exe)) {
    throw "zstd executable not found: $zstd_exe"
}
if (-not (Test-Path $install_prefix)) {
    throw "install prefix not found: $install_prefix"
}
if (-not (Test-Path $output_dir)) {
    New-Item -ItemType Directory -Path $output_dir -Force | Out-Null
}

$archInfo = Get-ArchInfo
$debug = ($build_type -eq 'Debug')
$buildTypeSuffix = if ($debug) { '_debug' } else { '' }
$archiveName = "llvm-mlir_${llvm_project_ref}_windows_$($archInfo.Arch)_$($archInfo.HostTarget)$buildTypeSuffix.tar.zst"
$archivePath = Join-Path $output_dir $archiveName
$tempTar = Join-Path ([IO.Path]::GetTempPath()) ("$archiveName.tar")

Write-Step "Creating archive: $archiveName"
Remove-Item -Path $archivePath -Force -ErrorAction SilentlyContinue
Remove-Item -Path $tempTar -Force -ErrorAction SilentlyContinue

pushd $install_prefix > $null
try {
    Invoke-Checked -Command 'tar' -Arguments @('-cf', $tempTar, '.') -ErrorMessage 'Failed to create tar archive'
    Invoke-Checked -Command $zstd_exe -Arguments @('-19', '--long=30', '--threads=0', '-f', '-o', $archivePath, $tempTar) -ErrorMessage 'Failed to compress tar archive with zstd'
} finally {
    popd > $null
    Remove-Item -Path $tempTar -Force -ErrorAction SilentlyContinue
}
Write-Done

Write-Host "Archive created: $archivePath"

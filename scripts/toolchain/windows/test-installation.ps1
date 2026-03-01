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
    [Parameter(Mandatory)][string]$ArchivePath,
    [Parameter(Mandatory)][string]$ZstdInstallPrefix
)

$ErrorActionPreference = 'Stop'

$ZstdExe = Join-Path $ZstdInstallPrefix "zstd.exe"

Write-Host "Testing installation from $ArchivePath..."

$TestInstallDir = Join-Path ([System.IO.Path]::GetTempPath()) ([System.IO.Path]::GetRandomFileName())
$TestBuildDir   = Join-Path ([System.IO.Path]::GetTempPath()) ([System.IO.Path]::GetRandomFileName())
New-Item -ItemType Directory -Force -Path $TestInstallDir | Out-Null
New-Item -ItemType Directory -Force -Path $TestBuildDir   | Out-Null

try {
    # Extract the archive using the bundled zstd
    & $ZstdExe -d --long=30 $ArchivePath -c | tar -xf - -C $TestInstallDir
    if ($LASTEXITCODE -ne 0) { throw "Extraction failed" }

    # Verify basic structure
    foreach ($d in @("bin", "include")) {
        $p = Join-Path $TestInstallDir $d
        if (-not (Test-Path $p)) {
            throw "Error: $d not found in installation"
        }
    }

    # Find cmake config directories
    $MLIRCMakeDir = Get-ChildItem -Recurse -Directory -Path $TestInstallDir |
            Where-Object { $_.Name -eq "mlir" -and $_.FullName -match "cmake" } |
            Select-Object -First 1 -ExpandProperty FullName
    $LLVMCMakeDir = Get-ChildItem -Recurse -Directory -Path $TestInstallDir |
            Where-Object { $_.Name -eq "llvm" -and $_.FullName -match "cmake" } |
            Select-Object -First 1 -ExpandProperty FullName

    if (-not $MLIRCMakeDir) { throw "Error: MLIR cmake directory not found in installation" }
    if (-not $LLVMCMakeDir) { throw "Error: LLVM cmake directory not found in installation" }

    Write-Host "Found MLIR cmake dir: $MLIRCMakeDir"
    Write-Host "Found LLVM cmake dir: $LLVMCMakeDir"

    # Verify key binaries run
    $env:PATH = "$TestInstallDir\bin;$env:PATH"
    & "$TestInstallDir\bin\mlir-opt.exe" --version
    if ($LASTEXITCODE -ne 0) { throw "mlir-opt --version failed" }
    & "$TestInstallDir\bin\mlir-translate.exe" --version
    if ($LASTEXITCODE -ne 0) { throw "mlir-translate --version failed" }

    # Locate integration test sources relative to this script
    $ScriptDir  = Split-Path -Parent $MyInvocation.MyCommand.Path
    $RepoRoot   = (Resolve-Path (Join-Path $ScriptDir "..\..\..")).Path
    $IntegrationSrc = Join-Path $RepoRoot "tests\integration"

    if (-not (Test-Path $IntegrationSrc)) {
        throw "Error: integration test sources not found at $IntegrationSrc"
    }

    cmake -G Ninja `
    -S $IntegrationSrc `
    -B $TestBuildDir `
    -DCMAKE_BUILD_TYPE=Release `
    "-DMLIR_DIR=$MLIRCMakeDir" `
    "-DLLVM_DIR=$LLVMCMakeDir"
    if ($LASTEXITCODE -ne 0) { throw "cmake configure failed" }

    cmake --build $TestBuildDir
    if ($LASTEXITCODE -ne 0) { throw "cmake build failed" }

    & "$TestBuildDir\hello_mlir.exe"
    if ($LASTEXITCODE -ne 0) { throw "hello_mlir failed" }

    Write-Host "Integration test passed!"
} finally {
    Remove-Item -Recurse -Force $TestInstallDir -ErrorAction SilentlyContinue
    Remove-Item -Recurse -Force $TestBuildDir   -ErrorAction SilentlyContinue
}

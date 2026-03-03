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

# Windows build script: build and package the MLIR toolchain
#
# Description:
#   Builds LLVM and MLIR for Windows (arch-aware), and packages the results.
#
# Usage:
#   scripts/toolchain/windows/build.ps1 -llvm_project_ref <llvm_project_ref> -install_prefix <install_prefix> [-build_type <Release|Debug>]
#     llvm_project_ref llvm-project Git ref or commit SHA (e.g., llvmorg-21.1.8 or 179d30f...)
#     install_prefix   Absolute path for the final install
#     build_type       Build type (Release or Debug). Defaults to Release.
#
# Outputs:
#   - Installs into <install_prefix>
#   - Creates llvm-mlir_<llvm_project_ref>_windows_<arch>_<host_target>[_debug].tar.zst in the current directory
#   - Creates zstd-<zstd_version>_windows_<arch>_<host_target>.zip in the current directory

param(
    [Parameter(Mandatory=$true)]
    [string]$llvm_project_ref,
    [Parameter(Mandatory=$true)]
    [string]$install_prefix,
    [ValidateSet("Release", "Debug")]
    [string]$build_type = "Release"
)

$ErrorActionPreference = "Stop"

# ---------------------------------------------------------------------------
# Logging helpers
# ---------------------------------------------------------------------------
$_step_sw = [Diagnostics.Stopwatch]::new()
function Write-Step([string]$msg) {
    $_step_sw.Restart()
    Write-Host ""
    Write-Host "════════════════════════════════════════════════════════════════"
    Write-Host "  ▶  $msg"
    Write-Host "     $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    Write-Host "════════════════════════════════════════════════════════════════"
}
function Write-Done {
    $e = $_step_sw.Elapsed
    Write-Host "────────────────────────────────────────────────────────────────"
    Write-Host ("  ✔  Done  ({0}m {1:D2}s)" -f [int]$e.TotalMinutes, $e.Seconds)
    Write-Host "────────────────────────────────────────────────────────────────"
    Write-Host ""
}
# ---------------------------------------------------------------------------

$zstd_version = "1.5.7"
$ninja_version = "1.13.0"
$root_dir = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath(".")
$debug = ($build_type -eq "Debug")

# Detect architecture
$arch = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture

# Find and enter VS developer shell to set up MSVC environment for Ninja
$vsInstaller = if (Test-Path "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe") {
    "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
} else {
    "C:\Program Files\Microsoft Visual Studio\Installer\vswhere.exe"
}
$vsPath = & $vsInstaller -latest -property installationPath 2>$null
if (-not $vsPath) { throw "Visual Studio installation not found" }
$devShell = Join-Path $vsPath "Common7\Tools\Launch-VsDevShell.ps1"
$vsArch = switch ($arch) {
    'X64'   { 'amd64' }
    'Arm64' { 'arm64' }
    default { throw "Unsupported architecture: $arch" }
}
Write-Step "Setting up VS developer environment ($vsArch)"
& $devShell -Arch $vsArch -SkipAutomaticLocation
if (-not $?) { throw "Failed to set up VS developer environment" }
Write-Done

# Ensure Ninja is available for fast, parallel builds
Write-Step "Installing build tools (Ninja $ninja_version)"
uv tool install "ninja==$ninja_version"
if ($LASTEXITCODE -ne 0) { throw "Failed to install Ninja via uv" }
# Ensure uv-installed tools are on the PATH
$env:PATH = "$env:USERPROFILE\.local\bin;$env:PATH"
Write-Done

# Determine target
switch ($arch) {
    x64 {
        $host_target = "X86"
    }
    arm64 {
        $host_target = "AArch64"
    }
    default {
        Write-Error "Unsupported architecture on Windows: $arch. Only x64 and arm64 are supported."
        exit 1
    }
}

Write-Host "Building MLIR $llvm_project_ref into $install_prefix..."

# Build zstd
Write-Step "Building zstd v$zstd_version"
$zstd_install_prefix = Join-Path $root_dir "zstd-install"
if (Test-Path $zstd_install_prefix) { Remove-Item -Recurse -Force $zstd_install_prefix }
$zstd_dir = "zstd-$zstd_version"
if (Test-Path $zstd_dir) { Remove-Item -Recurse -Force $zstd_dir }

$zstd_tarball = "zstd-$zstd_version.tar.gz"
$zstd_checksum_file = "$zstd_tarball.sha256"
$zstd_url = "https://github.com/facebook/zstd/releases/download/v$zstd_version/$zstd_tarball"
$zstd_checksum_url = "https://github.com/facebook/zstd/releases/download/v$zstd_version/$zstd_checksum_file"

Write-Host "Downloading zstd from $zstd_url..."
Invoke-WebRequest -Uri $zstd_url -OutFile $zstd_tarball
Write-Host "Downloading zstd checksum from $zstd_checksum_url..."
Invoke-WebRequest -Uri $zstd_checksum_url -OutFile $zstd_checksum_file

Write-Host "Verifying checksum..."
$expected_hash_line = Get-Content $zstd_checksum_file | Select-Object -First 1
$expected_hash = ($expected_hash_line -split ' ')[0]
$actual_hash = (Get-FileHash $zstd_tarball -Algorithm SHA256).Hash

if ($actual_hash.ToLower() -ne $expected_hash.ToLower()) {
    throw "Checksum verification failed for $zstd_tarball. Expected: $expected_hash, Actual: $actual_hash"
}

Write-Host "Extracting zstd..."
tar -xzf $zstd_tarball
Remove-Item $zstd_tarball
Remove-Item $zstd_checksum_file

pushd (Join-Path $zstd_dir "build\cmake") > $null
$zstd_cmake_args = @(
    '-S', '.',
    '-B', 'build',
    '-G', 'Ninja',
    '-DCMAKE_BUILD_TYPE=Release',
    "-DCMAKE_INSTALL_PREFIX=$zstd_install_prefix",
    '-DZSTD_BUILD_STATIC=ON',
    '-DZSTD_BUILD_SHARED=OFF'
)
cmake @zstd_cmake_args
cmake --build build --target install --config Release
popd > $null
Remove-Item -Recurse -Force $zstd_dir
Write-Done

# Fetch LLVM project source archive
Write-Step "Downloading LLVM/MLIR source ($llvm_project_ref)"
$repo_dir = Join-Path $root_dir "llvm-project"
if (Test-Path $repo_dir) { Remove-Item -Recurse -Force $repo_dir }
New-Item -ItemType Directory -Path $repo_dir -Force | Out-Null
$archive_url = "https://github.com/llvm/llvm-project/archive/$llvm_project_ref.tar.gz"

# Download archive to temporary file
$temp_archive = Join-Path ([IO.Path]::GetTempPath()) ("llvm-project-$($llvm_project_ref).tar.gz")
Write-Host "Downloading $archive_url to $temp_archive..."
Invoke-WebRequest -Uri $archive_url -OutFile $temp_archive

# Extract archive
Write-Host "Extracting archive into $repo_dir..."
tar -xzf $temp_archive --strip-components=1 -C $repo_dir `
    --exclude='clang' `
    --exclude='lldb' `
    --exclude='polly' `
    --exclude='flang' `
    --exclude='openmp' `
    --exclude='libclc' `
    --exclude='libc' `
    --exclude='llvm/test' `
    --exclude='mlir/test' `
    --exclude='llvm/unittests' `
    --exclude='mlir/unittests'

# Clean up temporary file
Remove-Item -Path $temp_archive -Force -ErrorAction SilentlyContinue
Write-Done

# Change to repo directory
pushd $repo_dir > $null

# Build LLVM
try {
    $build_dir_stage1 = 'build_lld_release'
    $build_dir_stage2 = 'build_llvm'
    # Base cmake args shared by all stages (no build-type or build-dir yet).
    $cmake_args_base = @(
        '-S', 'llvm',
        "-DCMAKE_INSTALL_PREFIX=$install_prefix",
        # Only build the host target to speed up the build and reduce the size of the resulting binaries
        "-DLLVM_TARGETS_TO_BUILD=$host_target",
        # Use Ninja generator for better build parallelism and MSVC support
        '-G', 'Ninja',
        # No need to build examples, tests, or benchmarks
        '-DLLVM_BUILD_EXAMPLES=OFF',
        '-DLLVM_INCLUDE_EXAMPLES=OFF',
        '-DLLVM_BUILD_TESTS=OFF',
        '-DLLVM_INCLUDE_TESTS=OFF',
        '-DLLVM_INCLUDE_BENCHMARKS=OFF',
        # Enabling assertions is generally recommended to build LLVM
        '-DLLVM_ENABLE_ASSERTIONS=ON',
        # Disable LTO to avoid downstream consumers needing to have the same LTO configuration
        '-DLLVM_ENABLE_LTO=OFF',
        # Enable RTTI because we rely on it downstream
        '-DLLVM_ENABLE_RTTI=ON',
        # Disable components we don't need to speed up the build and reduce the size of the resulting binaries
        '-DLLVM_ENABLE_LIBXML2=OFF',
        '-DLLVM_ENABLE_LIBEDIT=OFF',
        '-DLLVM_ENABLE_LIBPFM=OFF',
        # Tools include FileCheck, not, and others that are useful to have in the install
        '-DLLVM_INSTALL_UTILS=ON',
        # We want an optimized TableGen build even during Debug builds
        '-DLLVM_OPTIMIZED_TABLEGEN=ON',
        # Suppress noisy MSVC warnings that heavily pollutes the log
        '-DLLVM_ENABLE_WARNINGS=OFF'
    )

    # Stage 1: build lld using the system linker, always in Release
    # mode. Building lld in Release (even for Debug toolchain builds) ensures the
    # linker itself is fast.
    $stage1_cmake_args = $cmake_args_base + @(
        '-B', $build_dir_stage1,
        '-DCMAKE_BUILD_TYPE=Release',
        '-DLLVM_ENABLE_PROJECTS=lld'
    )
    Write-Step "Stage 1 – CMake configure (lld only, Release, system linker)"
    cmake @stage1_cmake_args
    if ($LASTEXITCODE -ne 0) { throw "Stage 1 cmake configure failed" }
    Write-Done

    Write-Step "Stage 1 – Build lld (Release)"
    cmake --build $build_dir_stage1 --target lld --config Release
    if ($LASTEXITCODE -ne 0) { throw "Stage 1 lld build failed" }
    Write-Done

    # Make the stage-1 lld available on PATH so subsequent cmake invocations
    # pick up lld-link as the linker, which is far more memory-efficient
    # than MSVC link.exe.
    $env:PATH = "$(Join-Path $repo_dir $build_dir_stage1 bin);$env:PATH"

    # Stage 2: fresh build dir, lld-link as linker, build+install llvm+mlir only.
    $stage2_cmake_args = $cmake_args_base + @(
        '-B', $build_dir_stage2,
        "-DCMAKE_BUILD_TYPE=$build_type",
        '-DLLVM_ENABLE_PROJECTS=mlir',
        '-DLLVM_ENABLE_LLD=ON'
    )
    if ($debug) {
        $stage2_cmake_args += @(
            # Embed debug information in the object files to avoid having to distribute separate PDB files
            '-DCMAKE_MSVC_DEBUG_INFORMATION_FORMAT=Embedded',
            '-DCMAKE_POLICY_DEFAULT_CMP0141=NEW'
        )
    }
    Write-Step "Stage 2 – CMake configure ($build_type, lld-link linker)"
    cmake @stage2_cmake_args
    if ($LASTEXITCODE -ne 0) { throw "Stage 2 CMake configure failed" }
    Write-Done

    Write-Step "Stage 2 – Build and install LLVM/MLIR ($build_type)"
    cmake --build $build_dir_stage2 --target install --config $build_type
    if ($LASTEXITCODE -ne 0) { throw "Stage 2 install failed" }
    Write-Done
} finally {
    # Return to original directory
    popd > $null
    if (Test-Path $repo_dir) { Remove-Item -Recurse -Force $repo_dir }
}

# Define archive variables
$build_type_suffix = if ($debug) { "_debug" } else { "" }
$archive_name = "llvm-mlir_$($llvm_project_ref)_windows_$($arch)_$($host_target)$($build_type_suffix).tar.zst"
$archive_path = Join-Path $root_dir $archive_name

# Change to installation directory
pushd $install_prefix > $null

# Emit compressed archive (.tar.zst)
Write-Step "Creating archive: $archive_name"
try {
   $zstd_exe = Join-Path $zstd_install_prefix "bin\zstd.exe"
   tar -cf - . | & $zstd_exe -19 --long=30 --threads=0 -o $archive_path
   if ($LASTEXITCODE -ne 0) { throw "Archive creation failed" }
   Write-Done

   # Package zstd executable
   $zstd_archive_name = "zstd-$($zstd_version)_windows_$($arch)_$($host_target).zip"
   $zstd_archive_path = Join-Path $root_dir $zstd_archive_name
   Write-Step "Packaging zstd: $zstd_archive_name"
   Compress-Archive -Path (Join-Path $zstd_install_prefix "bin\zstd.exe") -DestinationPath $zstd_archive_path
   Write-Done
} catch {
    Write-Error "Failed to create archive: $($_.Exception.Message)"
    exit 1
} finally {
    # Return to original directory
    popd > $null
    if (Test-Path $zstd_install_prefix) { Remove-Item -Recurse -Force $zstd_install_prefix }
}

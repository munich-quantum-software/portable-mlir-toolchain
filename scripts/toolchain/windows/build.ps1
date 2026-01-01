# Copyright (c) 2025 Munich Quantum Software Company GmbH
# Copyright (c) 2025 Chair for Design Automation, TUM
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

# Usage: pwsh scripts/toolchain/windows/build.ps1 -llvm_project_ref <llvm-project ref> -install_prefix <installation directory> [-build_type <Release|Debug>]

param(
    [Parameter(Mandatory=$true)]
    [string]$llvm_project_ref,
    [Parameter(Mandatory=$true)]
    [string]$install_prefix,
    [ValidateSet("Release", "Debug")]
    [string]$build_type = "Release"
)

$ErrorActionPreference = "Stop"

$root_dir = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath(".")
$debug = ($build_type -eq "Debug")

# Detect architecture
$arch = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture

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
$zstd_install_prefix = Join-Path $root_dir "zstd-install"
if (Test-Path $zstd_install_prefix) { Remove-Item -Recurse -Force $zstd_install_prefix }
$zstd_dir = "zstd-1.5.7"
if (Test-Path $zstd_dir) { Remove-Item -Recurse -Force $zstd_dir }
$zstd_archive_url = "https://github.com/facebook/zstd/archive/refs/tags/v1.5.7.tar.gz"
$zstd_temp_archive = Join-Path ([IO.Path]::GetTempPath()) "zstd-v1.5.7.tar.gz"
Write-Host "Downloading zstd from $zstd_archive_url..."
Invoke-WebRequest -Uri $zstd_archive_url -OutFile $zstd_temp_archive
tar -xzf $zstd_temp_archive
Remove-Item $zstd_temp_archive

pushd (Join-Path $zstd_dir "build\cmake") > $null
$zstd_cmake_args = @(
    '-S', '.',
    '-B', 'build',
    '-G', 'Visual Studio 17 2022',
    "-DCMAKE_INSTALL_PREFIX=$zstd_install_prefix",
    '-DZSTD_BUILD_STATIC=ON',
    '-DZSTD_BUILD_SHARED=OFF'
)
cmake @zstd_cmake_args
cmake --build build --target install --config Release
popd > $null
Remove-Item -Recurse -Force $zstd_dir

# Fetch LLVM project source archive
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

# Change to repo directory
pushd $repo_dir > $null

# Build LLVM
try {
    $build_dir = 'build_llvm'
    $cmake_args = @(
        '-S', 'llvm',
        '-B', $build_dir,
        '-G', 'Visual Studio 17 2022',
        "-DCMAKE_BUILD_TYPE=$build_type",
        "-DCMAKE_INSTALL_PREFIX=$install_prefix",
        '-DLLVM_BUILD_EXAMPLES=OFF',
        '-DLLVM_BUILD_TESTS=OFF',
        '-DLLVM_ENABLE_ASSERTIONS=ON',
        '-DLLVM_ENABLE_ZSTD=ON',
        "-DCMAKE_PREFIX_PATH=$zstd_install_prefix",
        '-DLLVM_ENABLE_LTO=OFF',
        '-DLLVM_ENABLE_RTTI=ON',
        '-DLLVM_ENABLE_LIBXML2=OFF',
        '-DLLVM_ENABLE_TERMINFO=OFF',
        '-DLLVM_ENABLE_LIBEDIT=OFF',
        '-DLLVM_ENABLE_LIBPFM=OFF',
        '-DLLVM_INCLUDE_BENCHMARKS=OFF',
        '-DLLVM_INCLUDE_EXAMPLES=OFF',
        '-DLLVM_INCLUDE_TESTS=OFF',
        '-DLLVM_INSTALL_UTILS=ON',
        '-DLLVM_OPTIMIZED_TABLEGEN=ON',
        "-DLLVM_TARGETS_TO_BUILD=$host_target"
    )
    # Build lld first to use it as linker
    cmake @cmake_args '-DLLVM_ENABLE_PROJECTS=lld'
    if ($LASTEXITCODE -ne 0) { throw "LLVM LLD configuration failed" }
    cmake --build $build_dir --target lld --config $build_type
    if ($LASTEXITCODE -ne 0) { throw "LLVM LLD build failed" }
    # Add build_dir/bin to path so lld-link can be found
    $env:PATH = "$(Join-Path $repo_dir $build_dir)\bin;$env:PATH"
    cmake @cmake_args '-DLLVM_ENABLE_PROJECTS=mlir;lld' '-DLLVM_ENABLE_LLD=ON'
    if ($LASTEXITCODE -ne 0) { throw "LLVM configuration failed" }
    cmake --build $build_dir --target install --config $build_type
    if ($LASTEXITCODE -ne 0) { throw "LLVM build failed" }
} finally {
    # Return to original directory
    popd > $null
    if (Test-Path $repo_dir) { Remove-Item -Recurse -Force $repo_dir }
}

# Remove non-essential binaries from bin directory
$install_bin = Join-Path $install_prefix "bin"
if (Test-Path $install_bin) {
    $patterns = @(
        'clang*.exe',
        'llvm-bolt.exe',
        'perf2bolt.exe'
    )
    Get-ChildItem -Path $install_bin -Include $patterns -Recurse -File | Remove-Item -ErrorAction SilentlyContinue
}

# Remove non-essential directories
$dirs_to_remove = @("lib\clang", "share")
foreach ($dir in $dirs_to_remove) {
    $path = Join-Path $install_prefix $dir
    if (Test-Path $path) { Remove-Item -Path $path -Recurse -Force -ErrorAction SilentlyContinue }
}

# Define archive variables
$build_type_suffix = if ($debug) { "_debug" } else { "" }
$archive_name = "llvm-mlir_$($llvm_project_ref)_windows_$($arch)_$($host_target)$($build_type_suffix).tar.zst"
$archive_path = Join-Path $root_dir $archive_name

# Change to installation directory
pushd $install_prefix > $null

# Emit compressed archive (.tar.zst)
try {
   $zstd_exe = Join-Path $zstd_install_prefix "bin\zstd.exe"
   tar -cf - . | & $zstd_exe -19 --long=30 --threads=0 -o $archive_path
   if ($LASTEXITCODE -ne 0) { throw "Archive creation failed" }
} catch {
    Write-Error "Failed to create archive: $($_.Exception.Message)"
    exit 1
} finally {
    # Return to original directory
    popd > $null
    if (Test-Path $zstd_install_prefix) { Remove-Item -Recurse -Force $zstd_install_prefix }
}

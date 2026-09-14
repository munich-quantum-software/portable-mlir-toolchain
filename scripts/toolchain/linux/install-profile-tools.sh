#!/usr/bin/env bash
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

# Build only the profiling components omitted by manylinux's static Clang.
set -euo pipefail
: "${CC:?}" "${CXX:?}"
root=$(realpath -m "${1:?profiling work directory}")
[[ $($CC -dumpversion) == 22.1.8 ]] || { echo 'This recipe requires Clang 22.1.8' >&2; exit 1; }
commit=ca7933e47d3a3451d81e72ac174dcb5aa28b59d1
mkdir -p "$root/source"
curl --fail --location --retry 3 "https://github.com/llvm/llvm-project/archive/$commit.tar.gz" -o "$root/source.tar.gz"
printf '%s  %s\n' 9dd0aba32a0c2b9e8e808e9b67502cc977f22220f67268bbfd937fa07e5ee6ce "$root/source.tar.gz" > "$root/source.sha256"
sha256sum --check "$root/source.sha256"
tar -xf "$root/source.tar.gz" -C "$root/source" --strip-components=1
rm "$root/source.tar.gz"
triple=$($CC -dumpmachine)
cmake -S "$root/source/runtimes" -B "$root/runtime" -G Ninja \
  -DCMAKE_BUILD_TYPE=Release -DLLVM_ENABLE_RUNTIMES=compiler-rt \
  -DCMAKE_C_COMPILER_TARGET="$triple" -DCMAKE_CXX_COMPILER_TARGET="$triple" \
  -DCOMPILER_RT_BUILD_PROFILE=ON -DCOMPILER_RT_BUILD_BUILTINS=OFF \
  -DCOMPILER_RT_BUILD_SANITIZERS=OFF -DCOMPILER_RT_BUILD_XRAY=OFF \
  -DCOMPILER_RT_BUILD_LIBFUZZER=OFF -DCOMPILER_RT_BUILD_CTX_PROFILE=OFF \
  -DCOMPILER_RT_BUILD_MEMPROF=OFF -DCOMPILER_RT_BUILD_ORC=OFF \
  -DCOMPILER_RT_BUILD_SCUDO_STANDALONE=OFF -DCOMPILER_RT_INCLUDE_TESTS=OFF \
  -DCOMPILER_RT_DEFAULT_TARGET_ONLY=ON -DLLVM_ENABLE_PER_TARGET_RUNTIME_DIR=ON \
  -DCMAKE_CXX_SCAN_FOR_MODULES=OFF
cmake --build "$root/runtime" --target profile -j "${CMAKE_BUILD_PARALLEL_LEVEL:-4}"
runtime_dir=$($CC -print-resource-dir)/lib/$triple
mkdir -p "$runtime_dir"
cp "$root/runtime/compiler-rt/lib/$triple/libclang_rt.profile.a" "$runtime_dir/"
cmake -S "$root/source/llvm" -B "$root/tools" -G Ninja \
  -DCMAKE_BUILD_TYPE=Release -DLLVM_TARGETS_TO_BUILD=host -DLLVM_ENABLE_ASSERTIONS=OFF \
  -DLLVM_INCLUDE_TESTS=OFF -DLLVM_INCLUDE_EXAMPLES=OFF -DLLVM_INCLUDE_BENCHMARKS=OFF \
  -DLLVM_ENABLE_LIBXML2=OFF -DLLVM_ENABLE_LIBEDIT=OFF -DLLVM_ENABLE_LIBPFM=OFF \
  -DLLVM_ENABLE_ZSTD=OFF -DLLVM_ENABLE_WARNINGS=OFF -DLLVM_USE_LINKER=lld \
  -DLLVM_PARALLEL_LINK_JOBS=1 -DCMAKE_AR="${AR:?}" -DCMAKE_RANLIB="${RANLIB:?}"
cmake --build "$root/tools" --target llvm-profdata -j "${CMAKE_BUILD_PARALLEL_LEVEL:-4}"
printf 'int main() { return 0; }\n' > "$root/probe.cpp"
"$CXX" -fprofile-generate "$root/probe.cpp" -o "$root/generate"
LLVM_PROFILE_FILE="$root/probe.profraw" "$root/generate"
"$root/tools/bin/llvm-profdata" merge "$root/probe.profraw" -o "$root/probe.profdata"
"$CXX" -fprofile-use="$root/probe.profdata" -Werror "$root/probe.cpp" -o "$root/use"
"$root/use"
"$root/tools/bin/llvm-profdata" show --all-functions --counts "$root/probe.profdata"

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

# Keep the development libraries, headers, CMake packages and all MLIR tools.
set(LLVM_STRICT_DISTRIBUTIONS
    ON
    CACHE BOOL "")
set(components
    llvm-libraries
    llvm-headers
    cmake-exports
    mlir-libraries
    mlir-headers
    mlir-cmake-exports
    mlir-opt
    mlir-translate
    mlir-tblgen
    mlir-pdll
    mlir-src-sharder
    mlir-irdl-to-cpp
    mlir-linalg-ods-yaml-gen
    mlir-lsp-server
    mlir-pdll-lsp-server
    mlir-query
    mlir-reduce
    mlir-rewrite
    mlir-runner
    tblgen-lsp-server
    tblgen-to-irdl
    llvm-config
    llvm-tblgen
    llvm-as
    llvm-dis
    opt
    llc
    llvm-link
    FileCheck
    not
    count
    split-file
    llvm-ar
    llvm-ranlib
    llvm-lib
    llvm-dlltool
    llvm-nm
    llvm-objcopy
    llvm-strip
    llvm-objdump
    llvm-readobj
    llvm-readelf
    llvm-symbolizer
    llvm-addr2line
    llvm-profdata
    llvm-mc
    llvm-size
    llvm-dwarfdump)

if(CMAKE_HOST_SYSTEM_NAME STREQUAL "Linux")
  list(APPEND components LLVMgold)
elseif(CMAKE_HOST_APPLE)
  list(APPEND components llvm-install-name-tool llvm-bitcode-strip)
elseif(CMAKE_HOST_WIN32)
  list(APPEND components llvm-rc llvm-cvtres)
endif()

set(LLVM_DISTRIBUTION_COMPONENTS
    "${components}"
    CACHE STRING "Portable LLVM/MLIR SDK components")

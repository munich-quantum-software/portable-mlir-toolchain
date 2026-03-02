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

cmake_minimum_required(VERSION 3.24...4.2)
project(mlir_integration_test C CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(MLIR REQUIRED CONFIG)

message(STATUS "Found MLIR ${MLIR_PACKAGE_VERSION} in: ${MLIR_DIR}")
message(STATUS "Using LLVMConfig.cmake in: ${LLVM_DIR}")

list(APPEND CMAKE_MODULE_PATH "${MLIR_CMAKE_DIR}")
list(APPEND CMAKE_MODULE_PATH "${LLVM_CMAKE_DIR}")

include(AddLLVM)
include(AddMLIR)
include(HandleLLVMOptions)

include_directories(SYSTEM ${LLVM_INCLUDE_DIRS} ${MLIR_INCLUDE_DIRS})
link_directories(${LLVM_BUILD_LIBRARY_DIR})
add_definitions(${LLVM_DEFINITIONS})

add_llvm_executable(hello_mlir main.cpp)
target_link_libraries(hello_mlir PRIVATE
        MLIRIR
        MLIRSupport
        LLVMSupport
)
llvm_update_compile_flags(hello_mlir)

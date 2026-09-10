# Copyright (c) 2023 - 2026 Chair for Design Automation, TUM
# Copyright (c) 2025 - 2026 Munich Quantum Software Company GmbH
# All rights reserved.
#
# SPDX-License-Identifier: MIT
#
# Licensed under the MIT License

include("${CMAKE_SOURCE_DIR}/test/release/optimization.cmake")

function(mqt_study_adapter_rtti)
  if(APPLE)
    # The pinned Core revision overrides this adapter's LLVM_REQUIRES_RTTI. Restore its requested
    # setting so libc++ can match std::exception when rethrowing the driver's exception_ptr.
    target_compile_options(obj.MQTCompilerQDMIAdapter PRIVATE -frtti)
  endif()
endfunction()

if(CMAKE_SOURCE_DIR STREQUAL CMAKE_CURRENT_SOURCE_DIR)
  cmake_language(DEFER CALL mqt_study_adapter_rtti)
endif()

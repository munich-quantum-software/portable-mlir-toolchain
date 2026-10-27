#!/bin/bash
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

set -euo pipefail
linux=false macos=false windows=false
while IFS= read -r -d '' path; do
  case "$path" in
    scripts/toolchain/linux/*|.github/workflows/build-mlir-linux*) linux=true ;;
    scripts/toolchain/macos/*|.github/workflows/build-mlir-macos*) macos=true ;;
    scripts/toolchain/windows/*|.github/workflows/build-mlir-windows*) windows=true ;;
    scripts/*|tests/*|.github/workflows/*) linux=true macos=true windows=true ;;
  esac
done
printf 'run-linux=%s\nrun-macos=%s\nrun-windows=%s\n' "$linux" "$macos" "$windows"

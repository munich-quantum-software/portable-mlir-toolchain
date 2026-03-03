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

# ---------------------------------------------------------------------------
# Shared logging helpers
# ---------------------------------------------------------------------------
_STEP_START=0
log_step() {
  local msg="$*"
  _STEP_START=$(date +%s)
  echo ""
  echo "════════════════════════════════════════════════════════════════"
  echo "  ▶  ${msg}"
  echo "     $(date '+%Y-%m-%d %H:%M:%S %Z')"
  echo "════════════════════════════════════════════════════════════════"
}
log_done() {
  local elapsed=$(( $(date +%s) - _STEP_START ))
  echo "────────────────────────────────────────────────────────────────"
  echo "  ✔  Done  ($(printf '%dm %02ds' $((elapsed/60)) $((elapsed%60))))"
  echo "────────────────────────────────────────────────────────────────"
  echo ""
}
# ---------------------------------------------------------------------------

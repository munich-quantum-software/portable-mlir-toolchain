#!/usr/bin/env python3
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

"""Train and validate the SDK's optimizer, translator, and table generator."""

from __future__ import annotations

import subprocess
import sys
import tempfile
from pathlib import Path


def main() -> None:
    sdk = Path(sys.argv[1]).resolve()
    with tempfile.TemporaryDirectory() as directory:
        work = Path(directory)
        source = work / "train.mlir"
        source.write_text("module {\n" + "\n".join(
            f"func.func @f{i}(%n: index, %a: i64) -> i64 {{ "
            "%c0 = arith.constant 0 : index\n %c1 = arith.constant 1 : index\n"
            "%r = scf.for %i = %c0 to %n step %c1 iter_args(%s = %a) -> (i64) {\n"
            "%v = arith.addi %s, %a : i64\n scf.yield %v : i64 }\n return %r : i64 }"
            for i in range(32)
        ) + "\n}")
        result = subprocess.run([str(sdk / "bin" / "mlir-opt"), str(source), "--canonicalize", "--cse", "--convert-scf-to-cf"], capture_output=True, text=True, check=True)
        assert "cf.cond_br" in result.stdout and "@f31" in result.stdout
        source.write_text("module { llvm.func @answer() -> i64 { %v = llvm.mlir.constant(42 : i64) : i64\n llvm.return %v : i64 } }")
        result = subprocess.run([str(sdk / "bin" / "mlir-translate"), "--mlir-to-llvmir", str(source)], capture_output=True, text=True, check=True)
        assert "ret i64 42" in result.stdout
        result = subprocess.run([str(sdk / "bin" / "mlir-tblgen"), "-gen-op-decls", "-I", str(sdk / "include"), str(sdk / "include" / "mlir" / "Dialect" / "Arith" / "IR" / "ArithOps.td")], capture_output=True, text=True, check=True)
        assert "class AddIOp" in result.stdout


if __name__ == "__main__":
    main()

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

"""Invalid rebuild inputs must not modify an existing SDK."""

from pathlib import Path
import os
import subprocess
import sys
import tempfile
import unittest


class LibraryRebuildInputs(unittest.TestCase):
    def test_source_version_must_match_native_sdk(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source, sdk = root / "source", root / "sdk"
            (source / "llvm").mkdir(parents=True)
            (source / "llvm/CMakeLists.txt").touch()
            (source / "cmake/Modules").mkdir(parents=True)
            (source / "cmake/Modules/LLVMVersion.cmake").write_text(
                "set(LLVM_VERSION_MAJOR 23)\nset(LLVM_VERSION_MINOR 1)\nset(LLVM_VERSION_PATCH 1)\n")
            (sdk / "lib").mkdir(parents=True)
            (sdk / "lib/libLLVMCore.a").write_bytes(b"preserve")
            (root / "targets.json").write_text('["LLVMCore"]')
            (sdk / "bin").mkdir()
            for name in ["llvm-tblgen", "mlir-tblgen", "mlir-pdll", "mlir-src-sharder", "mlir-linalg-ods-yaml-gen"]:
                (sdk / "bin" / name).touch()
            compiler = root / "clang"
            compiler.write_text(f"#!{sys.executable}\nprint('clang version 22.1.8')\n")
            compiler.chmod(0o755)
            config = sdk / "bin/llvm-config"
            config.write_text(f"#!{sys.executable}\nprint('23.1.0')\n")
            config.chmod(0o755)
            result = subprocess.run(
                [sys.executable, str(Path(__file__).parents[1] / "scripts/toolchain/rebuild-libraries.py"),
                 "--source", str(source), "--base-sdk", str(sdk),
                 "--build", str(root / "build"), "--install", str(root / "install"), "--targets", str(root / "targets.json")],
                env=os.environ | {"CC": str(compiler), "CXX": str(compiler)}, capture_output=True, text=True, check=False)
            self.assertEqual(result.returncode, 2)
            self.assertIn("source version 23.1.1 differs from base SDK version 23.1.0", result.stderr)
            self.assertFalse((root / "build").exists())
            self.assertFalse((root / "install").exists())
            self.assertEqual((sdk / "lib/libLLVMCore.a").read_bytes(), b"preserve")

    def test_overlapping_installation_preserves_sdk(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            sdk = root / "sdk"
            sdk.mkdir()
            sentinel = sdk / "keep"
            sentinel.write_bytes(b"original SDK")
            command = [sys.executable, str(Path(__file__).parents[1] / "scripts/toolchain/rebuild-libraries.py"),
                       "--source", str(root / "source"),
                       "--base-sdk", str(sdk), "--build", str(root / "build"), "--install", str(sdk),
                       "--targets", str(root / "targets.json")]
            result = subprocess.run(command, capture_output=True, text=True, check=False)
            self.assertEqual(result.returncode, 2)
            self.assertIn("must not overlap", result.stderr)
            self.assertEqual(sentinel.read_bytes(), b"original SDK")
            self.assertFalse((root / "build").exists())



if __name__ == "__main__":
    unittest.main()

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

"""Invalid experimental inputs must not modify an existing SDK."""

from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


class LibraryVariantInputs(unittest.TestCase):
    def test_overlapping_installation_preserves_sdk(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            sdk = root / "sdk"
            sdk.mkdir()
            sentinel = sdk / "keep"
            sentinel.write_bytes(b"original SDK")
            command = [sys.executable, str(Path(__file__).parents[1] / "scripts/toolchain/build-library-variant.py"),
                       "--source", str(root / "source"), "--source-id", "a" * 40,
                       "--base-sdk", str(sdk), "--build", str(root / "build"), "--install", str(sdk),
                       "--lto", "OFF"]
            result = subprocess.run(command, capture_output=True, text=True, check=False)
            self.assertEqual(result.returncode, 2)
            self.assertIn("must not overlap", result.stderr)
            self.assertEqual(sentinel.read_bytes(), b"original SDK")
            self.assertFalse((root / "build").exists())

    def test_missing_profile_fails_before_building(self):
        result = subprocess.run([sys.executable, str(Path(__file__).parents[1] / "scripts/toolchain/build-library-variant.py"),
                                 "--source", "unused-source", "--source-id", "a" * 40,
                                 "--base-sdk", "unused-sdk", "--build", "unused-build", "--install", "unused-install",
                                 "--lto", "Full", "--phase", "use"], capture_output=True, text=True, check=False)
        self.assertEqual(result.returncode, 2)
        self.assertIn("--profile is required", result.stderr)


if __name__ == "__main__":
    unittest.main()

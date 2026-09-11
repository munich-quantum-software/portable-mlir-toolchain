#!/usr/bin/env python3
# Copyright (c) 2023 - 2026 Chair for Design Automation, TUM
# Copyright (c) 2025 - 2026 Munich Quantum Software Company GmbH
# All rights reserved.
#
# SPDX-License-Identifier: MIT
#
# Licensed under the MIT License

"""Give the pinned static musl linker an 8 MiB default worker stack."""

from __future__ import annotations

import argparse
import hashlib
import json
import struct
import sys
from pathlib import Path


def configure(binary: Path) -> dict:
    """Update only PT_GNU_STACK's size and return before/after identities.

    Returns:
        The original and configured hashes and default stack sizes.

    Raises:
        ValueError: The input is not a supported static ELF64 linker executable.
    """
    with binary.open("r+b") as stream:
        before = hashlib.file_digest(stream, "sha256").hexdigest()
        stream.seek(0)
        header = stream.read(64)
        if (
            len(header) != 64
            or header[:6] != b"\x7fELF\x02\x01"
            or struct.unpack_from("<H", header, 16)[0] != 2
            or struct.unpack_from("<H", header, 18)[0] not in {62, 183}
        ):
            msg = "expected a little-endian x86-64 or AArch64 ELF64 executable"
            raise ValueError(msg)
        offset = struct.unpack_from("<Q", header, 32)[0]
        width, count = struct.unpack_from("<HH", header, 54)
        if offset < 64 or width != 56 or offset + width * count > binary.stat().st_size:
            msg = "invalid ELF program header table"
            raise ValueError(msg)
        stack_headers = []
        for index in range(count):
            position = offset + width * index
            stream.seek(position)
            program = stream.read(width)
            kind = struct.unpack_from("<I", program)[0]
            if kind == 3:
                msg = "the linker must be statically linked"
                raise ValueError(msg)
            if kind == 0x6474E551:
                stack_headers.append((position + 40, struct.unpack_from("<Q", program, 40)[0]))
        if len(stack_headers) != 1:
            msg = "expected exactly one PT_GNU_STACK header"
            raise ValueError(msg)
        position, old_size = stack_headers[0]
        new_size = max(old_size, 8 * 1024 * 1024)
        stream.seek(position)
        stream.write(struct.pack("<Q", new_size))
        stream.flush()
        stream.seek(0)
        after = hashlib.file_digest(stream, "sha256").hexdigest()
    return {"original_sha256": before, "configured_sha256": after, "old_bytes": old_size, "new_bytes": new_size}


def main() -> None:
    """Configure the verified linker and print its provenance record."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("linker", type=Path)
    args = parser.parse_args()
    sys.stdout.write(json.dumps(configure(args.linker), indent=2) + "\n")


if __name__ == "__main__":
    main()

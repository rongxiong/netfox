#!/usr/bin/env python3
"""Keep every netfox version marker in sync.

    python3 scripts/update_version.py --version 2.0.6
    python3 scripts/update_version.py --check --version 2.0.6
    python3 scripts/update_version.py --check

The script refuses to write anything unless every marker it knows about is
present exactly the expected number of times and already agrees with the
version declared in netfox.podspec.
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

PODSPEC = "netfox.podspec"
SOURCE = "netfox/Core/NFX.swift"
README = "README.md"
PROJECT = "netfox.xcodeproj/project.pbxproj"
TESTS = "netfoxTests/NFXHelperTests.swift"

SEMVER = r"[0-9]+\.[0-9]+\.[0-9]+"
VERSION_RE = re.compile(rf"^{SEMVER}$")
PODSPEC_VERSION_RE = re.compile(
    rf'(?m)^([ \t]*s\.version[ \t]*=[ \t]*")({SEMVER})(")'
)


def fail(message: str) -> None:
    print(f"error: {message}", file=sys.stderr)
    raise SystemExit(1)


def read(root: Path, relative: str) -> str:
    path = root / relative
    if not path.is_file():
        fail(f"missing file: {relative}")
    # newline="" keeps the CRLF line endings used by this repository intact.
    with path.open("r", encoding="utf-8", newline="") as handle:
        return handle.read()


def write(root: Path, relative: str, text: str) -> None:
    path = root / relative
    with path.open("w", encoding="utf-8", newline="") as handle:
        handle.write(text)


def podspec_version(podspec_text: str) -> str:
    matches = PODSPEC_VERSION_RE.findall(podspec_text)
    if len(matches) != 1:
        fail("expected exactly one s.version entry in netfox.podspec")
    return matches[0][1]


def markers(old: str, new: str) -> list[tuple[str, re.Pattern[str], str, int]]:
    """(path, pattern, replacement, expected matches) for each marker."""
    version = re.escape(old)
    return [
        (PODSPEC,
         re.compile(rf'(?m)^([ \t]*s\.version[ \t]*=[ \t]*"){version}(")'),
         rf"\g<1>{new}\g<2>", 1),
        (SOURCE,
         re.compile(rf'(private let nfxSourceVersion = "){version}(")'),
         rf"\g<1>{new}\g<2>", 1),
        (README,
         re.compile(rf"(badge/version-){version}(-green\.svg)"),
         rf"\g<1>{new}\g<2>", 1),
        # Only the four framework targets carry the library version; the test
        # and demo targets keep their own 1.0 build numbers.
        (PROJECT,
         re.compile(rf"MARKETING_VERSION = {version};"),
         f"MARKETING_VERSION = {new};", 4),
        (TESTS,
         re.compile(rf'(#expect\(nfxVersion == "){version}("\))'),
         rf"\g<1>{new}\g<2>", 1),
    ]


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--version", help="version to write, e.g. 2.0.6")
    parser.add_argument("--check", action="store_true",
                        help="verify all markers are in sync without writing")
    parser.add_argument("--root", type=Path,
                        default=Path(__file__).resolve().parent.parent,
                        help="repository root (defaults to the script's parent)")
    args = parser.parse_args()

    if args.version and not VERSION_RE.fullmatch(args.version):
        fail(f"version must look like 2.0.6, got '{args.version}'")

    root = args.root.resolve()
    old = podspec_version(read(root, PODSPEC))

    if args.check:
        if args.version and old != args.version:
            fail(f"repository is at {old}, expected {args.version}")
        for relative, pattern, _, expected in markers(old, old):
            count = len(pattern.findall(read(root, relative)))
            if count != expected:
                fail(f"{relative}: expected {expected} marker(s) for {old}, found {count}")
        print(f"All version markers are in sync at {old}")
        return

    if not args.version:
        fail("--version is required unless --check is used")
    new = args.version

    # Validate every marker before touching a single file.
    updates: list[tuple[str, str]] = []
    for relative, pattern, replacement, expected in markers(old, new):
        updated, count = pattern.subn(replacement, read(root, relative))
        if count != expected:
            fail(f"{relative}: expected {expected} marker(s) for {old}, found {count}")
        updates.append((relative, updated))

    if new == old:
        print(f"Version is already {new}; nothing to do")
        return

    for relative, updated in updates:
        write(root, relative, updated)
    print(f"Updated {len(updates)} files: {old} -> {new}")


if __name__ == "__main__":
    main()

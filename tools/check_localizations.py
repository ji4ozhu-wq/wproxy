#!/usr/bin/env python3
"""Validate localization tables against the English source.

Usage:
    python3 tools/check_localizations.py            # check every *.lproj except en
    python3 tools/check_localizations.py ja ko      # check selected language codes

Checks per table:
- key sets are identical (missing / extra keys)
- printf placeholders (%@, %d, %lld, %f, %%) appear the same number of times
- duplicate keys
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RES = ROOT / "Wuji" / "Resources"
TABLES = ["Localizable", "Nodes", "Settings", "Routing", "Subscriptions", "InfoPlist"]
ENTRY = re.compile(r'"((?:[^"\\]|\\.)*)"\s*=\s*"((?:[^"\\]|\\.)*)"\s*;')
PLACEHOLDER = re.compile(r"%(?:@|d|ld|lld|f|\.\d+f|%)")


def parse(path: Path):
    entries, duplicates = {}, []
    for lineno, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        if not line.strip() or line.lstrip().startswith("/*") or line.lstrip().startswith("//"):
            continue
        match = ENTRY.search(line)
        if not match:
            continue
        key, value = match.group(1), match.group(2)
        if key in entries:
            duplicates.append((key, lineno))
        entries[key] = value
    return entries, duplicates


def placeholders(value: str):
    return sorted(PLACEHOLDER.findall(value))


def check(code: str) -> list:
    problems = []
    for table in TABLES:
        source_path = RES / "en.lproj" / f"{table}.strings"
        target_path = RES / f"{code}.lproj" / f"{table}.strings"
        if not source_path.exists():
            continue
        if not target_path.exists():
            problems.append(f"{code}/{table}: missing file")
            continue
        source, _ = parse(source_path)
        target, duplicates = parse(target_path)
        for key, lineno in duplicates:
            problems.append(f"{code}/{table}: duplicate key {key!r} (line {lineno})")
        for key in source:
            if key not in target:
                problems.append(f"{code}/{table}: missing key {key!r}")
            elif placeholders(source[key]) != placeholders(target[key]):
                problems.append(
                    f"{code}/{table}: placeholder mismatch {key!r}: "
                    f"en={placeholders(source[key])} {code}={placeholders(target[key])}")
        for key in target:
            if key not in source:
                problems.append(f"{code}/{table}: extra key {key!r}")
    return problems


def main():
    codes = sys.argv[1:] or sorted(
        p.name[:-6] for p in RES.glob("*.lproj") if p.name != "en.lproj")
    if not codes:
        print("No localized folders found besides en.lproj")
        return 1
    failed = 0
    for code in codes:
        problems = check(code)
        if problems:
            failed += 1
            print(f"FAIL {code} ({len(problems)} problems)")
            for problem in problems:
                print("  -", problem)
        else:
            print(f"OK   {code}")
    print()
    print(f"{len(codes) - failed}/{len(codes)} language(s) passed")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())

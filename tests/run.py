"""Offline checks: compile every Luau file, then run every tests/*.luau suite.

    python tests/run.py

Needs the Luau CLI (luau.exe and luau-compile.exe). It looks in $LUAU_DIR,
then in tools/luau/, then in %TEMP%/codex-luau-*.
"""

import glob
import os
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent


def find_luau():
    candidates = []
    if os.environ.get("LUAU_DIR"):
        candidates.append(pathlib.Path(os.environ["LUAU_DIR"]))
    candidates.append(ROOT / "tools" / "luau")
    temp = os.environ.get("TEMP") or os.environ.get("TMP")
    if temp:
        candidates += sorted(pathlib.Path(p) for p in glob.glob(os.path.join(temp, "codex-luau-*")))
    for folder in candidates:
        exe = folder / ("luau.exe" if os.name == "nt" else "luau")
        if exe.exists():
            return folder
    sys.exit("No Luau CLI found. Set LUAU_DIR to a folder holding luau and luau-compile.")


def main():
    luau_dir = find_luau()
    ext = ".exe" if os.name == "nt" else ""
    luau = str(luau_dir / f"luau{ext}")
    compiler = str(luau_dir / f"luau-compile{ext}")

    failures = 0

    sources = sorted(str(p) for p in (ROOT / "src").rglob("*.luau"))
    for path in sources:
        data = pathlib.Path(path).read_bytes()
        bad = sum(1 for b in data if b < 0x09)
        if bad:
            print(f"CONTROL BYTES: {path} has {bad} bytes under 0x09")
            failures += 1
        result = subprocess.run([compiler, "--null", path], capture_output=True, text=True)
        if result.returncode != 0:
            print(f"COMPILE FAIL: {path}\n{result.stdout}{result.stderr}")
            failures += 1
    print(f"compiled {len(sources)} files")

    for suite in sorted((ROOT / "tests").glob("*.luau")):
        result = subprocess.run([luau, str(suite)], capture_output=True, text=True, cwd=str(ROOT / "tests"))
        print(result.stdout.strip())
        if result.returncode != 0:
            print(result.stderr.strip())
            failures += 1

    if failures:
        sys.exit(f"{failures} problem(s)")
    print("all green")


if __name__ == "__main__":
    main()

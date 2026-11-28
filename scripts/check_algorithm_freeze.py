"""Check pinned Git blobs; warn about shared-path changes requiring review."""
import argparse
import json
import re
import subprocess
import sys

MANIFEST = "docs/algorithm-freeze.json"
GUARD_FILES = (MANIFEST, "scripts/check_algorithm_freeze.py",
               ".github/workflows/algorithm-freeze.yml", "AGENTS.md",
               "docs/ALGORITHM_FREEZE.md")

def git(*args):
    return subprocess.check_output(["git", *args])

def blobs(ref):
    result = {}
    for entry in git("ls-tree", "-rz", ref).split(b"\0"):
        if not entry:
            continue
        meta, path = entry.split(b"\t", 1)
        mode, kind, sha = meta.decode("ascii").split()
        if kind == "blob" and mode in ("100644", "100755"):
            result[path.decode("utf-8")] = sha
    return result

def check(manifest, actual):
    pins = manifest["protected_blobs"]
    if manifest["schema"] != 1 or not pins:
        raise ValueError("Invalid or empty freeze manifest")
    errors = []
    for path, expected in sorted(pins.items()):
        if not re.fullmatch(r"[0-9a-f]{40}", expected):
            raise ValueError("Invalid pinned Git blob: " + path)
        if actual.get(path) != expected:
            errors.append(path)
    return errors

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--base", help="PR base commit (trusted existing policy)")
    args = parser.parse_args()
    actual = blobs("HEAD")
    manifest = json.loads(git("show", "HEAD:" + MANIFEST))
    errors = check(manifest, actual)
    if args.base:
        base = blobs(args.base)
        if MANIFEST in base:
            for path in GUARD_FILES:
                if actual.get(path) != base.get(path):
                    errors.append(path + " (freeze policy change requires owner review)")
            trusted = json.loads(git("show", args.base + ":" + MANIFEST))
            errors.extend(check(trusted, actual))
        else:
            print("Bootstrap: no freeze manifest on base; verify owner-approved initial pins.")
        for path in manifest["shared_review_paths"]:
            if actual.get(path) != base.get(path):
                print("REVIEW REQUIRED: shared protected data path changed:", path)
    for error in sorted(set(errors)):
        print("FREEZE VIOLATION:", error, file=sys.stderr)
    if errors:
        return 1
    print("Pinned source and test blobs verified:", len(manifest["protected_blobs"]))
    return 0

if __name__ == "__main__":
    sys.exit(main())

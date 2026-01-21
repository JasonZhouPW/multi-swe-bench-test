#!/usr/bin/env python3
import os
import re


def fix_file(filepath):
    with open(filepath, "r") as f:
        content = f.read()

    # Remove .replace() calls that reference pr.base.sha
    # Pattern: .replace(..., pr.base.sha)
    pattern = r"\.replace\([^,]+,\s*pr\.base\.sha[^)]*\)"
    new_content = re.sub(pattern, "", content)

    if new_content != content:
        with open(filepath, "w") as f:
            f.write(new_content)
        print(f"Fixed: {filepath}")
    else:
        print(f"No changes: {filepath}")


def main():
    for root, dirs, files in os.walk("multi_swe_bench/harness/repos"):
        for file in files:
            if file.endswith(".py"):
                filepath = os.path.join(root, file)
                fix_file(filepath)


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
import json
import sys
import os
import tempfile

if __name__ == "__main__":
    data = {}
    for key in [
        "INSTANCE_ID",
        "REPO",
        "BASE_COMMIT",
        "PROBLEM_STATEMENT",
        "HINTS_TEXT",
        "CREATED_AT",
        "PATCH",
    ]:
        value = os.environ.get(key, "")
        temp_file = os.environ.get(f"{key}_FILE", "")
        if temp_file and os.path.exists(temp_file):
            with open(temp_file, "r") as f:
                value = f.read()
        data[key] = value

    output = {
        "instance_id": data["INSTANCE_ID"],
        "text": "",
        "repo": data["REPO"],
        "base_commit": data["BASE_COMMIT"],
        "problem_statement": data["PROBLEM_STATEMENT"],
        "hints_text": data["HINTS_TEXT"],
        "created_at": data["CREATED_AT"],
        "patch": data["PATCH"],
        "test_patch": "",
        "version": "",
        "FAIL_TO_PASS": "[]",
        "PASS_TO_PASS": "[]",
        "environment_setup_commit": "",
    }
    print(json.dumps(output, separators=(",", ":"), ensure_ascii=False), end="")

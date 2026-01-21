import json
import os
import sys


def process_file(filepath):
    results = []
    with open(filepath, "r") as f:
        for line_num, line in enumerate(f, 1):
            line = line.strip()
            if not line:
                continue
            try:
                record = json.loads(line)
                title = record.get("title", "").lower()
                body = record.get("body", "").lower() if record.get("body") else ""
                if "fix" in title or "fix" in body:
                    # Check if it really fixes bugs
                    original_title = record.get("title", "")
                    if (
                        original_title.lower().startswith("fix(")
                        or "fix" in original_title.lower()
                        or "bug" in original_title.lower()
                    ):
                        results.append(line)
            except json.JSONDecodeError:
                continue
    return results


if __name__ == "__main__":
    import glob

    files = glob.glob("go_ds/*.jsonl")
    all_results = []
    for file in files:
        results = process_file(file)
        all_results.extend(results)

    with open("final_ds/bf2.jsonl", "w") as out_f:
        for line in all_results[15:25]:
            out_f.write(line + "\n")

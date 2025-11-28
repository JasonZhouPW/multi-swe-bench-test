import json

FILE = "zeromicro__go-zero_filtered_prs.jsonl"

with open(FILE, "r", encoding="utf-8") as f:
    print("123")
    for i, line in enumerate(f, 1):
        line = line.strip()
        if not line:
            print(f"[Line {i}] ❗ Empty line")
            continue
        try:
            data = json.loads(line)
        except Exception as e:
            print(f"[Line {i}] ❌ JSON parse error:", e)
            print("Line content:", line)
            continue

        if "base" not in data:
            print(f"[Line {i}] ❗ Missing 'base' field")
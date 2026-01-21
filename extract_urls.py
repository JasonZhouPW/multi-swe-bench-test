import json


def extract_urls(input_file, output_file):
    with open(input_file, "r") as f:
        lines = f.readlines()

    urls = []
    for line in lines:
        line = line.strip()
        if not line:
            continue
        try:
            record = json.loads(line)
            org = record.get("org")
            repo = record.get("repo")
            number = record.get("number")
            if org and repo and number:
                url = f"https://github.com/{org}/{repo}/pull/{number}"
                urls.append(url)
        except json.JSONDecodeError:
            continue

    with open(output_file, "w") as f:
        for url in urls:
            f.write(url + "\n")


if __name__ == "__main__":
    extract_urls("final_ds/bf2.jsonl", "final_ds/bf2_urls.txt")

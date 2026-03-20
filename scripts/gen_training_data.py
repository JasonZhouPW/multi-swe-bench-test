import json
import re


def load_data(path):
    with open(path) as f:
        return [json.loads(l) for l in f]


def clean_problem_statement(text):
    """提取核心bug描述，去掉markdown噪声"""
    text = re.sub(r'- \[.\].*\n?', '', text)
    text = re.sub(r'\n{3,}', '\n\n', text)
    return text.strip()


def extract_patch_summary(patch):
    """从patch中提取修改的文件列表"""
    return re.findall(r'diff --git a/(.+?) b/', patch)


def to_sft(record):
    problem = clean_problem_statement(record['problem_statement'])
    patch = record['patch'].replace('<patch>', '').replace('</patch>', '').strip() if record.get('patch') else ''

    pr_text = record.get('text', '')
    title_match = re.search(r'Issue Title:\n(.+)', pr_text)
    title = title_match.group(1).strip() if title_match else ''

    user_content = f"You are an expert software engineer. Fix the following bug in the repository `{record['repo']}`.\n\n## Bug Report\n{problem}\n"
    if title:
        user_content = f"## Issue: {title}\n\n" + user_content

    assistant_content = f"I'll analyze the bug and provide the fix.\n\n```diff\n{patch}\n```"

    return {
        "messages": [
            {"role": "user", "content": user_content},
            {"role": "assistant", "content": assistant_content}
        ]
    }


def to_completion(record):
    problem = clean_problem_statement(record['problem_statement'])
    patch = record['patch'].replace('<patch>', '').replace('</patch>', '').strip() if record.get('patch') else ''

    prompt = f"<issue>\nRepository: {record['repo']}\nCommit: {record['base_commit']}\n\n{problem}\n</issue>\n\n<patch>"
    completion = f"\n{patch}\n</patch>"

    return {"prompt": prompt, "completion": completion}


def to_dpo(record):
    problem = clean_problem_statement(record['problem_statement'])
    patch = record['patch'].replace('<patch>', '').replace('</patch>', '').strip() if record.get('patch') else ''

    files = extract_patch_summary(record.get('patch', ''))
    rejected_patch = f"# Incomplete fix\n# Files affected: {', '.join(files)}\n# TODO: actual fix needed"

    prompt = f"Fix the bug described in this GitHub issue from repository `{record['repo']}`:\n\n{problem}\n\nProvide a unified diff patch that resolves the issue."

    return {
        "prompt": prompt,
        "chosen": f"Here is the complete fix:\n\n```diff\n{patch}\n```",
        "rejected": f"Here is a partial attempt:\n\n```diff\n{rejected_patch}\n```"
    }


FORMATS = {
    'sft':        ('train_sft.jsonl',        to_sft),
    'completion': ('train_completion.jsonl', to_completion),
    'dpo':        ('train_dpo.jsonl',        to_dpo),
}


def convert(input_path, output_dir, formats):
    data = load_data(input_path)
    print(f"加载 {len(data)} 条记录")

    for fmt in formats:
        filename, converter = FORMATS[fmt]
        records = [converter(r) for r in data]
        path = f"{output_dir}/{filename}"
        with open(path, 'w') as f:
            for r in records:
                f.write(json.dumps(r, ensure_ascii=False) + '\n')
        print(f"✅ 写出 {filename}：{len(records)} 条")


if __name__ == '__main__':
    import argparse
    import os

    parser = argparse.ArgumentParser(description='Convert PR data to training formats')
    parser.add_argument('input', help='Input JSONL file path')
    parser.add_argument('output_dir', help='Output directory path')
    parser.add_argument(
        '--formats', nargs='+',
        choices=['sft', 'completion', 'dpo'], default=['sft', 'completion', 'dpo'],
        metavar='FORMAT',
        help='Formats to generate: sft, completion, dpo (default: all)'
    )
    args = parser.parse_args()

    os.makedirs(args.output_dir, exist_ok=True)
    convert(args.input, args.output_dir, args.formats)
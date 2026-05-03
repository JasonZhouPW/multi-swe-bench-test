#!/usr/bin/env python3
"""
从 new_filtered_raw_datasets/<lang>/ 目录下的 jsonl 文件生成大模型微调数据。
支持三种格式: SFT, Completion, DPO
输出文件名为 *_*_from_raw.jsonl
"""
import argparse
import json
import os
import re
from pathlib import Path


def load_data(path):
    """加载 JSONL 数据"""
    with open(path) as f:
        return [json.loads(l) for l in f]


def clean_problem_statement(text):
    """清理问题描述，去除 markdown 噪声和 HTML 注释"""
    if not text:
        return ""
    # 移除 HTML 注释 <!-- ... -->
    text = re.sub(r'<!--[\s\S]*?-->', '', text)
    # 移除 Markdown checkbox 项 (e.g., "- [x] No AI tools were used")
    text = re.sub(r'- \[.\].*\n?', '', text)
    # 移除常见的模板占位符文本
    text = re.sub(r'Replace XXXXX with.*?(?=\n|$)', '', text, flags=re.IGNORECASE)
    text = re.sub(r'Or delete the line.*?(?=\n|$)', '', text, flags=re.IGNORECASE)
    text = re.sub(r'Please select exactly ONE.*?(?=\n|$)', '', text, flags=re.IGNORECASE)
    text = re.sub(r'\[REQUIRED\]', '', text)
    # 移除常见的 GitHub 模板噪声
    text = re.sub(r'(GitHub is reserved|Logstash Plugins are located|See https://.*community/security)', '', text)
    # 移除 "N/A" 行（仅包含 N/A 的行）
    text = re.sub(r'^\s*N/?A\s*$\n?', '', text, flags=re.MULTILINE)
    # 压缩多余空行
    text = re.sub(r'\n{3,}', '\n\n', text)
    return text.strip()


def clean_patch(patch):
    """清理 patch，修复字面 \\n 为真正换行"""
    if not patch:
        return ""
    # 将字面的 \n (反斜杠+n) 转为真正的换行
    patch = patch.replace(r'\n', '\n')
    return patch


def extract_patch_summary(patch):
    """从 patch 中提取修改的文件列表"""
    if not patch:
        return []
    return re.findall(r'diff --git a/(.+?) b/', patch)


def to_sft(record):
    """转换为 SFT 格式 (对话格式)"""
    problem = clean_problem_statement(record.get('body', ''))
    patch = clean_patch(record.get('fix_patch', ''))
    title = record.get('title', '')
    repo = f"{record.get('org', '')}/{record.get('repo', '')}"

    user_content = f"You are an expert software engineer. Fix the following bug in the repository `{repo}`.\n\n## Bug Report\n{problem}\n"
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
    """转换为 Completion 格式 (前缀补全)"""
    problem = clean_problem_statement(record.get('body', ''))
    patch = clean_patch(record.get('fix_patch', ''))
    repo = f"{record.get('org', '')}/{record.get('repo', '')}"
    base_commit = record.get('base_commit_hash', '')

    prompt = f"<issue>\nRepository: {repo}\nCommit: {base_commit}\n\n{problem}\n</issue>\n\n<patch>"
    completion = f"\n{patch}\n</patch>"

    return {"prompt": prompt, "completion": completion}


def to_dpo(record):
    """转换为 DPO 格式 (偏好对齐)"""
    problem = clean_problem_statement(record.get('body', ''))
    patch = clean_patch(record.get('fix_patch', ''))
    repo = f"{record.get('org', '')}/{record.get('repo', '')}"

    files = extract_patch_summary(patch)
    rejected_patch = f"# Incomplete fix\n# Files affected: {', '.join(files)}\n# TODO: actual fix needed"

    prompt = f"Fix the bug described in this GitHub issue from repository `{repo}`:\n\n{problem}\n\nProvide a unified diff patch that resolves the issue."

    return {
        "prompt": prompt,
        "chosen": f"Here is the complete fix:\n\n```diff\n{patch}\n```",
        "rejected": f"Here is a partial attempt:\n\n```diff\n{rejected_patch}\n```"
    }


def is_valid_record(record, min_body_len=20, min_patch_len=10):
    """验证记录是否有效"""
    body = record.get('body', '')
    patch = record.get('fix_patch', '')

    # 检查 body 是否为空或太短
    if len(body.strip()) < min_body_len:
        return False, "body太短"

    # 检查 patch 是否为空或太短
    if len(patch.strip()) < min_patch_len:
        return False, "patch太短"

    # 检查 patch 是否包含实际的 diff
    if 'diff --git' not in patch:
        return False, "patch中无diff"

    return True, "有效"


def filter_valid_records(data):
    """过滤出有效记录"""
    valid = []
    invalid_reasons = {}
    for record in data:
        is_valid, reason = is_valid_record(record)
        if is_valid:
            valid.append(record)
        else:
            invalid_reasons[reason] = invalid_reasons.get(reason, 0) + 1
    return valid, invalid_reasons


def deduplicate_records(records):
    """去除完全重复的记录"""
    seen = set()
    unique = []
    dup_count = 0
    for record in records:
        # 使用 JSON 序列化的字符串作为唯一标识
        record_key = json.dumps(record, sort_keys=True, ensure_ascii=False)
        if record_key not in seen:
            seen.add(record_key)
            unique.append(record)
        else:
            dup_count += 1
    return unique, dup_count


FORMATS = {
    'sft': ('train_sft_from_raw.jsonl', to_sft),
    'completion': ('train_completion_from_raw.jsonl', to_completion),
    'dpo': ('train_dpo_from_raw.jsonl', to_dpo),
}


def convert_file(input_path, output_dir, formats, skip_existing=True):
    """转换单个 raw dataset 文件"""
    filename = os.path.basename(input_path)
    # 从文件名提取 repo 名称: owner__repo_raw_dataset.jsonl -> owner__repo
    repo_name = filename.replace('_raw_dataset.jsonl', '')
    print(f"\n📂 处理: {filename}")

    data = load_data(input_path)
    print(f"   加载 {len(data)} 条记录")

    # 过滤无效记录
    valid_data, invalid_reasons = filter_valid_records(data)
    if invalid_reasons:
        print(f"   ⚠️  过滤掉 {len(data) - len(valid_data)} 条无效记录:")
        for reason, count in invalid_reasons.items():
            print(f"      - {reason}: {count}")

    if not valid_data:
        print(f"   ❌ 没有有效记录，跳过")
        return 0

    # 去重
    valid_data, dup_count = deduplicate_records(valid_data)
    if dup_count > 0:
        print(f"   ⚠️  去除 {dup_count} 条重复记录")

    repo_output_dir = os.path.join(output_dir, repo_name)
    os.makedirs(repo_output_dir, exist_ok=True)

    total_generated = 0
    for fmt in formats:
        filename_fmt, converter = FORMATS[fmt]
        output_path = os.path.join(repo_output_dir, filename_fmt)

        if skip_existing and os.path.exists(output_path):
            existing_count = sum(1 for _ in open(output_path))
            print(f"   ⏭️  跳过 {filename_fmt} (已存在 {existing_count} 条)")
            continue

        records = [converter(r) for r in valid_data]
        with open(output_path, 'w') as f:
            for r in records:
                f.write(json.dumps(r, ensure_ascii=False) + '\n')
        print(f"   ✅ 生成 {filename_fmt}: {len(records)} 条")
        total_generated += len(records)

    return total_generated


def main():
    parser = argparse.ArgumentParser(
        description='从 new_filtered_raw_datasets 目录生成微调数据',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
示例:
  # 处理所有语言，生成所有格式
  python scripts/gen_training_data_from_raw.py

  # 指定语言
  python scripts/gen_training_data_from_raw.py --lang Go

  # 指定输出目录
  python scripts/gen_training_data_from_raw.py --output-dir ./training_data_raw

  # 只生成特定格式
  python scripts/gen_training_data_from_raw.py --formats sft dpo
        """
    )
    parser.add_argument(
        '--input-dir',
        default='./new_filtered_raw_datasets',
        help='输入目录路径 (默认: ./new_filtered_raw_datasets)'
    )
    parser.add_argument(
        '--lang',
        help='指定语言目录 (如 Go, Python, JavaScript)'
    )
    parser.add_argument(
        '--output-dir',
        default='training_data_from_raw',
        help='输出目录路径 (默认: training_data_from_raw)'
    )
    parser.add_argument(
        '--formats',
        nargs='+',
        choices=['sft', 'completion', 'dpo'],
        default=['sft', 'completion', 'dpo'],
        metavar='FORMAT',
        help='生成格式: sft, completion, dpo (默认: 全部)'
    )
    parser.add_argument(
        '--no-skip',
        action='store_true',
        help='不跳过已存在的文件，重新生成'
    )
    parser.add_argument(
        '--merge',
        action='store_true',
        help='合并所有项目到一个文件 (train_*_from_raw.jsonl)'
    )

    args = parser.parse_args()

    input_dir = Path(args.input_dir)
    if not input_dir.exists():
        print(f"❌ 错误: 输入目录不存在: {input_dir}")
        return 1

    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    print(f"📁 输入目录: {input_dir}")
    print(f"📁 输出目录: {output_dir}")
    print(f"📦 生成格式: {', '.join(args.formats)}")

    # 确定要处理的语言目录
    if args.lang:
        lang_dirs = [input_dir / args.lang]
        if not lang_dirs[0].exists():
            print(f"❌ 错误: 语言目录不存在: {lang_dirs[0]}")
            return 1
    else:
        lang_dirs = [d for d in input_dir.iterdir() if d.is_dir() and not d.name.startswith('.')]

    print(f"🔍 找到 {len(lang_dirs)} 个语言目录")

    # 收集所有要处理的 jsonl 文件
    jsonl_files = []
    for lang_dir in lang_dirs:
        for jsonl_file in lang_dir.glob('*_raw_dataset.jsonl'):
            jsonl_files.append(jsonl_file)

    if not jsonl_files:
        print(f"❌ 错误: 没有找到 *_raw_dataset.jsonl 文件")
        return 1

    print(f"🔍 找到 {len(jsonl_files)} 个 raw dataset 文件")

    total_generated = 0
    for jsonl_file in jsonl_files:
        count = convert_file(
            str(jsonl_file),
            str(output_dir),
            args.formats,
            skip_existing=not args.no_skip
        )
        total_generated += count

    print(f"\n📊 总计生成: {total_generated} 条记录")

    # 合并所有项目到一个文件
    if args.merge:
        print("\n📦 合并所有项目到单一文件...")
        for fmt in args.formats:
            filename, _ = FORMATS[fmt]
            merged_path = output_dir / filename
            merged_count = 0

            with open(merged_path, 'w') as out_f:
                for repo_dir in sorted(output_dir.iterdir()):
                    if not repo_dir.is_dir() or repo_dir.name.startswith('.'):
                        continue
                    fmt_file = repo_dir / filename
                    if fmt_file.exists():
                        with open(fmt_file) as in_f:
                            for line in in_f:
                                out_f.write(line)
                                merged_count += 1

            print(f"   ✅ {filename}: {merged_count} 条")
        print("📦 合并完成!")

    print("\n" + "=" * 50)
    print("🎉 所有 raw dataset 处理完成!")
    print("=" * 50)

    return 0


if __name__ == '__main__':
    exit(main())

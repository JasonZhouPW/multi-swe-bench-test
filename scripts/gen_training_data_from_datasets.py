#!/usr/bin/env python3
"""
从 data/datasets 目录下的 jsonl 文件生成大模型微调数据。
支持三种格式: SFT, Completion, DPO
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
    'sft': ('train_sft.jsonl', to_sft),
    'completion': ('train_completion.jsonl', to_completion),
    'dpo': ('train_dpo.jsonl', to_dpo),
}


def convert_dataset(input_path, output_dir, formats, skip_existing=True):
    """转换单个数据集文件"""
    filename = os.path.basename(input_path)
    repo_name = filename.replace('_dataset.jsonl', '')
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
        # 去重
        records, dup_count = deduplicate_records(records)
        if dup_count > 0:
            print(f"   ⚠️  去除 {dup_count} 条重复记录 ({fmt})")

        with open(output_path, 'w') as f:
            for r in records:
                f.write(json.dumps(r, ensure_ascii=False) + '\n')
        print(f"   ✅ 生成 {filename_fmt}: {len(records)} 条")
        total_generated += len(records)

    return total_generated


def main():
    parser = argparse.ArgumentParser(
        description='从 datasets 目录生成微调数据',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
示例:
  # 处理所有数据集，生成所有格式
  python scripts/gen_training_data_from_datasets.py

  # 指定输出目录，处理指定格式
  python scripts/gen_training_data_from_datasets.py --output-dir ./training_data --formats sft dpo

  # 处理特定项目
  python scripts/gen_training_data_from_datasets.py --filter gohugoio__hugo ansible__ansible
        """
    )
    parser.add_argument(
        '--datasets-dir',
        default='data/datasets',
        help='数据集目录路径 (默认: data/datasets)'
    )
    parser.add_argument(
        '--output-dir',
        default='training_data',
        help='输出目录路径 (默认: training_data)'
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
        '--filter',
        nargs='*',
        metavar='REPO',
        help='只处理指定的项目 (如 gohugoio__hugo ansible__ansible)'
    )
    parser.add_argument(
        '--no-skip',
        action='store_true',
        help='不跳过已存在的文件，重新生成'
    )
    parser.add_argument(
        '--merge',
        action='store_true',
        help='合并所有项目到一个文件 (train_sft.jsonl, train_completion.jsonl, train_dpo.jsonl)'
    )

    args = parser.parse_args()

    datasets_dir = Path(args.datasets_dir)
    if not datasets_dir.exists():
        print(f"❌ 错误: 数据集目录不存在: {datasets_dir}")
        return 1

    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    print(f"📁 数据集目录: {datasets_dir}")
    print(f"📁 输出目录: {output_dir}")
    print(f"📦 生成格式: {', '.join(args.formats)}")

    jsonl_files = sorted(datasets_dir.glob('*_dataset.jsonl'))

    if args.filter:
        # 允许传入带或不带 _dataset 后缀的名称
        filter_set = set(args.filter)
        filter_with_dataset = set(f"{x}_dataset" if not x.endswith('_dataset') else x for x in args.filter)
        jsonl_files = [f for f in jsonl_files if f.stem in filter_set or f.stem in filter_with_dataset]
        if not jsonl_files:
            print(f"❌ 错误: 没有找到匹配的项目: {args.filter}")
            return 1

    if not jsonl_files:
        print(f"❌ 错误: 没有找到数据集文件")
        return 1

    print(f"🔍 找到 {len(jsonl_files)} 个数据集文件")

    total_sft = 0
    total_completion = 0
    total_dpo = 0

    for jsonl_file in jsonl_files:
        convert_dataset(
            str(jsonl_file),
            str(output_dir),
            args.formats,
            skip_existing=not args.no_skip
        )

        repo_name = jsonl_file.stem
        repo_output = output_dir / repo_name
        if repo_output.exists():
            for fmt in args.formats:
                fmt_file = repo_output / FORMATS[fmt][0]
                if fmt_file.exists():
                    count = sum(1 for _ in open(fmt_file))
                    if fmt == 'sft':
                        total_sft += count
                    elif fmt == 'completion':
                        total_completion += count
                    elif fmt == 'dpo':
                        total_dpo += count

    print("\n" + "=" * 50)
    print("🎉 所有数据集处理完成!")
    print(f"📊 统计:")
    if 'sft' in args.formats:
        print(f"   SFT: {total_sft} 条")
    if 'completion' in args.formats:
        print(f"   Completion: {total_completion} 条")
    if 'dpo' in args.formats:
        print(f"   DPO: {total_dpo} 条")
    print("=" * 50)

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

    return 0


if __name__ == '__main__':
    exit(main())

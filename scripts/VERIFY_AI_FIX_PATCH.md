# AI Fix-Patch Verification Guide

本指南说明如何验证 AI 生成的 fix-patch 是否有效。

## 目录结构

```
scripts/
├── verify_ai_fix_patch.py      # Python 验证脚本
├── verify_ai_fix_patch.sh      # Shell 包装脚本（推荐使用）
└── check_verification_report.py # 检查验证报告脚本
```

## 快速开始

### 方法 1：使用 Shell 脚本（推荐）

#### 从数据集 JSON 中读取 fix-patch

```bash
# 基本用法 - 自动检测 instance 目录
./scripts/verify_ai_fix_patch.sh \
    --dataset-json final_output/2026_03_20/OpenHands_OpenHands-13368/OpenHands_OpenHands-13368_dataset.json

# 指定输出目录
./scripts/verify_ai_fix_patch.sh \
    --dataset-json final_output/2026_03_20/OpenHands_OpenHands-13368/OpenHands_OpenHands-13368_dataset.json \
    --output-dir ./my_verify_output

# 查看所有选项
./scripts/verify_ai_fix_patch.sh --help
```

#### 使用外部 AI 生成的 fix-patch 文件

```bash
# 指定外部 fix-patch 文件（覆盖 JSON 中的 fix_patch）
./scripts/verify_ai_fix_patch.sh \
    --dataset-json final_output/2026_03_20/OpenHands_OpenHands-13368/OpenHands_OpenHands-13368_dataset.json \
    --fix-patch /path/to/ai-generated-fix.patch

# 同时指定 fix-patch 和 test-patch 文件
./scripts/verify_ai_fix_patch.sh \
    --dataset-json final_output/2026_03_20/OpenHands_OpenHands-13368/OpenHands_OpenHands-13368_dataset.json \
    --fix-patch /path/to/fix.patch \
    --test-patch /path/to/test.patch
```

### 方法 2：直接使用 Python 脚本

```bash
python3 scripts/verify_ai_fix_patch.py \
    --dataset-json final_output/2026_03_20/OpenHands_OpenHands-13368/OpenHands_OpenHands-13368_dataset.json \
    --output-dir ./verify_output \
    --instance-dir final_output/2026_03_20/OpenHands_OpenHands-13368/image
```

### 方法 3：检查现有验证报告

如果已经运行过验证（instance 目录下有 report.json），直接查看结果：

```bash
# 查看单个报告
python3 scripts/check_verification_report.py \
    final_output/2026_03_20/OpenHands_OpenHands-13368/instance/report.json

# 查看目录下所有报告
python3 scripts/check_verification_report.py \
    --dir final_output/2026_03_20/

# JSON 格式输出
python3 scripts/check_verification_report.py \
    --dir final_output/2026_03_20/ --json
```

## 验证流程

验证脚本执行以下步骤：

1. **加载数据集 JSON** - 读取包含 fix_patch 和 test_patch 的数据集文件
2. **准备 Patch 文件** - 将 test_patch 和 fix_patch 写入临时文件
3. **运行 Docker 容器** - 使用已有的 Docker 镜像执行三个阶段：
   - `run` - 基础测试（无 patch）
   - `test` - 应用 test_patch 后运行测试
   - `fix` - 应用 fix_patch 后运行测试
4. **解析测试结果** - 从日志中提取测试通过/失败信息
5. **生成验证报告** - 比较三个阶段的结果，判断 fix 是否有效

## 验证报告说明

### 报告结构

```json
{
  "org": "OpenHands",
  "repo": "OpenHands",
  "number": 13368,
  "valid": true,
  "error_msg": "",
  "run_result": {"passed": 0, "failed": 0, "skipped": 0, "tests": {...}},
  "test_patch_result": {"passed": 10, "failed": 5, "skipped": 2, "tests": {...}},
  "fix_patch_result": {"passed": 15, "failed": 0, "skipped": 0, "tests": {...}},
  "f2p_tests": {...},  // FAIL → PASS 的测试
  "p2p_tests": {...}   // PASS → PASS 的测试
}
```

### 有效性判断

一个 fix-patch 被认为是**有效**的条件：

- ✅ 至少有一个测试从 FAIL 变为 PASS（f2p_tests）
- ✅ 没有回归测试（PASS → FAIL）
- ✅ 测试执行过程中没有错误

### 输出目录

验证完成后，输出目录包含：

```
verify_output/
├── test.patch                  # test_patch 内容
├── fix.patch                   # fix_patch 内容
├── run.log                     # 基础测试日志
├── test-patch-run.log          # test_patch 测试日志
├── fix-patch-run.log           # fix_patch 测试日志
└── report.json                 # 验证报告
```

## 常见问题

### Docker 镜像不存在

```
Error: No such image: envagent/openhands_m_openhands:pr-13368
```

确保 `organize_datasets.sh` 脚本已经运行并生成了 image 目录，然后需要先构建 Docker 镜像。

### 脚本找不到 instance 目录

使用 `--instance-dir` 参数明确指定：

```bash
./scripts/verify_ai_fix_patch.sh \
    --dataset-json final_output/2026_03_20/OpenHands_OpenHands-13368/OpenHands_OpenHands-13368_dataset.json \
    --instance-dir final_output/2026_03_20/OpenHands_OpenHands-13368/image
```

### 验证超时

默认超时时间为 10 分钟，对于大型项目可能不够。修改 `verify_ai_fix_patch.py` 中的超时设置：

```python
result = subprocess.run(
    docker_cmd,
    capture_output=True,
    text=True,
    timeout=600  # 修改为更大的值，如 1800 (30 分钟)
)
```

## 批量验证

当有多个 AI 生成的 fix-patch 需要验证时，使用批量脚本：

### 使用批量验证脚本

```bash
# 基本用法
./scripts/batch_verify.sh \
    --dataset-dir datasets/ \
    --patch-dir ai_patches/

# 并行处理（4 个并行任务）
./scripts/batch_verify.sh \
    --dataset-dir datasets/ \
    --patch-dir ai_patches/ \
    --parallel 4

# 预先查看（dry run）
./scripts/batch_verify.sh \
    --dataset-dir datasets/ \
    --patch-dir ai_patches/ \
    --dry-run
```

### 文件命名约定

批量脚本通过文件名匹配 dataset JSON 和 patch 文件：

| Dataset JSON | Patch 文件 |
|-------------|-----------|
| `OpenHands_OpenHands-13368_dataset.json` | `OpenHands_OpenHands-13368.patch` |
| `ansible_ansible-86642_dataset.json` | `ansible_ansible-86642.diff` |

**规则**: patch 文件名 = dataset JSON 文件名去掉 `_dataset.json`，加上 `.patch` 或 `.diff`

### 批量验证输出

```
verify_output/
├── 20260320_170000/           # 时间戳命名的输出目录
│   ├── batch_summary.txt      # 文本摘要
│   ├── batch_summary.json     # JSON 摘要
│   ├── OpenHands_OpenHands-13368/  # 单个验证结果
│   │   ├── verify.log
│   │   ├── report.json
│   │   └── ...
│   └── ansible_ansible-86642/
│       └── ...
```

### 批量验证摘要

运行完成后会显示摘要：

```
=========================================
📊 BATCH VERIFICATION SUMMARY
=========================================
Total processed: 10
✅ Passed:  7
❌ Failed:  2
⚠️  Errors:  1
=========================================
```
验证多个数据集：

```bash
#!/bin/bash
for json in final_output/2026_03_20/*/*_dataset.json; do
    ./scripts/verify_ai_fix_patch.sh --dataset-json "$json"
done
```

查看批量验证结果：

```bash
python3 scripts/check_verification_report.py --dir verify_output/
```

## 集成到 CI/CD

可以在 CI/CD 流水线中使用验证脚本：

```yaml
# GitHub Actions 示例
- name: Verify AI Fix Patches
  run: |
    for json in final_output/*/*_dataset.json; do
      ./scripts/verify_ai_fix_patch.sh --dataset-json "$json"
    done

- name: Check Results
  run: |
    python3 scripts/check_verification_report.py --dir verify_output/
```

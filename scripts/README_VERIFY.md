# AI Fix-Patch 验证工具

## 概述

本工具集用于验证 AI 生成的 fix-patch 是否能有效修复软件问题。

## 脚本说明

| 脚本 | 用途 | 场景 |
|------|------|------|
| `verify_ai_fix_patch.sh` | 单个验证 | 验证单个 AI 生成的 fix-patch |
| `batch_verify.sh` | 批量验证 | 同时验证多个 AI 生成的 fix-patch |
| `check_verification_report.py` | 查看报告 | 检查已生成的验证报告 |

## 快速开始

### 单个验证

```bash
# 使用外部 AI 生成的 fix-patch 文件
./scripts/verify_ai_fix_patch.sh \
    --dataset-json datasets/OpenHands_OpenHands-13368_dataset.json \
    --fix-patch ai_patches/OpenHands_OpenHands-13368.patch
```

### 批量验证

```bash
# 批量验证目录下的所有 patch
./scripts/batch_verify.sh \
    --dataset-dir datasets/ \
    --patch-dir ai_patches/

# 并行处理加速
./scripts/batch_verify.sh \
    --dataset-dir datasets/ \
    --patch-dir ai_patches/ \
    --parallel 4
```

### 查看结果

```bash
# 查看单个报告
python3 scripts/check_verification_report.py \
    verify_output/20260320_170000/OpenHands_OpenHands-13368/report.json

# 批量查看
python3 scripts/check_verification_report.py \
    --dir verify_output/20260320_170000/
```

## 文件命名约定

批量验证要求文件命名匹配：

- Dataset JSON: `<org>_<repo>-<pr_number>_dataset.json`
- Patch 文件：`<org>_<repo>-<pr_number>.patch` (或 `.diff`)

示例：
- `OpenHands_OpenHands-13368_dataset.json` ↔ `OpenHands_OpenHands-13368.patch`

## 输出结构

```
verify_output/
└── 20260320_170000/          # 时间戳目录
    ├── batch_summary.txt     # 批量摘要
    ├── batch_summary.json    # JSON 摘要
    └── <org>_<repo>-<pr>/    # 单个验证结果
        ├── verify.log
        ├── report.json
        ├── fix.patch
        └── ...
```

## 验证判断标准

| 结果 | 说明 |
|------|------|
| ✅ PASS | fix-patch 有效，有测试从 FAIL→PASS |
| ❌ FAIL | fix-patch 无效，无修复或有回归 |
| ⚠️ ERROR | 执行错误，无法完成验证 |

## 详细文档

查看 `VERIFY_AI_FIX_PATCH.md` 获取完整使用指南。

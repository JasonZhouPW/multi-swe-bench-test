# AI Fix-Patch 验证逻辑

## 验证规则

```
✅ VALID:   fix_passed >= test_passed  (AI 修复通过数 ≥ 原始通过数)
❌ INVALID: fix_passed < test_passed   (AI 修复通过数 < 原始通过数)
```

## 验证流程

1. **运行原始测试** - 只应用 test_patch → 记录通过数量 `test_passed`
2. **运行 AI 修复** - 应用 test_patch + fix_patch → 记录通过数量 `fix_passed`
3. **比较判断** - `fix_passed >= test_passed` 则为 **VALID**

## 使用示例

### 单个验证

```bash
./scripts/verify_ai_fix_patch.sh \
    --dataset-json datasets/OpenHands_OpenHands-13368_dataset.json \
    --fix-patch ai_patches/OpenHands_OpenHands-13368.patch
```

输出示例：
```
============================================================
📋 VERIFICATION SUMMARY
============================================================
Repository: OpenHands/OpenHands
PR Number: 13368
Valid: ✅ YES

📊 Test Results:
  Test Patch (original): 45 passed, 5 failed, 2 skipped
  Fix Patch (AI):        47 passed, 3 failed, 2 skipped

🔍 Comparison:
  ✅ AI fix-patch passed 2 MORE tests than original

  Message: Fix patch passed 2 more tests than original
============================================================
```

### 批量验证

```bash
./scripts/batch_verify.sh \
    --dataset-dir datasets/ \
    --patch-dir ai_patches/ \
    --parallel 4
```

输出示例：
```
=========================================
📊 BATCH VERIFICATION SUMMARY
=========================================
Total processed: 20
✅ Valid:   15 (fix >= original)
❌ Invalid: 4  (fix < original)
⚠️  Errors:  1
=========================================
```

## 报告格式

```json
{
  "org": "OpenHands",
  "repo": "OpenHands",
  "number": 13368,
  "valid": true,
  "message": "Fix patch passed 2 more tests than original",
  "comparison": {
    "test_passed": 45,
    "fix_passed": 47
  },
  "test_patch_result": {"passed": 45, "failed": 5, "skipped": 2},
  "fix_patch_result": {"passed": 47, "failed": 3, "skipped": 2}
}
```

## 退出码

| 退出码 | 含义 |
|-------|------|
| 0 | VALID - AI fix 通过数 ≥ 原始通过数 |
| 1 | INVALID - AI fix 通过数 < 原始通过数 |
| 2+ | ERROR - 执行错误 |

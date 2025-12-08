# Multi-SWE-Bench 全流程使用指南

## 概述

Multi-SWE-Bench
是一个用于自动评测与训练多智能体代码修复系统的框架。本指南涵盖从原始 PR
数据收集到最终评测的完整四步流程，包括：

1. 生成 Raw Dataset
2. 注册仓库、构建 Docker 环境
3. 基于 Raw Dataset 生成 Patch
4. 构建 Dataset 并执行 run_evaluation

------------------------------------------------------------------------

## 步骤一：生成 Raw Dataset

### 使用脚本

- `gen_raw_dataset.sh`
- `collect_raw_dataset.sh`

### 作用

这两个脚本从 GitHub PR 自动收集信息，包括： - PR 基本信息（repo、PR
id） - base / head commit - changed files - patch 内容 -
编程语言（用于生成对应 repo 环境） - metadata（作者、提交时间、标签等）

生成结果示例：

    repo: owner/name  
    language: Python  
    pr_number: 1234  
    base_commit: abcdef  
    head_commit: 123456  
    patch: ...

输出文件位于：

    data/raw_datasets/<repo>__raw_dataset.jsonl

------------------------------------------------------------------------

## 步骤二：统一仓库脚本，生成 repo/docker 环境

### 使用脚本

- `unify_repo_scripts.sh`

### 作用

从步骤一生成的 raw_dataset 中识别编程语言（如 Go / Python /
JS），然后：

1. 克隆对应版本的仓库代码
2. 注入 prepare.sh、Dockerfile
3. 生成 multi-swe-bench 的 repo 目录结构

输出目录示例：

    data/repos/<repo_name>/
        Dockerfile
        prepare.sh
        source_code/

------------------------------------------------------------------------

## 步骤三：基于 Raw Dataset 生成 AI Patch

### 说明

依据 Raw Dataset 的 PR 信息（包括 commit diff、changed
files、上下文），使用大模型生成自动修复 Patch。

建议流程： 1. 调用模型读取 Raw Dataset 中的 diff 2. 生成 patch 建议 3.
写入：

    data/patches/<repo>__patch.jsonl

示例 patch：

    {
      "repo": "pandas-dev/pandas",
      "pr_number": 54321,
      "patch": "diff --git ..."
    }

------------------------------------------------------------------------

## 步骤四：完整执行 Pipeline（构建 dataset + 评测）

### 使用脚本

- `run_full_pipeline.sh`

### 作用

根据 Raw Dataset 执行两个关键流程：

#### 1. build_dataset

由 multi_swe_bench/harness/build_dataset 完成，将 raw_dataset → dataset\
包括： - 创建 container - 应用 prepare.sh - 对仓库执行回滚/应用 patch
并检查能否复现问题 - 生产最终 dataset JSONL

输出：

    data/output/<repo>_dataset.jsonl

#### 2. run_evaluation

将步骤三生成的模型 patch 与步骤四的 dataset 输入框架进行自动评测。

输出：

    evaluation_results/<benchmark>/<repo>.json

------------------------------------------------------------------------

# 总结流程图

    ┌──────────────────────┐
    │ Step 1: Raw Dataset  │
    └──────────┬───────────┘
               ▼
    ┌──────────────────────┐
    │ Step 2: Docker/Repo  │
    └──────────┬───────────┘
               ▼
    ┌──────────────────────┐
    │ Step 3: Gen Patch    │
    └──────────┬───────────┘
               ▼
    ┌──────────────────────┐
    │ Step 4: Full Pipeline│
    │ build_dataset + eval │
    └──────────────────────┘

------------------------------------------------------------------------



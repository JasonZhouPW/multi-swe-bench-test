# Multi-SWE-Bench 全流程执行清单

下面为经过整理与验证的“正确、可复现”的全流程（四步），包含必要前置条件、每步命令、输出校验与常见排查建议。

---

## 前置条件 🔧

- 安装 Docker（并确保 Docker 可运行）
- Python 环境：建议执行 `make install`（或 `make install-dev`）以安装依赖：
  - `make install` → 安装 package
  - `make install-dev` → 安装开发依赖（可选）
- 可选：预下载镜像（加速评测）：
  - macOS / Linux: `bash scripts/download_images.sh scripts/images_mini.txt`
- 若需要从 GitHub 抓取数据：准备 GitHub token（用于 `gen_raw_dataset.sh` / collect 脚本）

---

## 全流程顺序（按序执行） 📋

> [!TIP]
> **新功能**：现在可以使用根目录下的 `./entry.sh` 脚本通过交互式菜单快速执行以下常用步骤。

1) **Step1 — 生成 Raw Dataset（必须最先执行）**
- 目的：从 GitHub 拉取 PR 并整合为 `*_raw_dataset.jsonl`
- 主要脚本：
  - 生成 PR 数据：
    - 传统脚本：`./scripts/gen_raw_dataset.sh <owner/repo>`
    - GraphQL 脚本 (更稳定/高效)：`./scripts/new_gen_raw_dataset_graphql.sh -l <lang> -s <min_stars>`
    - 批量生成：`./data_pipeline/gen_all_raw_datasets_new.sh`
  - 补全并分类：`./scripts/collect_raw_dataset.sh`
- 输出：`data/raw_datasets/<owner__repo>_raw_dataset.jsonl`
- 校验：确认 `data/raw_datasets` 下存在 `*_raw_dataset.jsonl`

1.1) **Step1.1 — 数据过滤与精炼（可选）**
- 目的：筛选特定类别（如 Bug Fix, Performance）或限制 patch 大小
- 脚本：`./scripts/filter_raw_dataset.sh -i <input_dir> -o <output_dir> [options]`
- 特色：
    - 支持交互式菜单（不带参数运行）。
    - 预设模式：New Feature, Bug Fix, Edge Case, Performance。
    - Patch 过滤：使用 `-p <bytes>` 指定最小补丁大小（仅计算代码部分）。


2) **Step2 — 生成 Repo Docker 与脚本并构建 dataset（可与 Step3 并行）**
- 目的：为每 repo 生成 `Dockerfile`、`prepare.sh`、`test.sh`，并生成 `*_dataset.jsonl`
- 主要脚本：
  - 自动生成仓库脚本并构建 dataset（单文件或目录）：
    `./scripts/unify_repo_scripts.sh data/raw_datasets/*_raw_dataset.jsonl`
  - 单文件构建（替代方式）：`./data_pipeline/build_dataset.sh <raw_dataset.jsonl>`
- 输出：`data/repos/<owner__repo>/...` 以及 `data/datasets/<base>_dataset.jsonl`
- 校验：确认 `data/datasets/<base>_dataset.jsonl` 存在


3) **Step 3 — 生成 Patch（可与 Step2 并行）**
- 目的：使用 LLM 或 Agent 工具 from raw dataset 提取并生成最终 patches JSONL
- 脚本 A (SWE-Agent)：`./scripts/run_patch.sh data/raw_datasets/<base>_raw_dataset.jsonl`
  - 内部流程：`run_extract_raw_dataset.sh` → `run_sweagent_for_jsonl.sh` → `gen_patches_jsonl.sh`
- 脚本 B (Massgen)：`./scripts/run_massgen_for_jsonl.sh <work-dir> <jsonl_path>`
  - 目的：利用 `massgen` 批量生成 patch
- 输出：`data/patches/<base>_patch.jsonl` 或指定目录下的 `.patch` 文件
- 校验：建议执行 Patch Quality Check（见下文）

4) **Step 4 — Patch Quality Check（质量校验，可选但建议）**
- 目的：在执行完整 Evaluation 前，先对生成的 patch 进行静态扫描与评分
- 脚本：
  - 扫描文件：`./scripts/semgrep_scan.sh <patch_file> <output_json>`
  - 评分分析：`./scripts/analyze_patch.sh <semgrep_result.json>`
- 输出：Semgrep 扫描结果与质量评分报告（S/A/B/C/F 级）

5) **Step 5 — 执行 Evaluation（必须等待 Step2 + Step3 完成）**
- 脚本：`./scripts/run_full_pipeline.sh data/raw_datasets/<base>_raw_dataset.jsonl`
  - 要求：`data/patches/<base>_patch.jsonl` 与 `data/datasets/<base>_dataset.jsonl` 已存在
  - 内部调用：`./data_pipeline/run_evaluation.sh` → Python: `python -m multi_swe_bench.harness.run_evaluation --config <config.json>`
- 输出：`data/output/`（中间）与 `data/final_output/`（最终报告）
- 校验：查看 `final_report.json` 与 `data/final_output/` 中的报告与日志

6) **Step 6 — 训练数据提取（用于模型微调）**
- 目的：将处理好的数据集转换为 LLM 训练格式（JSON）
- 脚本：`./scripts/extract_training_data.sh <input_path> <output_file>`
- 功能：支持处理单个文件或整个目录，自动合并并进行双向转换（PR->Patch, Patch->PR）。

---

## 并行策略与快速运行建议 ⚡

- **Step2 与 Step3 可并行**（两者仅依赖 Step1）：

```
./scripts/unify_repo_scripts.sh data/raw_datasets/*_raw_dataset.jsonl &   # Step2
./scripts/run_patch.sh data/raw_datasets/*_raw_dataset.jsonl &           # Step3
wait
./scripts/run_full_pipeline.sh data/raw_datasets/*_raw_dataset.jsonl      # Step4
```

- 若处理多个 raw_dataset，可使用 `./scripts/run_all_pipeline.sh`（会遍历 `data/raw_datasets/*_raw_dataset.jsonl` 并依次调用 `run_full_pipeline.sh`）

---

## 常见错误 & 解决要点 ⚠️

- **找不到 `*_raw_dataset.jsonl`** → 检查 `./scripts/gen_raw_dataset.sh` / `./scripts/collect_raw_dataset.sh` 是否成功执行并写入
- **`patch JSONL not found` 或 `dataset JSONL not found`** → 按顺序先生成 Step2/Step3 的产物
- **Docker build failed (code 127)** → 检查 `prepare.sh` 权限与 Dockerfile 是否安装 `bash`; 建议在 Dockerfile 中添加：
  ```dockerfile
  RUN chmod +x /home/prepare.sh
  RUN apk add --no-cache bash  # 或 apt-get install -y bash
  ```
- **JSONDecodeError / Invalid control character** → 使用 `jq -c` 清洗/校验 JSONL

---

## 常用快速命令汇总 🧭

- Step1:
  - `./scripts/gen_raw_dataset.sh owner/repo`
  - `./scripts/new_gen_raw_dataset_graphql.sh -l Python -s 10000`
  - 批量生成 (GraphQL): `./data_pipeline/gen_all_raw_datasets_new.sh`
  - `./scripts/collect_raw_dataset.sh`
  - 数据过滤: `./scripts/filter_raw_dataset.sh -i ./raw_ds -o ./filtered -p 1024`
  - 生成训练数据: `./scripts/extract_training_data.sh data/datasets output.json`
- 交互式入口:
  - `bash entry.sh`
- Step2:
  - `./scripts/unify_repo_scripts.sh data/raw_datasets/*_raw_dataset.jsonl`
  - 或单文件：`./data_pipeline/build_dataset.sh <raw_dataset.jsonl>`
  - RepoLaunch 准备：`./scripts/gen_repolaunch.sh <org> <repo> <instance_id> <language>`
- Step3:
  - SWE-Agent: `./scripts/run_patch.sh data/raw_datasets/<base>_raw_dataset.jsonl`
  - Massgen: `./scripts/run_massgen_for_jsonl.sh <work-dir> <jsonl_path>`
- Step4 (Quality Check):
  - `./scripts/semgrep_scan.sh <patch_file> <output_json>`
  - `./scripts/analyze_patch.sh <output_json>`
  - 批量分析: `./scripts/batch_analyze_patches.sh <patch_dir> [result_file]`
  - 批量分析 (CSV): `./scripts/batch_patch_analysis.sh <patch_dir> [result_csv]`
- Step5:
  - `./scripts/run_full_pipeline.sh data/raw_datasets/<base>_raw_dataset.jsonl`
- 批量运行所有 raw datasets:
  - `./scripts/run_all_pipeline.sh`

---

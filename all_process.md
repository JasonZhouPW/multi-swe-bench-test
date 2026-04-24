# Multi-SWE-Bench 全流程执行清单

下面为经过整理与验证的"正确、可复现"的全流程（六步），包含必要前置条件、每步命令、输出校验与常见排查建议。

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

---

### Step 1 - 生成 Raw Dataset（必须最先执行）

**目的**：从 GitHub 拉取 PR 并整合为 `*_raw_dataset.jsonl`

**主要脚本**：
- 生成 PR 数据：
  - GraphQL 脚本 (更稳定/高效)：`./scripts/new_gen_raw_dataset_graphql.sh -l <lang> -s <min_stars>`
  - 批量生成：`./data_pipeline/gen_all_raw_datasets_new.sh`
- 补全并分类：`./scripts/collect_raw_dataset.sh`

**输出**：`data/raw_datasets/<owner__repo>_raw_dataset.jsonl`

**校验**：确认 `data/raw_datasets` 下存在 `*_raw_dataset.jsonl`

**示例**：
```bash
# 单个语言
./scripts/new_gen_raw_dataset_graphql.sh -l Python -s 10000 -n 20 -o ./data/raw_datasets

# 批量生成所有语言
./data_pipeline/gen_all_raw_datasets_new.sh

# 完整流程
./scripts/collect_raw_dataset.sh
```

---

### Step 1.1 - 数据过滤与精炼（可选）

**目的**：筛选特定类别（如 Bug Fix, Performance）或限制 patch 大小

**脚本**：`./scripts/filter_raw_dataset.sh -i <input_dir> -o <output_dir> [options]`

**特色**：
- 支持交互式菜单（不带参数运行）。
- 预设模式：New Feature, Bug Fix, Edge Case, Performance。
- Patch 过滤：使用 `-p <bytes>` 指定最小补丁大小（仅计算代码部分）。

**输出**：过滤后的 JSONL 文件

**示例**：
```bash
# 交互式
./scripts/filter_raw_dataset.sh

# 过滤 Bug Fix 类别
./scripts/filter_raw_dataset.sh -i ./raw_datasets -o ./filtered -c "bug,bugfix"

# 过滤并有最小 patch 大小限制
./scripts/filter_raw_dataset.sh -i ./raw_datasets -o ./filtered -p 1024 -pt 512
```

---

### Step 2 - Merge JSONL Files by Category（新增）

**目的**：将按类别分类的 JSONL 文件合并到单个文件中

**脚本**：`./scripts/merge_jsonl_by_subdir.sh <directory>`

**输出文件命名格式**：`filtered_YYYYMMDD_<category>_raw_dataset.jsonl`

**功能特性**：
- 自动递归处理子目录
- 过滤二进制文件（macOS extended attributes）
- 验证 JSON 格式
- 移除 null bytes

**示例**：
```bash
./scripts/merge_jsonl_by_subdir.sh ./raw_datasets/filtered
# 输出：
#   - filtered_20260204_bug-fix_raw_dataset.jsonl
#   - filtered_20260204_edge_raw_dataset.jsonl
#   - filtered_20260204_performance_raw_dataset.jsonl
#   - filtered_20260204_refactor_raw_dataset.jsonl
```

---

### Step 3 - 生成 Repo Docker 与脚本并构建 Dataset

**目的**：为每 repo 生成 `Dockerfile`、`prepare.sh`、`test.sh`，并生成 `*_dataset.jsonl`

**主要脚本**：
- 自动生成仓库脚本并构建 dataset（单文件或目录）：
  - 单文件：`./scripts/unify_repo_scripts.sh data/raw_datasets/*_raw_dataset.jsonl`
  - 目录模式：`./scripts/unify_repo_scripts.sh ./data/raw_datasets/filtered/bug-fix`
- 批量处理：`./scripts/batch_unify_repos.sh ./data/raw_datasets/filtered`

**输出**：
- `multi_swe_bench/harness/repos/<lang>/<org>/<repo>/` - 自动生成的测试环境
- `data/datasets/<base>_dataset.jsonl` - 最终 dataset JSONL
- `multi_swe_bench/harness/repos/<lang>/__init__.py` - 语言根目录自动生成
- `multi_swe_bench/harness/repos/<lang>/<org>/__init__.py` - org 目录自动生成
- `multi_swe_bench/harness/repos/__init__.py` - repos 根目录自动更新

**校验**：
- 确认 `data/datasets/<base>_dataset.jsonl` 存在
- 确认目录结构完整

**新功能**：
- 支持 JSONL 文递归查找（处理子目录中的 `*_raw_dataset.jsonl``）
- 自动生成和维护所有层级的 `__init__.py` 文件
- 跳过 binary 文件，防止数据污染

**示例**：
```bash
# 处理单个 raw dataset
./scripts/unify_repo_scripts.sh data/raw_datasets/OpenAPITools__openapi-generator_raw_dataset.jsonl

# 处理目录（包含多个 jsonl）
./scripts/unify_repo_scripts.sh ./data/raw_datasets/filtered/bug-fix

# 批量处理多个子目录
./scripts/batch_unify_repos.sh ./data/raw_datasets/filtered
```

---

### Step 4 - 生成 Patch（可与 Step3 并行）

**目的**：使用 LLM 或 Agent 工具 from raw dataset 提取并生成最终 patches JSONL

**脚本 A (SWE-Agent)**：
```bash
./scripts/run_patch.sh data/raw_datasets/rust_raw_dataset.jsonl
```

**脚本 B (Massgen)**：
```bash
./scripts/run_massgen_for_jsonl.sh <work-dir> <jsonl_path>
```

**输出**：`data/patches/<base>_patch.jsonl` 或指定目录下的 `.patch` 文件

**校验**：建议执行 Patch Quality Check（见下文）

---

### Step 5 - Patch Quality Check（质量校验，可选但建议）

**目的**：在执行完整 Evaluation 前，先对生成的 patch 进行静态扫描与评分

**脚本**：
- 扫描文件：`./scripts/semgrep_scan.sh <patch_file> <output_json>`
- 评分分析：`./scripts/analyze_patch.sh <semgrep_result.json>`
- 批量分析：`./scripts/batch_patch_analysis.sh <patch_dir> [result_file]`
- 批量分析 (CSV)：`./scripts/batch_patch_analysis.sh <patch_dir> [result_csv]`

**输出**：Semgrep 扫描结果与质量评分报告（S/A/B/C/F 级）

---

### Step 6 - 执行 Evaluation（必须等待 Step3 + Step4 完成）

**脚本**：`./scripts/run_full_pipeline.sh data/raw_datasets/<base>_raw_dataset.jsonl`

**要求**：
- `data/patches/<base>_patch.jsonl` 已存在
- `data/datasets/<base>_dataset.jsonl` 已存在

**内部调用**：
- `./data_pipeline/run_evaluation.sh`
- Python: `python -m multi_swe_bench.harness.run_evaluation --config <config.json>`

**输出**：`data/output/`（中间）与 `data/final_output/`（最终报告）

**校验**：查看 `final_report.json` 与 `data/final_output/` 中的报告与日志

---

### Step 7 - 训练数据提取（用于模型微调）

**目的**：将 `data/datasets` 下的数据集转换为 LLM 微调格式（SFT/Completion/DPO）

**脚本**：`python scripts/gen_training_data_from_datasets.py [options]`

**功能**：
- 支持三种格式：SFT（对话）、Completion（前缀补全）、DPO（偏好对齐）
- 自动过滤无效记录（body太短、patch太短、无diff）
- 去除重复记录
- 清理 HTML 注释和模板噪声
- 修复 patch 中的字面 `\n` 为真正换行符
- 支持合并所有项目到单一文件

**输出**：
- 按项目分目录：`training_data/{repo_name}/train_sft.jsonl`
- 合并文件（加 `--merge`）：`training_data/train_sft.jsonl`、`train_completion.jsonl`、`train_dpo.jsonl`

**示例**：
```bash
# 生成所有格式并合并到单一文件
python scripts/gen_training_data_from_datasets.py --merge

# 只生成 SFT 格式
python scripts/gen_training_data_from_datasets.py --formats sft

# 处理特定项目
python scripts/gen_training_data_from_datasets.py --filter gohugoio__hugo kubernetes__kubernetes

# 重新生成（不跳过已存在的文件）
python scripts/gen_training_data_from_datasets.py --no-skip --merge
```

**格式说明**：
| 格式 | 字段 | 用途 |
|------|------|------|
| SFT | `messages` | 对话格式，适合 Chat 模型 |
| Completion | `prompt` + `completion` | 前缀补全，适合代码模型 |
| DPO | `prompt` + `chosen` + `rejected` | 偏好对齐，适合 RLHF 训练 |

---

### Step 7.1 - 从 Raw Dataset 生成训练数据（未处理的数据）

**目的**：直接从 `new_filtered_raw_datasets/<lang>/` 目录下的未处理原始数据生成微调数据

**脚本**：`python scripts/gen_training_data_from_raw.py [options]`

**功能**：与 Step 7 类似，但直接从原始 raw dataset 生成（无需先经过 Step 3 处理）

**输出**：
- 按项目分目录：`training_data_from_raw/{repo_name}/train_sft_from_raw.jsonl`
- 合并文件：`training_data_from_raw/train_sft_from_raw.jsonl` 等

**示例**：
```bash
# 处理所有语言，生成所有格式并合并
python scripts/gen_training_data_from_raw.py --merge

# 只处理 Go 语言
python scripts/gen_training_data_from_raw.py --lang Go --merge

# 指定输出目录
python scripts/gen_training_data_from_raw.py --output-dir ./my_raw_training_data
```

---

## 并行策略与快速运行建议 ⚡

**Step 3 与 Step 4 可并行**（两者仅依赖 Step1 和 Step 2）：

```bash
./scripts/unify_repo_scripts.sh data/raw_datasets/*_raw_dataset.jsonl &   # Step 3
./scripts/run_patch.sh data/raw_datasets/*_raw_dataset.jsonl &           # Step 4
wait
./scripts/run_full_pipeline.sh data/raw_datasets/*_raw_dataset.jsonl      # Step 6
```

**批处理策略**：
- 使用 `./scripts/batch_unify_repos.sh` 批量处理目录
- 使用 `./scripts/run_all_pipeline.sh` 遍历多个 raw_dataset 并依次执行

---

## 常见错误 & 解决要点 ⚠️

- **找不到 `*_raw_dataset.jsonl`** → 检查 `./scripts/new_gen_raw_dataset_graphql.sh` / `./scripts/collect_raw_dataset.sh` 是否成功执行并写入
- **`patch JSONL not found` 或 `dataset JSONL not found`** → 按顺序先生成 Step 3/Step 4 的产物
- **Docker build failed (code 127)** → 检查 `prepare.sh` 权限与 Dockerfile 是否安装 `bash`; 建议在 Dockerfile 中添加：
  ```dockerfile
    RUN chmod +x /home/prepare.sh
    RUN apk add --no-cache bash
    ```
- **JSONDecodeError / Invalid control character** →
  - 使用 `jq -c` 清洗/校验 JSONL
  - 使用 `merge_jsonl_by_subdir.sh` 自动过滤 binary 文件
- **Import Error: 某个模块找不到** →
  - 检查 `__init__.py` 是否正确生成
  - 重新运行 Step 3 重建 `__init__.py`
- **Terminal backspace 不工作** →
  - 已在 `entry.sh` 中修复（使用 `read -rep` 替代 `read -rp`）
  - 重新运行脚本或使用交互式菜单
- **生成的 __init__.py 中 import 语句被连接** →
  - 已修复所有 gen 脚本，现在每个 import 后会添加换行
  - 重新运行脚本

---

## 常用快速命令汇总 🧭

### 交互式菜单
```bash
./entry.sh  # 启动交互式菜单
```

### Step 1: Fetch PRs
```bash
./scripts/new_gen_raw_dataset_graphql.sh -l Python -s 10000 -n 20 -o ./data/raw_datasets
./data_pipeline/gen_all_raw_datasets_new.sh  # 批量生成
./scripts/collect_raw_dataset.sh  # 完整流程
```

### Step 2: Filter Data
```bash
./scripts/filter_raw_dataset.sh -i ./raw_datasets -o ./filtered -p 1024
./scripts/merge_jsonl_by_subdir.sh ./data/raw_datasets/filtered
```

### Step 3: Build Dataset
```bash
# 单文件
./scripts/unify_repo_scripts.sh data/raw_datasets/<file>_raw_dataset.jsonl

# 目录（递归）
./scripts/batch_unify_repos.sh ./data/raw_datasets/filtered

# 批量
./data_pipeline/gen_instance_from_dataset_java.sh <temp_file>
```

### Step 4: Generate Patches
```bash
./scripts/run_patch.sh data/raw_datasets/<base>_raw_dataset.jsonl
./scripts/run_massgen_for_jsonl.sh <work-dir> <jsonl_path>
```

### Step 5: Quality Check
```bash
./scripts/semgrep_scan.sh <patch_file> <output_json>
./scripts/analyze_patch.sh <output_json>
./scripts/batch_analyze_patches.sh <patch_dir> [result_file]
```

### Step 6: Evaluation
```bash
./scripts/run_full_pipeline.sh data/raw_datasets/<base>_raw_dataset.jsonl
./scripts/run_all_pipeline.sh  # 批量运行
```

### Step 7: Training Data
```bash
# 生成并合并所有格式（从已处理的 datasets）
python scripts/gen_training_data_from_datasets.py --merge

# 只生成特定格式
python scripts/gen_training_data_from_datasets.py --formats sft dpo

# 处理特定项目
python scripts/gen_training_data_from_datasets.py --filter gohugoio__hugo

# 从原始 raw dataset 生成（无需 Step 3 处理）
python scripts/gen_training_data_from_raw.py --merge

# 只处理特定语言
python scripts/gen_training_data_from_raw.py --lang Go --merge
```

---

## 测试与验证 🧪

### 验证 Raw Data
```bash
# 检查文件是否存在
ls -lh data/raw_datasets/*_raw_dataset.jsonl

# 检查 JSON 格式
jq -c . data/raw_datasets/*.jsonl 2>&1 | head -5
```

### 验证 Directory Structure
```bash
# 检查语言根目录
ls -la multi_swe_bench/harness/repos/

# 检查 org 目录
ls -la multi_swe_bench/harness/repos/java/apache/

# 检查 org/__init__.py
cat multi_swe_bench/harness/repos/java/openapitools/openapi-generator/__init__.py

# 检查语言根 __init__.py
cat multi_swe_bench/harness/repos/java/__init__.py
```

### 验证 Dataset
```bash
# 检查 dataset 文件
ls -lh data/datasets/*.jsonl

# 统计行数
wc -l data/datasets/*.jsonl
```

---

## 新增功能亮点 ✨

### 1. 交互式菜单（entry.sh）
- 统一的入口点，不需要记忆复杂命令
- 6 个主要选项，涵盖所有常用流程
- 支持 backspace 键修复（Linux/macOS 兼容）

### 2. 批量处理（batch_unify_repos.sh）
- 批量处理多个子目录
- 自动处理每个子目录的 `*_raw_dataset.jsonl` 文件

### 3. JSONL 合并（merge_jsonl_by_subdir.sh）
- 按子目录合并 JSONL 文件
- 自动过滤二进制文件
- 自动添加 `_raw_dataset` 后缀

### 4. 递归处理（unify_repo_scripts.sh）
- 支持递归查找子目录中的文件
- 自动处理深层嵌套结构

### 5. 自动 __init__.py 管理
- 自动生成 org/__init__.py
- 自动重建语言根 __init__.py
- 自动添加换行符，防止 import 语句合并

### 6. 多格式 JSON 支持（create_org_dir.sh）
- 支持扁平结构和嵌套结构的 JSON
- 向后兼容旧的 JSON 格式

---

## 工作流建议 💡

**小型项目（单个 dataset）**：
```bash
./entry.sh
# 选择选项 1 → Fetch PRs
# 选择选项 2 → Filter (可选)
# 选择选项 3 → Build Dataset
# 选择选项 4 → Generate Patches
```

**中型项目（多个 dataset）**：
```bash
./entry.sh
# 选择选项 5 → Fetch All Datasets (一次性获取所有语言)
# 选择选项 2 → Filter Data
# 选择选项 3 → Build Dataset
# 选择选项 4 → Generate Patches
```

**大型项目（分类处理）**：
```bash
./entry.sh
# 选择选项 5 → Fetch All Datasets
# 选择选项 2 → Filter Data (生成多个 filtered 目录)
./scripts/merge_jsonl_by_subdir.sh ./data/raw_datasets/filtered
./scripts/batch_unify_repos.sh ./data/raw_datasets/filtered
# 选择选项 4 → Generate Patches
```

---

## 故障排查 🔧

### Docker 相关
```bash
# 检查 Docker 状态
docker ps

# 查看 Docker 日志
docker logs <container_id>

# 清理无用的 Docker 资源
docker system prune -a
```

### Python 环境
```bash
# 检查 Python 版本
python --version

# 重新安装包
make install

# 检查依赖
pip list | grep -E "docker|jq|gitpython"
```

### GitHub API
```bash
# 验证 token
curl -H "Authorization: token YOUR_TOKEN" https://api.github.com/user

# 查询速率限制
curl -H "Authorization: token YOUR_TOKEN" https://api.github.com/rate_limit
```

---

## 性能优化 ⚡

- **预下载 Docker 镜像**：`bash scripts/download_images.sh scripts/images_mini.txt`
- **并行执行**：Step 3 和 Step 4 可以并行
- **批量处理**：使用 batch 脚本减少重复劳动
- **增量更新**：unify_repo_scripts.sh 支持单独处理新的 raw_dataset 文件
- **数据过滤**：Step 1.1 提前过滤可以减少后续步骤的处理量

---

## 总结 📝

完整流程共 8 步：
1. Fetch PRs from GitHub (Step 1)
2. Filter & Refine Data (Step 1.1, 可选)
3. Merge JSONL by Category (Step 2, 新增)
4. Build Dataset (Step 3)
5. Generate Patches (Step 4)
6. Patch Quality Check (Step 5, 可选)
7. Run Evaluation (Step 6)
8. Extract Training Data (Step 7, 可选，支持 SFT/Completion/DPO 三种格式)

每个脚本都有详细的错误处理和进度提示，遇到问题时会给出明确的错误信息和建议的解决方法。

开始使用前，建议先运行 `./entry.sh` 探索交互式菜单功能！

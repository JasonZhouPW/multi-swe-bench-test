# Multi-SWE-Bench 全流程使用指南

本指南描述 Multi-SWE-Bench 的完整 4 步全流程：从 PR 收集到最终评测。文档包含每一步的脚本、输入输出、依赖关系，以及并行化建议（Step2 & Step3 可并行，Step4 依赖 Step2+Step3）。

---

## 目录

1. 概述  
2. 流程总览  
3. 步骤详解  
   - Step1：生成 Raw Dataset  
   - Step2：注册 Repo（生成 Dockerfile 与 repo 脚本） 并生成 dataset 文件  
   - Step3：基于 Raw Dataset 生成 Patch（LLM）  
   - Step4：执行 Evaluation  
4. 依赖关系与并行策略  
5. 文件夹结构示例  
6. 常见问题与排查  
7. 操作命令汇总

---

## 1. 概述

Multi-SWE-Bench 是用于评估和训练代码修复系统的框架。本流水线目标是自动化地将 GitHub PR 转换为可执行的评测流程：抓取 PR → 生成 raw dataset → 为每个仓库生成构建环境（Docker）→ 使用 LLM 生成 patch → 构建 dataset 并运行评测。

---

## 2. 流程总览（四步）

```
Step1: 生成 Raw Dataset
  ├─ gen_raw_dataset.sh
  └─ collect_raw_dataset.sh

Step2: 生成 Repo Docker 与脚本（unify_repo_scripts.sh）
  (依赖 Step1 输出 raw_dataset)

Step3: 使用 LLM 生成 Patch（run_patch.sh）
  (依赖 Step1 输出 raw_dataset)

Step4: 执行 Evaluation（run_full_pipeline.sh）
  (依赖 Step2 + Step3 输出)
```

说明：

- Step2 与 Step3 可以并行执行（两者都只依赖 Step1）。
- Step4 必须等待 Step2 与 Step3 完成，因为它需要通过Docker环境生成的 dataset文件 与 patch 文件共同参与评测。

---

## 3. 步骤详解

### Step1：生成 Raw Dataset（必须最先执行）

### 1.1 gen_raw_dataset.sh

功能：  

- 从 GitHub API 拉取 PR 列表与基本信息。  
- 生成中间文件：`*_prs.jsonl`、`*_filtered_prs.jsonl`、`*_related_issues.jsonl` 等。  
- 最终产物：`*_raw_dataset.jsonl`。

示例输出目录：

```
lllyasviel__Fooocus_prs.jsonl
lllyasviel__Fooocus_filtered_prs.jsonl
lllyasviel__Fooocus_related_issues.jsonl
lllyasviel__Fooocus_raw_dataset.jsonl
```

### 1.2 collect_raw_dataset.sh

功能：  

- 扫描所有 `*_raw_dataset.jsonl` 文件（文件名必须包含 raw_dataset）。  
- 为每条记录补充完整信息（patch、commit、修改文件等）。  
- 自动识别语言字段，并按语言分类：

```
data/raw_datasets/python/
data/raw_datasets/go/
data/raw_datasets/javascript/
```

---

### Step2：注册 Repo / 生成 Dockerfile 得到最终的 dataset 文件（unify_repo_scripts.sh）

功能：  

- 为每个 repo 生成测试环境：Dockerfile、prepare.sh、test.sh 等。  
- 根据 repo.language 选择模板（Python、Go、JS 等）。  
- 输出目录示例：

```
data/repos/mark3labs__mcp-go/
 ├─ Dockerfile
 ├─ prepare.sh
 └─ test.sh
```

注意：  

- 确保 prepare.sh 可执行。  
- 确保 Dockerfile 中安装 bash、git、语言相关依赖。

---

### Step3：使用 LLM 生成 Patch（gen_patch_from_raw_dataset.py）

功能：  

- 解析 raw_dataset 中的 PR 信息（title、body、diff、文件内容）。  
- 调用 LLM 生成修复补丁 patch。  
- 每条 PR 输出一条 JSONL 记录，例如：

```json
{"org":"mark3labs","repo":"mcp-go","number":287,"fix_patch":"diff --git ..."}
```

输出目录：

```
data/patches/mark3labs__mcp-go_patch.jsonl
```

注意：  

- Patch 必须保持 diff 格式。  
- 建议生成后使用 `git apply --check` 验证可用性。

---

### Step4：执行 Evaluation（run_full_pipeline.sh）

功能：  

1. 使用 Step1 采集github上的PR → 生成 raw_dataset  
2. 使用 Step2 Docker 环境, 构建 runner image → 生成 dataset  
3. 使用 Step3 的 patches 文件 和 Step2 生成的 dataset 文件 → 运行 evaluation

完成后输出到：

```
data/final_output/
```

必须确保 Step2、Step3 都完成后才能运行 Step4。

---

## 4. 依赖关系与并行策略

### 依赖图

```
Step1 → Step2 →  
        Step3 → Step4
```

### 并行建议

```
./unify_repo_scripts.sh &          # Step2
python gen_patch_from_raw_dataset.py &   # Step3
wait
./run_full_pipeline.sh
```

---

## 5. 文件夹结构参考

```
data/
 ├─ raw_datasets/
 │   └─ repo_raw_dataset.jsonl
 ├─ repos/
 │   └─ owner__repo/
 │       ├─ Dockerfile
 │       ├─ prepare.sh
 │       └─ test.sh
 ├─ patches/
 │   └─ owner__repo_patch.jsonl
 ├─ datasets/
 │   └─ owner__repo_dataset.jsonl
 ├─ final_output/
 │   └─ repo
 │        └─ repo_final_report.jsonl
 └─ logs/
```

---

## 6. 常见问题与排查

### 错误：Invalid control character / JSONDecodeError

原因：raw_dataset 或 patch 含未转义字符。  
解决：确保 JSONL 写入使用转义（`jq -c` 可修复）。

### 错误：Docker build failed (code 127)

原因：prepare.sh 不存在或未赋权限，或 bash 未安装。  
解决：在 Dockerfile 中添加：

```
RUN chmod +x /home/prepare.sh
RUN apk add --no-cache bash  # 或 apt-get install -y bash
```

### 错误：⚠️ Warning: record #N failed to produce dataset

原因：repo commit checkout 失败、依赖缺失、测试命令错误。  
解决：检查 logs/ 中对应日志。

---

## 7. 操作命令汇总

### Step1：生成 Raw Dataset

```bash
./gen_raw_dataset.sh owner/repo
./collect_raw_dataset.sh
```

### Step2：生成 Docker & repo 脚本, 并生成 dataset 文件

```bash
./unify_repo_scripts.sh data/raw_datasets/*_raw_dataset.jsonl
```

### Step3：生成 patch

```bash
 ./run_patch.sh  data/raw_datasets/*_raw_dataset.jsonl
```

### Step4：评测 run_evaluation

```bash
./run_full_pipeline.sh data/raw_datasets/*_raw_dataset.jsonl
```

---

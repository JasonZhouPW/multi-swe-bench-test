# 🚀 Multi-SWE-Bench 全流程自动化管线文档

**（run_all_pipeline.sh + run_full_pipeline.sh + gen_patch_jsonl.sh +
build_dataset.sh + run_evaluation.sh）**

本文件介绍如何使用一套脚本实现：

- 自动读取所有 `*_raw_dataset.jsonl`
- 自动生成 patch JSONL (`*_patch.jsonl`)
- 自动构建 dataset (`*_dataset.jsonl`)
- 自动执行 SWE-Bench evaluation
- 自动输出最终评测报告

------------------------------------------------------------------------

# 📁 目录结构要求

    project-root/
    │
    ├── run_all_pipeline.sh
    ├── run_full_pipeline.sh
    ├── gen_patch_jsonl.sh
    ├── build_dataset.sh
    ├── run_evaluation.sh
    │
    └── data/
        ├── raw_datasets/
        │     ├── mark3labs__mcp-go_raw_dataset.jsonl
        │     ├── example2_raw_dataset.jsonl
        │     └── ...
        │
        ├── patches/
        │     ├── mark3labs__mcp-go.patch
        │     ├── example2.patch
        │     └── ...
        │
        ├── mcp_data/
        ├── output/
        ├── final_output/
        ├── workdir/
        ├── repos/
        └── logs/

------------------------------------------------------------------------

# 🧩 1. 脚本用途说明

## ✔ gen_patch_jsonl.sh

根据 raw dataset + patch 文件生成：

    <basename>_patch.jsonl

格式如下：

``` json
{
  "org": "mark3labs",
  "repo": "mcp-go",
  "number": 287,
  "fix_patch": "这里是完整 patch 内容（含换行）"
}
```

输出目录：

    ./data/mcp_data/

------------------------------------------------------------------------

## ✔ build_dataset.sh

输入：

    *_raw_dataset.jsonl

输出：

    *_dataset.jsonl

输出目录：

    ./data/output/

------------------------------------------------------------------------

## ✔ run_evaluation.sh

使用生成的 dataset + patch 文件执行 SWE-Bench evaluation。

自动生成：

    ./data/final_output/

------------------------------------------------------------------------

## ✔ run_full_pipeline.sh

针对一个 raw dataset 文件执行完整流程：

1) 生成 patch JSONL\
2) 构建 dataset JSONL\
3) 运行 evaluation

示例：

``` bash
./run_full_pipeline.sh mark3labs__mcp-go_raw_dataset.jsonl
```

------------------------------------------------------------------------

## ✔ run_all_pipeline.sh

自动读取所有：

    ./data/raw_datasets/*_raw_dataset.jsonl

并依次执行：

    run_full_pipeline.sh <file>

------------------------------------------------------------------------

# 🔧 3. 使用步骤

## ★ Step 1 --- 放入 raw dataset

将 raw dataset 放入：

    ./data/raw_datasets/

## ★ Step 2 --- 放入对应 patch 文件

放入：

    ./data/patches/

## ★ Step 3 --- 运行全部 pipeline

``` bash
./run_all_pipeline.sh
```

## ★ Step 4 --- 查看输出

结果会被存入：

- `./data/mcp_data/*_patch.jsonl`
- `./data/output/*_dataset.jsonl`
- `./data/final_output/`

------------------------------------------------------------------------

# 🎉 完整文档结束

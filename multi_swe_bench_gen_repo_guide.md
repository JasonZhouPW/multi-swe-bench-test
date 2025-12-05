# Multi-SWE-Bench Gen Repo 操作文档

## 1. 目的

本操作文档用于指导如何通过脚本自动生成 `multi_swe_bench/harness/repos`
目录下对应语言（golang/python/rust/...）的实例库，包括：

- 自动识别 raw_dataset 中的 org/repo/language\
- 自动创建语言目录\
- 自动创建 org 目录\
- 自动写入 `__init__.py`\
- 自动生成该 repo 对应的实例文件（例如 golang 的 mcp_go.py）\
- 自动加载 import 到语言入口模块

## 2. 数据来源说明

系统从 `./data/raw_datasets/` 目录读取所有包含 `raw_dataset` 的 JSONL
文件，例如：

    mark3labs__mcp-go_raw_dataset.jsonl

文件内容中必须包含字段：

``` json
"base": {
  "repo": {
    "language": "Go",
    "full_name": "mark3labs/mcp-go",
    ...
  }
}
```

脚本从此结构中提取：

- org\
- repo\
- language

并进行语言映射（如 Go → golang）。

## 3. 运行脚本

### 3.1 主脚本（自动遍历所有 raw_dataset 文件）

运行：

``` bash
chmod +x unify_repo_scripts.sh
./unify_repo_scripts.sh
```

该脚本将：

1. 遍历 `./data/raw_datasets` 下所有 **文件名包含 raw_dataset 的文件**\
2. 每个文件只读取第一行\
3. 调用三个子脚本：
    - `auto_add_import.sh`\
    - `create_org_dir.sh`\
    - `gen_instance_from_dataset_golang.sh`

### 自动生成结果目录结构

例如：

    multi_swe_bench/
      harness/
        repos/
          golang/
            mark3labs/
              __init__.py
              mcp_go.py
          python/
          rust/

并自动在 `__init__.py` 中添加：

``` python
from multi_swe_bench.harness.repos.golang.mark3labs.mcp_go import *
```

## 4. 脚本说明

### 4.1 auto_add_import.sh

负责写入语言入口文件的 import 语句。

### 4.2 create_org_dir.sh

负责：

- 根据 dataset 自动创建语言目录\
- 根据 org 创建目录\
- 写 `__init__.py`

### 4.3 gen_instance_from_dataset_golang.sh

模板化生成 `mcp_go.py`。
目前仅支持 golang PR版本。
未来可扩展为：

- Python 版本\
- Rust 版本\
- JavaScript 版本

## 5. 文件命名要求

必须包含字符串：`raw_dataset`：

✔ 会被处理

    mark3labs__mcp-go_raw_dataset.jsonl

✘ 不会被处理

    xxx_patch.jsonl
    xxx_dataset.jsonl

## 6. 示例执行流程

运行主脚本后：

- 自动生成语言目录\
- 自动生成 org 目录\
- 自动生成 mcp_go.py\
- 自动添加 import\
- 全流程完成无人值守的初始化

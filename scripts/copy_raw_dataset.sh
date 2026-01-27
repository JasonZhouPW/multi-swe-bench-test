#!/bin/bash

# 查询文件夹下（包含子文件夹）的所有*_raw_dataset.jsonl文件
# 如果文件大小>0,则将文件拷贝到目标文件夹

# 用法: ./copy_raw_dataset.sh <源目录> <目标目录>

if [ $# -lt 2 ]; then
    echo "用法: $0 <源目录> <目标目录>"
    exit 1
fi

SOURCE_DIR="$1"
TARGET_DIR="$2"

# 检查源目录是否存在
if [ ! -d "$SOURCE_DIR" ]; then
    echo "错误: 源目录 '$SOURCE_DIR' 不存在"
    exit 1
fi

# 如果目标目录不存在，创建它
if [ ! -d "$TARGET_DIR" ]; then
    mkdir -p "$TARGET_DIR"
fi

# 查找所有 *_raw_dataset.jsonl 文件，检查大小>0后拷贝到目标文件夹
find "$SOURCE_DIR" -name "*_raw_dataset.jsonl" -type f -size +0 -exec cp {} "$TARGET_DIR/" \;

echo "完成! 已将非空的 *_raw_dataset.jsonl 文件拷贝到 $TARGET_DIR"

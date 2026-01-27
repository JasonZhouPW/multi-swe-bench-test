# Multi-SWE-Bench: A Multilingual Benchmark for Issue Resolving

Multi-SWE-Bench is a comprehensive framework for evaluating and training Large Language Models (LLMs) on real-world software issue resolution across multiple programming languages. Unlike original Python-centric benchmarks, Multi-SWE-Bench supports **7+ languages** including Java, TypeScript, JavaScript, Go, Rust, C, and C++.

## 🚀 Features

- **Multilingual Support**: High-quality instances curated for Java, TS, JS, Go, Rust, C, and C++.
- **End-to-End Pipeline**: Fully automated workflow from GitHub PR collection to final evaluation reports.
- **Robust Data Collection**: Supports both traditional REST API and high-performance GraphQL API for fetching PRs.
- **Reproducible Evaluation**: Uses Docker-based environments for isolated and consistent code execution.
- **Enhanced Filtering**: Advanced tools to filter raw datasets by category (Bug Fix, Feature, etc.) and patch size.
- **Training Utilities**: Tools to extract and format data for model fine-tuning.

---

## 🛠️ Installation & Setup

### Prerequisites
- **Docker**: Must be installed and running.
- **Python 3.10+**: Recommended version 3.11+.

### Setup
Clone the repository and install dependencies:
```bash
git clone https://github.com/ontology-tech/multi-swe-bench.git
cd multi-swe-bench
make install
```

---

## 📋 Full Execution Pipeline

The pipeline follows a structured 5-step process. Detailed instructions can be found in [all_process.md](all_process.md).

### 1. Generate Raw Dataset
Fetch PRs from GitHub and consolidate them into raw JSONL files.
```bash
# New GraphQL-based collection (Recommended)
./scripts/new_gen_raw_dataset_graphql.sh -l Python -s 10000 -n 5 -o ./data/raw_datasets/test_py

# Complete and categorize data
./scripts/collect_raw_dataset.sh
```

### 2. (Optional) Filter & Refine Data
Filter by bug type or patch complexity.
```bash
./scripts/filter_raw_dataset.sh -i ./data/raw_datasets -o ./data/filtered -p 1024
```

### 3. Build Dataset & Environment
Generate Dockerfiles and environment scripts for evaluation.
```bash
./scripts/unify_repo_scripts.sh data/raw_datasets/example_raw_dataset.jsonl
```

### 4. Generate Repair Patches
Use agents like **SWE-Agent** or tools like **Massgen** to generate fixes.
```bash
./scripts/run_patch.sh data/raw_datasets/example_raw_dataset.jsonl
```

### 5. Run Evaluation
Execute the final benchmark evaluation.
```bash
./scripts/run_full_pipeline.sh data/raw_datasets/example_raw_dataset.jsonl
```

---

## 🧭 Common Commands Summary

| Task | Command |
|------|---------|
| **GraphQL Fetch** | `./scripts/new_gen_raw_dataset_graphql.sh -l [Lang] -s [Stars] -o [Dir]` |
| **Unified Setup** | `./scripts/unify_repo_scripts.sh [Raw_Dataset]` |
| **Run Agent** | `./scripts/run_patch.sh [Raw_Dataset]` |
| **Evaluate** | `./scripts/run_full_pipeline.sh [Raw_Dataset]` |
| **Quality Check**| `./scripts/analyze_patch.sh [Semgrep_Output]` |
| **Training Data**| `./scripts/extract_training_data.sh [Input_Path] [Output_JSON]` |

---

## 📂 Directory Structure
- `multi_swe_bench/`: Core Python logic and harness.
- `data_pipeline/`: Internal scripts for data processing.
- `scripts/`: Unified entry-point scripts for root-level execution.
- `data/`: Generated datasets, patches, logs, and environments.


## 📜 License
This project is licensed under the Apache License 2.0.

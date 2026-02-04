# Multi-SWE-Bench: A Multilingual Benchmark for Issue Resolving

Multi-SWE-Bench is a comprehensive framework for evaluating and training Large Language Models (LLMs) on real-world software issue resolution across multiple programming languages. Unlike original Python-centric benchmarks, Multi-SWE-Bench supports **8+ languages** with high-quality curated instances.

## 🌍 Supported Languages

- **Java** - Enterprise-scale applications (`java_ds/`)
- **TypeScript** - Modern web development (`ts_ds/`)
- **JavaScript** - Frontend and Node.js projects (`js_ds/`)
- **Go** - Cloud-native and microservices (`go_ds/`)
- **Rust** - Systems programming (`rust_ds/`)
- **C++** - Performance-critical applications (`cpp_ds/`)
- **Python** - Data science, ML, and automation (`python_ds/`)

Each language has a dedicated dataset directory with thousands of real-world PRs from popular GitHub repositories. The framework uses GraphQL API to fetch high-quality instances with metadata including:
- Pull request details and changes
- Linked issues and discussions
- Commit messages and reviews
- Code patches and diff files

## 🚀 Key Features

- **Multilingual Support**: 8+ programming languages with dedicated datasets
  - Java, TypeScript, JavaScript, Go, Rust, C++, Python
  - Each language has specialized instance generation scripts

- **GraphQL-Powered Data Collection**
  - High-performance GitHub PR fetching via GraphQL API
  - Custom query support for flexible filtering
  - Language/star/date filters for targeted collection
  - Automatic issue-PR relationship resolution

- **Interactive CLI Workflow**
  - `entry.sh` provides menu-driven interface for common tasks
  - No need to memorize complex command-line arguments
  - Streamlined 6-step pipeline execution

- **Filtering & Data Processing**
  - Keyword-based filtering (supports comma-separated lists)
  - Category filtering (Bug Fix, Feature, Refactor, etc.)
  - Match mode options (any/all)
  - Batch processing for multiple datasets
  - Binary data filtering for clean JSONL files

- **Docker-Based Evaluation**
  - Isolated test environments for reproducible results
  - Automatic Dockerfile generation from repository configurations
  - Parallel execution support for faster evaluation

- **Training Data Extraction**
  - Format raw datasets for LLM fine-tuning
  - Structured JSON output with metadata
  - Support for patch generation training

- **Comprehensive Test Harness**
  - Automated test execution
  - Report generation with detailed metrics
  - Patch analysis with Semgrep integration

- **Automated __init__.py Management**
  - Auto-generate org/__init__.py files
  - Auto-rebuild language root __init__.py
  - Auto-update repos/__init__.py
  - Prevents duplicate imports

---

## 🛠️ Installation & Setup

### System Requirements

**Minimum Requirements:**
- **Docker**: Must be installed and running (required for evaluation)
  - Verify: `docker ps`
- **Python 3.10+**: Recommended version 3.11 or 3.12
  - Verify: `python --version`
- **GitHub Token**: Required for PR fetching
  - Create at: https://github.com/settings/tokens
  - Select scopes: `repo`, `read:org`

**Recommended:**
- 8GB+ RAM memory
- 50GB+ free disk space
- Stable internet connection for GitHub API access

### Installation Steps

Clone the repository and install dependencies:
```bash
git clone https://github.com/ontology-tech/multi-swe-bench.git
cd multi-swe-bench

# Install the package (creates virtual environment if needed)
make install

# (Optional) Install development dependencies
make install-dev
```

**Python Dependencies:**
- `dataclasses_json` - Data serialization
- `docker` - Docker API integration
- `tqdm` - Progress bars
- `gitpython` - Git operations
- `toml` - Configuration parsing
- `pyyaml` - YAML processing
- `PyGithub` - GitHub API client

**System Tools:**
- `jq` - JSON processing
- `git` - Version control
- `bash` - Shell scripting (required for all scripts)

---

## 🎯 Quick Start (Interactive Mode)

Run the interactive menu for guided setup:

```bash
./entry.sh
```

The entry menu provides easy access to:
1. Fetch PRs from GitHub (GraphQL)
2. Filter Raw Dataset
3. Build Dataset by PRs
4. Extract Training Data
5. Fetch All Raw Datasets
6. **Batch Unify Repos** (batch process directories)
7. Exit

---

## 📖 Usage Guide

### 1. Fetch PRs from GitHub

Use GraphQL API to fetch PRs from GitHub repositories:

```bash
# Fetch by language and minimum stars
./scripts/new_gen_raw_dataset_graphql.sh -l Python -s 10000 -o ./data/raw_datasets

# Fetch using custom query
./scripts/new_gen_raw_dataset_graphql.sh -q "language:Java stars:>10000 is:pr is:merged" -o ./data/raw_datasets

# Specify date range
./scripts/new_gen_raw_dataset_graphql.sh -l Go -s 5000 -m "2025-01-01" -o ./data/raw_datasets
```

#### Batch Processing (All Languages)

```bash
# fetch all languages at once
./data_pipeline/gen_all_raw_datasets_new.sh
```

### 2. Filter Raw Datasets

Filter datasets by keywords, categories, or patch size:

```bash
# Interactive mode (no arguments)
./scripts/filter_raw_dataset.sh

# Filter by keywords
./scripts/filter_raw_dataset.sh -i ./data/raw_datasets -o ./data/filtered -k "security,bug"

# Filter by category
./scripts/./scripts/filter_raw_dataset.sh -i ./data/raw_datasets -o ./data/bug-fix -c "bug,bugfix"

# Match mode (any/all)
./scripts/filter_raw_dataset.sh -i ./data/raw_datasets -o ./data/filtered -m all

# Minimum patch size (excluding docs)
./scripts/filter_raw_dataset.sh -i ./data/raw_datasets -o ./data/filtered -p 1024 --min-test-patch-size 512
```

### 3. Build Dataset by PRs

Generate test environments and dataset JSONL files:

```bash
# Process single raw dataset
./scripts/unify_repo_scripts.sh ./data/raw_datasets/rust_raw_dataset.jsonl

# Process multiple raw datasets
./scripts/unify_repo_scripts.sh ./data/raw_datasets/*_raw_dataset.jsonl

# Process directories recursively (supports subdirectories)
./scripts/unify_repo_scripts.sh ./data/raw_datasets/filtered/bug-fix
```

This step creates:
- Repositories in `multi_swe_bench/harness/repos/`
- Test instances and evaluation configs
- Dockerfiles for isolated testing
- `__init__.py` files for proper Python imports

### 4. Batch Unify Repos

Process multiple directories in batch:

```bash
# Process all subdirectories
./scripts/batch_unify_repos.sh ./data/raw_datasets

# Or use entry.sh menu option 6
./entry.sh
# Select option 6 and enter directory path
```

This is useful when you have structured data like:
```
./data/raw_datasets/filtered/
  ├── bug-fix/
  ├── edge/
  ├── performance/
  └── refactor/
```

### 5. Merge JSONL Files by Subdirectory

Merge JSONL files from subdirectories:

```bash
./scripts/merge_jsonl_by_subdir.sh ./data/raw_datasets/filtered
```

Output files:
```
./data/raw_datasets/filtered/
  ├── filtered_20260204_bug-fix_raw_dataset.jsonl
  ├── filtered_20260204_edge_raw_dataset.jsonl
  ├── filtered_20260204_performance_raw_dataset.jsonl
  └── filtered_20260204_refactor_raw_dataset.jsonl
```

Features:
- Skips binary files (macOS extended attributes)
- Validates JSON format before merging
- Removes null bytes from input files

### 6. Generate Repair Patches

Use agents like **SWE-Agent** or tools like **Massgen** to generate fixes:

```bash
# Generate patches using SWE-Agent
./scripts/run_patch.sh ./data/raw_datasets/rust_raw_dataset.jsonl

# Or use Massgen for bulk generation
./scripts/run_massgen_for_jsonl.sh ./data/raw_datasets/ts_data.jsonl

# Batch patch analysis
./scripts/batch_patch_analysis.sh ./data/patches/
```

### 7. Run Evaluation

Execute the final benchmark evaluation:

```bash
# Full pipeline with evaluation
./scripts/run_full_pipeline.sh ./data/raw_datasets/rust_raw_dataset.jsonl

# Run evaluation only
./scripts/run_evaluation.sh ./data/evaluation_results/

# Generate reports
./scripts/analyze_patch.sh ./data/evaluation_results/semgrep_output.jsonl
```

---

## 🔧 Advanced Usage

### Data Processing Utilities

#### SWE-bench Oracle Dataset Generation

Generate a comprehensive `dataset.jsonl` compatible with SWE-bench:

```bash
# Step 1: Compile raw data
./scripts/gen_swe_oracle_dataset.sh ./data/raw_datasets swe_oracle_dataset.jsonl

# Step 2: Enrich with Oracle text
python scripts/generate_oracle_text.py --directory ./path/to/dataset_dir
python scripts/generate_oracle_text.py --file swe_oracle_dataset.jsonl
```

#### Patch Size Filtering

Filter instances by patch size:

```bash
./scripts/filter_large_patches.sh ./data/raw_datasets ./data/filtered/large_patches.jsonl 1024
```

#### Fix Base Commit Hash

Fix incorrect or missing `base_commit` hashes:

```bash
python scripts/fix_commithash.py ./data/raw_datasets
```

---

## 🧭 Common Commands Summary

| Task | Command | Description |
|------|---------|-------------|
| **Interactive Menu** | `./entry.sh` | Interactive menu for all tasks |
| **Fetch PRs** | `./scripts/new_gen_raw_dataset_graphql.sh -l [Lang] -s [Stars] -n [N] -o [Dir]` | GraphQL API for fetching PRs |
| **Custom Query** | `./scripts/new_gen_raw_dataset_graphql.sh -q "[query]" -o [Dir] -n [N]` | Custom GitHub search query |
| **Filter Data** | `./scripts/filter_raw_dataset.sh -i [Input] -o [Output] -k [Keywords]` | Filter by keywords/categories |
| **Build Dataset** | `./scripts/unify_repo_scripts.sh [Raw_Dataset]` | Generate test environments |
| **Collect Data** | `./scripts/collect_raw_dataset.sh` | Complete and categorize raw data |
| **Copy Datasets** | `./scripts/copy_raw_dataset.sh [Source] [Target]` | Merge datasets |
| **Batch Unify** | `./scripts/batch_unify_repos.sh [Directory]` | Batch process directories |
| **Merge JSONL** | `./scripts/merge_jsonl_by_subdir.sh [Directory]` | Merge JSONL by subdirectory |
| **Extract Training** | `./scripts/extract_training_data.sh [Input] [Output_JSON]` | Format for fine-tuning |
| **Run Patches** | `./scripts/run_patch.sh [Raw_Dataset]` | Generate repair patches |
| **Run Evaluation** | `scripts/run_full_pipeline.sh [Raw_Dataset]` | Complete evaluation pipeline |

---

## 🧪 Testing & Validation

### Test Mode

Use test mode for dry runs:

```bash
./scripts/unify_repo_scripts_test.sh ./data/raw_datasets/test_raw_dataset.jsonl
```

### Data Quality Checks

```bash
# Check for JSON validation errors
jq -c . ./data/raw_datasets/*.jsonl 2>&1 | head -10

# Check for blank lines
grep -c '^$' ./data/raw_datasets/*.jsonl

# Validate instance count
wc -l ./data/raw_datasets/*.jsonl
```

---

## 📊 Evaluation Metrics

The framework tracks multiple metrics for evaluation:

- **Success Rate**: Percentage of instances resolved
- **Patch Validity**: Whether the patch correctly addresses the issue
- **Test Pass Rate**: Automated test execution results
- **Code Quality**: Semgrep-based static analysis
- **Execution Time**: Time taken to apply and test

---

## 🤝 Contributing

We welcome contributions! Please see `docs/CONTRIBUTING.md` for guidelines.

---

## 📚 Documentation

- `docs/Multi-SWE-Bench_Full_Guide.md` - Comprehensive guide
- `docs/build-dataset-quick-start.md` - Quick start guide
- `docs/Multi-SWE-Bench_Full_Guide.md` - Full workflow documentation
- `docs/contribution-demo.md` - Contribution examples
- `all_process.md` - Process flow documentation
- `TASk_COMPLETION_SUMMARY.md` - Task completion summary

---

## 📞 Support

For issues and questions:
- GitHub Issues: https://github.com/ontology-tech/multi-swe-bench/issues
- Discord: [Link to Discord server if applicable]

---

## 📄 License

[Specify your license here]

---

## 🔗 Related Projects

- [SWE-bench](https://swe-bench.github.io/)
- [SWE-Agent](https://github.com/princeton-nlp/SWE-Agent)
- [Massgen](https://github.com/princeton-nlp/Massgen)

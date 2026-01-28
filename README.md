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
  - Streamlined 4-step pipeline execution

- **Filtering & Data Processing**
  - Keyword-based filtering (supports comma-separated lists)
  - Category filtering (Bug Fix, Feature, Refactor, etc.)
  - Match mode options (any/all)
  - Batch processing for multiple datasets

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
- `unidiff` - Diff parsing
- `swe-rex` - Regular expressions for SWE tasks

**Dev Dependencies:**
- `ruff` - Fast Python linter and formatter
- `typos` - Source code spell checker
- `prettier` - Code formatter

### 🎯 Quick Start
Use the interactive entry script to start common tasks:
```bash
bash entry.sh
```

The interactive menu provides options for:
1. **Fetch PRs from GitHub** using GraphQL API
2. **Filter Raw Dataset** by keywords and categories
3. **Build Dataset by PRs** for environment setup
4. **Extract Training Data** for fine-tuning

---

## 📋 Full Execution Pipeline

The pipeline follows a structured 5-step process. Detailed instructions can be found in [all_process.md](all_process.md).

### 1. Generate Raw Dataset (GraphQL-based)

Fetch PRs from GitHub using the high-performance GraphQL API:
```bash
# Basic fetch with language filter
./scripts/new_gen_raw_dataset_graphql.sh -l Rust -s 10000 -n 20 -o ./data/raw_datasets/rust_data

# With additional filters
./scripts/new_gen_raw_dataset_graphql.sh \
  -l TypeScript \
  -s 5000 \
  -n 50 \
  -o ./data/raw_datasets/ts_data \
  -m 2025-01-01 \
  -k "bug fix"

# Use custom query for advanced filtering
./scripts/new_gen_raw_dataset_graphql.sh \
  -q "language:go stars:>1000" \
  -o ./data/raw_datasets/go_custom \
  -n 100

# Collect and categorize data
./scripts/collect_raw_dataset.sh
```

**Parameters:**
- `-l`: Programming language (Python, Rust, Java, TypeScript, etc.)
- `-s`: Minimum star count (default: 10000)
- `-n`: Maximum number of repos to fetch
- `-o`: Output directory (required)
- `-m`: "Merged after" date in ISO format (e.g., 2025-01-01)
- `-k`: Keywords to append to search query
- `-q`: Custom GraphQL search query (overrides -l, -s, -k)
- `-t`: GitHub token path (default: ./tokens.txt)

### 2. (Optional) Filter & Refine Data

Filter datasets by keywords, categories, and match modes:
```bash
# Filter by keywords
./scripts/filter_raw_dataset.sh \
  -i ./data/raw_datasets/rust_data \
  -o ./data/filtered/rust_bugfix \
  -k "bug,fix,repair"

# Filter by categories (Bug Fix, Feature, Refactor, etc.)
./scripts/filter_raw_dataset.sh \
  -i ./data/raw_datasets \
  -o ./data/filtered/features \
  -c "Feature,Enhancement"

# Combine filters with match mode
./scripts/filter_raw_dataset.sh \
  -i ./data/raw_datasets \
  -o ./data/filtered/strict \
  -k "memory,performance" \
  -m all
```

**Filter Modes:**
- `any`: Match any of the criteria (default)
- `all`: Match all criteria

### 3. Build Dataset & Environment

Generate Dockerfiles and environment scripts for evaluation:
```bash
# Process single dataset file
./scripts/unify_repo_scripts.sh ./data/raw_datasets/rust_raw_dataset.jsonl

# Process entire directory
./scripts/unify_repo_scripts.sh ./data/raw_datasets/

# Test mode (dry run)
./scripts/unify_repo_scripts_test.sh ./data/raw_datasets/test_raw_dataset.jsonl
```

This step creates:
- Repositories in `multi-swe-bench/harness/repos/`
- Test instances and evaluation configs
- Dockerfiles for isolated testing

### 4. Generate Repair Patches

Use agents like **SWE-Agent** or tools like **Massgen** to generate fixes:
```bash
# Generate patches using SWE-Agent
./scripts/run_patch.sh ./data/raw_datasets/rust_raw_dataset.jsonl

# Or use Massgen for bulk generation
./scripts/run_massgen_for_jsonl.sh ./data/raw_datasets/ts_data.jsonl

# Batch patch analysis
./scripts/batch_patch_analysis.sh ./data/patches/
```

### 5. Run Evaluation

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

## 🧭 Common Commands Summary

| Task | Command | Description |
|------|---------|-------------|
| **Fetch PRs** | `./scripts/new_gen_raw_dataset_graphql.sh -l [Lang] -s [Stars] -n [N] -o [Dir]` | GraphQL API for fetching PRs |
| **Custom Query** | `./scripts/new_gen_raw_dataset_graphql.sh -q "[query]" -o [Dir] -n [N]` | Custom GitHub search query |
| **Filter Data** | `./scripts/filter_raw_dataset.sh -i [Input] -o [Output] -k [Keywords]` | Filter by keywords/categories |
| **Build Dataset** | `./scripts/unify_repo_scripts.sh [Raw_Dataset]` | Generate test environments |
| **Collect Data** | `./scripts/collect_raw_dataset.sh` | Complete and categorize raw data |
| **Copy Datasets** | `./scripts/copy_raw_dataset.sh [Source] [Target]` | Merge datasets |
| **Extract Training** | `./scripts/extract_training_data.sh [Input] [Output_JSON]` | Format for fine-tuning |
| **Run Patches** | `./scripts/run_patch.sh [Raw_Dataset]` | Generate repair patches |
| **Evaluate** | `./scripts/run_full_pipeline.sh [Raw_Dataset]` | Full evaluation pipeline |
| **Analyze Patches** | `./scripts/analyze_patch.sh [Semgrep_Output]` | Quality check on patches |
| **Format Code** | `make format` | Format Python files |
| **Lint Code** | `make lint` | Run ruff linter |
| **Fix Linting** | `make fix` | Auto-fix linting issues |
| **Clean Cache** | `make clean` | Remove Python cache files |

---

## 📂 Project Structure

### Core Components

```
multi-swe-bench/
├── entry.sh                         # Interactive menu for common operations
├── Makefile                         # Build and development commands
├── setup.py                         # Package configuration
├── config.json                      # Main configuration file
│
├── scripts/                         # High-level entry scripts (29+ files)
│   ├── new_gen_raw_dataset_graphql.sh      # GraphQL API PR fetching
│   ├── filter_raw_dataset.sh                 # Dataset filtering
│   ├── unify_repo_scripts.sh                 # Build evaluation environments
│   ├── run_full_pipeline.sh                  # Complete pipeline runner
│   ├── extract_training_data.sh              # Training data extraction
│   ├── run_evaluation.sh                     # Evaluation runner
│   └── ...
│
├── data_pipeline/                   # Data processing workers
│   ├── Python Scripts:
│   │   ├── new_fetch_prs_graphql.py         # GraphQL PR fetching logic
│   │   ├── fetch_github_repo_gql.py         # GitHub repository fetching
│   │   ├── filter_prs.py                     # PR filtering utilities
│   │   ├── filter_repo.py                    # Repository filtering
│   │   ├── build_dataset.py                  # Dataset building (in harness/)
│   │   ├── get_related_issues.py             # Issue-PR relationship
│   │   ├── merge_prs_with_issues.py          # Data merging
│   │   └── util.py                          # General utilities
│   └── Shell Scripts:
│       ├── gen_instance_from_dataset_*.sh   # Language-specific instance generation
│       ├── gen_all_raw_datasets_new.sh      # Batch dataset generation
│       ├── create_org_dir.sh                # Organization directory setup
│       └── run_*.sh                         # Various runner scripts
│
├── multi_swe_bench/                  # Core Python package
│   ├── collect/                         # Data collection components
│   │   └── new_fetch_prs_graphql.py     # Main GraphQL fetcher
│   ├── harness/                         # Evaluation harness
│   │   ├── build_dataset.py             # Build benchmark instances
│   │   ├── gen_report.py                # Generate evaluation reports
│   │   ├── run_evaluation.py            # Execute tests in Docker
│   │   └── dataset.py                   # Dataset models and utilities
│   └── utils/                           # Shared utilities
│       ├── args_util.py                 # Argument parsing
│       ├── docker_util.py               # Docker operations
│       ├── env_to_dockerfile.py         # Environment to Dockerfile conversion
│       ├── git_util.py                  # Git operations
│       ├── session_util.py              # Session management
│       └── logger.py                    # Logging utilities
│
├── data/                            # Generated data directory
│   ├── raw_datasets/                # Collected GitHub PR data (JSONL format)
│   ├── datasets/                    # Processed benchmark instances
│   ├── repos/                       # Cloned GitHub repositories
│   ├── patches/                     # Generated repair patches
│   ├── logs/                        # Execution and evaluation logs
│   └── workdir/                     # Temporary working directories
│
├── tests/                           # Unit and integration tests
│   ├── test_pr_details.py
│   ├── test_graphql_query.py
│   └── ...
│
├── docs/                            # Additional documentation
│   └── ...
│
└── Documentation Files:
    ├── all_process.md               # Complete pipeline workflow
    ├── Multi-SWE-Bench_Full_Guide.md # Comprehensive user guide
    ├── gen_dataset.md               # Dataset generation instructions
    ├── run_all_pipeline.md         # Pipeline execution guide
    └── sh_functions.md             # Shell function reference
```


## 📜 License

This project is licensed under the Apache License 2.0.

## 📖 Additional Documentation

| Document | Description |
|----------|-------------|
| [all_process.md](all_process.md) | Detailed step-by-step pipeline documentation |
| [Multi-SWE-Bench_Full_Guide.md](Multi-SWE-Bench_Full_Guide.md) | Comprehensive user guide |
| [gen_dataset.md](gen_dataset.md) | Dataset generation guide |
| [Makefile commands](#common-commands-summary) | Development and build commands |

## ⚙️ Configuration

### GitHub Token

Create a GitHub personal access token and save it to `tokens.txt`:
```bash
echo "your_github_token_here" > tokens.txt
chmod 600 tokens.txt
```

### config.json

The main configuration file (`config.json`) contains settings for:
- Model configs (API endpoints, model names)
- Evaluation parameters
- Data collection settings

## 🐛 Troubleshooting

### Docker Issues
- Ensure Docker daemon is running: `docker ps`
- Check disk space: `docker system df`

### GitHub Rate Limits
- For large fetches (>100 repos), consider using multiple tokens
- GraphQL has higher limits than REST API

### Memory Issues
- Limit concurrent jobs in `run_full_pipeline.sh`
- Use `filter_raw_dataset.sh` to reduce dataset size

## 🤝 Contributing

Contributions are welcome! Please follow these guidelines:
1. Format code: `make format`
2. Run linter: `make lint`
3. Add tests for new features
4. Update documentation

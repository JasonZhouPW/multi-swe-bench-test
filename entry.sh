#!/usr/bin/env bash
set -euo pipefail

# ================================================================
# Multi-SWE-Bench Root Entry Script
# ================================================================

# Get the directory where this script is located
PROJ_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$PROJ_ROOT/scripts"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

clear
echo -e "${CYAN}================================================================${NC}"
echo -e "${CYAN}              Multi-SWE-Bench Entry Menu                      ${NC}"
echo -e "${CYAN}================================================================${NC}"
echo -e "Project Root: ${YELLOW}$PROJ_ROOT${NC}"
echo ""

show_menu() {
    echo -e "Please select an option:"
    echo -e "1) ${GREEN}Fetch PRs from GitHub${NC} (GraphQL API)"
    echo -e "2) ${GREEN}Filter Raw Dataset${NC} (Filter records)"
    echo -e "3) ${GREEN}Build Dataset by PRs${NC} (Environment Setup)"
    echo -e "4) ${GREEN}Extract Training Data${NC} (For Fine-tuning)"
    echo -e "5) ${GREEN}Fetch All Raw Datasets${NC} (All Languages)"
    echo -e "q) Exit"
    echo ""
}

while true; do
    show_menu
    read -rep "Selection: " choice

    case $choice in
        1)
            echo -e "\n${YELLOW}--- Option 1: Fetch PRs from GitHub (GraphQL) ---${NC}"
            
            # Default values from the original script logic
            read -rep "Language (default: Rust): " lang
            lang=${lang:-Rust}
            
            read -rep "Min Stars (default: 10000): " stars
            stars=${stars:-10000}
            
            read -rep "Max Results (default: 20): " max_res
            max_res=${max_res:-20}
            
            read -rep "Token Path (default: ./tokens.txt): " token
            token=${token:-./tokens.txt}
            
            read -rep "Merged After (ISO format, e.g., 2025-01-01, optional): " merged_after
            
            read -rep "Keywords (optional): " keywords
            
            read -rep "Custom Query (overrides lang/stars/keywords, optional): " query
            
            read -rep "Output Subdir Name (required): " out_name
            if [ -z "$out_name" ]; then
                echo -e "${RED}Error: Output Subdir Name is required.${NC}"
                continue
            fi

            read -rep "Enter target central directory (default: $PROJ_ROOT/data/raw_datasets): " target_dir
            target_dir=${target_dir:-$PROJ_ROOT/data/raw_datasets}
            
            output_dir="$PROJ_ROOT/data/raw_datasets/$out_name"
            mkdir -p "$output_dir"
            
            # Construct the command
            CMD="bash \"$SCRIPTS_DIR/new_gen_raw_dataset_graphql.sh\" -l \"$lang\" -s \"$stars\" -n \"$max_res\" -t \"$token\" -o \"$output_dir\""
            
            if [ -n "$merged_after" ]; then
                CMD="$CMD -m \"$merged_after\""
            fi
            if [ -n "$keywords" ]; then
                CMD="$CMD -k \"$keywords\""
            fi
            if [ -n "$query" ]; then
                CMD="$CMD -q \"$query\""
            fi
            
            echo -e "${CYAN}Executing: $CMD${NC}"
            eval "$CMD"
            
            # Automatic copy step after fetch
            echo -e "${CYAN}Executing: bash \"$SCRIPTS_DIR/copy_raw_dataset.sh\" \"$output_dir\" \"$target_dir\"${NC}"
            bash "$SCRIPTS_DIR/copy_raw_dataset.sh" "$output_dir" "$target_dir"

            echo -e "\n${GREEN}Fetch and Copy complete.${NC}\n"
            ;;
        2)
            # echo -e "\n${YELLOW}--- Option 2: Filter Raw Dataset ---${NC}"

            # echo -e "Available raw datasets in data/raw_datasets/:"
            # ls "$PROJ_ROOT/data/raw_datasets"/*_raw_dataset.jsonl 2>/dev/null | xargs -n 1 basename | sort
            # echo ""
            read -rep "Enter input directory : " input_dir

            if [ "$input_dir" = "list" ]; then
                input_dir="$PROJ_ROOT/data/raw_datasets/all_raw_datasets"
            else
                if [ ! -d "$input_dir" ]; then
                    echo -e "${RED}Error: Directory not found: $input_dir${NC}"
                    continue
                fi
            fi

            read -rep "Enter output directory name: " output_name
            output_dir="$PROJ_ROOT/$output_name"

            mkdir -p "$output_dir"

            echo -e "${CYAN}Please specify filter options:${NC}"
            read -rep "Keywords (comma-separated, optional): " keywords
            read -rep "Categories (comma-separated, optional): " categories
            read -rep "Match mode (any/all, default: any): " match_mode
            match_mode=${match_mode:-any}
            read -rep "Min fix patch size (bytes, default: 0): " min_patch_size
            min_patch_size=${min_patch_size:-0}
            read -rep "Min test patch size (bytes, default: 0): " min_test_patch_size
            min_test_patch_size=${min_test_patch_size:-0}

            CMD="bash \"$SCRIPTS_DIR/filter_raw_dataset.sh\" -i \"$input_dir\" -o \"$output_dir\""

            if [ -n "$keywords" ]; then
                CMD="$CMD -k \"$keywords\""
            fi
            if [ -n "$categories" ]; then
                CMD="$CMD -c \"$categories\""
            fi
            if [ -n "$match_mode" ] && [ "$match_mode" != "any" ]; then
                CMD="$CMD -m \"$match_mode\""
            fi
            if [ "$min_patch_size" -gt 0 ]; then
                CMD="$CMD -p \"$min_patch_size\""
            fi
            if [ "$min_test_patch_size" -gt 0 ]; then
                CMD="$CMD -pt \"$min_test_patch_size\""
            fi

            echo -e "${CYAN}Executing: $CMD${NC}"
            eval "$CMD"

            echo -e "\n${GREEN}Filter complete. Results saved to: $output_dir${NC}\n"
            ;;
        3)
            echo -e "\n${YELLOW}--- Option 3: Build Dataset by PRs ---${NC}"
            # echo -e "Available raw datasets in data/raw_datasets/:"
            # ls "$PROJ_ROOT/data/raw_datasets"/*_raw_dataset.jsonl 2>/dev/null | xargs -n 1 basename | sort
            # echo ""
            read -rep "Enter relative path to raw dataset (or directory): " ds_path
            
            full_ds_path="$PROJ_ROOT/$ds_path"
            if [ ! -e "$full_ds_path" ] && [ -e "$PROJ_ROOT/$ds_path" ]; then
                full_ds_path="$PROJ_ROOT/$ds_path"
            fi

            echo -e "${CYAN}Executing: ./scripts/unify_repo_scripts.sh $full_ds_path${NC}"
            bash "$SCRIPTS_DIR/unify_repo_scripts.sh" "$full_ds_path"
            echo -e "\n${GREEN}Build complete.${NC}\n"
            ;;
        4)
            echo -e "\n${YELLOW}--- Option 4: Extract Training Data ---${NC}"
            read -rep "Input path (file or dir): " input_path
            read -rep "Output file name (e.g., my_training_data.json): " output_file
            
            full_output_path="$PROJ_ROOT/data/$output_file"
            
            echo -e "${CYAN}Executing: ./scripts/extract_training_data.sh $input_path $full_output_path${NC}"
            bash "$SCRIPTS_DIR/extract_training_data.sh" "$input_path" "$full_output_path"
            echo -e "\n${GREEN}Extraction complete. Result saved to: $full_output_path${NC}\n"
            ;;
        5)
            echo -e "\n${YELLOW}--- Option 5: Fetch All Raw Datasets (All Languages) ---${NC}"
            
            # Define languages array
            LANGUAGES=("Go" "Java" "Python" "Rust" "JavaScript" "TypeScript" "C" "C++")
            
            read -rep "Output directory (required): " output_dir
            if [ -z "$output_dir" ]; then
                echo -e "${RED}Error: Output directory is required.${NC}"
                continue
            fi
            
            read -rep "Merged After (ISO format, e.g., 2025-01-01, required): " merged_after
            if [ -z "$merged_after" ]; then
                echo -e "${RED}Error: Merged After date is required.${NC}"
                continue
            fi
            
            read -rep "Max Results per language (default: 20): " max_results
            max_results=${max_results:-20}
            
            mkdir -p "$output_dir"
            
            echo -e "\n${CYAN}Will fetch raw datasets for ${#LANGUAGES[@]} languages:${NC}"
            printf '  - %s\n' "${LANGUAGES[@]}"
            echo ""
            
            for lang in "${LANGUAGES[@]}"; do
                lang_output_dir="$output_dir/$lang"
                mkdir -p "$lang_output_dir"
                
                echo -e "\n${CYAN}[$lang] Fetching raw dataset...${NC}"
                
                CMD="bash \"$SCRIPTS_DIR/new_gen_raw_dataset_graphql.sh\" -l \"$lang\" -o \"$lang_output_dir\" -m \"$merged_after\" -n \"$max_results\""
                echo -e "${CYAN}Executing: $CMD${NC}"
                
                if eval "$CMD"; then
                    echo -e "${GREEN}[$lang] Completed successfully.${NC}"
                else
                    echo -e "${RED}[$lang] Failed. Continuing with next language...${NC}"
                fi
            done
            
            echo -e "\n${GREEN}Fetch all raw datasets complete.${NC}"
            echo -e "Results saved to: $output_dir"
            echo -e "Subdirectories: ${LANGUAGES[*]}\n"
            ;;
        q|Q)
            echo -e "${YELLOW}Exiting. Goodbye!${NC}"
            exit 0
            ;;
        *)
            echo -e "${RED}Invalid selection.${NC}\n"
            ;;
    esac
done

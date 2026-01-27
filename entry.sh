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
    echo -e "2) ${GREEN}Build Dataset by PRs${NC} (Environment Setup)"
    echo -e "3) ${GREEN}Extract Training Data${NC} (For Fine-tuning)"
    echo -e "q) Exit"
    echo ""
}

while true; do
    show_menu
    read -rp "Selection: " choice

    case $choice in
        1)
            echo -e "\n${YELLOW}--- Option 1: Fetch PRs from GitHub (GraphQL) ---${NC}"
            
            # Default values from the original script logic
            read -rp "Language (default: Rust): " lang
            lang=${lang:-Rust}
            
            read -rp "Min Stars (default: 10000): " stars
            stars=${stars:-10000}
            
            read -rp "Max Results (default: 20): " max_res
            max_res=${max_res:-20}
            
            read -rp "Token Path (default: ./tokens.txt): " token
            token=${token:-./tokens.txt}
            
            read -rp "Merged After (ISO format, e.g., 2025-01-01, optional): " merged_after
            
            read -rp "Keywords (optional): " keywords
            
            read -rp "Custom Query (overrides lang/stars/keywords, optional): " query
            
            read -rp "Output Subdir Name (required): " out_name
            if [ -z "$out_name" ]; then
                echo -e "${RED}Error: Output Subdir Name is required.${NC}"
                continue
            fi

            read -rp "Enter target central directory (default: $PROJ_ROOT/data/raw_datasets): " target_dir
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
            echo -e "\n${YELLOW}--- Option 2: Build Dataset by PRs ---${NC}"
            echo -e "Available raw datasets in data/raw_datasets/:"
            find "$PROJ_ROOT/data/raw_datasets" -name "*_raw_dataset.jsonl" -printf "%P\n" | sort
            echo ""
            read -rp "Enter relative path to raw dataset (or directory): " ds_path
            
            full_ds_path="$PROJ_ROOT/data/raw_datasets/$ds_path"
            if [ ! -e "$full_ds_path" ] && [ -e "$PROJ_ROOT/$ds_path" ]; then
                full_ds_path="$PROJ_ROOT/$ds_path"
            fi

            echo -e "${CYAN}Executing: ./scripts/unify_repo_scripts.sh $full_ds_path${NC}"
            bash "$SCRIPTS_DIR/unify_repo_scripts.sh" "$full_ds_path"
            echo -e "\n${GREEN}Build complete.${NC}\n"
            ;;
        3)
            echo -e "\n${YELLOW}--- Option 3: Extract Training Data ---${NC}"
            read -rp "Input path (file or dir): " input_path
            read -rp "Output file name (e.g., my_training_data.json): " output_file
            
            full_output_path="$PROJ_ROOT/data/$output_file"
            
            echo -e "${CYAN}Executing: ./scripts/extract_training_data.sh $input_path $full_output_path${NC}"
            bash "$SCRIPTS_DIR/extract_training_data.sh" "$input_path" "$full_output_path"
            echo -e "\n${GREEN}Extraction complete. Result saved to: $full_output_path${NC}\n"
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

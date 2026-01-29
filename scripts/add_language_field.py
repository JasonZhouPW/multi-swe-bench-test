import json
import os
import argparse
from collections import OrderedDict

def process_file(file_path, language):
    print(f"Processing {file_path} for language {language}...")
    temp_file_path = file_path + ".tmp"
    
    with open(file_path, 'r', encoding='utf-8') as f_in, \
         open(temp_file_path, 'w', encoding='utf-8') as f_out:
        for line in f_in:
            if not line.strip():
                continue
            try:
                # Load JSON and preserve order
                data = json.loads(line, object_pairs_hook=OrderedDict)
                
                # Create a new OrderedDict to ensure the order: org, repo, language, ...
                new_data = OrderedDict()
                for key, value in data.items():
                    new_data[key] = value
                    if key == "repo":
                        new_data["language"] = language
                
                # If "repo" wasn't found (shouldn't happen based on format), just add it
                if "language" not in new_data:
                    new_data["language"] = language
                
                f_out.write(json.dumps(new_data, ensure_ascii=False) + "\n")
            except json.JSONDecodeError as e:
                print(f"Error parsing line in {file_path}: {e}")
                continue

    # Replace original file with temporary file
    os.replace(temp_file_path, file_path)
    print(f"Finished processing {file_path}")

def main():
    parser = argparse.ArgumentParser(description="Add language field to JSONL files.")
    parser.add_argument("-d", "--dir", required=True, help="Directory containing JSONL files.")
    parser.add_argument("-l", "--language", required=True, help="Language value to add.")
    
    args = parser.parse_args()

    target_dir = os.path.abspath(args.dir)
    if not os.path.exists(target_dir):
        print(f"Directory {target_dir} not found.")
        return

    for filename in os.listdir(target_dir):
        if filename.endswith(".jsonl"):
            file_path = os.path.join(target_dir, filename)
            process_file(file_path, args.language)

if __name__ == "__main__":
    main()

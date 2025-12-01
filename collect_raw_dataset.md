
## Collect Raw Datasets

```bash
#!/bin/bash
set -e

ROOT_DIR="data/raw_datasets/catchorg__Catch5"
OUTPUT_DIR="data/raw_datasets/all_raw_datasets"

echo "Collecting *_raw_dataset.jsonl from $ROOT_DIR ..."
mkdir -p "$OUTPUT_DIR"

find "$ROOT_DIR" -type f -name "*_raw_dataset.jsonl" | while read -r FILE; do
    DIR_NAME=$(basename "$(dirname "$FILE")")

    BASE_FILE=$(basename "$FILE")

    NEW_FILE="${DIR_NAME}__${BASE_FILE}"

    echo "Copy: $FILE -> $OUTPUT_DIR/$NEW_FILE"
    cp "$FILE" "$OUTPUT_DIR/$NEW_FILE"
done

echo "Done! All raw_dataset.jsonl have been collected into $OUTPUT_DIR"

```

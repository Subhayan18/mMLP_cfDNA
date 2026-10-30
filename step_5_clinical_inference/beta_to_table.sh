#!/bin/bash
# Extract block-level beta values from a set of .beta files with wgbstools beta_to_table
# Usage: bash run_beta_to_table.sh -k BLOCKS_BED -i BETA_DIR -o OUTPUT_TSV [-m MIN_COV] [-t THREADS]

module load Anaconda3/2024.02-1
module load GCC/12.3.0 SAMtools/1.18 parallel/20230722
conda activate wgbstools

WGBSTOOLS="/.../wgbstools"
MIN_COV=4
THREADS=8

while getopts ":k:i:o:m:t:" opt; do
    case $opt in
        k) BLOCKS_BED="$OPTARG" ;;
        i) BETA_DIR="$OPTARG" ;;
        o) OUTPUT_TSV="$OPTARG" ;;
        m) MIN_COV="$OPTARG" ;;
        t) THREADS="$OPTARG" ;;
        *) echo "Usage: $0 -k BLOCKS_BED -i BETA_DIR -o OUTPUT_TSV [-m MIN_COV] [-t THREADS]"; exit 1 ;;
    esac
done

[[ -z "$BLOCKS_BED" || -z "$BETA_DIR" || -z "$OUTPUT_TSV" ]] && { echo "ERROR: -k, -i and -o are required"; exit 1; }

mapfile -t BETAS < <(find "$BETA_DIR" -name "*.beta" | sort)
[[ ${#BETAS[@]} -eq 0 ]] && { echo "ERROR: no .beta files in $BETA_DIR"; exit 1; }
echo "${#BETAS[@]} beta files, min_cov=$MIN_COV"

mkdir -p "$(dirname "$OUTPUT_TSV")"
"$WGBSTOOLS" beta_to_table "$BLOCKS_BED" --betas "${BETAS[@]}" \
    --min_cov "$MIN_COV" --threads "$THREADS" > "$OUTPUT_TSV" || { echo "beta_to_table failed"; exit 1; }

echo "Done: $(($(wc -l < "$OUTPUT_TSV") - 1)) blocks x $(($(head -1 "$OUTPUT_TSV" | awk -F'\t' '{print NF}') - 5)) samples -> $OUTPUT_TSV"

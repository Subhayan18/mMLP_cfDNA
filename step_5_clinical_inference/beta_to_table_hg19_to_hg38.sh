#!/bin/bash
# Extract block beta values from hg19 .beta files and report them on hg38 blocks
# BLOCKS_BED: hg38 blocks in model order (chr start end startCpG endCpG); defines output rows
# LINK_BED columns: chr hg38_start hg38_end hg19_start hg19_end hg38_startCpG hg38_endCpG
# Usage: bash beta_to_table_hg19_to_hg38.sh -k BLOCKS_BED -l LINK_BED -i BETA_DIR -o OUTPUT_TSV [-m MIN_COV] [-t THREADS]

module load Anaconda3/2024.02-1
module load GCC/12.3.0 SAMtools/1.18 parallel/20230722
conda activate wgbstools
set -o pipefail

WGBSTOOLS="/.../wgbstools"
MIN_COV=4
THREADS=8

while getopts ":k:l:i:o:m:t:" opt; do
    case $opt in
        k) BLOCKS_BED="$OPTARG" ;;
        l) LINK_BED="$OPTARG" ;;
        i) BETA_DIR="$OPTARG" ;;
        o) OUTPUT_TSV="$OPTARG" ;;
        m) MIN_COV="$OPTARG" ;;
        t) THREADS="$OPTARG" ;;
        *) echo "Usage: $0 -k BLOCKS_BED -l LINK_BED -i BETA_DIR -o OUTPUT_TSV [-m MIN_COV] [-t THREADS]"; exit 1 ;;
    esac
done

[[ -z "$BLOCKS_BED" || -z "$LINK_BED" || -z "$BETA_DIR" || -z "$OUTPUT_TSV" ]] && { echo "ERROR: -k, -l, -i and -o are required"; exit 1; }

mkdir -p "$(dirname "$OUTPUT_TSV")"
PREFIX="${OUTPUT_TSV%.tsv}"
HG19_BED="${PREFIX}.hg19_blocks.bed"
HG19_TSV="${PREFIX}.hg19.tsv"

# 1. hg19 coordinates -> hg19 CpG indices (blocks that failed liftover are skipped)
awk 'BEGIN{OFS="\t"} $4 ~ /^[0-9]+$/ && $5 ~ /^[0-9]+$/ {print $1,$4,$5}' "$LINK_BED" \
    | sort -k1,1 -k2,2n -u > "${PREFIX}.hg19_coords.bed"
"$WGBSTOOLS" convert --genome hg19 -L "${PREFIX}.hg19_coords.bed" \
    | awk 'BEGIN{OFS="\t"} $4 ~ /^[0-9]+$/ && $5 > $4 {print $1,$2,$3,$4,$5}' \
    | sort -k4,4n > "$HG19_BED" || { echo "convert failed"; exit 1; }
rm "${PREFIX}.hg19_coords.bed"
echo "$(wc -l < "$LINK_BED") hg38 blocks, $(wc -l < "$HG19_BED") with hg19 CpG indices"

# 2. Extract beta values on hg19 blocks
mapfile -t BETAS < <(find "$BETA_DIR" -name "*.beta" | sort)
[[ ${#BETAS[@]} -eq 0 ]] && { echo "ERROR: no .beta files in $BETA_DIR"; exit 1; }
echo "${#BETAS[@]} beta files, min_cov=$MIN_COV"
"$WGBSTOOLS" beta_to_table "$HG19_BED" --betas "${BETAS[@]}" \
    --min_cov "$MIN_COV" --threads "$THREADS" > "$HG19_TSV" || { echo "beta_to_table failed"; exit 1; }

# 3. Map back to hg38 blocks, in BLOCKS_BED order (blocks absent from link or unmapped -> NA)
python - "$BLOCKS_BED" "$LINK_BED" "$HG19_TSV" "$OUTPUT_TSV" <<'EOF'
import sys, pandas as pd
blocks, link, tab, out = sys.argv[1:]
B = pd.read_csv(blocks, sep='\t', header=None, usecols=range(5), dtype=str,
                names=['chr', 'start', 'end', 'startCpG', 'endCpG'])
B[['start', 'end']] = B[['start', 'end']].astype(int)
L = pd.read_csv(link, sep='\t', header=None, usecols=range(5),
                names=['chr', 'start', 'end', 's19', 'e19'])
L[['s19', 'e19']] = L[['s19', 'e19']].apply(pd.to_numeric, errors='coerce').astype('Int64')
T = pd.read_csv(tab, sep='\t')
samples = list(T.columns[5:])
T = T.iloc[:, [0, 1, 2] + list(range(5, T.shape[1]))]
T.columns = ['chr', 's19', 'e19'] + samples
T[['s19', 'e19']] = T[['s19', 'e19']].astype('Int64')
M = (B.merge(L.drop_duplicates(['chr', 'start', 'end']), on=['chr', 'start', 'end'], how='left')
       .merge(T.drop_duplicates(['chr', 's19', 'e19']), on=['chr', 's19', 'e19'], how='left'))
M[['chr', 'start', 'end', 'startCpG', 'endCpG'] + samples].to_csv(out, sep='\t', index=False, na_rep='NA')
print(f"{len(M)} hg38 blocks ({M.s19.notna().sum()} with hg19 coordinates) x {len(samples)} samples, "
      f"{M[samples].notna().any(axis=1).sum()} blocks with data in >=1 sample -> {out}")
EOF

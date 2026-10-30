#!/bin/bash
# .beta files -> block table -> coverage QC -> PASS/WARN samples -> model input (HDF5) + short QC report
# Usage: bash 01_wrapper_beta_to_hdf5.sh -i BETA_DIR -g hg19|hg38 -o OUT_DIR [-m MIN_COV] [-t THREADS]

set -eo pipefail
module load Anaconda3/2024.02-1
conda activate wgbstools

SCRIPTS="$(cd "$(dirname "$0")" && pwd)"
BLOCKS_HG38="/.../TWIST_blocks.bed"
LINK_HG19="/.../TWIST_blocks_hg38_hg19.bed"
MIN_COV=4
THREADS=8

while getopts ":i:g:o:m:t:" opt; do
    case $opt in
        i) BETA_DIR="$OPTARG" ;;
        g) GENOME="$OPTARG" ;;
        o) OUT="$OPTARG" ;;
        m) MIN_COV="$OPTARG" ;;
        t) THREADS="$OPTARG" ;;
        *) echo "Usage: $0 -i BETA_DIR -g hg19|hg38 -o OUT_DIR [-m MIN_COV] [-t THREADS]"; exit 1 ;;
    esac
done
[[ -z "$BETA_DIR" || -z "$OUT" ]] && { echo "ERROR: -i and -o are required"; exit 1; }
[[ "$GENOME" != "hg19" && "$GENOME" != "hg38" ]] && { echo "ERROR: -g must be hg19 or hg38"; exit 1; }
mkdir -p "$OUT"

# 1. Block extraction (always reported on hg38 blocks)
echo "== 1. beta_to_table ($GENOME)"
if [[ "$GENOME" == "hg38" ]]; then
    bash "$SCRIPTS/beta_to_table.sh" -k "$BLOCKS_HG38" -i "$BETA_DIR" -o "$OUT/BETA_all.tsv" -m "$MIN_COV" -t "$THREADS"
    COV_BLOCKS="$BLOCKS_HG38"
else
    bash "$SCRIPTS/beta_to_table_hg19_to_hg38.sh" -k "$BLOCKS_HG38" -l "$LINK_HG19" -i "$BETA_DIR" -o "$OUT/BETA_all.tsv" -m "$MIN_COV" -t "$THREADS"
    COV_BLOCKS="$OUT/BETA_all.hg19_blocks.bed"
fi

# 2. Coverage statistics (on the genome the .beta files are in)
echo "== 2. coverage stats"
python "$SCRIPTS/beta_coverage_stats.py" --blocks "$COV_BLOCKS" --beta_dir "$BETA_DIR" \
    --output "$OUT/coverage_stats.csv" --min_cov "$MIN_COV" --threads "$THREADS"

# 3. PASS / WARN / FAIL
echo "== 3. coverage QC"
python "$SCRIPTS/flag_coverage_qc.py" --input "$OUT/coverage_stats.csv" --output "$OUT/coverage_stats_qc.csv"

# 4. Keep non-FAIL samples + QC report
echo "== 4. sample selection"
python - "$OUT" "$BETA_DIR" "$GENOME" <<'EOF'
import sys, datetime, pandas as pd
out, beta_dir, genome = sys.argv[1:]
qc = pd.read_csv(f'{out}/coverage_stats_qc.csv')
t = pd.read_csv(f'{out}/BETA_all.tsv', sep='\t')
keep = set(qc.loc[qc.qc_status != 'FAIL', 'sample'])
cols = [c for c in t.columns[5:] if c in keep]
missing = sorted(keep - set(t.columns))
if not cols:
    sys.exit('ERROR: no QC-passing sample names found in BETA_all.tsv header')
t[list(t.columns[:5]) + cols].to_csv(f'{out}/BETA_qc.tsv', sep='\t', index=False, na_rep='NA')

m = ['panel_mean_depth', 'blocks_pass_min_cov_pct', 'blocks_depth_ge10_pct']
q = qc[m].quantile([0, .5, 1]).T.round(2)
q.columns = ['min', 'median', 'max']
fails = qc.loc[qc.qc_status == 'FAIL', ['sample', 'qc_reason']]
with open(f'{out}/qc_report.txt', 'w') as f:
    f.write(f"QC report  {datetime.date.today()}\ninput: {beta_dir} ({genome})\n\n")
    f.write(f"samples: {len(qc)}  " + "  ".join(f"{k}: {v}" for k, v in qc.qc_status.value_counts().items()) + "\n")
    f.write(f"to model: {len(cols)}  (QC names not in table: {len(missing)})\n")
    f.write(f"hg38 blocks with data in >=1 sample: {t.iloc[:, 5:].notna().any(axis=1).sum()} / {len(t)}\n\n")
    f.write(q.to_string() + "\n\n")
    f.write("FAIL:\n" + (fails.to_string(index=False) if len(fails) else "none") + "\n")
print(open(f'{out}/qc_report.txt').read())
EOF

# 5. Model input
echo "== 5. convert to HDF5"
conda activate base
python "$SCRIPTS/convert_beta_to_input.py" --input_tsv "$OUT/BETA_qc.tsv" --output_h5 "$OUT/samples.h5" \
    --simulation_method probabilistic --n_simulated_reads 10 --verbose

echo "Done: $OUT/samples.h5, $OUT/samples.csv, $OUT/qc_report.txt"

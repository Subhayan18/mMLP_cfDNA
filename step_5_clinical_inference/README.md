# Step 5: Clinical Inference

Converts a directory of WGBS `.beta` files (hg19 or hg38) into model input, with coverage QC, and runs tissue deconvolution. Usage is described in the main README (Implementation).

| Script | Step | Purpose |
|---|---|---|
| `run_pipeline.sh` | 1-5 | Wrapper |
| `beta_to_table.sh` | 1 | Block extraction, hg38 `.beta` |
| `beta_to_table_hg19_to_hg38.sh` | 1 | Block extraction, hg19 `.beta`, reported on hg38 blocks |
| `beta_coverage_stats.py` | 2 | Per-sample coverage statistics |
| `flag_coverage_qc.py` | 3 | PASS / WARN / FAIL flags |
| `convert_beta_to_input.py` | 5 | TSV to HDF5 |
| `Run_pdac_inference.py` | 6 | Inference |

Supporting files: `tissue_names.txt`, `model_deconvolution.py`, `TWIST_blocks.bed`, `TWIST_blocks_hg38_hg19.bed`.

## Steps

1. **Block extraction:** `wgbstools beta_to_table` on the hg38 panel blocks. For hg19 input, blocks are located via the link file, extracted on hg19 and mapped back to hg38 blocks, so output rows always match `TWIST_blocks.bed`.
2. **Coverage statistics:** genome and panel mean depth, % panel CpGs covered, median observations per block, % blocks passing the minimum coverage, % blocks with depth of at least 1x and 10x.
3. **QC:** FAIL if fewer than 25% of blocks pass or panel mean depth is under 0.5x; WARN if below cohort Q1 - 1.5 IQR; otherwise PASS. Thresholds are `--min_blocks_pct` and `--min_depth` in `flag_coverage_qc.py`.
4. **Sample selection:** FAIL samples dropped, `qc_report.txt` written.
5. **Conversion:** `convert_beta_to_input.py`, probabilistic read simulation (10 reads per block).
6. **Inference:** `Run_pdac_inference.py` with optional renormalisation.

## Model input and output

```
Input:  [batch, regions, 150]   0 unmethylated, 1 methylated, 2 missing
mean per region -> projection (512) -> MLP -> 22 -> sigmoid + L1 normalisation
Output: sample_name, Adipocytes, Aorta, Bladder, Blood, ...   (22 proportions, sum 1)
```

Tissues: Adipocytes, Aorta, Bladder, Blood, Bone, Cerebellum, Colon, Coronary, Cortex, Dermal, Epidermal, Gastric, Heart, Kidney, Liver, Lung, Neuron, Oligodendrocytes, Pancreas, Prostate, Skeletal, Small (intestine).

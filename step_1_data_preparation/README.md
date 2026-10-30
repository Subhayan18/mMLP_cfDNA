# Step 1: Data Preparation

Builds the panel-specific, read-level training set from the Loyfer atlas.

| Substep | Input | Output |
|---|---|---|
| 1.1 Panel regions | Loyfer `.beta` files, panel BED | `TWIST_blocks.bed`, `panel_beta_matrix.tsv` |
| 1.2 Simulated reads | `panel_beta_matrix.tsv` | One NPZ of synthetic reads per sample |
| 1.3 Sequence context | `TWIST_blocks.bed`, hg38 | FASTA and 3-mer tokens |
| 1.4 Training dataset | 1.1-1.3 outputs | NPZ per sample and augmentation, `metadata.csv` |
| 1.5 Cleaning, synthetics, splits | 1.4 outputs | `combined_metadata.csv`, `data_splits/` |

## 1.1 Panel regions

```bash
wgbstools convert --bed <PANEL_BED> --genome hg38 --output TWIST_blocks.bed
wgbstools beta_to_table TWIST_blocks.bed --betas <BETA_DIR>/*.beta \
  --output panel_beta_matrix.tsv --min_cov 4 --threads 8
```

## 1.2 Simulated reads

`01_inspect_data.py` validates the input, `02_simulate_reads.py` simulates 500 150 bp reads per region from the block beta with 5% flip noise, `03_verify_output.py` checks the output. `run_step1.2.sh` runs all three.

## 1.3 Sequence and 3-mers

```bash
python step1.3_extract_sequences_and_tokenize.py --bed TWIST_blocks.bed --fasta hg38.fa.gz \
  --output-dir ./step1.3_output --output-prefix TWIST_panel_sequences
```

Writes a FASTA and a tab-separated 3-mer file (64 3-mers plus 5 special tokens).

## 1.4 Training dataset

`create_training_dataset.py` (settings in `config.py`) writes one NPZ per sample and augmentation with `dna_tokens`, `methylation`, `tissue_label`, `region_ids`, `n_reads`, `sample_name`, `tissue_name`.

| Version | Coverage | Jitter |
|---|---|---|
| aug0 | 500x | none |
| aug1-aug4 | 100x, 50x, 30x, 10x | +/-5% |

## 1.5 Cleaning, synthetics, splits

1. `update_metadata_tissues.py`: collapses tissue subtypes to 22 tissues (`updated_metadata.csv`, `tissue_index_mapping.csv`).
2. `generate_synthetic_samples_binary.py`: tops up tissues with fewer than 4 samples using spatially correlated binary flip noise (10% default), validated against the source sample (`synthetic_samples/`, `combined_metadata.csv`, `validation_results.csv`).
3. `split_train_val_test.py`: sample-level 70/15/15 split, stratified by tissue (`data_splits/`).
4. `validate_final_data.py`: integrity, split and loading checks.

# mMLP: cfDNA Tissue-of-Origin Deconvolution

Estimates tissue proportions in cell-free DNA from targeted methylation data, to detect tissue damage from pre-metastatic disease in pancreatic ductal adenocarcinoma (PDAC).

**Hypothesis:** micrometastases damage distant organs (liver, lung, brain, bone) before they are visible on imaging. The damaged tissue releases cfDNA carrying its own methylation pattern, so the tissue-of-origin profile of plasma cfDNA can flag the damage early.

## Pipeline

| Step | Folder | Output |
|---|---|---|
| 1. Data preparation | [step_1_data_preparation](step_1_data_preparation/README.md) | Read-level training set, synthetic rare-tissue samples, train/val/test splits |
| 2. Data format and loading | [step_2_model_architecture](step_2_model_architecture/README.md) | HDF5 dataset, dataloader, architecture decision |
| 3. Single-tissue training | [step_3_model_training](step_3_model_training/README.md) | File-level MLP tissue classifier |
| 4. Mixture deconvolution | [step_4_mixture_augmentation](step_4_mixture_augmentation/README.md) | Proportion model, renormalization, blood-masked Stage 2 |
| 5. Clinical inference | [step_5_clinical_inference](step_5_clinical_inference/README.md) | `.beta` files to tissue proportions with coverage QC |

## Data

- **Reference:** Loyfer WGBS atlas (39 cell types), collapsed to **22 broad tissues**.
- **Panel:** custom TWIST capture panel, annotated with CpG blocks.
- **Training files:** one NPZ per sample and augmentation, holding all panel regions (`dna_tokens` and `methylation` per region and 150 positions; methylation 0 = unmethylated, 1 = methylated, 2 = no CpG).
- **Augmentation:** five coverage levels per sample (500x, 100x, 50x, 30x, 10x).
- **Rare tissues:** tissues with fewer than 4 samples were supplemented with synthetic samples (flip-based noise, validated against the source sample).
- **Splits:** by sample, about 70/15/15, stratified by tissue.

## Model

File-level MLP. The per-region mean methylation vector is projected to 512 dimensions, passed through a three-layer MLP (BatchNorm, ReLU, dropout) and a linear head, about 27M parameters.

| Task | Output | Loss |
|---|---|---|
| Single-tissue classification | softmax over 22 tissues | cross-entropy, label smoothing 0.1 |
| Mixture deconvolution | sigmoid + L1 normalisation, 22 proportions | MSE |

## Results

Single-tissue classification (validation accuracy): chr1 only 93.3%, full genome **97.8%**. Logistic regression on region means: 91-93%.

Mixture deconvolution (held-out synthetic mixtures):

| Model | Test MAE | R² | Pearson r |
|---|---|---|---|
| Phase 1: 2-tissue | 2.8% | 0.88 | 0.96 |
| Phase 2: 3-5 tissues | 2.6% | 0.87 | 0.94 |
| Phase 3: realistic, raw | 3.0% | 0.85 | 0.96 |
| Phase 3: threshold 1% | 1.3% | 0.94 | 0.98 |

## Implementation

Run the trained model on your own WGBS `.beta` files. Everything below is implemented in [step_5_clinical_inference](step_5_clinical_inference/README.md); the commands are copy-paste ready once the paths are set.
mMLP will also accept SeSaMe beta .tsv files but may require some modifications.

### 1. Dependencies

On an LMOD cluster, load everything with `source step_2_model_architecture/LMOD.sourceme`. 

**IMPORTANT!** Modify the `LMOD.sourcme` with corresponding dependancies as this will be called by inference scripts.

| Dependency | Version |
|---|---|
| GCC | 12.3.0 |
| OpenMPI | 4.1.5 |
| CUDA-Python | 12.1.0 (CUDA 12.1.1) |
| PyTorch | 2.1.2 |
| Transformers | 4.39.3 |
| TensorBoard | 2.15.1 |
| SciPy-bundle (NumPy, SciPy, pandas) | 2023.07 |
| matplotlib | 3.7.2 |
| scikit-learn | 1.3.1 |
| h5py | 3.9.0 |
| Python | 3.11.3 |
| Seaborn | 0.13.2 |

Additionally, [wgbstools](https://github.com/nloyfer/wgbs_tools) in a conda environment named `wgbstools` (block extraction and QC), with hg38 initialised (and hg19 if your `.beta` files are hg19). Conversion to model input runs in the base environment, which needs `h5py`. A GPU is recommended; `--device cpu` also works.

### 2. Get the code and checkpoint

```bash
git clone https://github.com/Subhayan18/mMLP_cfDNA.git
cd mMLP_cfDNA/step_5_clinical_inference
```

Download the trained checkpoint and .bed files from Zenodo, DOI [10.5281/zenodo.23732978](https://doi.org/10.5281/zenodo.23732978), and point `--checkpoint` at the `checkpoint_best.pt` it contains.

Files needed in `step_5_clinical_inference` (paths are set at the top of `run_pipeline.sh`):

| File | Purpose |
|---|---|
| `TWIST_blocks.bed` | hg38 panel blocks: `chr start end startCpG endCpG` |
| `TWIST_blocks_hg38_hg19.bed` | hg38 to hg19 link (hg19 input only): `chr hg38_start hg38_end hg19_start hg19_end hg38_startCpG hg38_endCpG` |
| `tissue_names.txt` | the 22 tissue names, in model output order |
| `model_deconvolution.py` | model definition (required) |

### 3. Build the model input from `.beta` files

One wrapper runs block extraction, coverage statistics, QC, sample selection and conversion:

```bash
bash run_pipeline.sh -i /path/to/beta_dir -g hg19 -o /path/to/out
```

| Flag | Meaning |
|---|---|
| `-i` | parent directory, searched recursively for `*.beta` |
| `-g` | `hg19` or `hg38`: genome of the `.beta` files |
| `-o` | output directory |
| `-m` | minimum site observations per block (default 4) |
| `-t` | threads (default 8) |

Run with `bash`, not `sh`. The wrapper stops at the first failing step. Samples failing coverage QC (under 25% of blocks passing `-m`, or panel mean depth under 0.5x) are dropped; samples below cohort Q1 minus 1.5 IQR are kept with a WARN. Outputs in `/path/to/out`:

| File | Content |
|---|---|
| `BETA_all.tsv` | beta values, all samples, hg38 blocks |
| `coverage_stats.csv`, `coverage_stats_qc.csv` | per-sample coverage, and the same with `qc_status` / `qc_reason` |
| `BETA_qc.tsv` | beta values for non-FAIL samples |
| `qc_report.txt` | PASS / WARN / FAIL counts and reasons |
| `samples.h5`, `samples.csv` | model input and sample metadata |

### 4. Beta TSV format and conversion to model input

If you already have a beta table, you can skip the wrapper and convert it directly. The TSV is tab-separated, one row per hg38 panel block, in the same order as `TWIST_blocks.bed`:

```
chr    start    end      startCpG  endCpG   Sample1  Sample2
chr1   273778   273898   2782      2784     0.51     0.66
chr1   642988   643382   6127      6130     0.85     NA
```

The first five columns are block coordinates and CpG indices; every further column is one sample with beta values from 0 to 1, or `NA` for blocks below the coverage floor.

```bash
python convert_beta_to_input.py \
  --input_tsv /path/to/out/BETA_qc.tsv \
  --output_h5 /path/to/out/samples.h5 \
  --output_metadata /path/to/out/samples.csv \
  --simulation_method probabilistic --n_simulated_reads 10
```

| Option | Default | Meaning |
|---|---|---|
| `--input_tsv` | required | beta TSV as above |
| `--output_h5` | required | model input |
| `--output_metadata` | h5 name with `.csv` | per-sample metadata |
| `--simulation_method` | `probabilistic` | `probabilistic`: simulate reads per block, majority vote; `binary`: threshold at 0.5 (quick tests); `replicate`: spread methylation uniformly |
| `--n_simulated_reads` | 10 | reads per block for `probabilistic` |
| `--seq_length` | 150 | positions per region |
| `--n_regions` | 51089 | expected regions (adjusted to the TSV) |
| `--verbose` | off | progress output |

Output format:

```
samples.h5
  methylation  [n_samples, n_regions, 150]  int8, gzip level 4
               0 = unmethylated, 1 = methylated, 2 = missing
samples.csv
  sample_idx,sample_name,n_regions,seq_length,methylation_pct,missing_pct
```

The model averages each region over its non-missing positions. A block that is fully missing becomes 0% methylated, indistinguishable from unmethylated, so watch `missing_pct`.

### 5. Run inference

```bash
python Run_pdac_inference.py \
  --input_h5 /path/to/out/samples.h5 \
  --input_metadata /path/to/out/samples.csv \
  --checkpoint /path/to/checkpoint_best.pt \
  --output_dir /path/to/out/predictions \
  --tissue_names tissue_names.txt \
  --apply_renormalization --renorm_strategy threshold --renorm_threshold 0.05 \
  --batch_size 8 --verbose
```

| Option | Default | Meaning |
|---|---|---|
| `--input_h5` | required | `samples.h5` from step 4 |
| `--input_metadata` | required | `samples.csv` |
| `--checkpoint` | required | trained checkpoint |
| `--output_dir` | required | where predictions are written |
| `--tissue_names` | generic names | tissue names file, one per line |
| `--batch_size` | 8 | lower it (4 or 1) on out-of-memory |
| `--device` | `cuda` | `cuda` or `cpu` |
| `--apply_renormalization` | off | zero small predictions and rescale to sum to 1 |
| `--renorm_strategy` | `threshold` | `threshold`, `soft_threshold` or `bayesian`; hard threshold performed best |
| `--renorm_threshold` | 0.05 | minimum proportion kept |
| `--min_proportion` | 0.01 | minimum shown in clinical reports |
| `--verbose` | off | progress output |

Run once more without `--apply_renormalization` and a separate `--output_dir` to keep the raw proportions: a 5% threshold zeroes genuine trace signals. Lower thresholds (about 1%) suit sparse, blood-dominant samples (see Results).

Outputs in `predictions/`:

| File | Content |
|---|---|
| `tissue_proportions_all_samples.csv` | one row per sample: `sample_name,Adipocytes,Aorta,Bladder,Blood,...` (22 tissues, summing to 1) |
| `clinical_reports/*.txt` | one report per sample |
| `predictions.json`, `summary_statistics.json` | same predictions as JSON, and cohort summary |

### 6. Reading the output

- Healthy cfDNA is roughly 70-90% blood cells with under 5% per organ tissue; a non-blood tissue above about 2x its baseline, or above 10% absolute, suggests tissue damage.
- The model was trained at 10x or more per region, whereas shallow cfDNA WGBS is typically 1-2x on the panel. Check `blocks_depth_ge10_pct` in `qc_report.txt` before trusting low-depth samples.

### Troubleshooting

| Problem | Fix |
|---|---|
| `IndexError: index ... out of bounds` in the coverage step | `.beta` genome differs from the blocks genome; rerun with the correct `-g` (28,217,448 rows = hg19, 29,401,795 = hg38) |
| `No module named 'h5py'` | conversion is running in the `wgbstools` env; run it in base |
| CUDA out of memory | `--batch_size 4` or `1`, or `--device cpu` |

## References

- Loyfer et al., [*A DNA methylation atlas of normal human cell types*](https://www.nature.com/articles/s41586-022-05580-6)
- Mattox et al., [*The Origin of Highly Elevated Cell-Free DNA in Healthy Individuals and Patients with Pancreatic, Colorectal, Lung, or Ovarian Cancer*](https://doi.org/10.1158/2159-8290.cd-21-1252)
- Petersson et al., [*Reliable on-treatment prognostication and target identification with a customized assay for circulating tumor DNA in patients with newly diagnosed pancreatic cancer*](https://www.nature.com/articles/s41598-025-22369-5)

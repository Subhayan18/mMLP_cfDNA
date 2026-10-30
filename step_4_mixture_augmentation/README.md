# Step 4: Mixture Deconvolution

Fine-tunes the step 3 classifier to predict tissue proportions in synthetic cfDNA-like mixtures.

## Model

`model_deconvolution.py` (`TissueBERTDeconvolution`): the step 3 MLP with sigmoid + L1 normalisation (22 proportions summing to 1), MSE loss, and optional post-hoc renormalisation in `forward(..., apply_renorm, renorm_strategy, renorm_params)`.

## Mixtures and phases

Mixtures are linear combinations of region-mean methylation from pure samples of different tissues, generated on the fly for training and pre-generated for validation and test (`generate_mixture_datasets.py`).

| Phase | Mixture | Proportions | Per epoch | Val/test |
|---|---|---|---|---|
| 1 | 2 tissues | 50/50 to 80/20 | 2,500 | 500 each |
| 2 | 3-5 tissues | Dirichlet | 5,000 | 1,000 each |
| 3 | 6-9 tissues, blood-dominant | skewed | 7,500 | 1,500 each |

Each phase starts from the previous best checkpoint at a lower learning rate.

```bash
python generate_mixture_datasets.py --phase 2 --n_mixtures 1000 --output_dir <DIR> --seed 42
python train_deconvolution.py --config config_phase2_multitissue.yaml
```

## Evaluation

```bash
python evaluate_deconvolution.py --checkpoint <ckpt> --test_h5 <test.h5> --output_dir <out> \
  --device cuda --renorm_strategy threshold --threshold 0.05
python visualize_mixture_miami.py --checkpoint <ckpt> --test_h5 <test.h5> --output miami.png \
  --summary summary.csv --device cuda --renorm_strategy threshold --threshold 0.05
```

`--renorm_strategy` is `threshold`, `soft_threshold`, `bayesian` or `NULL`. Outputs: `metrics.json`, `evaluation_report.txt`, `per_tissue_metrics.csv`, predictions, figures, and a Miami plot of true versus predicted proportions.

| Phase | Test MAE | R² |
|---|---|---|
| 1 | 2.8% | 0.88 |
| 2 | 2.6% | 0.87 |
| 3 raw | 3.0% | 0.85 |
| 3, threshold 1% | 1.3% | 0.94 |

## Renormalisation

Zeroes small predictions and rescales to sum to 1.

| Strategy | Parameters | Phase 2 MAE | False positives |
|---|---|---|---|
| Raw | none | 3.5% | 14,795 |
| Hard threshold | `threshold` 0.05 | 1.8% | 733 |
| Soft threshold | `threshold`, `temperature` | 2.7% | 9,960 |
| Bayesian | `prior_sparsity` | 3.5% | 14,795 |

## Stage 2: blood-masked deconvolution

Input is the same mixed sample (blood included); labels have blood removed and renormalised, giving 21 non-blood proportions. Initialised from Phase 3 with a re-initialised classifier.

Scripts: `dataloader_mixture_stage2.py`, `generate_stage2_mixtures.py`, `train_stage2_bloodmasked.py`, `evaluate_stage2.py`; config `config_stage2_bloodmasked.yaml`. Test MAE 6.3% (5.5% after extended training).

Final non-blood tissue proportion = Stage 2 proportion x (1 - blood fraction from the Phase 3 model).

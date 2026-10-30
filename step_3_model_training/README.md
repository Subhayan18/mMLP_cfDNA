# Step 3: Single-Tissue Classifier (File-Level MLP)

Classifies each sample into one of 22 tissues from per-region mean methylation.

```
methylation [B, regions, 150] -> mean per region (CpGs only)
  -> Linear -> 512 -> MLP (BatchNorm, ReLU, dropout) -> Linear -> 22 logits
```

About 27M parameters. Cross-entropy with label smoothing 0.1, AdamW, 50 epochs.

| File | Purpose |
|---|---|
| `create_fullgenome_dataset.py` | Links the HDF5 and split CSVs into `fullgenome_subset/` |
| `model_fullgenome.py` | Model with fixed region count |
| `config_fullgenome.yaml` | Batch 4, gradient accumulation 8, 12 workers |
| `submit_training_fullgenome.sh` | SLURM: 24 CPUs, 64 GB RAM, 1x A100 |
| `evaluate_model.py` | Test metrics, confusion matrices, per-tissue accuracy/F1 |

```bash
python create_fullgenome_dataset.py
sbatch submit_training_fullgenome.sh config_fullgenome.yaml
python evaluate_model.py --checkpoint <checkpoint_best_acc.pt> --config config_fullgenome.yaml --output <DIR>
```

| Input | Val accuracy |
|---|---|
| chr1 | 93.3% |
| Full genome | 97.8% |

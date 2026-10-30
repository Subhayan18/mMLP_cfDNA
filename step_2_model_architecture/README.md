# Step 2: Data Format and Loading

Converts the NPZ training files to HDF5 and provides the dataloader. Environment modules: `LMOD.sourceme`.

The final model is a file-level MLP (step 3). A from-scratch BERT-style transformer was tested here and not used.

| Script | Purpose |
|---|---|
| `convert_to_hdf5.py` | NPZ to one gzip HDF5 with 22-class `tissue_index` labels from `combined_metadata.csv` |
| `check_hdf5.py` | Confirms 22 classes (0-21) |
| `dataset_dataloader.py` | `create_dataloaders(hdf5_path, train_csv, val_csv, test_csv, ...)` |

```bash
python convert_to_hdf5.py
python check_hdf5.py
python dataset_dataloader.py   # smoke test
```

The split CSVs need `filename` and `tissue_index` columns.

## Dataloader

- Tissue-balanced sampling at file level.
- CpG dropout (default 5%) on training data only; masked CpGs become 2 (missing).
- Batch fields: `dna_tokens`, `methylation`, `n_reads`, `tissue_label`.

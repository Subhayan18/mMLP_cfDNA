#!/usr/bin/env python3
"""Per-sample coverage statistics for .beta files over a panel blocks file.

Usage: python beta_coverage_stats.py --blocks TWIST_blocks.bed --beta_dir DIR --output coverage_stats.csv [--min_cov 4] [--threads 8]
"""
import argparse
from multiprocessing import Pool
from pathlib import Path

import numpy as np
import pandas as pd


def init(s, e, min_cov):
    global S, E, MIN_COV
    S, E, MIN_COV = s, e, min_cov


def stats(path):
    cov = np.fromfile(path, dtype=np.uint8).reshape(-1, 2)[:, 1].astype(np.int64)
    cs_obs = np.concatenate([[0], np.cumsum(cov)])
    cs_hit = np.concatenate([[0], np.cumsum(cov > 0)])
    obs = cs_obs[E] - cs_obs[S]          # site observations per block
    n_cpg = E - S
    depth = obs / n_cpg                  # mean CpG depth per block
    return {
        'sample': path.name.removesuffix('.beta'),
        'genome_mean_depth': cov.mean(),
        'panel_mean_depth': obs.sum() / n_cpg.sum(),
        'panel_cpgs_covered_pct': 100 * (cs_hit[E] - cs_hit[S]).sum() / n_cpg.sum(),
        'block_median_obs': np.median(obs),
        'blocks_pass_min_cov_pct': 100 * (obs >= MIN_COV).mean(),
        'blocks_depth_ge1_pct': 100 * (depth >= 1).mean(),
        'blocks_depth_ge10_pct': 100 * (depth >= 10).mean(),
    }


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--blocks', required=True)
    p.add_argument('--beta_dir', required=True)
    p.add_argument('--output', required=True)
    p.add_argument('--min_cov', type=int, default=4)
    p.add_argument('--threads', type=int, default=8)
    a = p.parse_args()

    b = pd.read_csv(a.blocks, sep='\t', header=None, usecols=[3, 4], comment='#')
    b = b.apply(pd.to_numeric, errors='coerce').dropna().astype(np.int64)
    b = b[b[4] > b[3]]
    s, e = b[3].values - 1, b[4].values - 1    # 1-based CpG index -> 0-based rows, end exclusive

    betas = sorted(Path(a.beta_dir).rglob('*.beta'))
    print(f'{len(b)} blocks, {len(betas)} beta files, min_cov={a.min_cov}')

    with Pool(a.threads, initializer=init, initargs=(s, e, a.min_cov)) as pool:
        df = pd.DataFrame(pool.map(stats, betas))

    Path(a.output).parent.mkdir(parents=True, exist_ok=True)
    df.round(4).to_csv(a.output, index=False)
    print(df.drop(columns='sample').median().round(3).to_string())
    print(f'-> {a.output}')


if __name__ == '__main__':
    main()

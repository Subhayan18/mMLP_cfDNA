#!/usr/bin/env python3
"""Flag samples as PASS / WARN / FAIL from beta_coverage_stats.py output.

FAIL: blocks_pass_min_cov_pct < --min_blocks_pct or panel_mean_depth < --min_depth (absolute floors)
WARN: below cohort Q1 - 1.5*IQR on either metric (kept, reported)

Usage: python flag_coverage_qc.py --input coverage_stats.csv [--output coverage_stats_qc.csv]
                                  [--min_blocks_pct 25] [--min_depth 0.5]
"""
import argparse
from pathlib import Path

import pandas as pd

METRICS = {'blocks_pass_min_cov_pct': 'min_blocks_pct', 'panel_mean_depth': 'min_depth'}

p = argparse.ArgumentParser()
p.add_argument('--input', required=True)
p.add_argument('--output')
p.add_argument('--min_blocks_pct', type=float, default=25)
p.add_argument('--min_depth', type=float, default=0.5)
a = p.parse_args()

df = pd.read_csv(a.input)
fail, warn = [], []
for col, arg in METRICS.items():
    floor = getattr(a, arg)
    q1, q3 = df[col].quantile([0.25, 0.75])
    lower = q1 - 1.5 * (q3 - q1)
    fail.append(df[col].lt(floor).map({True: f'{col}<{floor:g}', False: ''}))
    warn.append(df[col].lt(lower).map({True: f'{col}<{lower:.3g} (cohort outlier)', False: ''}))
    print(f'{col}: floor {floor:g}, cohort lower bound {lower:.3g}')

fail = pd.concat(fail, axis=1).agg(lambda r: '; '.join(x for x in r if x), axis=1)
warn = pd.concat(warn, axis=1).agg(lambda r: '; '.join(x for x in r if x), axis=1)
df['qc_status'] = 'PASS'
df.loc[warn != '', 'qc_status'] = 'WARN'
df.loc[fail != '', 'qc_status'] = 'FAIL'
df['qc_reason'] = fail.where(fail != '', warn)

out = a.output or str(Path(a.input).with_name(Path(a.input).stem + '_qc.csv'))
df.to_csv(out, index=False)
print(df['qc_status'].value_counts().to_string())
print(f'-> {out}')

# The 11% Case File

**Claim:** "Recovery has improved by 11% month-on-month."
**Finding:** The 11% is February (28 days) vs March (31 days). Per day, recovery moved **+0.3%**, and it has been flat since January.

## What's in here
| Deliverable | Where |
|---|---|
| SQL repository | [`sql/`](sql) — `01_staging` → `02_clean` → `03_golden` → `04_metrics` → `05_forensics` → `06_analysis` |
| Analysis notebook | [`notebooks/case_file.ipynb`](notebooks/case_file.ipynb) |
| Golden dataset + pipeline | [`run_pipeline.py`](run_pipeline.py) → `output/golden/*.csv` |
| Data quality report | [`reports/data_quality_report.md`](reports/data_quality_report.md) |
| Executive dashboard | [`dashboard/index.html`](dashboard/index.html) (open in a browser) |
| Executive memo | [`reports/executive_memo.md`](reports/executive_memo.md) |
| Architecture + production design | [`reports/architecture.md`](reports/architecture.md) |

## How to run
```bash
pip install pandas duckdb matplotlib jupyter
python run_pipeline.py
jupyter notebook notebooks/case_file.ipynb
```
The raw CSVs go in `collections_30k_dataset/`. The pipeline rebuilds every table and the dashboard data from them.

## How I approached it
1. Profiled every table before touching anything (`notebooks/00_profile.py`).
2. Built a golden layer where every dropped row is logged with a reason.
3. Reverse-engineered the 11%: found the exact month pair and formula that produce it.
4. Walked from the reported number to the true one, one correction at a time (the waterfall).
5. Checked each data "suspect" (A–G) and stamped every finding: FACT / STRONG / CORRELATION / HYPOTHESIS.
6. Kept the methods simple enough to explain in two lines each.

## Investigation log
> *(My own notes: what I tried first, what surprised me, what I'd do differently with more time.)*

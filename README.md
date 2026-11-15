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
**Step 1: Look before cleaning.** I profiled every table first. Two surprises: the data covers only 1 Jan – 8 Aug 2026, not 12 months, and almost every category is split evenly (statuses, channels, outcomes all ~20% each). That made me expect a flat business, not a growing one.

**Step 2: Guess the cause, then test it.** My first guess was that duplicate payments created the 11%. Wrong. Removing the 500 duplicate rows moved Feb→Mar from 10.99% to 11.03%, because the duplicates are spread evenly across months.

**Step 3: Find the exact 11%.** I computed month-on-month change for every month on raw SUCCESS payments. Only Feb→Mar gives 11.0%. Then I noticed February has 28 days and March 31. Per day, the change is +0.3%. This was the key moment of the analysis.

**Step 4: Check the other suspects anyway.** Even after finding the cause, I went through all seven checks from the brief. Two results surprised me: only 9% of payments had any contact in the 7 days before, and 75% of collected money comes from accounts whose current status is closed, paid or written off. Both would mislead a report even though neither caused the 11%.

**Step 5: Look underneath the flat total.** Splitting Feb→Mar by DPD bucket showed 1–30 DPD up 11% and 30+ DPD down 5–9%. The total hid two opposite movements.

**Step 6: Try the counterfactual, and not trust it.** The before/after comparison for the targeting change gave +3%, but the parallel-trends chart showed the treated group was already rising before April. I reported the number and said why it isn't reliable.

**Step 7: Be honest about the ₹10 Cr.** No lever in the data clearly moves recovery, so instead of forcing a big ROI number I recommended paying ₹0.8 Cr for a proper test before committing the rest.

**What I'd do with more time:**
- Rebuild point-in-time DPD from the status history instead of using the current DPD.
- Get real cost data instead of my unit-cost assumptions.
- Ask the data owners how payment reversals link to the original payment.
- Confirm the timezone of the payments table, which I assumed was IST.

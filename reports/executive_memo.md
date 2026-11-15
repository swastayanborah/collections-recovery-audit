# Memo: Is recovery really up 11%?

**To:** Leadership team · **Re:** "Recovery has improved by 11% month-on-month" · **Data:** 1 Jan – 8 Aug 2026

## Bottom line
**No. Recovery has been flat since January.** The 11% is the jump from February to March, and almost all of it comes from March having 31 days against February's 28. Per day, March was only **0.3%** better than February. We should not spend ₹10 Cr on the back of this number.

## 1. What happened?
- Real recovery (successful, de-duplicated payments) is steady at **~₹60 lakh per day, ~₹18 Cr per month**. The trend is −0.4% per month, inside normal noise (±1.8%).
- The monthly headline zig-zags with month length: −9%, **+11%**, −8%, +5%, −4%, +7%. Choosing the best month makes a flat business look like it's growing.
- Under the flat total, Feb→Mar hid two opposite moves: **1–30 DPD accounts rose 11% while 30+ DPD fell 5–9%.**

## 2. Why did the number look good?
| What inflates the picture | Effect | Evidence |
|---|---|---|
| Comparing a 28-day month to a 31-day month | **+10.7 pts of the 11%** | FACT |
| Raw payments table includes failed, pending, reversed and duplicate rows | Totals overstated by **~45%** (₹192 Cr vs ₹132 Cr real) | FACT |
| Recovery rate measured on "worked" accounts only | Same Feb→Mar shows **+19%** | FACT |
| Payments credited to the last contact, however old | Credits 67% of payments; only **9%** had contact in the 7 days before | FACT |
| PTP kept rate ignores cancelled promises | Shows **49%**; true is **25%** | FACT |
| PTP counted under one code version only | PTP rate **halved** | FACT |

What did **not** drive it: portfolio mix (no segment moved >4 pts), telephony vendor, calling hour, call frequency. Each was checked; none moves recovery beyond noise.

## 3. How confident are we?
- **High** that the 11% is a calendar effect: simple arithmetic, reproducible from the raw data.
- **High** on the data-quality findings: each is a direct count.
- **Low** on what drives recovery. The data has no client, language or cost fields, covers 7 months not 12, and every operational lever we can see looks like noise.
- **Low** on the mid-year targeting change. The comparison says +3% (≈₹0.4 Cr over four months), but the two groups were already moving differently before the change, so the estimate isn't reliable. Most likely answer: recovery would have looked about the same without it.

## 4. What should we do?
**Invest in better borrower targeting, in stages, not all at once.**

1. **Now (₹0.8 Cr, 10 weeks):** put the cleaned data pipeline into production and run a proper test: new targeting on 90% of eligible accounts, old targeting on a random 10%.
2. **Gate:** release the remaining **₹9.2 Cr** only if the test shows **≥3% recovery lift** with 95% confidence.
3. **Immediately, at no cost:** report recovery **per day**, on the **full book**, with SUCCESS payments only. Stop month-total comparisons.

Why targeting: 91% of payments arrive with no recent contact, so today's effort isn't aimed at who needs it. Adding agents or calls doesn't help (2 calls convert the same as 1). Targeting improves every channel at once, and it's the cheapest option to test and reverse.

## 5. Expected financial impact
To pay back ₹10 Cr in one year, any option must lift recovery by **~4.6%** (run-rate ₹218 Cr/year).

| Scenario | Lift | Extra recovery / yr | Spend | Year-1 ROI | Break-even |
|---|---:|---:|---:|---:|---|
| Downside (test fails) | 0% | ₹0 | ₹0.8 Cr | −₹0.8 Cr | never, but ₹9.2 Cr protected |
| Base | 2.5% | ~₹5.5 Cr | ₹10 Cr | −45% | ~22 months |
| Upside | 5% | ~₹11 Cr | ₹10 Cr | +10% | ~11 months |

*The lift values are assumptions (typical for targeting projects), not measurements from our data. The test in step 1 replaces them with a real number.*

**Key assumptions:** run-rate holds at ₹218 Cr/yr; contact costs (~₹1.6 Cr/yr, estimated) stay the same; the test runs long enough to cover a full PTP cycle (~30 days) twice.

---
*Full analysis: `notebooks/case_file.ipynb` · Data issues: `reports/data_quality_report.md` · Reproduce: `python run_pipeline.py`*

"""Export the numbers the dashboard needs into dashboard/data.js.

A .js file (not .json) so index.html works by double-click, without a web server.
"""
import json
from pathlib import Path
import duckdb

ROOT = Path(__file__).resolve().parent.parent


def main():
    con = duckdb.connect(str(ROOT / "output" / "collections.duckdb"), read_only=True)
    rows = lambda sql: [dict(zip([d[0] for d in r.description], v)) for r in [con.execute(sql)] for v in r.fetchall()]

    audit = rows("select step, label, value_pct, change_from_previous from m_claim_audit order by step")
    monthly = rows("""
        select strftime(month, '%b') as m, reported_collected / 1e7 as reported_cr,
               true_collected_per_day * 30 / 1e7 as true_cr_30d
        from m_monthly where is_complete_month order by month""")
    kpi = rows("""
        select avg(true_collected_per_day) / 1e5 as lakh_per_day,
               regr_slope(true_collected_per_day, epoch(month)/86400/30) / avg(true_collected_per_day) * 100 as trend_pct,
               avg(ptp_kept_rate_true) * 100 as kept_true, avg(ptp_kept_rate_naive) * 100 as kept_naive,
               avg(cost_per_rupee) * 100 as paise_per_rupee
        from m_monthly where is_complete_month""")[0]
    wf = rows("select raw_amount / 1e7 raw_cr, golden_amount / 1e7 golden_cr from dq_waterfall where tbl = 'payments'")[0]
    attr = rows("select share_credited * 100 as pct from f_b_attribution where rule = 'last touch within 7 days'")[0]
    suspects = rows("select code, suspect, evidence, finding from f_summary order by code")

    data = dict(audit=audit, monthly=monthly, kpi=kpi, payments=wf, attr7=attr["pct"], suspects=suspects)
    (ROOT / "dashboard" / "data.js").write_text(
        "window.DASH = " + json.dumps(data, default=float, indent=1) + ";\n", encoding="utf-8")
    print("wrote dashboard/data.js")


if __name__ == "__main__":
    main()

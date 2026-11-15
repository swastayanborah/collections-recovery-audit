"""Run the whole SQL pipeline in order and export the golden + metric tables.

Usage:  python run_pipeline.py
Output: output/collections.duckdb  (all tables)
        output/golden/*.csv        (golden + metric tables for anyone without DuckDB)
"""
from pathlib import Path
import duckdb

ROOT = Path(__file__).resolve().parent
SQL_DIR = ROOT / "sql"
OUT = ROOT / "output"
EXPORT = [
    "g_accounts", "g_payments", "g_calls", "g_touches",
    "m_monthly", "m_mom", "m_claim_audit",
    "dq_waterfall", "f_summary",
]


def main():
    OUT.mkdir(exist_ok=True)
    (OUT / "golden").mkdir(exist_ok=True)
    db = OUT / "collections.duckdb"
    db.unlink(missing_ok=True)
    con = duckdb.connect(str(db))
    con.execute(f"SET file_search_path='{ROOT.as_posix()}'")

    for f in sorted(SQL_DIR.glob("*.sql")):
        print(f"running {f.name}")
        con.execute(f.read_text(encoding="utf-8"))

    tables = {r[0] for r in con.execute("select table_name from information_schema.tables").fetchall()}
    for t in EXPORT:
        if t in tables:
            con.execute(f"COPY {t} TO '{(OUT / 'golden' / (t + '.csv')).as_posix()}' (HEADER)")
    print("done ->", OUT)
    con.close()

    # refresh the dashboard numbers
    import runpy
    runpy.run_path(str(ROOT / "dashboard" / "build_data.py"), run_name="__main__")


if __name__ == "__main__":
    main()

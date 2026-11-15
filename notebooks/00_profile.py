# Phase 0 - first look at every table.
# Goal: before cleaning anything, see what each table really contains.
import pandas as pd
from pathlib import Path

DATA = Path(__file__).resolve().parent.parent / "collections_30k_dataset"
pd.set_option("display.width", 200, "display.max_columns", 30)

for f in sorted(DATA.glob("*.csv")):
    if f.stem == "data_dictionary":
        continue
    df = pd.read_csv(f, low_memory=False)
    print("=" * 100)
    print(f"{f.stem}: {len(df):,} rows, {df.shape[1]} cols, full-row duplicates = {df.duplicated().sum():,}")
    first = df.columns[0]
    print(f"  duplicate {first}: {df[first].duplicated().sum():,}")
    for c in df.columns:
        s = df[c]
        nulls = s.isna().mean() * 100
        nun = s.nunique()
        sample = s.dropna().astype(str).unique()[:6]
        extra = ""
        if nun <= 15:
            extra = " | values: " + str(s.value_counts(dropna=False).head(15).to_dict())
        print(f"  - {c:22s} null={nulls:5.1f}%  unique={nun:7,}  e.g. {list(sample)}{extra}")

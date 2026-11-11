"""Build a monthly US macro dataset from FRED: policy rate, inflation and output gap.

Downloads four public series from the Federal Reserve Bank of St. Louis,
aligns them on a monthly index, and exports summary statistics, a correlation
matrix and a chart. No API key is needed.

Run from the project folder: python fred_macro.py
"""

from pathlib import Path

import matplotlib.pyplot as plt
import pandas as pd

FRED_CSV_URL = "https://fred.stlouisfed.org/graph/fredgraph.csv?id={series_id}"
OUTPUT_DIR = Path("output")
LAG_MONTHS = 3  # policy reacts to data that is already a quarter old


def fetch_series(series_id: str) -> pd.Series:
    """Download one FRED series as a date-indexed Series."""
    frame = pd.read_csv(FRED_CSV_URL.format(series_id=series_id), parse_dates=[0], index_col=0)
    series = pd.to_numeric(frame.iloc[:, 0], errors="coerce")
    series.name = series_id
    return series


def build_dataset() -> pd.DataFrame:
    cpi = fetch_series("CPIAUCSL")            # consumer price index, monthly
    fed_funds = fetch_series("DFF")           # effective federal funds rate, daily
    potential_gdp = fetch_series("GDPPOT")    # real potential GDP, quarterly
    real_gdp = fetch_series("GDPC1")          # real GDP, quarterly

    # Monthly inflation in percent.
    inflation = cpi.pct_change().mul(100).rename("CPI")
    inflation.index = inflation.index.to_period("M")

    # Daily policy rate -> last observation of each month.
    policy_rate = fed_funds.resample("ME").last().rename("FFD")
    policy_rate.index = policy_rate.index.to_period("M")

    # Output gap: share of potential output that is not being produced.
    # Positive values mean slack in the economy.
    gap = ((potential_gdp - real_gdp) / potential_gdp).dropna().rename("GAP")
    gap.index = gap.index.to_period("M")

    data = pd.concat([policy_rate, inflation, gap], axis=1).sort_index()

    # The gap is quarterly: carry each value into the next two months only.
    data["GAP"] = data["GAP"].ffill(limit=2)

    # Lag the indicators so each row pairs the rate with information
    # that was available when it was set.
    data[["CPI", "GAP"]] = data[["CPI", "GAP"]].shift(LAG_MONTHS)
    return data.dropna()


def plot_dataset(data: pd.DataFrame) -> None:
    labels = {
        "FFD": "Federal funds rate (%)",
        "CPI": f"Monthly CPI inflation (%), lagged {LAG_MONTHS} months",
        "GAP": f"Output gap (share of potential GDP), lagged {LAG_MONTHS} months",
    }
    fig, axes = plt.subplots(3, 1, figsize=(10, 8), sharex=True)
    dates = data.index.to_timestamp()
    for ax, (column, label) in zip(axes, labels.items()):
        ax.plot(dates, data[column], linewidth=1)
        ax.axhline(0, color="grey", linewidth=0.5)
        ax.set_title(label, loc="left", fontsize=10)
    fig.tight_layout()
    fig.savefig(OUTPUT_DIR / "macro_series.png", dpi=150)
    plt.close(fig)


def main() -> None:
    OUTPUT_DIR.mkdir(exist_ok=True)
    data = build_dataset()

    print(f"{len(data)} monthly observations, {data.index.min()} to {data.index.max()}")
    print(data.head())

    summary = data.describe()
    correlation = data.corr()
    print("\nSummary statistics:\n", summary.round(4))
    print("\nCorrelation matrix:\n", correlation.round(3))

    data.to_csv(OUTPUT_DIR / "macro_monthly.csv")
    summary.to_csv(OUTPUT_DIR / "summary_stats.csv")
    correlation.to_csv(OUTPUT_DIR / "correlation_matrix.csv")
    plot_dataset(data)


if __name__ == "__main__":
    main()

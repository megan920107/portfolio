"""Baidu segment financials: Baidu Core versus iQIYI, Q1 2019 to Q2 2024.

Draws four charts from publicly reported quarterly figures (RMB millions):
revenue, cost-to-revenue ratio, operating income and revenue mix.

Run from the project folder: python baidu_financials.py
"""

from pathlib import Path

import matplotlib.pyplot as plt
import pandas as pd

FIG_DIR = Path("figures")
SEGMENTS = {"Baidu Core": "#0f6e6e", "iQIYI": "#d9822b"}

# Quarter-end dates, oldest first.
QUARTERS = pd.period_range("2019Q1", "2024Q2", freq="Q")

# One list per (segment, metric), in the same order as QUARTERS.
FIGURES = {
    ("Baidu Core", "revenue"): [
        17450, 19540, 21010, 21711, 15268, 18926, 21379, 23111, 20483, 24041, 24661,
        25978, 21378, 23160, 25239, 25654, 22998, 26407, 26572, 27488, 23803, 26687,
    ],
    ("iQIYI", "revenue"): [
        6990, 7110, 7397, 7497, 7650, 7412, 7188, 7458, 7968, 7608, 7589,
        7389, 7277, 6657, 7471, 7593, 8439, 7802, 8015, 7707, 7927, 7439,
    ],
    ("Baidu Core", "costs"): [
        16359, 17431, 15819, 14841, 13420, 13960, 13975, 16791, 16636, 19422, 20943,
        23020, 18854, 19914, 20257, 21872, 18907, 21839, 21074, 22820, 19265, 21079,
    ],
    ("iQIYI", "costs"): [
        9016, 8982, 10229, 10025, 9892, 8694, 8398, 8765, 8982, 8730, 8957,
        8364, 7183, 6531, 7161, 6811, 7490, 7192, 7268, 6934, 6982, 7097,
    ],
    ("Baidu Core", "operating_income"): [
        1091, 2109, 5191, 6870, 1848, 4966, 7404, 6320, 3847, 4619, 3718,
        2958, 2524, 3246, 4982, 3782, 4091, 4568, 5498, 4668, 4538, 5608,
    ],
    ("iQIYI", "operating_income"): [
        -2026, -1872, -2832, -2528, -2242, -1282, -1210, -1307, -1014, -1122, -1368,
        -975, 94, 126, 310, 782, 949, 610, 747, 773, 945, 342,
    ],
}


def load_financials() -> pd.DataFrame:
    """Return a table indexed by quarter with (segment, metric) columns."""
    data = pd.DataFrame(FIGURES, index=QUARTERS)
    data.columns.names = ["segment", "metric"]
    for segment in SEGMENTS:
        data[(segment, "cost_to_revenue")] = data[(segment, "costs")] / data[(segment, "revenue")]
    return data.sort_index(axis=1)


def line_chart(data: pd.DataFrame, metric: str, title: str, ylabel: str, filename: str,
               as_percent: bool = False, reference_line: float | None = None) -> None:
    fig, ax = plt.subplots(figsize=(10, 4.5))
    dates = data.index.to_timestamp(how="end")
    for segment, colour in SEGMENTS.items():
        values = data[(segment, metric)] * (100 if as_percent else 1)
        ax.plot(dates, values, marker="o", markersize=4, color=colour, label=segment)
    if reference_line is not None:
        ax.axhline(reference_line, color="grey", linestyle="--", linewidth=1)
    ax.set_title(title)
    ax.set_ylabel(ylabel)
    ax.grid(alpha=0.3)
    ax.legend()
    fig.tight_layout()
    fig.savefig(FIG_DIR / filename, dpi=150)
    plt.close(fig)


def revenue_mix_chart(data: pd.DataFrame) -> None:
    """Share of combined segment revenue, first versus latest quarter."""
    fig, ax = plt.subplots(figsize=(7, 3.2))
    quarters = [data.index[0], data.index[-1]]
    left = pd.Series(0.0, index=quarters)
    for segment, colour in SEGMENTS.items():
        revenue = data.loc[quarters, (segment, "revenue")]
        total = sum(data.loc[quarters, (s, "revenue")] for s in SEGMENTS)
        share = 100 * revenue / total
        bars = ax.barh([str(q) for q in quarters], share, left=left, color=colour, label=segment)
        ax.bar_label(bars, labels=[f"{s:.0f}%" for s in share], label_type="center", color="white")
        left += share
    ax.set_xlim(0, 100)
    ax.set_xlabel("Share of segment revenue (%)")
    ax.set_title("Revenue mix")
    ax.legend(loc="lower center", bbox_to_anchor=(0.5, -0.55), ncol=2, frameon=False)
    fig.tight_layout()
    fig.savefig(FIG_DIR / "revenue_mix.png", dpi=150)
    plt.close(fig)


def main() -> None:
    FIG_DIR.mkdir(exist_ok=True)
    data = load_financials()

    line_chart(data, "revenue", "Quarterly revenue", "RMB millions", "revenue_trend.png")
    line_chart(data, "cost_to_revenue", "Cost-to-revenue ratio", "Costs as % of revenue",
               "cost_to_revenue.png", as_percent=True, reference_line=100)
    line_chart(data, "operating_income", "Quarterly operating income", "RMB millions",
               "operating_income.png", reference_line=0)
    revenue_mix_chart(data)

    first, last = data.index[0], data.index[-1]
    print(f"{first} to {last}")
    for segment in SEGMENTS:
        revenue = data[(segment, "revenue")]
        income = data[(segment, "operating_income")]
        print(f"{segment}: revenue {revenue[first]:,} -> {revenue[last]:,} "
              f"({100 * (revenue[last] / revenue[first] - 1):+.0f}%), "
              f"operating margin {100 * income[first] / revenue[first]:.1f}% -> "
              f"{100 * income[last] / revenue[last]:.1f}%")


if __name__ == "__main__":
    main()

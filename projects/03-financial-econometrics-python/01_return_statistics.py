"""Return statistics for the S&P 500 and NASDAQ, plus a check of estimator unbiasedness.

Part 1 turns monthly index levels into returns and compares the two indices:
summary statistics, skewness, kurtosis, correlation and growth of $1.
Part 2 uses simulation to confirm that the sample mean and the sample variance
(with n - 1 in the denominator) are unbiased estimators.

Run from the project folder: python 01_return_statistics.py
"""

from pathlib import Path

import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
from scipy import stats

DATA_DIR = Path("data")
FIG_DIR = Path("figures")


def load_returns(csv_name: str) -> pd.DataFrame:
    """Read monthly index levels and add log and simple returns."""
    prices = pd.read_csv(DATA_DIR / csv_name, parse_dates=["Date"], index_col="Date")
    returns = pd.DataFrame(index=prices.index)
    returns["log_return"] = np.log(prices["Adj Close"]).diff()
    returns["simple_return"] = prices["Adj Close"].pct_change()
    return returns.dropna()


def describe_returns(returns: pd.DataFrame) -> pd.DataFrame:
    """Summary statistics extended with skewness and excess kurtosis."""
    summary = returns.describe()
    summary.loc["skew"] = returns.apply(stats.skew)
    summary.loc["excess_kurtosis"] = returns.apply(stats.kurtosis)
    return summary


def plot_growth_and_distribution(returns_by_index: dict[str, pd.DataFrame]) -> None:
    fig, (ax_growth, ax_hist) = plt.subplots(1, 2, figsize=(12, 4.5))

    for name, returns in returns_by_index.items():
        growth = np.exp(returns["log_return"].cumsum())
        ax_growth.plot(growth.index, growth, label=name)
        ax_hist.hist(returns["log_return"], bins=40, alpha=0.6, label=name)

    ax_growth.set_title("Growth of $1 invested at the start of the sample")
    ax_growth.set_ylabel("Value ($)")
    ax_growth.legend()

    ax_hist.set_title("Distribution of monthly log returns")
    ax_hist.set_xlabel("Monthly log return")
    ax_hist.set_ylabel("Number of months")
    ax_hist.legend()

    fig.tight_layout()
    fig.savefig(FIG_DIR / "index_returns.png", dpi=150)
    plt.close(fig)


def simulate_unbiasedness(rate: float, sample_size: int, n_simulations: int, seed: int) -> tuple[float, float]:
    """Average the sample mean and sample variance over many exponential samples.

    For an exponential distribution with the given rate, the true mean is
    1 / rate and the true variance is 1 / rate**2.
    """
    rng = np.random.default_rng(seed)
    samples = rng.exponential(scale=1 / rate, size=(n_simulations, sample_size))
    return samples.mean(axis=1).mean(), samples.var(axis=1, ddof=1).mean()


def main() -> None:
    FIG_DIR.mkdir(exist_ok=True)
    pd.set_option("display.width", 120)

    # ---- Part 1: index returns ----
    returns_by_index = {
        "S&P 500": load_returns("SP500m.csv"),
        "NASDAQ": load_returns("NASDAQm.csv"),
    }
    for name, returns in returns_by_index.items():
        print(f"\n{name}: {len(returns)} monthly returns, "
              f"{returns.index.min():%Y-%m} to {returns.index.max():%Y-%m}")
        print(describe_returns(returns).round(4))

    log_returns = pd.DataFrame({name: r["log_return"] for name, r in returns_by_index.items()})
    print("\nCorrelation of monthly log returns:")
    print(log_returns.corr().round(3))

    plot_growth_and_distribution(returns_by_index)

    # ---- Part 2: unbiasedness ----
    rate = 1.2
    avg_mean, avg_variance = simulate_unbiasedness(rate, sample_size=100, n_simulations=10_000, seed=123456)
    print("\nUnbiasedness check, exponential distribution with rate 1.2 (10,000 samples of 100):")
    print(f"  average sample mean     {avg_mean:.4f}   true mean     {1 / rate:.4f}")
    print(f"  average sample variance {avg_variance:.4f}   true variance {1 / rate**2:.4f}")


if __name__ == "__main__":
    main()

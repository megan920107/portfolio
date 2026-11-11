"""Ordinary least squares in practice: CEO pay, residual properties and the CAPM.

1. Does CEO salary rise with tenure? (Wooldridge `ceosal2` data)
2. A simulation showing what OLS residuals guarantee and what they do not.
3. The CAPM beta of Apple, estimated on raw and dividend-adjusted prices.

Run from the project folder: python 02_ols_and_capm.py
"""

from pathlib import Path

import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
import statsmodels.formula.api as smf
import wooldridge as woo

DATA_DIR = Path("data")
FIG_DIR = Path("figures")


def coefficient_table(results) -> pd.DataFrame:
    """Estimates, standard errors, t statistics and p-values in one table."""
    return pd.DataFrame({
        "coef": results.params,
        "std_err": results.bse,
        "t": results.tvalues,
        "p_value": results.pvalues,
    }).round(4)


def ceo_salary_and_tenure() -> None:
    ceos = woo.dataWoo("ceosal2")
    print("--- CEO salary and tenure ---")
    print(f"Average salary: ${ceos['salary'].mean():,.1f} thousand")
    print(f"Average tenure as CEO: {ceos['ceoten'].mean():.2f} years")
    print(f"CEOs in their first year: {(ceos['ceoten'] == 0).sum()}")
    print(f"Longest tenure: {ceos['ceoten'].max()} years")

    results = smf.ols("np.log(salary) ~ ceoten", data=ceos).fit()
    print(coefficient_table(results))
    print(f"One more year as CEO is associated with about "
          f"{100 * results.params['ceoten']:.2f}% higher salary.\n")


def residual_properties(seed: int = 2024) -> None:
    """Simulate y = 1 + 2x + u and compare OLS residuals with the true errors."""
    rng = np.random.default_rng(seed)
    n = 500
    x = rng.uniform(0, 10, size=n)
    u = rng.normal(0, 6, size=n)  # variance 36
    sample = pd.DataFrame({"x": x, "y": 1 + 2 * x + u})

    results = smf.ols("y ~ x", data=sample).fit()
    residuals = results.resid

    print("--- Residual properties (true model: y = 1 + 2x + u) ---")
    print(f"Estimated intercept {results.params['Intercept']:.3f}, slope {results.params['x']:.3f}")
    # By construction OLS residuals sum to zero and are orthogonal to x ...
    print(f"Sum of residuals:        {residuals.sum(): .6f}")
    print(f"Sum of x * residuals:    {np.dot(x, residuals): .6f}")
    # ... but the true errors satisfy this only on average, not in one sample.
    print(f"Sum of true errors:      {u.sum(): .3f}")
    print(f"Sum of x * true errors:  {np.dot(x, u): .3f}\n")


def apple_capm() -> None:
    prices = pd.read_csv(DATA_DIR / "data_exercise_2c.csv", parse_dates=["DATE"])
    risk_free = prices["RF_%"] / 100

    excess = pd.DataFrame({
        "market": prices["SP500"].pct_change() - risk_free,
        "aapl": prices["AAPL_Close"].pct_change() - risk_free,
        "aapl_adj": prices["AAPL_Adj_Close"].pct_change() - risk_free,
    }).dropna()

    print("--- CAPM for Apple ---")
    print(excess.describe().round(4))

    # The adjusted series includes dividends, so it is the correct total return.
    fits = {
        "Close price": smf.ols("aapl ~ market", data=excess).fit(),
        "Adjusted close (with dividends)": smf.ols("aapl_adj ~ market", data=excess).fit(),
    }
    for label, results in fits.items():
        print(f"\n{label}: alpha {results.params['Intercept']:.4f}, "
              f"beta {results.params['market']:.3f}, R-squared {results.rsquared:.3f}")
        print(coefficient_table(results))

    fig, axes = plt.subplots(1, 2, figsize=(11, 4.5), sharey=True)
    grid = np.linspace(excess["market"].min(), excess["market"].max(), 200)
    for ax, column, (label, results) in zip(axes, ["aapl", "aapl_adj"], fits.items()):
        ax.scatter(excess["market"], excess[column], s=14, alpha=0.7)
        ax.plot(grid, results.params["Intercept"] + results.params["market"] * grid,
                color="red", linestyle="--", label=f"CAPM fit (beta = {results.params['market']:.2f})")
        ax.set_title(f"Apple, {label.lower()}")
        ax.set_xlabel("Market excess return")
        ax.legend()
    axes[0].set_ylabel("Apple excess return")
    fig.tight_layout()
    fig.savefig(FIG_DIR / "apple_capm.png", dpi=150)
    plt.close(fig)


def main() -> None:
    FIG_DIR.mkdir(exist_ok=True)
    pd.set_option("display.width", 120)
    ceo_salary_and_tenure()
    residual_properties()
    apple_capm()


if __name__ == "__main__":
    main()

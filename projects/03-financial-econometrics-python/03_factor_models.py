"""Factor models for Apple, and two regression identities shown on wage data.

1. Does Apple's alpha survive as more risk factors are added? CAPM, then the
   Fama-French three- and five-factor models, then five factors plus momentum.
2. Omitted-variable bias: leaving IQ out of a wage equation.
3. The Frisch-Waugh-Lovell theorem: "partialling out" reproduces a multiple
   regression coefficient.

Run from the project folder: python 03_factor_models.py
"""

from pathlib import Path

import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
import statsmodels.formula.api as smf
import wooldridge as woo

DATA_DIR = Path("data")
FIG_DIR = Path("figures")

FACTOR_MODELS = {
    "CAPM": "aapl_excess ~ Mkt_RF",
    "FF3": "aapl_excess ~ Mkt_RF + SMB + HML",
    "FF5": "aapl_excess ~ Mkt_RF + SMB + HML + RMW + CMA",
    "FF5 + MOM": "aapl_excess ~ Mkt_RF + SMB + HML + RMW + CMA + MOM",
}


def apple_factor_models() -> pd.DataFrame:
    data = pd.read_csv(DATA_DIR / "data_exercise_3c.csv", parse_dates=["DATE"])
    # Factors are in percent per month, so put Apple's return on the same scale.
    data["aapl_excess"] = 100 * data["AAPL_Adj_Close"].pct_change() - data["RF"]
    data = data.dropna()

    rows = []
    for name, formula in FACTOR_MODELS.items():
        results = smf.ols(formula, data=data).fit()
        low, high = results.conf_int().loc["Intercept"]
        rows.append({
            "model": name,
            "alpha_pct_per_month": results.params["Intercept"],
            "alpha_ci_low": low,
            "alpha_ci_high": high,
            "alpha_p_value": results.pvalues["Intercept"],
            "market_beta": results.params["Mkt_RF"],
            "adj_r_squared": results.rsquared_adj,
        })
        if name == "FF5 + MOM":
            print(results.summary())

    comparison = pd.DataFrame(rows).set_index("model")
    print("\n--- Apple: alpha across factor models ---")
    print(comparison.round(3))

    fig, ax = plt.subplots(figsize=(7, 4))
    errors = [comparison["alpha_pct_per_month"] - comparison["alpha_ci_low"],
              comparison["alpha_ci_high"] - comparison["alpha_pct_per_month"]]
    ax.errorbar(comparison.index, comparison["alpha_pct_per_month"], yerr=errors, fmt="o", capsize=5)
    ax.axhline(0, color="grey", linestyle="--")
    ax.set_ylabel("Alpha (% per month)")
    ax.set_title("Apple's alpha with 95% confidence intervals")
    fig.tight_layout()
    fig.savefig(FIG_DIR / "apple_alpha_by_model.png", dpi=150)
    plt.close(fig)
    return comparison


def omitted_variable_bias() -> None:
    """Show that short-regression slope = long slope + (IQ effect) x (IQ on educ slope)."""
    wage2 = woo.dataWoo("wage2")
    iq_on_educ = smf.ols("IQ ~ educ", data=wage2).fit()
    short = smf.ols("lwage ~ educ", data=wage2).fit()
    long = smf.ols("lwage ~ educ + IQ", data=wage2).fit()

    implied = long.params["educ"] + long.params["IQ"] * iq_on_educ.params["educ"]
    print("\n--- Omitted-variable bias (wage on education, with and without IQ) ---")
    print(f"Return to education, IQ omitted:   {short.params['educ']:.4f}")
    print(f"Return to education, IQ included:  {long.params['educ']:.4f}")
    print(f"Long estimate + bias term:         {implied:.4f}  (matches the first line)")


def frisch_waugh_lovell() -> None:
    """Regressing y on the part of educ not explained by the other regressors
    gives the same coefficient as the full multiple regression."""
    wage1 = woo.dataWoo("wage1")
    full = smf.ols("lwage ~ educ + exper + tenure", data=wage1).fit()

    wage1["educ_resid"] = smf.ols("educ ~ exper + tenure", data=wage1).fit().resid
    partialled = smf.ols("lwage ~ educ_resid", data=wage1).fit()

    print("\n--- Frisch-Waugh-Lovell ---")
    print(f"educ coefficient, multiple regression: {full.params['educ']:.4f}")
    print(f"educ coefficient, partialled out:      {partialled.params['educ_resid']:.4f}")
    assert np.isclose(full.params["educ"], partialled.params["educ_resid"])


def main() -> None:
    FIG_DIR.mkdir(exist_ok=True)
    pd.set_option("display.width", 160)
    pd.set_option("display.max_columns", None)
    apple_factor_models()
    omitted_variable_bias()
    frisch_waugh_lovell()


if __name__ == "__main__":
    main()

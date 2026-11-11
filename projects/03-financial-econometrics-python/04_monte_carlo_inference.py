"""Statistical inference: confidence-interval coverage and hypothesis tests.

1. Monte Carlo: do 95% and 99% confidence intervals really contain the true
   coefficient 95% and 99% of the time?
2. Campaign spending: is a 1% rise in candidate A's spending offset by a 1%
   rise in candidate B's? (Wooldridge `vote1` data)
3. House prices: the effect of adding a 150 sq ft bedroom, with a confidence
   interval. (Wooldridge `hprice1` data)

Run from the project folder: python 04_monte_carlo_inference.py
"""

import numpy as np
import pandas as pd
import statsmodels.formula.api as smf
import wooldridge as woo

TRUE_BETAS = {"Intercept": 0.4, "x1": -1.46, "x2": 2.5}


def ci_coverage(n_obs: int, n_simulations: int, seed: int = 1234567) -> pd.DataFrame:
    """Share of simulations whose confidence interval contains the true value.

    The regressors are drawn once and held fixed; only the error term changes
    between simulations.
    """
    rng = np.random.default_rng(seed)
    x1 = rng.uniform(size=n_obs)
    x2 = rng.normal(loc=0.78, size=n_obs)
    truth = pd.Series(TRUE_BETAS)

    hits = {0.95: [], 0.99: []}
    for _ in range(n_simulations):
        u = rng.normal(size=n_obs)
        sample = pd.DataFrame({"x1": x1, "x2": x2})
        sample["y"] = truth["Intercept"] + truth["x1"] * x1 + truth["x2"] * x2 + u
        results = smf.ols("y ~ x1 + x2", data=sample).fit()

        for level in hits:
            interval = results.conf_int(alpha=1 - level)
            hits[level].append((interval[0] <= truth) & (truth <= interval[1]))

    return pd.DataFrame({f"{level:.0%} CI": pd.DataFrame(h).mean() for level, h in hits.items()})


def campaign_spending() -> None:
    vote1 = woo.dataWoo("vote1")
    results = smf.ols("voteA ~ lexpendA + lexpendB + prtystrA", data=vote1).fit()

    print("\n--- Campaign spending and vote share ---")
    print(results.summary().tables[1])

    # H0: beta_A + beta_B = 0, i.e. equal percentage increases cancel out.
    f_test = results.f_test("lexpendA + lexpendB = 0")
    print(f"H0: spending effects offset.  F = {float(f_test.statistic):.3f}, p = {float(f_test.pvalue):.3f}")

    # The same test as a t-test: rewrite the model so that the coefficient on
    # lexpendA equals beta_A + beta_B. Then t squared equals F.
    vote1["lB_minus_lA"] = vote1["lexpendB"] - vote1["lexpendA"]
    reparam = smf.ols("voteA ~ lexpendA + lB_minus_lA + prtystrA", data=vote1).fit()
    print(f"Reparameterised model: t = {reparam.tvalues['lexpendA']:.3f}, "
          f"t squared = {reparam.tvalues['lexpendA'] ** 2:.3f}, p = {reparam.pvalues['lexpendA']:.3f}")
    print("Conclusion: cannot reject that the two candidates' spending effects cancel out.")


def bedroom_premium() -> None:
    hprice1 = woo.dataWoo("hprice1")
    results = smf.ols("np.log(price) ~ sqrft + bdrms", data=hprice1).fit()

    # theta = effect on log(price) of one more bedroom that adds 150 sq ft.
    theta = 150 * results.params["sqrft"] + results.params["bdrms"]

    # Standard error of theta: substitute bdrms' coefficient = theta - 150 * beta_sqrft,
    # which makes theta the coefficient on bdrms in a regression on (sqrft - 150 * bdrms).
    hprice1["sqrft_net"] = hprice1["sqrft"] - 150 * hprice1["bdrms"]
    reparam = smf.ols("np.log(price) ~ sqrft_net + bdrms", data=hprice1).fit()

    print("\n--- Value of an extra 150 sq ft bedroom ---")
    print(f"Estimated price change: {100 * theta:.2f}%")
    for level in (0.95, 0.99):
        low, high = reparam.conf_int(alpha=1 - level).loc["bdrms"]
        print(f"{level:.0%} confidence interval: {100 * low:.2f}% to {100 * high:.2f}%")


def main() -> None:
    pd.set_option("display.width", 120)

    print("--- Confidence-interval coverage (300 observations per sample) ---")
    for n_simulations in (50, 200, 2000):
        print(f"\n{n_simulations} simulations:")
        print(ci_coverage(n_obs=300, n_simulations=n_simulations).round(3))

    campaign_spending()
    bedroom_premium()


if __name__ == "__main__":
    main()

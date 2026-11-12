"""Which employees are likely to leave, and what should HR do about it?

Compares two classifiers (Gaussian Naive Bayes and a support vector machine)
on 1,470 employee records, then picks the probability cut-off that HR should
use to flag someone as at risk.

The cut-off is chosen on the training data only (from out-of-fold
predictions), so the test set stays untouched until the final evaluation.

Run from the project folder: python attrition_model.py
"""

from pathlib import Path

import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
from sklearn.calibration import CalibratedClassifierCV
from sklearn.metrics import (
    ConfusionMatrixDisplay,
    RocCurveDisplay,
    accuracy_score,
    f1_score,
    precision_recall_curve,
    precision_score,
    recall_score,
    roc_auc_score,
)
from sklearn.model_selection import GridSearchCV, StratifiedKFold, cross_val_predict, train_test_split
from sklearn.naive_bayes import GaussianNB
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import StandardScaler
from sklearn.svm import SVC

DATA_FILE = Path("data") / "HR_Case.csv"
FIG_DIR = Path("figures")
SEED = 42
LEFT_COLOUR = "#d9534f"


# ---------------------------------------------------------------- data

def load_data() -> pd.DataFrame:
    """Read the employee file and turn the Yes/No target into 1/0."""
    employees = pd.read_csv(DATA_FILE, index_col=0)
    employees["Attrition"] = employees["Attrition"].map({"No": 0, "Yes": 1})
    assert employees.isna().sum().sum() == 0, "unexpected missing values"
    return employees


def attrition_rate_by(employees: pd.DataFrame, column: str) -> pd.Series:
    """Share of employees who left, for each level of a categorical column."""
    return employees.groupby(column)["Attrition"].mean().mul(100).sort_values()


def plot_drivers(employees: pd.DataFrame) -> None:
    fig, (ax_overtime, ax_role) = plt.subplots(1, 2, figsize=(13, 4.5), width_ratios=[1, 2])

    attrition_rate_by(employees, "OverTime").plot.bar(ax=ax_overtime, color=LEFT_COLOUR)
    ax_overtime.set_title("Attrition rate by overtime")
    ax_overtime.set_xlabel("Works overtime")
    ax_overtime.set_ylabel("Employees who left (%)")
    ax_overtime.tick_params(axis="x", rotation=0)

    role_rates = attrition_rate_by(employees, "JobRole")
    role_rates.index = role_rates.index.str.replace("_", " ")
    role_rates.plot.barh(ax=ax_role, color=LEFT_COLOUR)
    ax_role.set_title("Attrition rate by job role")
    ax_role.set_xlabel("Employees who left (%)")
    ax_role.set_ylabel("")

    fig.tight_layout()
    fig.savefig(FIG_DIR / "attrition_drivers.png", dpi=150)
    plt.close(fig)


# ---------------------------------------------------------------- models

def tune_svm(X_train: pd.DataFrame, y_train: pd.Series, cv: StratifiedKFold) -> Pipeline:
    """Grid-search an SVM. Features are standardised inside the pipeline so the
    scaler is re-fitted on every training fold and never sees validation rows."""
    pipeline = Pipeline([("scale", StandardScaler()), ("svc", SVC(random_state=SEED))])
    grid = [
        {"svc__kernel": ["linear"], "svc__C": [0.1, 1, 10]},
        {"svc__kernel": ["rbf"], "svc__C": [0.1, 1, 10], "svc__gamma": ["scale", 0.01, 0.1]},
    ]
    search = GridSearchCV(pipeline, grid, scoring="roc_auc", cv=cv, n_jobs=-1)
    search.fit(X_train, y_train)
    print(f"Best SVM settings: {search.best_params_} (cross-validated ROC-AUC {search.best_score_:.3f})")
    return search.best_estimator_


def choose_threshold(model, X_train, y_train, cv) -> tuple[float, pd.DataFrame]:
    """Pick the cut-off with the best F1 on out-of-fold training predictions."""
    oof_probability = cross_val_predict(model, X_train, y_train, cv=cv, method="predict_proba")[:, 1]
    precision, recall, thresholds = precision_recall_curve(y_train, oof_probability)
    f1 = 2 * precision * recall / (precision + recall + 1e-12)
    curve = pd.DataFrame({"threshold": thresholds, "precision": precision[:-1],
                          "recall": recall[:-1], "f1": f1[:-1]})
    best = curve.loc[curve["f1"].idxmax()]
    return float(best["threshold"]), curve


def score(name: str, y_true, probability, threshold: float) -> dict:
    predicted = (probability >= threshold).astype(int)
    return {
        "model": name,
        "threshold": round(threshold, 2),
        "accuracy": accuracy_score(y_true, predicted),
        "recall": recall_score(y_true, predicted),
        "precision": precision_score(y_true, predicted, zero_division=0),
        "f1": f1_score(y_true, predicted),
        "roc_auc": roc_auc_score(y_true, probability),
    }


# ---------------------------------------------------------------- charts

def plot_evaluation(y_test, probabilities: dict, curve: pd.DataFrame, threshold: float) -> None:
    fig, (ax_roc, ax_threshold) = plt.subplots(1, 2, figsize=(13, 4.5))

    for name, probability in probabilities.items():
        RocCurveDisplay.from_predictions(y_test, probability, name=name, ax=ax_roc)
    ax_roc.plot([0, 1], [0, 1], linestyle="--", color="grey", label="Random guess")
    ax_roc.set_title("ROC curves on the test set")
    ax_roc.legend()

    for column in ("precision", "recall", "f1"):
        ax_threshold.plot(curve["threshold"], curve[column], label=column.capitalize(),
                          linestyle="--" if column == "f1" else "-")
    ax_threshold.axvline(0.5, color="grey", linestyle=":", label="Default 0.50")
    ax_threshold.axvline(threshold, color=LEFT_COLOUR, label=f"Chosen {threshold:.2f}")
    ax_threshold.set_title("SVM: effect of the cut-off (training folds)")
    ax_threshold.set_xlabel("Probability cut-off for flagging an employee")
    ax_threshold.legend()

    fig.tight_layout()
    fig.savefig(FIG_DIR / "model_evaluation.png", dpi=150)
    plt.close(fig)


def plot_confusion(y_test, probability, threshold: float) -> None:
    fig, axes = plt.subplots(1, 2, figsize=(10, 4))
    for ax, cut_off in zip(axes, (0.5, threshold)):
        ConfusionMatrixDisplay.from_predictions(
            y_test, (probability >= cut_off).astype(int),
            display_labels=["Stayed", "Left"], colorbar=False, ax=ax, cmap="Blues",
        )
        ax.set_title(f"SVM at cut-off {cut_off:.2f}")
    fig.tight_layout()
    fig.savefig(FIG_DIR / "confusion_matrices.png", dpi=150)
    plt.close(fig)


# ---------------------------------------------------------------- main

def main() -> None:
    FIG_DIR.mkdir(exist_ok=True)
    pd.set_option("display.width", 140)

    employees = load_data()
    print(f"{len(employees)} employees, {employees['Attrition'].mean():.1%} left the company")

    for column in ("OverTime", "MaritalStatus", "BusinessTravel", "JobSatisfaction"):
        print(f"\nAttrition rate (%) by {column}:")
        print(attrition_rate_by(employees, column).round(1).to_string())
    print("\nAverages for stayers (0) and leavers (1):")
    print(employees.groupby("Attrition")[["Age", "MonthlyIncome", "TotalWorkingYears",
                                           "YearsAtCompany", "DistanceFromHome"]].mean().round(1))
    plot_drivers(employees)

    # One-hot encode the categorical columns; keep 20% of employees for the final test.
    X = pd.get_dummies(employees.drop(columns="Attrition"), drop_first=True, dtype=int)
    y = employees["Attrition"]
    X_train, X_test, y_train, y_test = train_test_split(
        X, y, test_size=0.20, stratify=y, random_state=SEED
    )
    cv = StratifiedKFold(n_splits=5, shuffle=True, random_state=SEED)

    naive_bayes = GaussianNB().fit(X_train, y_train)

    # SVMs output a distance, not a probability. Calibration converts it to a
    # probability HR can read, using cross-validation inside the training set.
    best_svm = tune_svm(X_train, y_train, cv)
    svm = CalibratedClassifierCV(best_svm, method="sigmoid", cv=cv)
    threshold, curve = choose_threshold(svm, X_train, y_train, cv)
    svm.fit(X_train, y_train)
    print(f"Cut-off with the best F1 on the training folds: {threshold:.2f}")

    probabilities = {
        "Naive Bayes": naive_bayes.predict_proba(X_test)[:, 1],
        "SVM": svm.predict_proba(X_test)[:, 1],
    }
    results = pd.DataFrame([
        score("Naive Bayes", y_test, probabilities["Naive Bayes"], 0.5),
        score("SVM", y_test, probabilities["SVM"], 0.5),
        score("SVM, tuned cut-off", y_test, probabilities["SVM"], threshold),
    ]).set_index("model")
    print("\nTest-set results (294 employees the models never saw):")
    print(results.round(3))

    flagged = int((probabilities["SVM"] >= threshold).sum())
    caught = int(((probabilities["SVM"] >= threshold) & (y_test == 1)).sum())
    print(f"\nAt the tuned cut-off HR would review {flagged} employees and reach "
          f"{caught} of the {int(y_test.sum())} who actually left.")

    plot_evaluation(y_test, probabilities, curve, threshold)
    plot_confusion(y_test, probabilities["SVM"], threshold)


if __name__ == "__main__":
    main()

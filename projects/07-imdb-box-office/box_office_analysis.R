# What explains the box office of IMDb's Top 250 films?
#
# Tests three hypotheses from a team statistics project:
#   H1  higher-rated films earn more
#   H2  bigger budgets earn more
#   H3  box office differs by age certificate
# then puts all three in one regression and checks it with ridge regression.
#
# Run from the project folder: Rscript box_office_analysis.R

library(tidyverse)
library(glmnet)

data_dir <- "data"
fig_dir <- "figures"
dir.create(fig_dir, showWarnings = FALSE)
set.seed(2023)

# ---- Load and clean ---------------------------------------------------------

# "2h 22m" -> 142
to_minutes <- function(run_time) {
  hours <- as.numeric(str_extract(run_time, "\\d+(?=h)"))
  minutes <- as.numeric(str_extract(run_time, "\\d+(?=m)"))
  coalesce(hours, 0) * 60 + coalesce(minutes, 0)
}

# No film on the list cost more than about $360 million. Larger "budgets" are
# amounts in a local currency (yen, rupees) with the symbol stripped, so they
# are treated as missing instead of being read as dollars.
MAX_PLAUSIBLE_BUDGET <- 4e8

films <- read_csv(file.path(data_dir, "imdb_top_250.csv"), col_types = cols(.default = col_character())) |>
  transmute(
    rank = as.integer(rank),
    name,
    rating = as.numeric(rating),
    certificate,
    run_time = to_minutes(run_time),
    budget = suppressWarnings(as.numeric(budget)), # "Not Available" -> NA
    box_office = suppressWarnings(as.numeric(box_office)),
    budget = if_else(budget > MAX_PLAUSIBLE_BUDGET, NA_real_, budget)
  )

cat(sprintf(
  "%d films; box office known for %d, budget for %d\n",
  nrow(films), sum(!is.na(films$box_office)), sum(!is.na(films$budget))
))

# Box office and budget span seven orders of magnitude and are heavily
# right-skewed, so every model works with base-10 logs.
complete <- films |>
  drop_na(box_office, budget) |>
  mutate(log_box_office = log10(box_office), log_budget = log10(budget))
cat(sprintf("%d films with both figures are used in the models\n", nrow(complete)))

report <- function(model, term) {
  row <- summary(model)$coefficients[term, ]
  cat(sprintf(
    "  %s: estimate %.3f, p-value %.4g, R-squared %.3f\n",
    term, row["Estimate"], row["Pr(>|t|)"], summary(model)$r.squared
  ))
}

# ---- H1: rating -------------------------------------------------------------

cat("\nH1: do higher-rated films earn more?\n")
model_rating <- lm(log_box_office ~ rating, data = complete)
report(model_rating, "rating")

# ---- H2: budget -------------------------------------------------------------

cat("\nH2: do bigger budgets earn more?\n")
model_budget <- lm(log_box_office ~ log_budget, data = complete)
report(model_budget, "log_budget")
cat("  (log-log model: the estimate is the % change in box office for a 1% larger budget)\n")

plot_budget <- ggplot(complete, aes(budget, box_office)) +
  geom_point(alpha = 0.6, colour = "#0f6e6e") +
  geom_smooth(method = "lm", formula = y ~ x, colour = "black", linewidth = 0.6) +
  geom_abline(slope = 1, intercept = 0, linetype = "dashed", colour = "grey50") +
  scale_x_log10(labels = scales::label_dollar(scale_cut = scales::cut_short_scale())) +
  scale_y_log10(labels = scales::label_dollar(scale_cut = scales::cut_short_scale())) +
  labs(
    title = "Bigger budgets, bigger box office",
    subtitle = "IMDb Top 250 films. Dashed line: box office equals budget",
    x = "Budget (log scale)", y = "Worldwide box office (log scale)"
  ) +
  theme_minimal(base_size = 12)
ggsave(file.path(fig_dir, "budget_vs_box_office.png"), plot_budget, width = 7, height = 4.5, dpi = 150)

# ---- H3: certificate --------------------------------------------------------

cat("\nH3: does box office differ by age certificate?\n")
# Keep certificates with at least 10 films so every group mean is meaningful.
by_certificate <- films |>
  drop_na(box_office) |>
  add_count(certificate, name = "films_in_group") |>
  filter(films_in_group >= 10) |>
  mutate(log_box_office = log10(box_office))

certificate_summary <- by_certificate |>
  group_by(certificate) |>
  summarise(films = n(), median_box_office_musd = median(box_office) / 1e6, .groups = "drop") |>
  arrange(desc(median_box_office_musd))
print(certificate_summary)

anova_certificate <- aov(log_box_office ~ certificate, data = by_certificate)
print(summary(anova_certificate))
print(kruskal.test(box_office ~ certificate, data = by_certificate)) # no normality assumption

plot_certificate <- ggplot(
  by_certificate,
  aes(x = reorder(certificate, box_office, FUN = median), y = box_office)
) +
  geom_boxplot(fill = "#e8f1f0", colour = "#0f6e6e", outlier.alpha = 0.5) +
  scale_y_log10(labels = scales::label_dollar(scale_cut = scales::cut_short_scale())) +
  coord_flip() +
  labs(
    title = "Box office by age certificate",
    x = NULL, y = "Worldwide box office (log scale)"
  ) +
  theme_minimal(base_size = 12)
ggsave(file.path(fig_dir, "box_office_by_certificate.png"), plot_certificate, width = 7, height = 4.5, dpi = 150)

# ---- All factors together ---------------------------------------------------

cat("\nMultiple regression: rating, budget, running time and certificate together\n")
model_data <- complete |>
  mutate(certificate = fct_lump_min(certificate, min = 10, other_level = "Other")) |>
  mutate(certificate = fct_relevel(certificate, "R")) # most common group as baseline

model_full <- lm(log_box_office ~ rating + log_budget + run_time + certificate, data = model_data)
print(round(summary(model_full)$coefficients, 4))
cat(sprintf("Adjusted R-squared: %.3f\n", summary(model_full)$adj.r.squared))

# ---- Ridge regression as a robustness check ---------------------------------

# Budget, rating and certificate are correlated with each other. Ridge shrinks
# coefficients towards zero, which shows whether the OLS signs are stable.
x <- model.matrix(log_box_office ~ rating + log_budget + run_time + certificate, data = model_data)[, -1]
y <- model_data$log_box_office

ridge_cv <- cv.glmnet(x, y, alpha = 0, nfolds = 10)
cat(sprintf("\nRidge: best lambda %.4f (10-fold cross-validation)\n", ridge_cv$lambda.min))

comparison <- tibble(
  term = colnames(x),
  ols = coef(model_full)[-1],
  ridge = as.numeric(coef(ridge_cv, s = "lambda.min"))[-1]
)
print(comparison |> mutate(across(c(ols, ridge), \(v) round(v, 4))))

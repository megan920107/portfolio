# A/B test: should the company switch to the new landing page?
#
# `analyze_ab_test()` compares the conversion rate of a control group and a
# treatment group. A logistic regression then checks whether the answer
# differs by country.
#
# Run from the project folder: Rscript 06_ab_test_analysis.R

library(tidyverse)

data_dir <- "data"
fig_dir <- "figures"
dir.create(fig_dir, showWarnings = FALSE)

# Compare two groups of 0/1 conversion outcomes.
#
# H0: the treatment converts no better than the control.
# H1: the treatment converts better (one-sided two-proportion z-test).
#
# Returns the two conversion rates, the lift, the p-value and the decision.
analyze_ab_test <- function(control, treatment, alpha = 0.05) {
  stopifnot(all(control %in% c(0, 1)), all(treatment %in% c(0, 1)))

  test <- prop.test(
    x = c(sum(treatment), sum(control)),
    n = c(length(treatment), length(control)),
    alternative = "greater",
    correct = FALSE
  )
  list(
    control_rate = mean(control),
    treatment_rate = mean(treatment),
    lift = mean(treatment) - mean(control),
    p_value = test$p.value,
    significant = test$p.value < alpha
  )
}

visits <- read_csv(file.path(data_dir, "ecommerce.csv"), show_col_types = FALSE) |>
  select(user_id, group, converted, country) |>
  drop_na(converted)

cat(sprintf("%d visits\n", nrow(visits)))
print(count(visits, group))

# ---- Overall result ---------------------------------------------------------

result <- analyze_ab_test(
  control = visits$converted[visits$group == "control"],
  treatment = visits$converted[visits$group == "treatment"],
  alpha = 0.05
)
cat(sprintf(
  "Control %.2f%%, treatment %.2f%%, lift %+.2f points, p-value %.4f -> %s\n",
  100 * result$control_rate, 100 * result$treatment_rate, 100 * result$lift, result$p_value,
  if (result$significant) "switch to the new page" else "no evidence the new page is better"
))

# ---- Does the effect differ by country? -------------------------------------

by_country <- visits |>
  group_by(country, group) |>
  summarise(
    visits = n(),
    rate = mean(converted),
    std_error = sqrt(rate * (1 - rate) / visits),
    .groups = "drop"
  )
print(by_country)

# Logistic regression with a group x country interaction. If the interaction
# terms are not significant, the page effect is the same in every country.
main_model <- glm(converted ~ group + country, data = visits, family = binomial)
interaction_model <- glm(converted ~ group * country, data = visits, family = binomial)
print(summary(interaction_model)$coefficients)
print(anova(main_model, interaction_model, test = "Chisq"))

plot_country <- ggplot(by_country, aes(x = country, y = rate, fill = group)) +
  geom_col(position = position_dodge(width = 0.8), width = 0.7) +
  geom_errorbar(
    aes(ymin = rate - 1.96 * std_error, ymax = rate + 1.96 * std_error),
    position = position_dodge(width = 0.8), width = 0.2
  ) +
  scale_y_continuous(labels = scales::percent) +
  scale_fill_manual(values = c(control = "#9aa5b1", treatment = "#0f6e6e")) +
  labs(
    title = "Conversion rate by country and page version",
    subtitle = "Error bars show 95% confidence intervals",
    x = "Country", y = "Conversion rate", fill = NULL
  ) +
  theme_minimal(base_size = 12)

ggsave(file.path(fig_dir, "ab_test_by_country.png"), plot_country, width = 7, height = 4, dpi = 150)

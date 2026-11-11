# Principal component analysis of company financial ratios
#
# Sixteen ratios describe each listed company. PCA shows which few dimensions
# (profitability, solvency, growth ...) carry most of the information.
#
# Run from the project folder: Rscript 04_financial_ratios_pca.R

library(tidyverse)

data_dir <- "data"
fig_dir <- "figures"
dir.create(fig_dir, showWarnings = FALSE)

# Some columns arrive as text (thousands separators, stray symbols), so read
# everything as text and convert explicitly.
ratios <- read_csv(
  file.path(data_dir, "financialdata.csv"),
  col_types = cols(.default = col_character())
) |>
  rename(quick_ratio = quick_rartio, equity_turnover = equity_turnnover) |> # fix typos in the source file
  mutate(across(-comp_id, ~ suppressWarnings(parse_number(.x)))) |>
  drop_na()

cat(sprintf("%d companies with complete data\n", nrow(ratios)))
features <- ratios |> select(-comp_id)

# ---- Correlation between ratios ---------------------------------------------

tile_theme <- theme_minimal(base_size = 11) +
  theme(axis.text.x = element_text(angle = 45, hjust = 1), axis.title = element_blank())

correlations <- cor(features) |>
  as.data.frame() |>
  rownames_to_column("ratio_a") |>
  pivot_longer(-ratio_a, names_to = "ratio_b", values_to = "correlation")

plot_correlation <- ggplot(correlations, aes(ratio_a, ratio_b, fill = correlation)) +
  geom_tile(colour = "white") +
  scale_fill_gradient2(low = "firebrick4", mid = "white", high = "steelblue", midpoint = 0, limits = c(-1, 1)) +
  labs(title = "Correlation between financial ratios", fill = "Correlation") +
  tile_theme

ggsave(file.path(fig_dir, "pca_correlation_heatmap.png"), plot_correlation, width = 7.5, height = 6, dpi = 150)

# ---- PCA --------------------------------------------------------------------

# Ratios are on very different scales, so centre and standardise first.
pca <- prcomp(features, center = TRUE, scale. = TRUE)

variance <- tibble(
  component = seq_along(pca$sdev),
  eigenvalue = pca$sdev^2,
  share = eigenvalue / sum(eigenvalue),
  cumulative_share = cumsum(share)
)
print(variance, n = Inf)

# Kaiser rule: keep components whose eigenvalue is above 1.
n_keep <- sum(variance$eigenvalue > 1)
cat(sprintf(
  "Kaiser rule keeps %d components; the first two explain %.1f%% of the variance\n",
  n_keep, 100 * variance$cumulative_share[2]
))

plot_scree <- ggplot(variance, aes(component, eigenvalue)) +
  geom_line() +
  geom_point() +
  geom_hline(yintercept = 1, linetype = "dashed", colour = "steelblue") +
  labs(title = "Scree plot", x = "Principal component", y = "Eigenvalue") +
  theme_minimal(base_size = 12)
ggsave(file.path(fig_dir, "pca_scree.png"), plot_scree, width = 6, height = 4, dpi = 150)

# ---- Which ratios define each component? ------------------------------------

loadings <- pca$rotation[, 1:5] |>
  as.data.frame() |>
  rownames_to_column("ratio") |>
  pivot_longer(-ratio, names_to = "component", values_to = "loading")

cat("\nThree largest loadings on each of the first three components:\n")
loadings |>
  filter(component %in% c("PC1", "PC2", "PC3")) |>
  group_by(component) |>
  slice_max(abs(loading), n = 3) |>
  print()

plot_loadings <- ggplot(loadings, aes(component, ratio, fill = loading)) +
  geom_tile(colour = "white") +
  scale_fill_gradient2(low = "firebrick4", mid = "white", high = "steelblue", midpoint = 0) +
  labs(title = "Loadings of the first five components", fill = "Loading") +
  tile_theme

ggsave(file.path(fig_dir, "pca_loadings.png"), plot_loadings, width = 6, height = 6, dpi = 150)

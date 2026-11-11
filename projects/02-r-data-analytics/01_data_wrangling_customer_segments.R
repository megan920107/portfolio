# Data wrangling and customer segment profiling
#
# Part 1 reshapes a wide stock-price table (one column per trading day) into
# tidy format. Part 2 joins three e-commerce tables and compares premium
# members (gold / diamond) with everyone else.
#
# Run from the project folder: Rscript 01_data_wrangling_customer_segments.R

library(tidyverse)

data_dir <- "data"
fig_dir <- "figures"
dir.create(fig_dir, showWarnings = FALSE)

# ---- Part 1: tidy the stock table -------------------------------------------

# Raw layout: one row per (stock, price type), one column per date.
# Tidy layout: one row per (stock, date), one column per price type.
stock <- read_csv(file.path(data_dir, "stock.csv"), show_col_types = FALSE) |>
  separate(id_name, into = c("id", "name"), sep = " ", convert = TRUE) |>
  pivot_longer(matches("^\\d{4}/"), names_to = "date", values_to = "price") |>
  pivot_wider(names_from = type, values_from = price) |>
  mutate(date = as.Date(date, format = "%Y/%m/%d")) |>
  arrange(id, date)

print(stock)

# ---- Part 2: build one sales table ------------------------------------------

sales <- read_csv(file.path(data_dir, "salesdata.csv"), show_col_types = FALSE) |>
  select(-1) # drop the unnamed row-number column
clients <- read_csv(file.path(data_dir, "client_list.csv"), show_col_types = FALSE) |>
  select(-1)

# The product file stores "101_iPhone" in a single column; split it in two.
products <- read_csv(file.path(data_dir, "product_list.csv"), show_col_types = FALSE) |>
  separate(Item, into = c("Product", "Item"), sep = "_", convert = TRUE)

full_table <- sales |>
  left_join(clients, by = "Client") |>
  left_join(products, by = "Product") |>
  mutate(
    Spend = UnitPrice * Quantity,
    Segment = if_else(Membership %in% c("gold", "diamond"), "gold_diamond", "other")
  )

# One row per client, so that people with many orders are not counted twice.
client_summary <- full_table |>
  group_by(Client, Segment, Age, Gender, Membership) |>
  summarise(
    orders = n(),
    total_spend = sum(Spend),
    main_region = names(which.max(table(Region))),
    .groups = "drop"
  )

# ---- Compare the two segments -----------------------------------------------

segment_profile <- client_summary |>
  group_by(Segment) |>
  summarise(
    clients = n(),
    avg_age = mean(Age),
    share_female = mean(Gender == "female"),
    avg_orders = mean(orders),
    avg_spend_per_client = mean(total_spend),
    .groups = "drop"
  )
print(segment_profile)

region_mix <- client_summary |>
  count(Segment, main_region) |>
  group_by(Segment) |>
  mutate(share = n / sum(n)) |>
  arrange(Segment, desc(share))
print(region_mix, n = Inf)

# ---- Focus on female customers ----------------------------------------------

female_profile <- client_summary |>
  filter(Gender == "female") |>
  summarise(clients = n(), avg_age = mean(Age), avg_spend_per_client = mean(total_spend))
print(female_profile)

female_spend_by_product <- full_table |>
  filter(Gender == "female") |>
  group_by(Item) |>
  summarise(total_spend = sum(Spend), .groups = "drop")

plot_female <- ggplot(female_spend_by_product, aes(x = reorder(Item, -total_spend), y = total_spend)) +
  geom_col(fill = "#0f6e6e") +
  labs(
    title = "Female customers: total spend by product",
    x = NULL, y = "Total spend"
  ) +
  theme_minimal(base_size = 12)

ggsave(file.path(fig_dir, "female_spend_by_product.png"), plot_female, width = 7, height = 4, dpi = 150)

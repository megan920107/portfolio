# Airline passenger satisfaction: what drives it, and who are the customers?
#
# Part 1 fits a decision tree to predict satisfaction and reads off the rules.
# Part 2 clusters passengers on their service ratings with k-means and
# profiles each cluster.
#
# Run from the project folder: Rscript 03_airline_satisfaction_tree_kmeans.R

library(tidyverse)
library(rpart)
library(rpart.plot)
library(factoextra)

data_dir <- "data"
fig_dir <- "figures"
dir.create(fig_dir, showWarnings = FALSE)
set.seed(125)

survey <- read_csv(file.path(data_dir, "airline_survey.csv"), show_col_types = FALSE) |>
  rename_with(make.names) |> # "Customer Type" -> "Customer.Type"
  mutate(satisfaction = factor(satisfaction))

# ---- Part 1: decision tree --------------------------------------------------

model_data <- survey |>
  select(
    satisfaction, Gender, Customer.Type, Type.of.Travel, Age, Class,
    Inflight.wifi.service, Departure.Arrival.time.convenient, Cleanliness,
    Gate.location, Food.and.drink, On.board.service
  )

# 70 / 30 train-test split
train_rows <- sample(nrow(model_data), size = floor(0.7 * nrow(model_data)))
train <- model_data[train_rows, ]
test <- model_data[-train_rows, ]

tree <- rpart(satisfaction ~ ., data = train, method = "class")
predicted <- predict(tree, newdata = test, type = "class")

confusion <- table(Actual = test$satisfaction, Predicted = predicted)
accuracy <- sum(diag(confusion)) / sum(confusion)
print(confusion)
cat(sprintf("Test accuracy: %.1f%%\n", 100 * accuracy))

cat("\nVariable importance (share of total):\n")
print(round(tree$variable.importance / sum(tree$variable.importance), 3))

cat("\nDecision rules:\n")
rpart.rules(tree, cover = TRUE)

png(file.path(fig_dir, "airline_decision_tree.png"), width = 1400, height = 800, res = 150)
rpart.plot(tree, main = "What predicts a satisfied passenger?")
dev.off()

# ---- Part 2: k-means on service ratings -------------------------------------

service_vars <- c(
  "Inflight.wifi.service", "Departure.Arrival.time.convenient", "Cleanliness",
  "Gate.location", "Food.and.drink", "On.board.service"
)
ratings <- survey[, service_vars] # all on the same 0-5 scale, so no rescaling

# Choosing k needs pairwise distances, so use a random sample for that step.
ratings_sample <- ratings[sample(nrow(ratings), 2000), ]

plot_elbow <- fviz_nbclust(ratings_sample, kmeans, method = "wss", k.max = 10) +
  geom_vline(xintercept = 3, linetype = 2) +
  labs(title = "Elbow method")
plot_silhouette <- fviz_nbclust(ratings_sample, kmeans, method = "silhouette", k.max = 10) +
  labs(title = "Silhouette method")
ggsave(file.path(fig_dir, "airline_elbow.png"), plot_elbow, width = 6, height = 4, dpi = 150)
ggsave(file.path(fig_dir, "airline_silhouette.png"), plot_silhouette, width = 6, height = 4, dpi = 150)

# Fit the final model on every passenger.
clusters <- kmeans(ratings, centers = 3, nstart = 25)
survey$cluster <- factor(clusters$cluster)

cluster_profile <- survey |>
  group_by(cluster) |>
  summarise(
    passengers = n(),
    share_satisfied = mean(satisfaction == "satisfied"),
    across(all_of(service_vars), mean),
    .groups = "drop"
  )
print(cluster_profile, width = Inf)

plot_profile <- cluster_profile |>
  pivot_longer(all_of(service_vars), names_to = "service", values_to = "avg_rating") |>
  mutate(service = str_replace_all(service, "\\.", " ")) |>
  ggplot(aes(x = service, y = avg_rating, fill = cluster)) +
  geom_col(position = "dodge") +
  coord_flip() +
  labs(
    title = "Average service rating by customer cluster",
    x = NULL, y = "Average rating (0-5)", fill = "Cluster"
  ) +
  theme_minimal(base_size = 12)

ggsave(file.path(fig_dir, "airline_cluster_profile.png"), plot_profile, width = 8, height = 4.5, dpi = 150)

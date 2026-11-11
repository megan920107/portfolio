# Text mining of IMDb reviews for the most-reviewed film of 2022
#
# Cleans the review text, counts the most frequent words, and scores the
# sentiment of every review with a dictionary-based method.
#
# Run from the project folder: Rscript 05_imdb_text_mining_sentiment.R

library(tidyverse)
library(tm)
library(SentimentAnalysis)

data_dir <- "data"
fig_dir <- "figures"
dir.create(fig_dir, showWarnings = FALSE)

reviews_all <- read_csv(
  file.path(data_dir, "IMDb_Feature Film_2022_review_data.csv"),
  show_col_types = FALSE
)

# ---- Pick the film with the most reviews ------------------------------------

top_film <- reviews_all |>
  count(Title, sort = TRUE) |>
  slice(1) |>
  pull(Title)
reviews <- reviews_all |>
  filter(Title == top_film, !is.na(Review)) |>
  pull(Review)
cat(sprintf("Most-reviewed film: %s (%d reviews)\n", top_film, length(reviews)))

# ---- Clean the text and count words -----------------------------------------

corpus <- VCorpus(VectorSource(reviews)) |>
  tm_map(content_transformer(tolower)) |>
  tm_map(removePunctuation) |>
  tm_map(removeNumbers) |>
  tm_map(removeWords, stopwords("english")) |>
  tm_map(stripWhitespace)

term_matrix <- TermDocumentMatrix(corpus)
word_counts <- tibble(
  word = rownames(term_matrix),
  n = slam::row_sums(term_matrix) # sums the sparse matrix without expanding it
) |>
  arrange(desc(n))

print(head(word_counts, 20))

plot_words <- word_counts |>
  slice_head(n = 20) |>
  ggplot(aes(x = reorder(word, n), y = n)) +
  geom_col(fill = "#0f6e6e") +
  coord_flip() +
  labs(title = paste("Most frequent words in reviews of", top_film), x = NULL, y = "Count") +
  theme_minimal(base_size = 12)
ggsave(file.path(fig_dir, "imdb_top_words.png"), plot_words, width = 7, height = 5, dpi = 150)

# Interactive word cloud (opens in the RStudio viewer):
# wordcloud2::wordcloud2(as.data.frame(head(word_counts, 300)))

# ---- Sentiment --------------------------------------------------------------

sentiment <- analyzeSentiment(reviews)

review_scores <- tibble(
  word_count = sentiment$WordCount,
  score = sentiment$SentimentQDAP, # QDAP dictionary, from -1 (negative) to +1 (positive)
  direction = convertToDirection(sentiment$SentimentQDAP)
) |>
  filter(!is.na(score))

cat("\nReview length (words):\n")
print(summary(review_scores$word_count))

cat("\nShare of reviews by sentiment:\n")
print(round(prop.table(table(review_scores$direction)), 3))
cat(sprintf("Average sentiment score: %.3f\n", mean(review_scores$score)))

plot_sentiment <- ggplot(review_scores, aes(score)) +
  geom_histogram(bins = 40, fill = "#0f6e6e") +
  geom_vline(xintercept = 0, linetype = "dashed") +
  labs(
    title = paste("Sentiment of reviews of", top_film),
    x = "Sentiment score (QDAP dictionary)", y = "Number of reviews"
  ) +
  theme_minimal(base_size = 12)
ggsave(file.path(fig_dir, "imdb_sentiment.png"), plot_sentiment, width = 7, height = 4, dpi = 150)

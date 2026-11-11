# Monte Carlo simulation of the casino game craps
#
# Estimates the probability of winning a pass-line bet and the expected value
# of a bet, then checks the estimate against the known exact answer (244/495).
#
# Run from the project folder: Rscript 02_craps_simulation.R

library(ggplot2)

fig_dir <- "figures"
dir.create(fig_dir, showWarnings = FALSE)

roll_dice <- function() sum(sample(1:6, 2, replace = TRUE))

# Play one round. Returns TRUE for a win, FALSE for a loss.
play_one_round <- function() {
  first_roll <- roll_dice()
  if (first_roll %in% c(7, 11)) return(TRUE)
  if (first_roll %in% c(2, 3, 12)) return(FALSE)

  # Any other total becomes the "point": keep rolling until it repeats (win)
  # or a 7 shows up (loss).
  point <- first_roll
  repeat {
    next_roll <- roll_dice()
    if (next_roll == point) return(TRUE)
    if (next_roll == 7) return(FALSE)
  }
}

# Simulate many rounds and summarise an even-money bet of `bet_size`.
simulate_craps <- function(n_rounds, bet_size) {
  wins <- replicate(n_rounds, play_one_round())
  win_prob <- mean(wins)
  list(
    n_rounds = n_rounds,
    win_prob = win_prob,
    expected_value = bet_size * (2 * win_prob - 1),
    wins = wins
  )
}

set.seed(2024)
exact_win_prob <- 244 / 495

scenarios <- list(
  c(n_rounds = 10, bet_size = 100),
  c(n_rounds = 1000, bet_size = 5),
  c(n_rounds = 10000, bet_size = 10)
)
for (s in scenarios) {
  result <- simulate_craps(s[["n_rounds"]], s[["bet_size"]])
  cat(sprintf(
    "%6d rounds, bet %3d: win probability %.4f (exact %.4f), expected value per bet %+.3f\n",
    result$n_rounds, s[["bet_size"]], result$win_prob, exact_win_prob, result$expected_value
  ))
}

# How quickly does the estimate settle near the exact value?
long_run <- simulate_craps(10000, 10)
convergence <- data.frame(
  round = seq_along(long_run$wins),
  running_win_prob = cumsum(long_run$wins) / seq_along(long_run$wins)
)

plot_convergence <- ggplot(convergence, aes(round, running_win_prob)) +
  geom_line(colour = "#0f6e6e") +
  geom_hline(yintercept = exact_win_prob, linetype = "dashed") +
  scale_x_log10() +
  labs(
    title = "Craps: simulated win probability converges to 244/495",
    x = "Rounds played (log scale)", y = "Running win probability"
  ) +
  theme_minimal(base_size = 12)

ggsave(file.path(fig_dir, "craps_convergence.png"), plot_convergence, width = 7, height = 4, dpi = 150)

#!/usr/bin/env Rscript
# Publication figure: success rate vs. grid size, by reagent count, for the paper supplement.
#
# Reads results/comparison.csv (written by compare_results.py) and reproduces the same aggregation
# as plot_success_rate.py, in ggplot2/theme_classic() instead of matplotlib:
#   - Ferdosi et al. (red, one line per n_types): per-instance max(greedy_success_rate,
#     beam_search_success_rate), averaged over instances within each (grid_n, n_types) cell.
#   - Pourfecto (blue, single line): mean of pourfecto_success_rate over ALL instances per grid_n,
#     pooling across n_types -- collapsed from three lines to one because Pourfecto's planning-only
#     solve reached success_rate == 1.0 for every (grid_n, n_types) cell (see README.md), so the
#     three n_types lines have nothing to distinguish them.
#
# Output: results/success_rate_ggplot.pdf (vector, for submission) and
#         results/success_rate_ggplot.png (raster, for quick preview).

suppressMessages({
  library(dplyr)
  library(ggplot2)
})

here <- dirname(sub("--file=", "", grep("--file=", commandArgs(trailingOnly = FALSE), value = TRUE)))
if (length(here) == 0 || here == "") here <- "."

comparison <- read.csv(file.path(here, "results", "comparison.csv"))

ferdosi <- comparison %>%
  mutate(ferdosi_success_rate = pmax(greedy_success_rate, beam_search_success_rate)) %>%
  group_by(grid_n, n_types) %>%
  summarise(success_rate = mean(ferdosi_success_rate), .groups = "drop") %>%
  mutate(series = paste0("Ferdosi et al. (k=", n_types, ")"))

pourfecto <- comparison %>%
  group_by(grid_n) %>%
  summarise(success_rate = mean(pourfecto_success_rate), .groups = "drop") %>%
  mutate(n_types = NA_integer_, series = "Pourfecto")

# Ferdosi reds (darker = more reagents), single fixed blue for the collapsed Pourfecto line.
series_levels <- c("Pourfecto", "Ferdosi et al. (k=1)", "Ferdosi et al. (k=2)", "Ferdosi et al. (k=4)")
series_colors <- c(
  "Pourfecto" = "#2166AC",
  "Ferdosi et al. (k=1)" = "#FCA082",
  "Ferdosi et al. (k=2)" = "#EF3B2C",
  "Ferdosi et al. (k=4)" = "#99000D"
)
ferdosi$series <- factor(ferdosi$series, levels = series_levels)
pourfecto$series <- factor(pourfecto$series, levels = series_levels)

# Pourfecto's success_rate is 1.0 at every grid size, exactly coinciding with the k=1 Ferdosi
# line -- drawn as its own layer, added last (on top) with a dashed linetype and larger points, so
# it stays visible instead of being fully hidden underneath an overlapping series.
p <- ggplot(mapping = aes(x = grid_n, y = success_rate, color = series)) +
  geom_line(data = ferdosi, linewidth = 0.8) +
  geom_point(data = ferdosi, size = 2) +
  geom_line(data = pourfecto, linewidth = 1, linetype = "22") +
  geom_point(data = pourfecto, size = 2.6) +
  scale_color_manual(values = series_colors, name = NULL, drop = FALSE) +
  scale_x_continuous(breaks = sort(unique(comparison$grid_n))) +
  scale_y_continuous(limits = c(0, 1)) +
  labs(
    title = "Success rate vs. grid size, by reagent count",
    x = "Grid size (N x N)",
    y = "Success rate"
  ) +
  theme_classic(base_size = 12) +
  theme(legend.position = "right")

out_pdf <- file.path(here, "results", "success_rate_ggplot.pdf")
out_png <- file.path(here, "results", "success_rate_ggplot.png")
ggsave(out_pdf, p, width = 7, height = 5)
ggsave(out_png, p, width = 7, height = 5, dpi = 300)

cat("wrote", out_pdf, "\n")
cat("wrote", out_png, "\n")

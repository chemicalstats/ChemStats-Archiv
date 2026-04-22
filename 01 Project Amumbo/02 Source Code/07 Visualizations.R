########################################################################################################################
# Vorbereitung des Systems
########################################################################################################################
packages <- c("tidyverse", "stringr", "plotly", "RColorBrewer", "purrr", "scales", "htmlwidgets")
invisible(lapply(packages, library, character.only = TRUE)); rm(packages)
if(.Platform$OS.type == "windows"){Sys.setlocale("LC_ALL", "en_US.UTF-8")}


########################################################################################################################
# Variante 1: Grafiken für die empirische Verteilung über SMA-Werte
########################################################################################################################
num_categories <- 60
categories <- seq(10, 600, by = 10)
palette <- hue_pal()(num_categories)

darken_color <- function(color, factor = 0.8){
  rgb_val <- col2rgb(color) / 255
  rgb(rgb_val[1] * factor, rgb_val[2] * factor, rgb_val[3] * factor)
}

years <- c(10, 20, 30, 40)

# --- Hilfsfunktion für Boxplot-Erstellung
make_plot <- function(data, metric, year_label, range_ub, range_lb, show_x = FALSE){
  p <- plot_ly(type = "box", showlegend = FALSE)
  for(i in seq_along(categories)){
    cat_data <- filter(data, SMA == categories[i])
    p <- add_trace(p,
                   y = cat_data[[metric]],
                   name = categories[i],
                   fillcolor = palette[i],
                   line = list(color = darken_color(palette[i], 0.7), width = 2),
                   marker = list(color = darken_color(palette[i], 0.7)))
  }
  y_title <- if(metric == "TTWROR"){
    paste0(year_label, " Years\nTrue Time Weighted Rates of Returns")
  } else {
    paste0("Maximum Drawdowns\n", year_label, " Years")
  }
  layout(p,
         yaxis = list(title = y_title,
                      range = if (metric == "TTWROR") c(range_lb, range_ub) else c(-0.05, 1.05),
                      tick0 = if (metric == "TTWROR") -0.5 else 0,
                      dtick = 0.1, side = if (metric == "Max_DD") "right" else "left",
                      zeroline = FALSE, gridcolor = "black", gridwidth = 0.05),
         xaxis = list(title = if (show_x) "SMA" else NULL))
}

#---- Hauptschleife über alle Kombinationen - Lump Sum - Long x2
ttwror_ranges_ub <- c(0.45, 0.35, 0.25, 0.25)
ttwror_ranges_lb <- c(-.45, -.35, -.25, -.25)
data_path <- "./03 Results Data/03 Moving Average - Lump Sum/Simple Moving Average - Lump Sum - Long x2 - German Taxes"
plot_data <- map(years, ~ read.csv(paste0(data_path, " - ", .x, " Years.csv")) %>%
                   select(SMA, Max_DD, TTWROR))

plots <- map2(seq_along(plot_data), plot_data, function(i, df){
  list(
    make_plot(df, "TTWROR", years[i], ttwror_ranges_ub[i], ttwror_ranges_lb[i]),
    make_plot(df, "Max_DD", years[i],  ttwror_ranges_ub[i], ttwror_ranges_lb[i], show_x = (i == 4)))}) %>% purrr::flatten()

figure <- subplot(plots, nrows = 4, titleX = TRUE, titleY = TRUE) %>%
  layout(
    title = "Empirical Distributions of Strategy Simulation Metrics\nSimple Moving Average - Simulated Long x2 - Lump Sum",
    margin = list(t = 50),
    showlegend = FALSE)
saveWidget(figure, "Simple Moving Average - Simulated Long x2 - Lump Sum.html", selfcontained = TRUE)

#---- Hauptschleife über alle Kombinationen - DCA Hold - Long x2
data_path <- "./03 Results Data/03 Moving Average - Lump Sum/Simple Moving Average - DCA Hold - Long x2 - German Taxes"
plot_data <- map(years, ~ read.csv(paste0(data_path, " - ", .x, " Years.csv")) %>%
                   select(SMA, Max_DD, TTWROR))

plots <- map2(seq_along(plot_data), plot_data, function(i, df){
  list(
    make_plot(df, "TTWROR", years[i], ttwror_ranges_ub[i], ttwror_ranges_lb[i]),
    make_plot(df, "Max_DD", years[i],  ttwror_ranges_ub[i], ttwror_ranges_lb[i], show_x = (i == 4)))}) %>% purrr::flatten()

figure <- subplot(plots, nrows = 4, titleX = TRUE, titleY = TRUE) %>%
  layout(
    title = "Empirical Distributions of Strategy Simulation Metrics\nSimple Moving Average - Simulated Long x2 - DCA",
    margin = list(t = 50),
    showlegend = FALSE)
saveWidget(figure, "Simple Moving Average - Simulated Long x2 - DCA Hold.html", selfcontained = TRUE)

#---- Hauptschleife über alle Kombinationen - Lump Sum - Long x1
ttwror_ranges_ub <- c(0.45, 0.35, 0.25, 0.25)
ttwror_ranges_lb <- c(-.45, -.35, -.25, -.25)
data_path <- "./03 Results Data/03 Moving Average - Lump Sum/Simple Moving Average - Lump Sum - Long x1 - German Taxes"
plot_data <- map(years, ~ read.csv(paste0(data_path, " - ", .x, " Years.csv")) %>%
                   select(SMA, Max_DD, TTWROR))

plots <- map2(seq_along(plot_data), plot_data, function(i, df){
  list(
    make_plot(df, "TTWROR", years[i], ttwror_ranges_ub[i], ttwror_ranges_lb[i]),
    make_plot(df, "Max_DD", years[i],  ttwror_ranges_ub[i], ttwror_ranges_lb[i], show_x = (i == 4)))}) %>% purrr::flatten()

figure <- subplot(plots, nrows = 4, titleX = TRUE, titleY = TRUE) %>%
  layout(
    title = "Empirical Distributions of Strategy Simulation Metrics\nSimple Moving Average - Simulated Long x1 - Lump Sum",
    margin = list(t = 50),
    showlegend = FALSE)
saveWidget(figure, "Simple Moving Average - Simulated Long x1 - Lump Sum.html", selfcontained = TRUE)

#---- Hauptschleife über alle Kombinationen - DCA Hold - Long x1
data_path <- "./03 Results Data/03 Moving Average - Lump Sum/Simple Moving Average - DCA Hold - Long x1 - German Taxes"
plot_data <- map(years, ~ read.csv(paste0(data_path, " - ", .x, " Years.csv")) %>%
                   select(SMA, Max_DD, TTWROR))

plots <- map2(seq_along(plot_data), plot_data, function(i, df){
  list(
    make_plot(df, "TTWROR", years[i], ttwror_ranges_ub[i], ttwror_ranges_lb[i]),
    make_plot(df, "Max_DD", years[i],  ttwror_ranges_ub[i], ttwror_ranges_lb[i], show_x = (i == 4)))}) %>% purrr::flatten()

figure <- subplot(plots, nrows = 4, titleX = TRUE, titleY = TRUE) %>%
  layout(
    title = "Empirical Distributions of Strategy Simulation Metrics\nSimple Moving Average - Simulated Long x1 - DCA",
    margin = list(t = 50),
    showlegend = FALSE)
saveWidget(figure, "Simple Moving Average - Simulated Long x1 - DCA Hold.html", selfcontained = TRUE)

#---- Hauptschleife über alle Kombinationen - Lump Sum - Short x1
ttwror_ranges_ub <- c(0.25, 0.25, 0.15, 0.15)
ttwror_ranges_lb <- c(-.25, -.25, -.15, -.15)
data_path <- "./03 Results Data/03 Moving Average - Lump Sum/Simple Moving Average - Lump Sum - Short x1 - German Taxes"
plot_data <- map(years, ~ read.csv(paste0(data_path, " - ", .x, " Years.csv")) %>%
                   select(SMA, Max_DD, TTWROR))

plots <- map2(seq_along(plot_data), plot_data, function(i, df){
  list(
    make_plot(df, "TTWROR", years[i], ttwror_ranges_ub[i], ttwror_ranges_lb[i]),
    make_plot(df, "Max_DD", years[i],  ttwror_ranges_ub[i], ttwror_ranges_lb[i], show_x = (i == 4)))}) %>% purrr::flatten()

figure <- subplot(plots, nrows = 4, titleX = TRUE, titleY = TRUE) %>%
  layout(
    title = "Empirical Distributions of Strategy Simulation Metrics\nSimple Moving Average - Simulated Short x1 - Lump Sum",
    margin = list(t = 50),
    showlegend = FALSE)
saveWidget(figure, "Simple Moving Average - Simulated Short x1 - Lump Sum.html", selfcontained = TRUE)

#---- Hauptschleife über alle Kombinationen - DCA Hold - Short x1
data_path <- "./03 Results Data/03 Moving Average - Lump Sum/Simple Moving Average - DCA Hold - Short x1 - German Taxes"
plot_data <- map(years, ~ read.csv(paste0(data_path, " - ", .x, " Years.csv")) %>%
                   select(SMA, Max_DD, TTWROR))

plots <- map2(seq_along(plot_data), plot_data, function(i, df){
  list(
    make_plot(df, "TTWROR", years[i], ttwror_ranges_ub[i], ttwror_ranges_lb[i]),
    make_plot(df, "Max_DD", years[i],  ttwror_ranges_ub[i], ttwror_ranges_lb[i], show_x = (i == 4)))}) %>% purrr::flatten()

figure <- subplot(plots, nrows = 4, titleX = TRUE, titleY = TRUE) %>%
  layout(
    title = "Empirical Distributions of Strategy Simulation Metrics\nSimple Moving Average - Simulated Short x1 - DCA",
    margin = list(t = 50),
    showlegend = FALSE)
saveWidget(figure, "Simple Moving Average - Simulated Short x1 - DCA Hold.html", selfcontained = TRUE)

#---- Hauptschleife über alle Kombinationen - Lump Sum - Short x2
ttwror_ranges_ub <- c(0.45, 0.35, 0.25, 0.25)
ttwror_ranges_lb <- c(-.45, -.35, -.25, -.25)
data_path <- "./03 Results Data/03 Moving Average - Lump Sum/Simple Moving Average - Lump Sum - Short x2 - German Taxes"
plot_data <- map(years, ~ read.csv(paste0(data_path, " - ", .x, " Years.csv")) %>%
                   select(SMA, Max_DD, TTWROR))

plots <- map2(seq_along(plot_data), plot_data, function(i, df){
  list(
    make_plot(df, "TTWROR", years[i], ttwror_ranges_ub[i], ttwror_ranges_lb[i]),
    make_plot(df, "Max_DD", years[i],  ttwror_ranges_ub[i], ttwror_ranges_lb[i], show_x = (i == 4)))}) %>% purrr::flatten()

figure <- subplot(plots, nrows = 4, titleX = TRUE, titleY = TRUE) %>%
  layout(
    title = "Empirical Distributions of Strategy Simulation Metrics\nSimple Moving Average - Simulated Short x2 - Lump Sum",
    margin = list(t = 50),
    showlegend = FALSE)
saveWidget(figure, "Simple Moving Average - Simulated Short x2 - Lump Sum.html", selfcontained = TRUE)

#---- Hauptschleife über alle Kombinationen - DCA Hold - Short x2
data_path <- "./03 Results Data/03 Moving Average - Lump Sum/Simple Moving Average - DCA Hold - Short x2 - German Taxes"
plot_data <- map(years, ~ read.csv(paste0(data_path, " - ", .x, " Years.csv")) %>%
                   select(SMA, Max_DD, TTWROR))

plots <- map2(seq_along(plot_data), plot_data, function(i, df){
  list(
    make_plot(df, "TTWROR", years[i], ttwror_ranges_ub[i], ttwror_ranges_lb[i]),
    make_plot(df, "Max_DD", years[i],  ttwror_ranges_ub[i], ttwror_ranges_lb[i], show_x = (i == 4)))}) %>% purrr::flatten()

figure <- subplot(plots, nrows = 4, titleX = TRUE, titleY = TRUE) %>%
  layout(
    title = "Empirical Distributions of Strategy Simulation Metrics\nSimple Moving Average - Simulated Short x2 - DCA",
    margin = list(t = 50),
    showlegend = FALSE)
saveWidget(figure, "Simple Moving Average - Simulated Short x2 - DCA Hold.html", selfcontained = TRUE)


########################################################################################################################
# Variante 2: Grafiken für die Heatmaps über SMA-Werte
########################################################################################################################
col_ribbon <- c("rgba(0, 200, 0, 0.3)", "rgba(255, 165, 0, 0.3)", "rgba(255, 0, 0, 0.3)")
col_lines  <- c("rgba(0, 200, 0, 0.7)", "rgba(255, 165, 0, 0.7)", "rgba(255, 0, 0, 0.7)")

#---- Hilfsfunktion für Berechnung SMA-Bänder
get_band <- function(data, var, quant_level = NULL, direction = "high"){
  data %>%
    group_by(Start_Date) %>%
    filter({
      v <- .data[[var]]
      if(is.null(quant_level)){
        if(direction == "high") v >= max(v, na.rm = TRUE) else v <= min(v, na.rm = TRUE)
      } else {
        threshold <- quantile(v, probs = quant_level, na.rm = TRUE)
        if(direction == "high") v >= threshold else v <= threshold
      }}) %>%
    summarise(
      sma_min = min(SMA, na.rm = TRUE),
      sma_max = max(SMA, na.rm = TRUE),
      .groups = "drop") %>%
    mutate(sma_mean = (sma_min + sma_max) / 2)
}

#---- Hilfsfunktion für Erstellung Heatmap-Plots mit Bändern
plot_with_bands <- function(data, var, label, z_range, y_title, direction = "high", band_labels = c("25%", "10%", "Max/Min"), quant_levels = NULL) {
  fig <- plot_ly(
    x = as.Date(data$Start_Date), y = data$SMA, z = data[[var]],
    type = "heatmap", colorscale = list(c(0, "white"), c(1, "black")),
    zmin = z_range[1], zmax = z_range[2], showscale = FALSE)
  
  for(j in seq_along(quant_levels)){
    band <- get_band(data, var, quant_levels[j], direction)
    fig <- fig %>%
      add_trace(data = band, x = ~as.Date(Start_Date), y = ~sma_mean,
                type = "scatter", mode = "lines", name = band_labels[j],
                line = list(color = col_lines[[j]], width = 1.5), inherit = FALSE, showlegend = FALSE) %>%
      add_ribbons(data = band, x = ~as.Date(Start_Date), ymin = ~sma_min, ymax = ~sma_max,
                  fillcolor = col_ribbon[[j]], line = list(color = col_lines[[j]], width = 1),
                  name = band_labels[j], inherit = FALSE, showlegend = FALSE)}
  
  fig %>% layout(
    xaxis = list(title = ""),
    yaxis = list(title = paste(label, y_title), range = c(10, 600),
                 side = if(var == "Max_DD") "right" else "left"))
}

year_labels <- c("10", "20", "30", "40")

#---- Hauptschleife über alle Kombinationen - Lump Sum - Long x2
filenames <- paste0("./03 Results Data/03 Moving Average - Lump Sum/Simple Moving Average - Lump Sum - Long x2 - German Taxes")
figs <- list()
for(year in year_labels){
  file <- paste(filenames, paste0(year, " Years.csv"), sep = " - ")
  data <- read.csv(file)
  
  fig_ttwror <- plot_with_bands(data, var = "TTWROR", label = paste(year, "Years\n"), 
                                z_range = c(-0.5, 0.5), y_title = "True Time Weighted Rates of Return", 
                                direction = "high", quant_levels = c(0.75, 0.90, 1))
  fig_maxdd <- plot_with_bands(data, var = "Max_DD", label = paste(year, "Years\n"),
                               z_range = c(0, 1), y_title = "Maximum Drawdowns",
                               direction = "low", quant_levels = c(0.25, 0.10, 0))
  
  figs <- append(figs, list(fig_ttwror, fig_maxdd))}

figure <- subplot(figs, nrows = 4, titleX = FALSE, titleY = TRUE) %>%
  layout(
    title = "Empirical Parameter Evaluation for Simulated Long x2 Lump Sum",
    margin = list(t = 50),
    showlegend = FALSE,
    xaxis7 = list(title = "Starting Date"),
    xaxis8 = list(title = "Starting Date"))
saveWidget(figure, "Empirical Parameter Evaluation for Simulated Long x2 Lump Sum.html", selfcontained = TRUE)

#---- Hauptschleife über alle Kombinationen - DCA Hold - Long x2
filenames <- paste0("./03 Results Data/03 Moving Average - Lump Sum/Simple Moving Average - DCA Hold - Long x2 - German Taxes")
figs <- list()
for(year in year_labels){
  file <- paste(filenames, paste0(year, " Years.csv"), sep = " - ")
  data <- read.csv(file)
  
  fig_ttwror <- plot_with_bands(data, var = "TTWROR", label = paste(year, "Years\n"), 
                                z_range = c(-0.5, 0.5), y_title = "True Time Weighted Rates of Return", 
                                direction = "high", quant_levels = c(0.75, 0.90, 1))
  fig_maxdd <- plot_with_bands(data, var = "Max_DD", label = paste(year, "Years\n"),
                               z_range = c(0, 1), y_title = "Maximum Drawdowns",
                               direction = "low", quant_levels = c(0.25, 0.10, 0))
  
  figs <- append(figs, list(fig_ttwror, fig_maxdd))}

figure <- subplot(figs, nrows = 4, titleX = FALSE, titleY = TRUE) %>%
  layout(
    title = "Empirical Parameter Evaluation for Simulated Long x2 DCA",
    margin = list(t = 50),
    showlegend = FALSE,
    xaxis7 = list(title = "Starting Date"),
    xaxis8 = list(title = "Starting Date"))
saveWidget(figure, "Empirical Parameter Evaluation for Simulated Long x2 DCA Hold.html", selfcontained = TRUE)


#---- Hauptschleife über alle Kombinationen - Lump Sum - Long x1
filenames <- paste0("./03 Results Data/03 Moving Average - Lump Sum/Simple Moving Average - Lump Sum - Long x1 - German Taxes")
figs <- list()
for(year in year_labels){
  file <- paste(filenames, paste0(year, " Years.csv"), sep = " - ")
  data <- read.csv(file)
  
  fig_ttwror <- plot_with_bands(data, var = "TTWROR", label = paste(year, "Years\n"), 
                                z_range = c(-0.5, 0.5), y_title = "True Time Weighted Rates of Return", 
                                direction = "high", quant_levels = c(0.75, 0.90, 1))
  fig_maxdd <- plot_with_bands(data, var = "Max_DD", label = paste(year, "Years\n"),
                               z_range = c(0, 1), y_title = "Maximum Drawdowns",
                               direction = "low", quant_levels = c(0.25, 0.10, 0))
  
  figs <- append(figs, list(fig_ttwror, fig_maxdd))}

figure <- subplot(figs, nrows = 4, titleX = FALSE, titleY = TRUE) %>%
  layout(
    title = "Empirical Parameter Evaluation for Simulated Long x1 Lump Sum",
    margin = list(t = 50),
    showlegend = FALSE,
    xaxis7 = list(title = "Starting Date"),
    xaxis8 = list(title = "Starting Date"))
saveWidget(figure, "Empirical Parameter Evaluation for Simulated Long x1 Lump Sum.html", selfcontained = TRUE)

#---- Hauptschleife über alle Kombinationen - DCA Hold - Long x1
filenames <- paste0("./03 Results Data/03 Moving Average - Lump Sum/Simple Moving Average - DCA Hold - Long x1 - German Taxes")
figs <- list()
for(year in year_labels){
  file <- paste(filenames, paste0(year, " Years.csv"), sep = " - ")
  data <- read.csv(file)
  
  fig_ttwror <- plot_with_bands(data, var = "TTWROR", label = paste(year, "Years\n"), 
                                z_range = c(-0.5, 0.5), y_title = "True Time Weighted Rates of Return", 
                                direction = "high", quant_levels = c(0.75, 0.90, 1))
  fig_maxdd <- plot_with_bands(data, var = "Max_DD", label = paste(year, "Years\n"),
                               z_range = c(0, 1), y_title = "Maximum Drawdowns",
                               direction = "low", quant_levels = c(0.25, 0.10, 0))
  
  figs <- append(figs, list(fig_ttwror, fig_maxdd))}

figure <- subplot(figs, nrows = 4, titleX = FALSE, titleY = TRUE) %>%
  layout(
    title = "Empirical Parameter Evaluation for Simulated Long x1 DCA",
    margin = list(t = 50),
    showlegend = FALSE,
    xaxis7 = list(title = "Starting Date"),
    xaxis8 = list(title = "Starting Date"))
saveWidget(figure, "Empirical Parameter Evaluation for Simulated Long x1 DCA Hold.html", selfcontained = TRUE)

#---- Hauptschleife über alle Kombinationen - Lump Sum - Short x1
filenames <- paste0("./03 Results Data/03 Moving Average - Lump Sum/Simple Moving Average - Lump Sum - Short x1 - German Taxes")
figs <- list()
for(year in year_labels){
  file <- paste(filenames, paste0(year, " Years.csv"), sep = " - ")
  data <- read.csv(file)
  
  fig_ttwror <- plot_with_bands(data, var = "TTWROR", label = paste(year, "Years\n"), 
                                z_range = c(-0.5, 0.5), y_title = "True Time Weighted Rates of Return", 
                                direction = "high", quant_levels = c(0.75, 0.90, 1))
  fig_maxdd <- plot_with_bands(data, var = "Max_DD", label = paste(year, "Years\n"),
                               z_range = c(0, 1), y_title = "Maximum Drawdowns",
                               direction = "low", quant_levels = c(0.25, 0.10, 0))
  
  figs <- append(figs, list(fig_ttwror, fig_maxdd))}

figure <- subplot(figs, nrows = 4, titleX = FALSE, titleY = TRUE) %>%
  layout(
    title = "Empirical Parameter Evaluation for Simulated Short x1 Lump Sum",
    margin = list(t = 50),
    showlegend = FALSE,
    xaxis7 = list(title = "Starting Date"),
    xaxis8 = list(title = "Starting Date"))
saveWidget(figure, "Empirical Parameter Evaluation for Simulated Short x1 Lump Sum.html", selfcontained = TRUE)

#---- Hauptschleife über alle Kombinationen - DCA Hold - Short x1
filenames <- paste0("./03 Results Data/03 Moving Average - Lump Sum/Simple Moving Average - DCA Hold - Short x1 - German Taxes")
figs <- list()
for(year in year_labels){
  file <- paste(filenames, paste0(year, " Years.csv"), sep = " - ")
  data <- read.csv(file)
  
  fig_ttwror <- plot_with_bands(data, var = "TTWROR", label = paste(year, "Years\n"), 
                                z_range = c(-0.5, 0.5), y_title = "True Time Weighted Rates of Return", 
                                direction = "high", quant_levels = c(0.75, 0.90, 1))
  fig_maxdd <- plot_with_bands(data, var = "Max_DD", label = paste(year, "Years\n"),
                               z_range = c(0, 1), y_title = "Maximum Drawdowns",
                               direction = "low", quant_levels = c(0.25, 0.10, 0))
  
  figs <- append(figs, list(fig_ttwror, fig_maxdd))}

figure <- subplot(figs, nrows = 4, titleX = FALSE, titleY = TRUE) %>%
  layout(
    title = "Empirical Parameter Evaluation for Simulated Short x1 DCA",
    margin = list(t = 50),
    showlegend = FALSE,
    xaxis7 = list(title = "Starting Date"),
    xaxis8 = list(title = "Starting Date"))
saveWidget(figure, "Empirical Parameter Evaluation for Simulated Short x1 DCA Hold.html", selfcontained = TRUE)

#---- Hauptschleife über alle Kombinationen - Lump Sum - Short x2
filenames <- paste0("./03 Results Data/03 Moving Average - Lump Sum/Simple Moving Average - Lump Sum - Short x2 - German Taxes")
figs <- list()
for(year in year_labels){
  file <- paste(filenames, paste0(year, " Years.csv"), sep = " - ")
  data <- read.csv(file)
  
  fig_ttwror <- plot_with_bands(data, var = "TTWROR", label = paste(year, "Years\n"), 
                                z_range = c(-0.5, 0.5), y_title = "True Time Weighted Rates of Return", 
                                direction = "high", quant_levels = c(0.75, 0.90, 1))
  fig_maxdd <- plot_with_bands(data, var = "Max_DD", label = paste(year, "Years\n"),
                               z_range = c(0, 1), y_title = "Maximum Drawdowns",
                               direction = "low", quant_levels = c(0.25, 0.10, 0))
  
  figs <- append(figs, list(fig_ttwror, fig_maxdd))}

figure <- subplot(figs, nrows = 4, titleX = FALSE, titleY = TRUE) %>%
  layout(
    title = "Empirical Parameter Evaluation for Simulated Short x2 Lump Sum",
    margin = list(t = 50),
    showlegend = FALSE,
    xaxis7 = list(title = "Starting Date"),
    xaxis8 = list(title = "Starting Date"))
saveWidget(figure, "Empirical Parameter Evaluation for Simulated Short x2 Lump Sum.html", selfcontained = TRUE)

#---- Hauptschleife über alle Kombinationen - DCA Hold - Short x2
filenames <- paste0("./03 Results Data/03 Moving Average - Lump Sum/Simple Moving Average - DCA Hold - Short x2 - German Taxes")
figs <- list()
for(year in year_labels){
  file <- paste(filenames, paste0(year, " Years.csv"), sep = " - ")
  data <- read.csv(file)
  
  fig_ttwror <- plot_with_bands(data, var = "TTWROR", label = paste(year, "Years\n"), 
                                z_range = c(-0.5, 0.5), y_title = "True Time Weighted Rates of Return", 
                                direction = "high", quant_levels = c(0.75, 0.90, 1))
  fig_maxdd <- plot_with_bands(data, var = "Max_DD", label = paste(year, "Years\n"),
                               z_range = c(0, 1), y_title = "Maximum Drawdowns",
                               direction = "low", quant_levels = c(0.25, 0.10, 0))
  
  figs <- append(figs, list(fig_ttwror, fig_maxdd))}

figure <- subplot(figs, nrows = 4, titleX = FALSE, titleY = TRUE) %>%
  layout(
    title = "Empirical Parameter Evaluation for Simulated Short x2 DCA",
    margin = list(t = 50),
    showlegend = FALSE,
    xaxis7 = list(title = "Starting Date"),
    xaxis8 = list(title = "Starting Date"))
saveWidget(figure, "Empirical Parameter Evaluation for Simulated Short x2 DCA Hold.html", selfcontained = TRUE)


########################################################################################################################
# Variante 3: Grafiken für die empirische Verteilung über SMA-Werte
########################################################################################################################
num_categories <- 60
categories <- seq(10, 600, by = 10)
palette <- hue_pal()(num_categories)

darken_color <- function(color, factor = 0.8){
  rgb_val <- col2rgb(color) / 255
  rgb(rgb_val[1] * factor, rgb_val[2] * factor, rgb_val[3] * factor)
}

years <- c(10, 20, 30, 40)

# --- Hilfsfunktion für Boxplot-Erstellung
make_plot <- function(data, metric, year_label, range_ub, range_lb, show_x = FALSE){
  p <- plot_ly(type = "box", showlegend = FALSE)
  for(i in seq_along(categories)){
    cat_data <- filter(data, SMA == categories[i])
    p <- add_trace(p,
                   y = cat_data[[metric]],
                   name = categories[i],
                   fillcolor = palette[i],
                   line = list(color = darken_color(palette[i], 0.7), width = 2),
                   marker = list(color = darken_color(palette[i], 0.7)))
  }
  y_title <- if(metric == "TTWROR"){
    paste0(year_label, " Years\nTrue Time Weighted Rates of Returns")
  } else {
    paste0("Maximum Drawdowns\n", year_label, " Years")
  }
  layout(p,
         yaxis = list(title = y_title,
                      range = if (metric == "TTWROR") c(range_lb, range_ub) else c(-0.05, 1.05),
                      tick0 = if (metric == "TTWROR") -0.5 else 0,
                      dtick = 0.1, side = if (metric == "Max_DD") "right" else "left",
                      zeroline = FALSE, gridcolor = "black", gridwidth = 0.05),
         xaxis = list(title = if (show_x) "SMA" else NULL))
}

#---- Hauptschleife über alle Kombinationen - Lump Sum - Long x2 - Alt Signal
ttwror_ranges_ub <- c(0.45, 0.35, 0.25, 0.25)
ttwror_ranges_lb <- c(-.45, -.35, -.25, -.25)
data_path <- "./03 Results Data/03 Moving Average - Alt Signal/Simple Moving Average - Lump Sum - Long x2 - Alt Signal - German Taxes"
plot_data <- map(years, ~ read.csv(paste0(data_path, " - ", .x, " Years.csv")) %>%
                   select(SMA, Max_DD, TTWROR))

plots <- map2(seq_along(plot_data), plot_data, function(i, df){
  list(
    make_plot(df, "TTWROR", years[i], ttwror_ranges_ub[i], ttwror_ranges_lb[i]),
    make_plot(df, "Max_DD", years[i],  ttwror_ranges_ub[i], ttwror_ranges_lb[i], show_x = (i == 4)))}) %>% purrr::flatten()

figure <- subplot(plots, nrows = 4, titleX = TRUE, titleY = TRUE) %>%
  layout(
    title = "Empirical Distributions of Strategy Simulation Metrics\nSimple Moving Average - Simulated Long x2 - Alt Signal - Lump Sum",
    margin = list(t = 50),
    showlegend = FALSE)
saveWidget(figure, "Simple Moving Average - Simulated Long x2 - Alt Signal - Lump Sum.html", selfcontained = TRUE)

#---- Hauptschleife über alle Kombinationen - DCA Hold - Long x2 - Alt Signal
data_path <- "./03 Results Data/03 Moving Average - Alt Signal/Simple Moving Average - DCA Hold - Long x2 - Alt Signal - German Taxes"

plot_data <- map(years, ~ read.csv(paste0(data_path, " - ", .x, " Years.csv")) %>%
                   select(SMA, Max_DD, TTWROR))

plots <- map2(seq_along(plot_data), plot_data, function(i, df){
  list(
    make_plot(df, "TTWROR", years[i], ttwror_ranges_ub[i], ttwror_ranges_lb[i]),
    make_plot(df, "Max_DD", years[i],  ttwror_ranges_ub[i], ttwror_ranges_lb[i], show_x = (i == 4)))}) %>% purrr::flatten()

figure <- subplot(plots, nrows = 4, titleX = TRUE, titleY = TRUE) %>%
  layout(
    title = "Empirical Distributions of Strategy Simulation Metrics\nSimple Moving Average - Simulated Long x2 - Alt Signal - DCA",
    margin = list(t = 50),
    showlegend = FALSE)
saveWidget(figure, "Simple Moving Average - Simulated Long x2 - Alt Signal - DCA Hold.html", selfcontained = TRUE)


########################################################################################################################
# Variante 4: Grafiken für die Heatmaps über SMA-Werte
########################################################################################################################
col_ribbon <- c("rgba(0, 200, 0, 0.3)", "rgba(255, 165, 0, 0.3)", "rgba(255, 0, 0, 0.3)")
col_lines  <- c("rgba(0, 200, 0, 0.7)", "rgba(255, 165, 0, 0.7)", "rgba(255, 0, 0, 0.7)")

#---- Hilfsfunktion für Berechnung SMA-Bänder
get_band <- function(data, var, quant_level = NULL, direction = "high"){
  data %>%
    group_by(Start_Date) %>%
    filter({
      v <- .data[[var]]
      if(is.null(quant_level)){
        if(direction == "high") v >= max(v, na.rm = TRUE) else v <= min(v, na.rm = TRUE)
      } else {
        threshold <- quantile(v, probs = quant_level, na.rm = TRUE)
        if(direction == "high") v >= threshold else v <= threshold
      }}) %>%
    summarise(
      sma_min = min(SMA, na.rm = TRUE),
      sma_max = max(SMA, na.rm = TRUE),
      .groups = "drop") %>%
    mutate(sma_mean = (sma_min + sma_max) / 2)
}

#---- Hilfsfunktion für Erstellung Heatmap-Plots mit Bändern
plot_with_bands <- function(data, var, label, z_range, y_title, direction = "high", band_labels = c("25%", "10%", "Max/Min"), quant_levels = NULL) {
  fig <- plot_ly(
    x = as.Date(data$Start_Date), y = data$SMA, z = data[[var]],
    type = "heatmap", colorscale = list(c(0, "white"), c(1, "black")),
    zmin = z_range[1], zmax = z_range[2], showscale = FALSE)
  
  for(j in seq_along(quant_levels)){
    band <- get_band(data, var, quant_levels[j], direction)
    fig <- fig %>%
      add_trace(data = band, x = ~as.Date(Start_Date), y = ~sma_mean,
                type = "scatter", mode = "lines", name = band_labels[j],
                line = list(color = col_lines[[j]], width = 1.5), inherit = FALSE, showlegend = FALSE) %>%
      add_ribbons(data = band, x = ~as.Date(Start_Date), ymin = ~sma_min, ymax = ~sma_max,
                  fillcolor = col_ribbon[[j]], line = list(color = col_lines[[j]], width = 1),
                  name = band_labels[j], inherit = FALSE, showlegend = FALSE)}
  
  fig %>% layout(
    xaxis = list(title = ""),
    yaxis = list(title = paste(label, y_title), range = c(10, 600),
                 side = if(var == "Max_DD") "right" else "left"))
}

year_labels <- c("10", "20", "30", "40")

#---- Hauptschleife über alle Kombinationen - Lump Sum - Long x2 - Alt Signal
filenames <- paste0("./03 Results Data/03 Moving Average - Lump Sum/Simple Moving Average - Lump Sum - Long x2 - Alt Signal - German Taxes")
figs <- list()
for(year in year_labels){
  file <- paste(filenames, paste0(year, " Years.csv"), sep = " - ")
  data <- read.csv(file)
  
  fig_ttwror <- plot_with_bands(data, var = "TTWROR", label = paste(year, "Years\n"), 
                                z_range = c(-0.5, 0.5), y_title = "True Time Weighted Rates of Return", 
                                direction = "high", quant_levels = c(0.75, 0.90, 1))
  fig_maxdd <- plot_with_bands(data, var = "Max_DD", label = paste(year, "Years\n"),
                               z_range = c(0, 1), y_title = "Maximum Drawdowns",
                               direction = "low", quant_levels = c(0.25, 0.10, 0))
  
  figs <- append(figs, list(fig_ttwror, fig_maxdd))}

figure <- subplot(figs, nrows = 4, titleX = FALSE, titleY = TRUE) %>%
  layout(
    title = "Empirical Parameter Evaluation for Simulated Long x2 - Alt Signal - Lump Sum",
    margin = list(t = 50),
    showlegend = FALSE,
    xaxis7 = list(title = "Starting Date"),
    xaxis8 = list(title = "Starting Date"))
saveWidget(figure, "Empirical Parameter Evaluation for Simulated Long x2 - Alt Signal - Lump Sum.html", selfcontained = TRUE)

#---- Hauptschleife über alle Kombinationen - DCA Hold - Long x2 - Alt Signal
filenames <- paste0("./03 Results Data/03 Moving Average - DCA Hold/Simple Moving Average - DCA Hold - Long x2 - Alt Signal - German Taxes")
figs <- list()
for(year in year_labels){
  file <- paste(filenames, paste0(year, " Years.csv"), sep = " - ")
  data <- read.csv(file)
  
  fig_ttwror <- plot_with_bands(data, var = "TTWROR", label = paste(year, "Years\n"), 
                                z_range = c(-0.5, 0.5), y_title = "True Time Weighted Rates of Return", 
                                direction = "high", quant_levels = c(0.75, 0.90, 1))
  fig_maxdd <- plot_with_bands(data, var = "Max_DD", label = paste(year, "Years\n"),
                               z_range = c(0, 1), y_title = "Maximum Drawdowns",
                               direction = "low", quant_levels = c(0.25, 0.10, 0))
  
  figs <- append(figs, list(fig_ttwror, fig_maxdd))}

figure <- subplot(figs, nrows = 4, titleX = FALSE, titleY = TRUE) %>%
  layout(
    title = "Empirical Parameter Evaluation for Simulated Long x2 - Alt Signal - DCA",
    margin = list(t = 50),
    showlegend = FALSE,
    xaxis7 = list(title = "Starting Date"),
    xaxis8 = list(title = "Starting Date"))
saveWidget(figure, "Empirical Parameter Evaluation for Simulated Long x2 - Alt Signal - DCA Hold.html", selfcontained = TRUE)


########################################################################################################################
# Variante 5: Grafiken für die empirische Verteilung über EMA-Werte
########################################################################################################################
num_categories <- 60
categories <- seq(10, 600, by = 10)
palette <- hue_pal()(num_categories)

darken_color <- function(color, factor = 0.8){
  rgb_val <- col2rgb(color) / 255
  rgb(rgb_val[1] * factor, rgb_val[2] * factor, rgb_val[3] * factor)
}

years <- c(10, 20, 30, 40)

# --- Hilfsfunktion für Boxplot-Erstellung
make_plot <- function(data, metric, year_label, range_ub, range_lb, show_x = FALSE){
  p <- plot_ly(type = "box", showlegend = FALSE)
  for(i in seq_along(categories)){
    cat_data <- filter(data, SMA == categories[i])
    p <- add_trace(p,
                   y = cat_data[[metric]],
                   name = categories[i],
                   fillcolor = palette[i],
                   line = list(color = darken_color(palette[i], 0.7), width = 2),
                   marker = list(color = darken_color(palette[i], 0.7)))
  }
  y_title <- if(metric == "TTWROR"){
    paste0(year_label, " Years\nTrue Time Weighted Rates of Returns")
  } else {
    paste0("Maximum Drawdowns\n", year_label, " Years")
  }
  layout(p,
         yaxis = list(title = y_title,
                      range = if (metric == "TTWROR") c(range_lb, range_ub) else c(-0.05, 1.05),
                      tick0 = if (metric == "TTWROR") -0.5 else 0,
                      dtick = 0.1, side = if (metric == "Max_DD") "right" else "left",
                      zeroline = FALSE, gridcolor = "black", gridwidth = 0.05),
         xaxis = list(title = if (show_x) "EMA" else NULL))
}

#---- Hauptschleife über alle Kombinationen - Lump Sum - Long x2 - Exponential Moving Average
ttwror_ranges_ub <- c(0.45, 0.35, 0.25, 0.25)
ttwror_ranges_lb <- c(-.45, -.35, -.25, -.25)
data_path <- "./03 Results Data/03 Moving Average - Lump Sum/Exponential Moving Average - Lump Sum - Long x2 - German Taxes"

plot_data <- map(years, ~ read.csv(paste0(data_path, " - ", .x, " Years.csv")) %>%
                   select(EMA, Max_DD, TTWROR))

plots <- map2(seq_along(plot_data), plot_data, function(i, df){
  list(
    make_plot(df, "TTWROR", years[i], ttwror_ranges_ub[i], ttwror_ranges_lb[i]),
    make_plot(df, "Max_DD", years[i],  ttwror_ranges_ub[i], ttwror_ranges_lb[i], show_x = (i == 4)))}) %>% purrr::flatten()

figure <- subplot(plots, nrows = 4, titleX = TRUE, titleY = TRUE) %>%
  layout(
    title = "Empirical Distributions of Strategy Simulation Metrics\nExponential Moving Average - Simulated Long x2 - Lump Sum",
    margin = list(t = 50),
    showlegend = FALSE)
saveWidget(figure, "Exponential Moving Average - Simulated Long x2 - Lump Sum.html", selfcontained = TRUE)

#---- Hauptschleife über alle Kombinationen - DCA Hold - Long x2 - Exponential Moving Average
data_path <- "./03 Results Data/03 Moving Average - DCA Hold/Exponential Moving Average - DCA Hold - Long x2 - German Taxes"

plot_data <- map(years, ~ read.csv(paste0(data_path, " - ", .x, " Years.csv")) %>%
                   select(EMA, Max_DD, TTWROR))

plots <- map2(seq_along(plot_data), plot_data, function(i, df){
  list(
    make_plot(df, "TTWROR", years[i], ttwror_ranges_ub[i], ttwror_ranges_lb[i]),
    make_plot(df, "Max_DD", years[i],  ttwror_ranges_ub[i], ttwror_ranges_lb[i], show_x = (i == 4)))}) %>% purrr::flatten()

figure <- subplot(plots, nrows = 4, titleX = TRUE, titleY = TRUE) %>%
  layout(
    title = "Empirical Distributions of Strategy Simulation Metrics\nExponential Moving Average - Simulated Long x2 - DCA",
    margin = list(t = 50),
    showlegend = FALSE)
saveWidget(figure, "Exponential Moving Average - Simulated Long x2 - DCA Hold.html", selfcontained = TRUE)

#---- Hauptschleife über alle Kombinationen - Lump Sum - Short x2 - Exponential Moving Average
ttwror_ranges_ub <- c(0.45, 0.35, 0.25, 0.25)
ttwror_ranges_lb <- c(-.45, -.35, -.25, -.25)
data_path <- "./03 Results Data/03 Moving Average - Lump Sum/Exponential Moving Average - Lump Sum - Short x2 - German Taxes"

plot_data <- map(years, ~ read.csv(paste0(data_path, " - ", .x, " Years.csv")) %>%
                   select(EMA, Max_DD, TTWROR))

plots <- map2(seq_along(plot_data), plot_data, function(i, df){
  list(
    make_plot(df, "TTWROR", years[i], ttwror_ranges_ub[i], ttwror_ranges_lb[i]),
    make_plot(df, "Max_DD", years[i],  ttwror_ranges_ub[i], ttwror_ranges_lb[i], show_x = (i == 4)))}) %>% purrr::flatten()

figure <- subplot(plots, nrows = 4, titleX = TRUE, titleY = TRUE) %>%
  layout(
    title = "Empirical Distributions of Strategy Simulation Metrics\nExponential Moving Average - Simulated Short x2 - Lump Sum",
    margin = list(t = 50),
    showlegend = FALSE)
saveWidget(figure, "Exponential Moving Average - Simulated Short x2 - Lump Sum.html", selfcontained = TRUE)

#---- Hauptschleife über alle Kombinationen - DCA Hold - Short x2 - Exponential Moving Average
data_path <- "./03 Results Data/03 Moving Average - DCA Hold/Exponential Moving Average - DCA Hold - Short x2 - German Taxes"

plot_data <- map(years, ~ read.csv(paste0(data_path, " - ", .x, " Years.csv")) %>%
                   select(EMA, Max_DD, TTWROR))

plots <- map2(seq_along(plot_data), plot_data, function(i, df){
  list(
    make_plot(df, "TTWROR", years[i], ttwror_ranges_ub[i], ttwror_ranges_lb[i]),
    make_plot(df, "Max_DD", years[i],  ttwror_ranges_ub[i], ttwror_ranges_lb[i], show_x = (i == 4)))}) %>% purrr::flatten()

figure <- subplot(plots, nrows = 4, titleX = TRUE, titleY = TRUE) %>%
  layout(
    title = "Empirical Distributions of Strategy Simulation Metrics\nExponential Moving Average - Simulated Short x2 - DCA",
    margin = list(t = 50),
    showlegend = FALSE)
saveWidget(figure, "Exponential Moving Average - Simulated Short x2 - DCA Hold.html", selfcontained = TRUE)


########################################################################################################################
# Variante 6: Grafiken für die Heatmaps über EMA-Werte
########################################################################################################################
col_ribbon <- c("rgba(0, 200, 0, 0.3)", "rgba(255, 165, 0, 0.3)", "rgba(255, 0, 0, 0.3)")
col_lines  <- c("rgba(0, 200, 0, 0.7)", "rgba(255, 165, 0, 0.7)", "rgba(255, 0, 0, 0.7)")

#---- Hilfsfunktion für Berechnung EMA-Bänder
get_band <- function(data, var, quant_level = NULL, direction = "high"){
  data %>%
    group_by(Start_Date) %>%
    filter({
      v <- .data[[var]]
      if(is.null(quant_level)){
        if(direction == "high") v >= max(v, na.rm = TRUE) else v <= min(v, na.rm = TRUE)
      } else {
        threshold <- quantile(v, probs = quant_level, na.rm = TRUE)
        if(direction == "high") v >= threshold else v <= threshold
      }}) %>%
    summarise(
      sma_min = min(EMA, na.rm = TRUE),
      sma_max = max(EMA, na.rm = TRUE),
      .groups = "drop") %>%
    mutate(sma_mean = (sma_min + sma_max) / 2)
}

#---- Hilfsfunktion für Erstellung Heatmap-Plots mit Bändern
plot_with_bands <- function(data, var, label, z_range, y_title, direction = "high", band_labels = c("25%", "10%", "Max/Min"), quant_levels = NULL) {
  fig <- plot_ly(
    x = as.Date(data$Start_Date), y = data$EMA, z = data[[var]],
    type = "heatmap", colorscale = list(c(0, "white"), c(1, "black")),
    zmin = z_range[1], zmax = z_range[2], showscale = FALSE)
  
  for(j in seq_along(quant_levels)){
    band <- get_band(data, var, quant_levels[j], direction)
    fig <- fig %>%
      add_trace(data = band, x = ~as.Date(Start_Date), y = ~sma_mean,
                type = "scatter", mode = "lines", name = band_labels[j],
                line = list(color = col_lines[[j]], width = 1.5), inherit = FALSE, showlegend = FALSE) %>%
      add_ribbons(data = band, x = ~as.Date(Start_Date), ymin = ~sma_min, ymax = ~sma_max,
                  fillcolor = col_ribbon[[j]], line = list(color = col_lines[[j]], width = 1),
                  name = band_labels[j], inherit = FALSE, showlegend = FALSE)}
  
  fig %>% layout(
    xaxis = list(title = ""),
    yaxis = list(title = paste(label, y_title), range = c(10, 600),
                 side = if(var == "Max_DD") "right" else "left"))
}

year_labels <- c("10", "20", "30", "40")

#---- Hauptschleife über alle Kombinationen - Lump Sum - Long x2 - Exponential Moving Average
filenames <- paste0("Exponential Moving Average - Lump Sum - Long x2 - German Taxes")
figs <- list()
for(year in year_labels){
  file <- paste(filenames, paste0(year, " Years.csv"), sep = " - ")
  data <- read.csv(file)
  
  fig_ttwror <- plot_with_bands(data, var = "TTWROR", label = paste(year, "Years\n"), 
                                z_range = c(-0.5, 0.5), y_title = "True Time Weighted Rates of Return", 
                                direction = "high", quant_levels = c(0.75, 0.90, 1))
  fig_maxdd <- plot_with_bands(data, var = "Max_DD", label = paste(year, "Years\n"),
                               z_range = c(0, 1), y_title = "Maximum Drawdowns",
                               direction = "low", quant_levels = c(0.25, 0.10, 0))
  
  figs <- append(figs, list(fig_ttwror, fig_maxdd))}

figure <- subplot(figs, nrows = 4, titleX = FALSE, titleY = TRUE) %>%
  layout(
    title = "Empirical Parameter Evaluation for Simulated Long x2 Lump Sum",
    margin = list(t = 50),
    showlegend = FALSE,
    xaxis7 = list(title = "Starting Date"),
    xaxis8 = list(title = "Starting Date"))
saveWidget(figure, "Empirical Parameter Evaluation for Simulated Long x2 Lump Sum.html", selfcontained = TRUE)

#---- Hauptschleife über alle Kombinationen - DCA Hold - Long x2 - Exponential Moving Average
filenames <- paste0("./03 Results Data/03 Moving Average - DCA Hold/Exponential Moving Average - DCA Hold - Long x2 - German Taxes")
year_labels <- c("10", "20", "30", "40")

figs <- list()
for(year in year_labels){
  file <- paste(filenames, paste0(year, " Years.csv"), sep = " - ")
  data <- read.csv(file)
  
  fig_ttwror <- plot_with_bands(data, var = "TTWROR", label = paste(year, "Years\n"), 
                                z_range = c(-0.5, 0.5), y_title = "True Time Weighted Rates of Return", 
                                direction = "high", quant_levels = c(0.75, 0.90, 1))
  fig_maxdd <- plot_with_bands(data, var = "Max_DD", label = paste(year, "Years\n"),
                               z_range = c(0, 1), y_title = "Maximum Drawdowns",
                               direction = "low", quant_levels = c(0.25, 0.10, 0))
  
  figs <- append(figs, list(fig_ttwror, fig_maxdd))}

figure <- subplot(figs, nrows = 4, titleX = FALSE, titleY = TRUE) %>%
  layout(
    title = "Empirical Parameter Evaluation for Simulated Long x2 DCA",
    margin = list(t = 50),
    showlegend = FALSE,
    xaxis7 = list(title = "Starting Date"),
    xaxis8 = list(title = "Starting Date"))
saveWidget(figure, "Empirical Parameter Evaluation for Simulated Long x2 DCA Hold.html", selfcontained = TRUE)


########################################################################################################################
# Variante 7: Grafiken für die Heatmaps über Normal- und Decile-Werte
########################################################################################################################
years   <- c(10, 20, 30, 40)
metrics <- c("min", "q1", "med", "q3", "max")

metric_sets <- list(
  TTWROR = list(label = "True Time Weighted Rates of Returns"),
  Max_DD = list(label = "Maximum Drawdowns")
)

datasets <- list(
  list(
    label = "Moving Deciles", threshold = "Decile",
    path = "03 Results Data/06 Moving Metrics - Lump Sum/Moving Deciles - Lump Sum - Long x2/Moving Deciles - Lump Sum - Long x2 - German Taxes - "
  )
)

# --- Hilfsfunktionen
load_data <- function(path, threshold, years){
  files <- paste0(path, years, " Years.csv")

  map2_df(files, years, ~read_csv(.x) %>% mutate(Years = .y)) %>%
    rename(Threshold = all_of(threshold)) %>%
    group_by(Years, Window_Size, Threshold) %>%
    summarise(
      across(
        c(TTWROR, Max_DD),
        list(
          min = ~min(.x, na.rm = TRUE),
          q1  = ~quantile(.x, 0.25, na.rm = TRUE),
          med = ~median(.x, na.rm = TRUE),
          q3  = ~quantile(.x, 0.75, na.rm = TRUE),
          max = ~max(.x, na.rm = TRUE)
        ),
        .names = "{.fn}_{.col}"
      ),
      .groups = "drop"
    )
}

make_long <- function(data, cols){
  data %>%
    select(Years, Window_Size, Threshold, all_of(cols)) %>%
    pivot_longer(cols = all_of(cols), names_to = "Statistic", values_to = "Value")
}

plot_heatmap <- function(data, year, metric){
  plot_ly(
    data = data %>% filter(Years == year, Statistic == metric),
    x = ~Threshold, y = ~Window_Size, z = ~Value,
    type = "heatmap", colorscale = "Viridis", showscale = FALSE
  )
}

heatmap_matrix <- function(data, metrics, years, title){
  rows <- lapply(years, function(y){
    plots <- lapply(metrics, function(m){plot_heatmap(data, y, m)})
    subplot(plots, shareY = TRUE, margin = 0.01)
  })

  subplot(rows, nrows = length(years), titleX = TRUE, titleY = TRUE) %>% 
    layout(
      title = title,
      margin = list(t = 60),
      xaxis18 = list(title = "Deciles"),
      yaxis = list(title = "10 Years\nWindow Length"),
      yaxis2 = list(title = "20 Years\nWindow Length"),
      yaxis3 = list(title = "30 Years\nWindow Length"),
      yaxis4 = list(title = "40 Years\nWindow Length")
  )
}


render_heatmaps <- function(quant_data, set, metric_key){
  cols <- paste0(metrics, "_", metric_key)
  long_data <- make_long(quant_data, cols)
  title <- paste0(set$label, " – ", metric_sets[[metric_key]]$label, " – Lump Sum – German Taxes", "\nMin – Q1 – Median – Q3 – Max")
  plot <- heatmap_matrix(long_data, cols, years, title)
  file_name <- paste0(tolower(metric_key), "_", gsub(" ", "_", set$label), ".html")
  saveWidget(plot, file = file_name, selfcontained = TRUE)
  print(plot)
}

for(set in datasets){
  quant_data <- load_data(set$path, set$threshold, years)

  for(metric_key in names(metric_sets)){
    render_heatmaps(quant_data, set, metric_key)
  }
}
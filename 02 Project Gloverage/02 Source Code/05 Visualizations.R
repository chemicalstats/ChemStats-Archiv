########################################################################################################################
# Vorbereitung des Systems
########################################################################################################################
packages <- c("tidyverse", "stringr", "plotly", "RColorBrewer", "purrr", "scales", "htmlwidgets")
invisible(lapply(packages, library, character.only = TRUE)); rm(packages)
if(.Platform$OS.type == "windows"){Sys.setlocale("LC_ALL", "en_US.UTF-8")}


########################################################################################################################
# Kapitel 1: Vergleichsgrafiken für Buy and Hold-Varianten
########################################################################################################################
years <- c("10", "20", "30", "40")

levels <- c("World - Long x2 - Lump Sum - USD", "World - Long x2 - DCA - USD",
            "North America - Long x2 - Lump Sum - USD", "North America - Long x2 - DCA - USD",
            "Europe - Long x2 - Lump Sum - USD", "Europe - Long x2 - DCA - USD",
            "Pacific - Long x2 - Lump Sum - USD", "Pacific - Long x2 - DCA - USD",
            "Emerging - Long x2 - Lump Sum - USD", "Emerging - Long x2 - DCA - USD")

colors <- c("World - Long x2 - Lump Sum - USD" = "#1F77B4", "World - Long x2 - DCA - USD" = "#AEC7E8",
             "North America - Long x2 - Lump Sum - USD"= "#2CA02C", "North America - Long x2 - DCA - USD"= "#98DF8A",
             "Europe - Long x2 - Lump Sum - USD"= "#FF7F0E", "Europe - Long x2 - DCA - USD" = "#FFBB78",
             "Pacific - Long x2 - Lump Sum - USD" = "#D62728", "Pacific - Long x2 - DCA - USD" = "#FF9896",
             "Emerging - Long x2 - Lump Sum - USD" = "#9467BD", "Emerging - Long x2 - DCA - USD" = "#C5B0D5")


data <- list.files("./03 Results Data/02 Buy and Hold", "\\.csv$", full.names = TRUE) %>%
  map_dfr(~read.csv(.x) %>%
            mutate(
              Type = factor(paste(strsplit(basename(.x), " - ")[[1]][c(1:4)], collapse = " - "), levels = levels),
              Span = factor(str_remove(strsplit(basename(.x), " - ")[[1]][6], " Years\\.csv"), levels = years, ordered = TRUE)) %>%
            select(Type, Span, TTWROR, Max_DD))


make_plot <- function(yvar, ytitle, legend = TRUE, side = "left", range = NULL){
  plot_ly(data, x = ~Span, y = as.formula(paste0("~", yvar)), color = ~Type, colors = colors,
          type = "box", showlegend = legend) %>%
    layout(
      xaxis = list(title = "Investment Horizons (Years)"),
      yaxis = list(title = ytitle, side = side, range = range, tick0 = 0, dtick = 0.1,
                   zeroline = FALSE, gridcolor = "darkgrey", gridwidth = 0.5), boxmode = "group")
}

figure <- subplot(
  make_plot("TTWROR", "True Time Weighted Rate of Returns", legend = TRUE, range = c(-0.55, 0.55)),
  make_plot("Max_DD", "Maximum Drawdowns", legend = FALSE, side = "right", range = c(-0.05, 1.05)),
  nrows = 1, shareX = TRUE, titleX = TRUE, titleY = TRUE) %>% 
  layout(title = "Empirical Distributions of Strategy Simulation Metrics\nBuy and Hold - Leveraged Exchange Traded Funds Simulation", 
         legend = list(orientation = 'h'), margin = list(t = 50))
saveWidget(figure, "Buy and Hold.html", selfcontained = TRUE)


########################################################################################################################
# Kapitel 2: Grafiken für die empirische Verteilung über SMA-Werte
########################################################################################################################
num_categories <- 60
categories <- seq(10, 600, by = 10)
palette <- hue_pal()(num_categories)

darken_color <- function(color, factor = 0.8) {
  rgb_val <- col2rgb(color) / 255
  rgb(rgb_val[1] * factor, rgb_val[2] * factor, rgb_val[3] * factor)
}

years <- c(10, 20, 30, 40)
ttwror_ranges_ub <- c(0.35, 0.25, 0.25, 0.25)
ttwror_ranges_lb <- c(-.05, -.05, -.05, -.05)


#---- Hilfsfunktion für Boxplot-Erstellung
make_plot <- function(data, metric, year_label, range_ub, range_lb, show_x = FALSE){
  plot <- plot_ly(type = "box", showlegend = FALSE)
  for(i in seq_along(categories)){
    cat_data <- filter(data, SMA == categories[i])
    plot <- add_trace(
      plot, y = cat_data[[metric]], name = categories[i], fillcolor = palette[i],
      line = list(color = darken_color(palette[i], 0.7), width = 2),
      marker = list(color = darken_color(palette[i], 0.7)))
  }
  
  y_title <- if(metric == "TTWROR"){
    paste0(year_label, " Years\nTrue Time Weighted Rate of Returns")
  } else {
    paste0("Maximum Drawdowns\n", year_label, " Years")
  }
  
  layout(p,
         yaxis = list(title = y_title, xaxis = list(title = if (show_x) "SMA" else NULL)),
                      range = if (metric == "TTWROR") c(range_lb, range_ub) else c(-0.05, 1.05),
                      tick0 = if (metric == "TTWROR") -0.5 else 0,
                      dtick = 0.1, side = if (metric == "Max_DD") "right" else "left",
                      zeroline = FALSE, gridcolor = "black", gridwidth = 0.05)
}


#---- Import Daten und Generierung Plots
data_path <- "./03 Results Data/03 Moving Average/World - Long x2 - Lump Sum - EUR/World - Long x2 - Lump Sum - EUR - German Taxes"

plot_data <- map(years, ~ read.csv(paste0(data_path, " - ", .x, " Years.csv")) %>%
                   select(SMA, Max_DD, TTWROR))

plots <- map2(seq_along(plot_data), plot_data, function(i, df){
  list(
    make_plot(df, "TTWROR", years[i], ttwror_ranges_ub[i], ttwror_ranges_lb[i]),
    make_plot(df, "Max_DD", years[i],  ttwror_ranges_ub[i], ttwror_ranges_lb[i], show_x = (i == 4)))}) %>% purrr::flatten()

figure <- subplot(plots, nrows = 4, titleX = TRUE, titleY = TRUE) %>%
  layout(
    title = "Empirical Distributions of Strategy Simulation Metrics\nSimple Moving Average - Simulated MSCI World LETF - Lump Sum",
    margin = list(t = 50),
    showlegend = FALSE)
saveWidget(figure, "Simple Moving Average - Simulated MSCI World LETF - Lump Sum.html", selfcontained = TRUE)


#---- Import Daten und Generierung Plots
data_path <- "./03 Results Data/03 Moving Average/World - Long x2 - DCA - EUR/World - Long x2 - DCA - EUR - German Taxes"

plot_data <- map(years, ~ read.csv(paste0(data_path, " - ", .x, " Years.csv")) %>%
                   select(SMA, Max_DD, TTWROR))

plots <- map2(seq_along(plot_data), plot_data, function(i, df){
  list(
    make_plot(df, "TTWROR", years[i], ttwror_ranges_ub[i], ttwror_ranges_lb[i]),
    make_plot(df, "Max_DD", years[i],  ttwror_ranges_ub[i], ttwror_ranges_lb[i], show_x = (i == 4)))}) %>% purrr::flatten()

figure <- subplot(plots, nrows = 4, titleX = TRUE, titleY = TRUE) %>%
  layout(
    title = "Empirical Distributions of Strategy Simulation Metrics\nSimple Moving Average - Simulated MSCI World LETF - DCA",
    margin = list(t = 50),
    showlegend = FALSE)
saveWidget(figure, "Simple Moving Average - Simulated MSCI World LETF - DCA.html", selfcontained = TRUE)


########################################################################################################################
# Kapitel 2: Grafiken für die Heatmaps über SMA-Werte
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

#---- Hilfsfunktion für Erstellung Heatmap-Plots mit Bändern ---
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


#---- Hauptschleife über alle Kombinationen Lump Sum
filenames <- paste0("./03 Results Data/03 Moving Average/World - Lump Sum - German Taxes")
year_labels <- c("10", "20", "30", "40")

figs <- list()
for(year in year_labels){
  file <- paste(filenames, paste0(year, " Years.csv"), sep = " - ")
  data <- read.csv(file)
  
  fig_ttwror <- plot_with_bands(data, var = "TTWROR", label = paste(year, "Years\n"), 
                                z_range = c(-0.3, 0.3), y_title = "True Time Weighted Rate of Returns", 
                                direction = "high", quant_levels = c(0.75, 0.90, 1))
  fig_maxdd <- plot_with_bands(data, var = "Max_DD", label = paste(year, "Years\n"),
                               z_range = c(0, 1), y_title = "Maximum Drawdowns",
                               direction = "low", quant_levels = c(0.25, 0.10, 0))
  
  figs <- append(figs, list(fig_ttwror, fig_maxdd))}

figure <- subplot(figs, nrows = 4, titleX = FALSE, titleY = TRUE) %>%
  layout(
    title = "Empirical Parameter Evaluation for Simulated MSCI World LETF Lump Sum",
    margin = list(t = 50),
    showlegend = FALSE,
    xaxis7 = list(title = "Starting Date"),
    xaxis8 = list(title = "Starting Date"))
saveWidget(figure, "Empirical Parameter Evaluation for Simulated MSCI World LETF Lump Sum.html", selfcontained = TRUE)


#---- Hauptschleife über alle Kombinationen DCA
filenames <- paste0("./03 Results Data/03 Moving Average/World - DCA - German Taxes")
year_labels <- c("10", "20", "30", "40")

figs <- list()
for(year in year_labels){
  file <- paste(filenames, paste0(year, " Years.csv"), sep = " - ")
  data <- read.csv(file)
  
  fig_ttwror <- plot_with_bands(data, var = "TTWROR", label = paste(year, "Years\n"), 
                                z_range = c(-0.3, 0.3), y_title = "True Time Weighted Rate of Returns", 
                                direction = "high", quant_levels = c(0.75, 0.90, 1))
  fig_maxdd <- plot_with_bands(data, var = "Max_DD", label = paste(year, "Years\n"),
                               z_range = c(0, 1), y_title = "Maximum Drawdowns",
                               direction = "low", quant_levels = c(0.25, 0.10, 0))
  
  figs <- append(figs, list(fig_ttwror, fig_maxdd))}

figure <- subplot(figs, nrows = 4, titleX = FALSE, titleY = TRUE) %>%
  layout(
    title = "Empirical Parameter Evaluation for Simulated MSCI World LETF DCA",
    margin = list(t = 50),
    showlegend = FALSE,
    xaxis7 = list(title = "Starting Date"),
    xaxis8 = list(title = "Starting Date"))
saveWidget(figure, "Empirical Parameter Evaluation for Simulated MSCI World LETF DCA.html", selfcontained = TRUE)


########################################################################################################################
# Kapitel 2: Grafiken für die Rolling Metric Analysis
########################################################################################################################
merging_data <- function(path, files, form, sma = NULL){
  list.files(path, files, full.names = TRUE) %>%
    map_dfr(~{
      data <- read.csv(.x) %>%
        select(all_of(c(c("Start_Date", "Stopp_Date", "TTWROR", "Max_DD"), intersect("SMA", names(data)))))
      
      if(form == "SMA" & !is.null(sma)){
        if(!"SMA" %in% names(data)){
          stop("Spalte 'SMA' existiert nicht in den Daten.")
        }
        data <- data %>% filter(SMA == sma)
      }
      
      type <- paste(strsplit(basename(.x), " - ")[[1]][c(1,3,4)], collapse = "_")
      span <- str_remove(strsplit(basename(.x), " - ")[[1]][6], " Years\\.csv")
      
      rename_cols <- intersect(c("TTWROR", "Max_DD", "SMA"), names(data))
      
      data <- data %>%
        rename_with(~ paste0(type, "_", form, "_", .), all_of(rename_cols)) %>%
        mutate(Span = factor(span))
      
      data
    })
}


#---- Buy and Hold Data
data <- list(
  merging_data("./03 Results Data/02 Buy and Hold", "World - Long x1 - Lump Sum - USD", "Base"),
  merging_data("./03 Results Data/02 Buy and Hold", "World - Long x1 - DCA - USD", "Base"),
  merging_data("./03 Results Data/02 Buy and Hold", "World - Long x2 - Lump Sum - USD", "Hold"),
  merging_data("./03 Results Data/02 Buy and Hold", "World - Long x2 - DCA - USD", "Hold"),
  merging_data("./03 Results Data/02 Buy and Hold", "North America - Long x2 - Lump Sum - USD", "Hold"),
  merging_data("./03 Results Data/02 Buy and Hold", "North America - Long x2 - DCA - USD", "Hold"),
  merging_data("./03 Results Data/02 Buy and Hold", "Europe - Long x2 - Lump Sum - EUR", "Hold"),
  merging_data("./03 Results Data/02 Buy and Hold", "Europe - Long x2 - DCA - EUR", "Hold"),
  merging_data("./03 Results Data/02 Buy and Hold", "Pacific - Long x2 - Lump Sum - USD", "Hold"),
  merging_data("./03 Results Data/02 Buy and Hold", "Pacific - Long x2 - DCA - USD", "Hold"),
  merging_data("./03 Results Data/02 Buy and Hold", "Emerging - Long x2 - Lump Sum - USD", "Hold"),
  merging_data("./03 Results Data/02 Buy and Hold", "Emerging - Long x2 - DCA - USD", "Hold")) %>%
  Reduce(function(x, y) left_join(x, y, by = c("Start_Date", "Stopp_Date", "Span")), .) %>%
  rename_with(~ str_replace_all(., " ", "_"))


#---- Rolling Metrics Analysis - Buy and Hold - Lump Sum
panel_1st <- data %>%
  mutate(
    across(
      .cols = contains("TTWROR") & !all_of("World_Lump_Sum_USD_Base_TTWROR"),
      .fns = ~ .x - get("World_Lump_Sum_USD_Base_TTWROR"),
      .names = "{.col}_vs_Base")) %>%
  filter(Span == 10) %>%
  plot_ly(type = "scatter", mode = "lines", showlegend = TRUE) %>%
  add_trace(x = ~Start_Date, y = ~World_Lump_Sum_USD_Hold_TTWROR_vs_Base, name = "World", line = list(color = "#1F77B4", width = 1)) %>%
  add_trace(x = ~Start_Date, y = ~North_America_Lump_Sum_USD_Hold_TTWROR_vs_Base, name = "North America", line = list(color = "#2CA02C", width = 1)) %>%
  add_trace(x = ~Start_Date, y = ~Europe_Lump_Sum_EUR_Hold_TTWROR_vs_Base, name = "Europe", line = list(color = "#FF7F0E", width = 1)) %>%
  add_trace(x = ~Start_Date, y = ~Pacific_Lump_Sum_USD_Hold_TTWROR_vs_Base, name = "Pacific", line = list(color = "#D62728", width = 1)) %>%
  add_trace(x = ~Start_Date, y = ~Emerging_Lump_Sum_USD_Hold_TTWROR_vs_Base, name = "Emerging", line = list(color = "#9467BD", width = 1)) %>%
  layout(xaxis = list(title = "Starting Dates"), yaxis = list(title = NULL, range = c(-0.35, 0.35), tick0 = 0, dtick = 0.1))

panel_2nd <- data %>%
  mutate(
    across(
      .cols = contains("TTWROR") & !all_of("World_Lump_Sum_USD_Base_TTWROR"),
      .fns = ~ .x - get("World_Lump_Sum_USD_Base_TTWROR"),
      .names = "{.col}_vs_Base")) %>%
  filter(Span == 20) %>%
  plot_ly(type = "scatter", mode = "lines", showlegend = FALSE) %>%
  add_trace(x = ~Start_Date, y = ~World_Lump_Sum_USD_Hold_TTWROR_vs_Base, name = "World", line = list(color = "#1F77B4", width = 1)) %>%
  add_trace(x = ~Start_Date, y = ~North_America_Lump_Sum_USD_Hold_TTWROR_vs_Base, name = "North America", line = list(color = "#2CA02C", width = 1)) %>%
  add_trace(x = ~Start_Date, y = ~Europe_Lump_Sum_EUR_Hold_TTWROR_vs_Base, name = "Europe", line = list(color = "#FF7F0E", width = 1)) %>%
  add_trace(x = ~Start_Date, y = ~Pacific_Lump_Sum_USD_Hold_TTWROR_vs_Base, name = "Pacific", line = list(color = "#D62728", width = 1)) %>%
  add_trace(x = ~Start_Date, y = ~Emerging_Lump_Sum_USD_Hold_TTWROR_vs_Base, name = "Emerging", line = list(color = "#9467BD", width = 1)) %>%
  layout(xaxis = list(title = "Starting Dates"), yaxis = list(title = NULL, range = c(-0.35, 0.35), tick0 = 0, dtick = 0.1))

panel_3rd <- data %>%
  mutate(
    across(
      .cols = contains("TTWROR") & !all_of("World_Lump_Sum_USD_Base_TTWROR"),
      .fns = ~ .x - get("World_Lump_Sum_USD_Base_TTWROR"),
      .names = "{.col}_vs_Base")) %>%
  filter(Span == 30) %>%
  plot_ly(type = "scatter", mode = "lines", showlegend = FALSE) %>%
  add_trace(x = ~Start_Date, y = ~World_Lump_Sum_USD_Hold_TTWROR_vs_Base, name = "World", line = list(color = "#1F77B4", width = 1)) %>%
  add_trace(x = ~Start_Date, y = ~North_America_Lump_Sum_USD_Hold_TTWROR_vs_Base, name = "North America", line = list(color = "#2CA02C", width = 1)) %>%
  add_trace(x = ~Start_Date, y = ~Europe_Lump_Sum_EUR_Hold_TTWROR_vs_Base, name = "Europe", line = list(color = "#FF7F0E", width = 1)) %>%
  add_trace(x = ~Start_Date, y = ~Pacific_Lump_Sum_USD_Hold_TTWROR_vs_Base, name = "Pacific", line = list(color = "#D62728", width = 1)) %>%
  add_trace(x = ~Start_Date, y = ~Emerging_Lump_Sum_USD_Hold_TTWROR_vs_Base, name = "Emerging", line = list(color = "#9467BD", width = 1)) %>%
  layout(xaxis = list(title = "Starting Dates"), yaxis = list(title = NULL, range = c(-0.35, 0.35), tick0 = 0, dtick = 0.1))

panel_4th <- data %>%
  mutate(
    across(
      .cols = contains("TTWROR") & !all_of("World_Lump_Sum_USD_Base_TTWROR"),
      .fns = ~ .x - get("World_Lump_Sum_USD_Base_TTWROR"),
      .names = "{.col}_vs_Base")) %>%
  filter(Span == 40) %>%
  plot_ly(type = "scatter", mode = "lines", showlegend = FALSE) %>%
  add_trace(x = ~Start_Date, y = ~World_Lump_Sum_USD_Hold_TTWROR_vs_Base, name = "World", line = list(color = "#1F77B4", width = 1)) %>%
  add_trace(x = ~Start_Date, y = ~North_America_Lump_Sum_USD_Hold_TTWROR_vs_Base, name = "North America", line = list(color = "#2CA02C", width = 1)) %>%
  add_trace(x = ~Start_Date, y = ~Europe_Lump_Sum_EUR_Hold_TTWROR_vs_Base, name = "Europe", line = list(color = "#FF7F0E", width = 1)) %>%
  add_trace(x = ~Start_Date, y = ~Pacific_Lump_Sum_USD_Hold_TTWROR_vs_Base, name = "Pacific", line = list(color = "#D62728", width = 1)) %>%
  add_trace(x = ~Start_Date, y = ~Emerging_Lump_Sum_USD_Hold_TTWROR_vs_Base, name = "Emerging", line = list(color = "#9467BD", width = 1)) %>%
  layout(xaxis = list(title = "Starting Dates"), yaxis = list(title = NULL, range = c(-0.35, 0.35), tick0 = 0, dtick = 0.1))

panel_5th <- data %>%
  mutate(
    across(
      .cols = contains("Max_DD") & !all_of("World_Lump_Sum_USD_Base_Max_DD"),
      .fns = ~ .x - get("World_Lump_Sum_USD_Base_Max_DD"),
      .names = "{.col}_vs_Base")) %>%
  filter(Span == 10) %>%
  plot_ly(type = "scatter", mode = "lines", showlegend = FALSE) %>%
  add_trace(x = ~Start_Date, y = ~World_Lump_Sum_USD_Hold_Max_DD_vs_Base, name = "World", line = list(color = "#1F77B4", width = 1)) %>%
  add_trace(x = ~Start_Date, y = ~North_America_Lump_Sum_USD_Hold_Max_DD_vs_Base, name = "North America", line = list(color = "#2CA02C", width = 1)) %>%
  add_trace(x = ~Start_Date, y = ~Europe_Lump_Sum_EUR_Hold_Max_DD_vs_Base, name = "Europe", line = list(color = "#FF7F0E", width = 1)) %>%
  add_trace(x = ~Start_Date, y = ~Pacific_Lump_Sum_USD_Hold_Max_DD_vs_Base, name = "Pacific", line = list(color = "#D62728", width = 1)) %>%
  add_trace(x = ~Start_Date, y = ~Emerging_Lump_Sum_USD_Hold_Max_DD_vs_Base, name = "Emerging", line = list(color = "#9467BD", width = 1)) %>%
  layout(xaxis = list(title = "Starting Dates"), yaxis = list(title = NULL, range = c(-0.05, 0.75), tick0 = 0, dtick = 0.1))

panel_6th <- data %>%
  mutate(
    across(
      .cols = contains("Max_DD") & !all_of("World_Lump_Sum_USD_Base_Max_DD"),
      .fns = ~ .x - get("World_Lump_Sum_USD_Base_Max_DD"),
      .names = "{.col}_vs_Base")) %>%
  filter(Span == 20) %>%
  plot_ly(type = "scatter", mode = "lines", showlegend = FALSE) %>%
  add_trace(x = ~Start_Date, y = ~World_Lump_Sum_USD_Hold_Max_DD_vs_Base, name = "World", line = list(color = "#1F77B4", width = 1)) %>%
  add_trace(x = ~Start_Date, y = ~North_America_Lump_Sum_USD_Hold_Max_DD_vs_Base, name = "North America", line = list(color = "#2CA02C", width = 1)) %>%
  add_trace(x = ~Start_Date, y = ~Europe_Lump_Sum_EUR_Hold_Max_DD_vs_Base, name = "Europe", line = list(color = "#FF7F0E", width = 1)) %>%
  add_trace(x = ~Start_Date, y = ~Pacific_Lump_Sum_USD_Hold_Max_DD_vs_Base, name = "Pacific", line = list(color = "#D62728", width = 1)) %>%
  add_trace(x = ~Start_Date, y = ~Emerging_Lump_Sum_USD_Hold_Max_DD_vs_Base, name = "Emerging", line = list(color = "#9467BD", width = 1)) %>%
  layout(xaxis = list(title = "Starting Dates"), yaxis = list(title = NULL, range = c(-0.05, 0.75), tick0 = 0, dtick = 0.1))

panel_7th <- data %>%
  mutate(
    across(
      .cols = contains("Max_DD") & !all_of("World_Lump_Sum_USD_Base_Max_DD"),
      .fns = ~ .x - get("World_Lump_Sum_USD_Base_Max_DD"),
      .names = "{.col}_vs_Base")) %>%
  filter(Span == 30) %>%
  plot_ly(type = "scatter", mode = "lines", showlegend = FALSE) %>%
  add_trace(x = ~Start_Date, y = ~World_Lump_Sum_USD_Hold_Max_DD_vs_Base, name = "World", line = list(color = "#1F77B4", width = 1)) %>%
  add_trace(x = ~Start_Date, y = ~North_America_Lump_Sum_USD_Hold_Max_DD_vs_Base, name = "North America", line = list(color = "#2CA02C", width = 1)) %>%
  add_trace(x = ~Start_Date, y = ~Europe_Lump_Sum_EUR_Hold_Max_DD_vs_Base, name = "Europe", line = list(color = "#FF7F0E", width = 1)) %>%
  add_trace(x = ~Start_Date, y = ~Pacific_Lump_Sum_USD_Hold_Max_DD_vs_Base, name = "Pacific", line = list(color = "#D62728", width = 1)) %>%
  add_trace(x = ~Start_Date, y = ~Emerging_Lump_Sum_USD_Hold_Max_DD_vs_Base, name = "Emerging", line = list(color = "#9467BD", width = 1)) %>%
  layout(xaxis = list(title = "Starting Dates"), yaxis = list(title = NULL, range = c(-0.05, 0.75), tick0 = 0, dtick = 0.1))

panel_8th <- data %>%
  mutate(
    across(
      .cols = contains("Max_DD") & !all_of("World_Lump_Sum_USD_Base_Max_DD"),
      .fns = ~ .x - get("World_Lump_Sum_USD_Base_Max_DD"),
      .names = "{.col}_vs_Base")) %>%
  filter(Span == 40) %>%
  plot_ly(type = "scatter", mode = "lines", showlegend = FALSE) %>%
  add_trace(x = ~Start_Date, y = ~World_Lump_Sum_USD_Hold_Max_DD_vs_Base, name = "World", line = list(color = "#1F77B4", width = 1)) %>%
  add_trace(x = ~Start_Date, y = ~North_America_Lump_Sum_USD_Hold_Max_DD_vs_Base, name = "North America", line = list(color = "#2CA02C", width = 1)) %>%
  add_trace(x = ~Start_Date, y = ~Europe_Lump_Sum_EUR_Hold_Max_DD_vs_Base, name = "Europe", line = list(color = "#FF7F0E", width = 1)) %>%
  add_trace(x = ~Start_Date, y = ~Pacific_Lump_Sum_USD_Hold_Max_DD_vs_Base, name = "Pacific", line = list(color = "#D62728", width = 1)) %>%
  add_trace(x = ~Start_Date, y = ~Emerging_Lump_Sum_USD_Hold_Max_DD_vs_Base, name = "Emerging", line = list(color = "#9467BD", width = 1)) %>%
  layout(xaxis = list(title = "Starting Dates"), yaxis = list(title = NULL, range = c(-0.05, 0.75), tick0 = 0, dtick = 0.1))

figure <- subplot(panel_1st, panel_2nd, panel_3rd, panel_4th, panel_5th, panel_6th, panel_7th, panel_8th, nrows = 2, shareX = TRUE, shareY = FALSE) %>%
  layout(
    title = "Moving Relative Metrics - Buy and Hold - Lump Sum\n10 Years - 20 Years - 30 Years - 40 Years",
    legend = list(orientation = 'h', x = 0.5, xanchor = "center", y = -0.05), margin = list(t = 75),
    yaxis = list(title = "Absolute Differences in True Time Weighted Rate of Returns"),
    yaxis5 = list(title = "Absolute Differences in Maximum Drawdowns"))
saveWidget(figure, "Buy and Hold Lum Sum.html", selfcontained = TRUE)


#---- Rolling Metrics Analysis - Buy and Hold - DCA
panel_1st <- data %>%
  mutate(
    across(
      .cols = contains("TTWROR") & !all_of("World_DCA_USD_Base_TTWROR"),
      .fns = ~ .x - get("World_DCA_USD_Base_TTWROR"),
      .names = "{.col}_vs_Base")) %>%
  filter(Span == 10) %>%
  plot_ly(type = "scatter", mode = "lines", showlegend = TRUE) %>%
  add_trace(x = ~Start_Date, y = ~World_DCA_USD_Hold_TTWROR_vs_Base, name = "World", line = list(color = "#1F77B4", width = 1)) %>%
  add_trace(x = ~Start_Date, y = ~North_America_DCA_USD_Hold_TTWROR_vs_Base, name = "North America", line = list(color = "#2CA02C", width = 1)) %>%
  add_trace(x = ~Start_Date, y = ~Europe_DCA_EUR_Hold_TTWROR_vs_Base, name = "Europe", line = list(color = "#FF7F0E", width = 1)) %>%
  add_trace(x = ~Start_Date, y = ~Pacific_DCA_USD_Hold_TTWROR_vs_Base, name = "Pacific", line = list(color = "#D62728", width = 1)) %>%
  add_trace(x = ~Start_Date, y = ~Emerging_DCA_USD_Hold_TTWROR_vs_Base, name = "Emerging", line = list(color = "#9467BD", width = 1)) %>%
  layout(xaxis = list(title = "Starting Dates"), yaxis = list(title = NULL, range = c(-0.35, 0.35), tick0 = 0, dtick = 0.1))

panel_2nd <- data %>%
  mutate(
    across(
      .cols = contains("TTWROR") & !all_of("World_DCA_USD_Base_TTWROR"),
      .fns = ~ .x - get("World_DCA_USD_Base_TTWROR"),
      .names = "{.col}_vs_Base")) %>%
  filter(Span == 20) %>%
  plot_ly(type = "scatter", mode = "lines", showlegend = FALSE) %>%
  add_trace(x = ~Start_Date, y = ~World_DCA_USD_Hold_TTWROR_vs_Base, name = "World", line = list(color = "#1F77B4", width = 1)) %>%
  add_trace(x = ~Start_Date, y = ~North_America_DCA_USD_Hold_TTWROR_vs_Base, name = "North America", line = list(color = "#2CA02C", width = 1)) %>%
  add_trace(x = ~Start_Date, y = ~Europe_DCA_EUR_Hold_TTWROR_vs_Base, name = "Europe", line = list(color = "#FF7F0E", width = 1)) %>%
  add_trace(x = ~Start_Date, y = ~Pacific_DCA_USD_Hold_TTWROR_vs_Base, name = "Pacific", line = list(color = "#D62728", width = 1)) %>%
  add_trace(x = ~Start_Date, y = ~Emerging_DCA_USD_Hold_TTWROR_vs_Base, name = "Emerging", line = list(color = "#9467BD", width = 1)) %>%
  layout(xaxis = list(title = "Starting Dates"), yaxis = list(title = NULL, range = c(-0.35, 0.35), tick0 = 0, dtick = 0.1))

panel_3rd <- data %>%
  mutate(
    across(
      .cols = contains("TTWROR") & !all_of("World_DCA_USD_Base_TTWROR"),
      .fns = ~ .x - get("World_DCA_USD_Base_TTWROR"),
      .names = "{.col}_vs_Base")) %>%
  filter(Span == 30) %>%
  plot_ly(type = "scatter", mode = "lines", showlegend = FALSE) %>%
  add_trace(x = ~Start_Date, y = ~World_DCA_USD_Hold_TTWROR_vs_Base, name = "World", line = list(color = "#1F77B4", width = 1)) %>%
  add_trace(x = ~Start_Date, y = ~North_America_DCA_USD_Hold_TTWROR_vs_Base, name = "North America", line = list(color = "#2CA02C", width = 1)) %>%
  add_trace(x = ~Start_Date, y = ~Europe_DCA_EUR_Hold_TTWROR_vs_Base, name = "Europe", line = list(color = "#FF7F0E", width = 1)) %>%
  add_trace(x = ~Start_Date, y = ~Pacific_DCA_USD_Hold_TTWROR_vs_Base, name = "Pacific", line = list(color = "#D62728", width = 1)) %>%
  add_trace(x = ~Start_Date, y = ~Emerging_DCA_USD_Hold_TTWROR_vs_Base, name = "Emerging", line = list(color = "#9467BD", width = 1)) %>%
  layout(xaxis = list(title = "Starting Dates"), yaxis = list(title = NULL, range = c(-0.35, 0.35), tick0 = 0, dtick = 0.1))

panel_4th <- data %>%
  mutate(
    across(
      .cols = contains("TTWROR") & !all_of("World_DCA_USD_Base_TTWROR"),
      .fns = ~ .x - get("World_DCA_USD_Base_TTWROR"),
      .names = "{.col}_vs_Base")) %>%
  filter(Span == 40) %>%
  plot_ly(type = "scatter", mode = "lines", showlegend = FALSE) %>%
  add_trace(x = ~Start_Date, y = ~World_DCA_USD_Hold_TTWROR_vs_Base, name = "World", line = list(color = "#1F77B4", width = 1)) %>%
  add_trace(x = ~Start_Date, y = ~North_America_DCA_USD_Hold_TTWROR_vs_Base, name = "North America", line = list(color = "#2CA02C", width = 1)) %>%
  add_trace(x = ~Start_Date, y = ~Europe_DCA_EUR_Hold_TTWROR_vs_Base, name = "Europe", line = list(color = "#FF7F0E", width = 1)) %>%
  add_trace(x = ~Start_Date, y = ~Pacific_DCA_USD_Hold_TTWROR_vs_Base, name = "Pacific", line = list(color = "#D62728", width = 1)) %>%
  add_trace(x = ~Start_Date, y = ~Emerging_DCA_USD_Hold_TTWROR_vs_Base, name = "Emerging", line = list(color = "#9467BD", width = 1)) %>%
  layout(xaxis = list(title = "Starting Dates"), yaxis = list(title = NULL, range = c(-0.35, 0.35), tick0 = 0, dtick = 0.1))

panel_5th <- data %>%
  mutate(
    across(
      .cols = contains("Max_DD") & !all_of("World_DCA_USD_Base_Max_DD"),
      .fns = ~ .x - get("World_DCA_USD_Base_Max_DD"),
      .names = "{.col}_vs_Base")) %>%
  filter(Span == 10) %>%
  plot_ly(type = "scatter", mode = "lines", showlegend = FALSE) %>%
  add_trace(x = ~Start_Date, y = ~World_DCA_USD_Hold_Max_DD_vs_Base, name = "World", line = list(color = "#1F77B4", width = 1)) %>%
  add_trace(x = ~Start_Date, y = ~North_America_DCA_USD_Hold_Max_DD_vs_Base, name = "North America", line = list(color = "#2CA02C", width = 1)) %>%
  add_trace(x = ~Start_Date, y = ~Europe_DCA_EUR_Hold_Max_DD_vs_Base, name = "Europe", line = list(color = "#FF7F0E", width = 1)) %>%
  add_trace(x = ~Start_Date, y = ~Pacific_DCA_USD_Hold_Max_DD_vs_Base, name = "Pacific", line = list(color = "#D62728", width = 1)) %>%
  add_trace(x = ~Start_Date, y = ~Emerging_DCA_USD_Hold_Max_DD_vs_Base, name = "Emerging", line = list(color = "#9467BD", width = 1)) %>%
  layout(xaxis = list(title = "Starting Dates"), yaxis = list(title = NULL, range = c(-0.05, 0.75), tick0 = 0, dtick = 0.1))

panel_6th <- data %>%
  mutate(
    across(
      .cols = contains("Max_DD") & !all_of("World_DCA_USD_Base_Max_DD"),
      .fns = ~ .x - get("World_DCA_USD_Base_Max_DD"),
      .names = "{.col}_vs_Base")) %>%
  filter(Span == 20) %>%
  plot_ly(type = "scatter", mode = "lines", showlegend = FALSE) %>%
  add_trace(x = ~Start_Date, y = ~World_DCA_USD_Hold_Max_DD_vs_Base, name = "World", line = list(color = "#1F77B4", width = 1)) %>%
  add_trace(x = ~Start_Date, y = ~North_America_DCA_USD_Hold_Max_DD_vs_Base, name = "North America", line = list(color = "#2CA02C", width = 1)) %>%
  add_trace(x = ~Start_Date, y = ~Europe_DCA_EUR_Hold_Max_DD_vs_Base, name = "Europe", line = list(color = "#FF7F0E", width = 1)) %>%
  add_trace(x = ~Start_Date, y = ~Pacific_DCA_USD_Hold_Max_DD_vs_Base, name = "Pacific", line = list(color = "#D62728", width = 1)) %>%
  add_trace(x = ~Start_Date, y = ~Emerging_DCA_USD_Hold_Max_DD_vs_Base, name = "Emerging", line = list(color = "#9467BD", width = 1)) %>%
  layout(xaxis = list(title = "Starting Dates"), yaxis = list(title = NULL, range = c(-0.05, 0.75), tick0 = 0, dtick = 0.1))

panel_7th <- data %>%
  mutate(
    across(
      .cols = contains("Max_DD") & !all_of("World_DCA_USD_Base_Max_DD"),
      .fns = ~ .x - get("World_DCA_USD_Base_Max_DD"),
      .names = "{.col}_vs_Base")) %>%
  filter(Span == 30) %>%
  plot_ly(type = "scatter", mode = "lines", showlegend = FALSE) %>%
  add_trace(x = ~Start_Date, y = ~World_DCA_USD_Hold_Max_DD_vs_Base, name = "World", line = list(color = "#1F77B4", width = 1)) %>%
  add_trace(x = ~Start_Date, y = ~North_America_DCA_USD_Hold_Max_DD_vs_Base, name = "North America", line = list(color = "#2CA02C", width = 1)) %>%
  add_trace(x = ~Start_Date, y = ~Europe_DCA_EUR_Hold_Max_DD_vs_Base, name = "Europe", line = list(color = "#FF7F0E", width = 1)) %>%
  add_trace(x = ~Start_Date, y = ~Pacific_DCA_USD_Hold_Max_DD_vs_Base, name = "Pacific", line = list(color = "#D62728", width = 1)) %>%
  add_trace(x = ~Start_Date, y = ~Emerging_DCA_USD_Hold_Max_DD_vs_Base, name = "Emerging", line = list(color = "#9467BD", width = 1)) %>%
  layout(xaxis = list(title = "Starting Dates"), yaxis = list(title = NULL, range = c(-0.05, 0.75), tick0 = 0, dtick = 0.1))

panel_8th <- data %>%
  mutate(
    across(
      .cols = contains("Max_DD") & !all_of("World_DCA_USD_Base_Max_DD"),
      .fns = ~ .x - get("World_DCA_USD_Base_Max_DD"),
      .names = "{.col}_vs_Base")) %>%
  filter(Span == 40) %>%
  plot_ly(type = "scatter", mode = "lines", showlegend = FALSE) %>%
  add_trace(x = ~Start_Date, y = ~World_DCA_USD_Hold_Max_DD_vs_Base, name = "World", line = list(color = "#1F77B4", width = 1)) %>%
  add_trace(x = ~Start_Date, y = ~North_America_DCA_USD_Hold_Max_DD_vs_Base, name = "North America", line = list(color = "#2CA02C", width = 1)) %>%
  add_trace(x = ~Start_Date, y = ~Europe_DCA_EUR_Hold_Max_DD_vs_Base, name = "Europe", line = list(color = "#FF7F0E", width = 1)) %>%
  add_trace(x = ~Start_Date, y = ~Pacific_DCA_USD_Hold_Max_DD_vs_Base, name = "Pacific", line = list(color = "#D62728", width = 1)) %>%
  add_trace(x = ~Start_Date, y = ~Emerging_DCA_USD_Hold_Max_DD_vs_Base, name = "Emerging", line = list(color = "#9467BD", width = 1)) %>%
  layout(xaxis = list(title = "Starting Dates"), yaxis = list(title = NULL, range = c(-0.05, 0.75), tick0 = 0, dtick = 0.1))

figure <- subplot(panel_1st, panel_2nd, panel_3rd, panel_4th, panel_5th, panel_6th, panel_7th, panel_8th, nrows = 2, shareX = TRUE, shareY = FALSE) %>%
  layout(
    title = "Moving Relative Metrics - Buy and Hold - DCA\n10 Years - 20 Years - 30 Years - 40 Years",
    legend = list(orientation = 'h', x = 0.5, xanchor = "center", y = -0.05), margin = list(t = 75),
    yaxis = list(title = "Absolute Differences in True Time Weighted Rate of Returns"),
    yaxis5 = list(title = "Absolute Differences in Maximum Drawdowns"))
saveWidget(figure, "Buy and Hold DCA.html", selfcontained = TRUE)


#---- Moving Average Data
data <- list(
  merging_data("./03 Results Data/02 Buy and Hold", "World - Long x1 - Lump Sum - USD", "Base"),
  merging_data("./03 Results Data/02 Buy and Hold", "World - Long x1 - DCA - USD", "Base"),
  merging_data("./03 Results Data/03 Moving Average", "World - Long x2 - Lump Sum - USD", "SMA", 370),
  merging_data("./03 Results Data/03 Moving Average", "World - Long x2 - DCA - USD", "SMA", 370),
  merging_data("./03 Results Data/03 Moving Average", "North America - Long x2 - Lump Sum - USD", "SMA", 410),
  merging_data("./03 Results Data/03 Moving Average", "North America - Long x2 - DCA - USD", "SMA", 410),
  merging_data("./03 Results Data/03 Moving Average", "Europe - Long x2 - Lump Sum - EUR", "SMA", 290),
  merging_data("./03 Results Data/03 Moving Average", "Europe - Long x2 - DCA - EUR", "SMA", 290),
  merging_data("./03 Results Data/03 Moving Average", "Pacific - Long x2 - Lump Sum - USD", "SMA", 200),
  merging_data("./03 Results Data/03 Moving Average", "Pacific - Long x2 - DCA - USD", "SMA", 200),
  merging_data("./03 Results Data/03 Moving Average", "Emerging - Long x2 - Lump Sum - USD", "SMA", 140),
  merging_data("./03 Results Data/03 Moving Average", "Emerging - Long x2 - DCA - USD", "SMA", 140)) %>%
  Reduce(function(x, y) left_join(x, y, by = c("Start_Date", "Stopp_Date", "Span")), .) %>%
  rename_with(~ str_replace_all(., " ", "_"))

#---- Rolling Metrics Analysis - Moving Average - Lump Sum
panel_1st <- data %>%
  mutate(
    across(
      .cols = contains("TTWROR") & !all_of("World_Lump_Sum_USD_Base_TTWROR"),
      .fns = ~ .x - get("World_Lump_Sum_USD_Base_TTWROR"),
      .names = "{.col}_vs_Base")) %>%
  filter(Span == 10) %>%
  plot_ly(type = "scatter", mode = "lines", showlegend = TRUE) %>%
  add_trace(x = ~Start_Date, y = ~World_Lump_Sum_USD_SMA_TTWROR_vs_Base, name = "World", line = list(color = "#1F77B4", width = 1)) %>%
  add_trace(x = ~Start_Date, y = ~North_America_Lump_Sum_USD_SMA_TTWROR_vs_Base, name = "North America", line = list(color = "#2CA02C", width = 1)) %>%
  add_trace(x = ~Start_Date, y = ~Europe_Lump_Sum_EUR_SMA_TTWROR_vs_Base, name = "Europe", line = list(color = "#FF7F0E", width = 1)) %>%
  add_trace(x = ~Start_Date, y = ~Pacific_Lump_Sum_USD_SMA_TTWROR_vs_Base, name = "Pacific", line = list(color = "#D62728", width = 1)) %>%
  add_trace(x = ~Start_Date, y = ~Emerging_Lump_Sum_USD_SMA_TTWROR_vs_Base, name = "Emerging", line = list(color = "#9467BD", width = 1)) %>%
  layout(xaxis = list(title = "Starting Dates"), yaxis = list(title = NULL, range = c(-0.35, 0.35), tick0 = 0, dtick = 0.1))

panel_2nd <- data %>%
  mutate(
    across(
      .cols = contains("TTWROR") & !all_of("World_Lump_Sum_USD_Base_TTWROR"),
      .fns = ~ .x - get("World_Lump_Sum_USD_Base_TTWROR"),
      .names = "{.col}_vs_Base")) %>%
  filter(Span == 20) %>%
  plot_ly(type = "scatter", mode = "lines", showlegend = FALSE) %>%
  add_trace(x = ~Start_Date, y = ~World_Lump_Sum_USD_SMA_TTWROR_vs_Base, name = "World", line = list(color = "#1F77B4", width = 1)) %>%
  add_trace(x = ~Start_Date, y = ~North_America_Lump_Sum_USD_SMA_TTWROR_vs_Base, name = "North America", line = list(color = "#2CA02C", width = 1)) %>%
  add_trace(x = ~Start_Date, y = ~Europe_Lump_Sum_EUR_SMA_TTWROR_vs_Base, name = "Europe", line = list(color = "#FF7F0E", width = 1)) %>%
  add_trace(x = ~Start_Date, y = ~Pacific_Lump_Sum_USD_SMA_TTWROR_vs_Base, name = "Pacific", line = list(color = "#D62728", width = 1)) %>%
  add_trace(x = ~Start_Date, y = ~Emerging_Lump_Sum_USD_SMA_TTWROR_vs_Base, name = "Emerging", line = list(color = "#9467BD", width = 1)) %>%
  layout(xaxis = list(title = "Starting Dates"), yaxis = list(title = NULL, range = c(-0.35, 0.35), tick0 = 0, dtick = 0.1))

panel_3rd <- data %>%
  mutate(
    across(
      .cols = contains("TTWROR") & !all_of("World_Lump_Sum_USD_Base_TTWROR"),
      .fns = ~ .x - get("World_Lump_Sum_USD_Base_TTWROR"),
      .names = "{.col}_vs_Base")) %>%
  filter(Span == 30) %>%
  plot_ly(type = "scatter", mode = "lines", showlegend = FALSE) %>%
  add_trace(x = ~Start_Date, y = ~World_Lump_Sum_USD_SMA_TTWROR_vs_Base, name = "World", line = list(color = "#1F77B4", width = 1)) %>%
  add_trace(x = ~Start_Date, y = ~North_America_Lump_Sum_USD_SMA_TTWROR_vs_Base, name = "North America", line = list(color = "#2CA02C", width = 1)) %>%
  add_trace(x = ~Start_Date, y = ~Europe_Lump_Sum_EUR_SMA_TTWROR_vs_Base, name = "Europe", line = list(color = "#FF7F0E", width = 1)) %>%
  add_trace(x = ~Start_Date, y = ~Pacific_Lump_Sum_USD_SMA_TTWROR_vs_Base, name = "Pacific", line = list(color = "#D62728", width = 1)) %>%
  add_trace(x = ~Start_Date, y = ~Emerging_Lump_Sum_USD_SMA_TTWROR_vs_Base, name = "Emerging", line = list(color = "#9467BD", width = 1)) %>%
  layout(xaxis = list(title = "Starting Dates"), yaxis = list(title = NULL, range = c(-0.35, 0.35), tick0 = 0, dtick = 0.1))

panel_4th <- data %>%
  mutate(
    across(
      .cols = contains("TTWROR") & !all_of("World_Lump_Sum_USD_Base_TTWROR"),
      .fns = ~ .x - get("World_Lump_Sum_USD_Base_TTWROR"),.names = "{.col}_vs_Base")) %>%
  filter(Span == 40) %>%
  plot_ly(type = "scatter", mode = "lines", showlegend = FALSE) %>%
  add_trace(x = ~Start_Date, y = ~World_Lump_Sum_USD_SMA_TTWROR_vs_Base, name = "World", line = list(color = "#1F77B4", width = 1)) %>%
  add_trace(x = ~Start_Date, y = ~North_America_Lump_Sum_USD_SMA_TTWROR_vs_Base, name = "North America", line = list(color = "#2CA02C", width = 1)) %>%
  add_trace(x = ~Start_Date, y = ~Europe_Lump_Sum_EUR_SMA_TTWROR_vs_Base, name = "Europe", line = list(color = "#FF7F0E", width = 1)) %>%
  add_trace(x = ~Start_Date, y = ~Pacific_Lump_Sum_USD_SMA_TTWROR_vs_Base, name = "Pacific", line = list(color = "#D62728", width = 1)) %>%
  add_trace(x = ~Start_Date, y = ~Emerging_Lump_Sum_USD_SMA_TTWROR_vs_Base, name = "Emerging", line = list(color = "#9467BD", width = 1)) %>%
  layout(xaxis = list(title = "Starting Dates"), yaxis = list(title = NULL, range = c(-0.35, 0.35), tick0 = 0, dtick = 0.1))

panel_5th <- data %>%
  mutate(
    across(
      .cols = contains("Max_DD") & !all_of("World_Lump_Sum_USD_Base_Max_DD"),
      .fns = ~ .x - get("World_Lump_Sum_USD_Base_Max_DD"),
      .names = "{.col}_vs_Base")) %>%
  filter(Span == 10) %>%
  plot_ly(type = "scatter", mode = "lines", showlegend = FALSE) %>%
  add_trace(x = ~Start_Date, y = ~World_Lump_Sum_USD_SMA_Max_DD_vs_Base, name = "World", line = list(color = "#1F77B4", width = 1)) %>%
  add_trace(x = ~Start_Date, y = ~North_America_Lump_Sum_USD_SMA_Max_DD_vs_Base, name = "North America", line = list(color = "#2CA02C", width = 1)) %>%
  add_trace(x = ~Start_Date, y = ~Europe_Lump_Sum_EUR_SMA_Max_DD_vs_Base, name = "Europe", line = list(color = "#FF7F0E", width = 1)) %>%
  add_trace(x = ~Start_Date, y = ~Pacific_Lump_Sum_USD_SMA_Max_DD_vs_Base, name = "Pacific", line = list(color = "#D62728", width = 1)) %>%
  add_trace(x = ~Start_Date, y = ~Emerging_Lump_Sum_USD_SMA_Max_DD_vs_Base, name = "Emerging", line = list(color = "#9467BD", width = 1)) %>%
  layout(xaxis = list(title = "Starting Dates"), yaxis = list(title = NULL, range = c(-0.35, 0.35), tick0 = 0, dtick = 0.1))

panel_6th <- data %>%
  mutate(
    across(
      .cols = contains("Max_DD") & !all_of("World_Lump_Sum_USD_Base_Max_DD"),
      .fns = ~ .x - get("World_Lump_Sum_USD_Base_Max_DD"),
      .names = "{.col}_vs_Base")) %>%
  filter(Span == 20) %>%
  plot_ly(type = "scatter", mode = "lines", showlegend = FALSE) %>%
  add_trace(x = ~Start_Date, y = ~World_Lump_Sum_USD_SMA_Max_DD_vs_Base, name = "World", line = list(color = "#1F77B4", width = 1)) %>%
  add_trace(x = ~Start_Date, y = ~North_America_Lump_Sum_USD_SMA_Max_DD_vs_Base, name = "North America", line = list(color = "#2CA02C", width = 1)) %>%
  add_trace(x = ~Start_Date, y = ~Europe_Lump_Sum_EUR_SMA_Max_DD_vs_Base, name = "Europe", line = list(color = "#FF7F0E", width = 1)) %>%
  add_trace(x = ~Start_Date, y = ~Pacific_Lump_Sum_USD_SMA_Max_DD_vs_Base, name = "Pacific", line = list(color = "#D62728", width = 1)) %>%
  add_trace(x = ~Start_Date, y = ~Emerging_Lump_Sum_USD_SMA_Max_DD_vs_Base, name = "Emerging", line = list(color = "#9467BD", width = 1)) %>%
  layout(xaxis = list(title = "Starting Dates"), yaxis = list(title = NULL, range = c(-0.35, 0.35), tick0 = 0, dtick = 0.1))

panel_7th <- data %>%
  mutate(
    across(
      .cols = contains("Max_DD") & !all_of("World_Lump_Sum_USD_Base_Max_DD"),
      .fns = ~ .x - get("World_Lump_Sum_USD_Base_Max_DD"),
      .names = "{.col}_vs_Base")) %>%
  filter(Span == 30) %>%
  plot_ly(type = "scatter", mode = "lines", showlegend = FALSE) %>%
  add_trace(x = ~Start_Date, y = ~World_Lump_Sum_USD_SMA_Max_DD_vs_Base, name = "World", line = list(color = "#1F77B4", width = 1)) %>%
  add_trace(x = ~Start_Date, y = ~North_America_Lump_Sum_USD_SMA_Max_DD_vs_Base, name = "North America", line = list(color = "#2CA02C", width = 1)) %>%
  add_trace(x = ~Start_Date, y = ~Europe_Lump_Sum_EUR_SMA_Max_DD_vs_Base, name = "Europe", line = list(color = "#FF7F0E", width = 1)) %>%
  add_trace(x = ~Start_Date, y = ~Pacific_Lump_Sum_USD_SMA_Max_DD_vs_Base, name = "Pacific", line = list(color = "#D62728", width = 1)) %>%
  add_trace(x = ~Start_Date, y = ~Emerging_Lump_Sum_USD_SMA_Max_DD_vs_Base, name = "Emerging", line = list(color = "#9467BD", width = 1)) %>%
  layout(xaxis = list(title = "Starting Dates"), yaxis = list(title = NULL, range = c(-0.35, 0.35), tick0 = 0, dtick = 0.1))

panel_8th <- data %>%
  mutate(
    across(
      .cols = contains("Max_DD") & !all_of("World_Lump_Sum_USD_Base_Max_DD"),
      .fns = ~ .x - get("World_Lump_Sum_USD_Base_Max_DD"),
      .names = "{.col}_vs_Base")) %>%
  filter(Span == 40) %>%
  plot_ly(type = "scatter", mode = "lines", showlegend = FALSE) %>%
  add_trace(x = ~Start_Date, y = ~World_Lump_Sum_USD_SMA_Max_DD_vs_Base, name = "World", line = list(color = "#1F77B4", width = 1)) %>%
  add_trace(x = ~Start_Date, y = ~North_America_Lump_Sum_USD_SMA_Max_DD_vs_Base, name = "North America", line = list(color = "#2CA02C", width = 1)) %>%
  add_trace(x = ~Start_Date, y = ~Europe_Lump_Sum_EUR_SMA_Max_DD_vs_Base, name = "Europe", line = list(color = "#FF7F0E", width = 1)) %>%
  add_trace(x = ~Start_Date, y = ~Pacific_Lump_Sum_USD_SMA_Max_DD_vs_Base, name = "Pacific", line = list(color = "#D62728", width = 1)) %>%
  add_trace(x = ~Start_Date, y = ~Emerging_Lump_Sum_USD_SMA_Max_DD_vs_Base, name = "Emerging", line = list(color = "#9467BD", width = 1)) %>%
  layout(xaxis = list(title = "Starting Dates"), yaxis = list(title = NULL, range = c(-0.35, 0.35), tick0 = 0, dtick = 0.1))

figures <- subplot(panel_1st, panel_2nd, panel_3rd, panel_4th, panel_5th, panel_6th, panel_7th, panel_8th, nrows = 2, shareX = TRUE, shareY = FALSE) %>%
  layout(
    title = "Moving Relative Metrics - Moving Average - Lump Sum\n10 Years - 20 Years - 30 Years - 40 Years",
    legend = list(orientation = 'h', x = 0.5, xanchor = "center", y = -0.05), margin = list(t = 75),
    yaxis = list(title = "Absolute Differences in True Time Weighted Rate of Returns"),
    yaxis5 = list(title = "Absolute Differences in Maximum Drawdowns"))
saveWidget(figures, "Moving Average Lump Sum.html", selfcontained = TRUE)


#---- Rolling Metrics Analysis - Moving Average - DCA
panel_1st <- data %>%
  mutate(
    across(
      .cols = contains("TTWROR") & !all_of("World_DCA_USD_Base_TTWROR"),
      .fns = ~ .x - get("World_DCA_USD_Base_TTWROR"),
      .names = "{.col}_vs_Base")) %>%
  filter(Span == 10) %>%
  plot_ly(type = "scatter", mode = "lines", showlegend = TRUE) %>%
  add_trace(x = ~Start_Date, y = ~World_DCA_USD_SMA_TTWROR_vs_Base, name = "World", line = list(color = "#1F77B4", width = 1)) %>%
  add_trace(x = ~Start_Date, y = ~North_America_DCA_USD_SMA_TTWROR_vs_Base, name = "North America", line = list(color = "#2CA02C", width = 1)) %>%
  add_trace(x = ~Start_Date, y = ~Europe_DCA_EUR_SMA_TTWROR_vs_Base, name = "Europe", line = list(color = "#FF7F0E", width = 1)) %>%
  add_trace(x = ~Start_Date, y = ~Pacific_DCA_USD_SMA_TTWROR_vs_Base, name = "Pacific", line = list(color = "#D62728", width = 1)) %>%
  add_trace(x = ~Start_Date, y = ~Emerging_DCA_USD_SMA_TTWROR_vs_Base, name = "Emerging", line = list(color = "#9467BD", width = 1)) %>%
  layout(xaxis = list(title = "Starting Dates"), yaxis = list(title = NULL, range = c(-0.35, 0.35), tick0 = 0, dtick = 0.1))

panel_2nd <- data %>%
  mutate(
    across(
      .cols = contains("TTWROR") & !all_of("World_DCA_USD_Base_TTWROR"),
      .fns = ~ .x - get("World_DCA_USD_Base_TTWROR"),
      .names = "{.col}_vs_Base")) %>%
  filter(Span == 20) %>%
  plot_ly(type = "scatter", mode = "lines", showlegend = FALSE) %>%
  add_trace(x = ~Start_Date, y = ~World_DCA_USD_SMA_TTWROR_vs_Base, name = "World", line = list(color = "#1F77B4", width = 1)) %>%
  add_trace(x = ~Start_Date, y = ~North_America_DCA_USD_SMA_TTWROR_vs_Base, name = "North America", line = list(color = "#2CA02C", width = 1)) %>%
  add_trace(x = ~Start_Date, y = ~Europe_DCA_EUR_SMA_TTWROR_vs_Base, name = "Europe", line = list(color = "#FF7F0E", width = 1)) %>%
  add_trace(x = ~Start_Date, y = ~Pacific_DCA_USD_SMA_TTWROR_vs_Base, name = "Pacific", line = list(color = "#D62728", width = 1)) %>%
  add_trace(x = ~Start_Date, y = ~Emerging_DCA_USD_SMA_TTWROR_vs_Base, name = "Emerging", line = list(color = "#9467BD", width = 1)) %>%
  layout(xaxis = list(title = "Starting Dates"), yaxis = list(title = NULL, range = c(-0.35, 0.35), tick0 = 0, dtick = 0.1))

panel_3rd <- data %>%
  mutate(
    across(
      .cols = contains("TTWROR") & !all_of("World_DCA_USD_Base_TTWROR"),
      .fns = ~ .x - get("World_DCA_USD_Base_TTWROR"),
      .names = "{.col}_vs_Base")) %>%
  filter(Span == 30) %>%
  plot_ly(type = "scatter", mode = "lines", showlegend = FALSE) %>%
  add_trace(x = ~Start_Date, y = ~World_DCA_USD_SMA_TTWROR_vs_Base, name = "World", line = list(color = "#1F77B4", width = 1)) %>%
  add_trace(x = ~Start_Date, y = ~North_America_DCA_USD_SMA_TTWROR_vs_Base, name = "North America", line = list(color = "#2CA02C", width = 1)) %>%
  add_trace(x = ~Start_Date, y = ~Europe_DCA_EUR_SMA_TTWROR_vs_Base, name = "Europe", line = list(color = "#FF7F0E", width = 1)) %>%
  add_trace(x = ~Start_Date, y = ~Pacific_DCA_USD_SMA_TTWROR_vs_Base, name = "Pacific", line = list(color = "#D62728", width = 1)) %>%
  add_trace(x = ~Start_Date, y = ~Emerging_DCA_USD_SMA_TTWROR_vs_Base, name = "Emerging", line = list(color = "#9467BD", width = 1)) %>%
  layout(xaxis = list(title = "Starting Dates"), yaxis = list(title = NULL, range = c(-0.35, 0.35), tick0 = 0, dtick = 0.1))

panel_4th <- data %>%
  mutate(
    across(
      .cols = contains("TTWROR") & !all_of("World_DCA_USD_Base_TTWROR"),
      .fns = ~ .x - get("World_DCA_USD_Base_TTWROR"),
      .names = "{.col}_vs_Base")) %>%
  filter(Span == 40) %>%
  plot_ly(type = "scatter", mode = "lines", showlegend = FALSE) %>%
  add_trace(x = ~Start_Date, y = ~World_DCA_USD_SMA_TTWROR_vs_Base, name = "World", line = list(color = "#1F77B4", width = 1)) %>%
  add_trace(x = ~Start_Date, y = ~North_America_DCA_USD_SMA_TTWROR_vs_Base, name = "North America", line = list(color = "#2CA02C", width = 1)) %>%
  add_trace(x = ~Start_Date, y = ~Europe_DCA_EUR_SMA_TTWROR_vs_Base, name = "Europe", line = list(color = "#FF7F0E", width = 1)) %>%
  add_trace(x = ~Start_Date, y = ~Pacific_DCA_USD_SMA_TTWROR_vs_Base, name = "Pacific", line = list(color = "#D62728", width = 1)) %>%
  add_trace(x = ~Start_Date, y = ~Emerging_DCA_USD_SMA_TTWROR_vs_Base, name = "Emerging", line = list(color = "#9467BD", width = 1)) %>%
  layout(xaxis = list(title = "Starting Dates"), yaxis = list(title = NULL, range = c(-0.35, 0.35), tick0 = 0, dtick = 0.1))

panel_5th <- data %>%
  mutate(
    across(
      .cols = contains("Max_DD") & !all_of("World_DCA_USD_Base_Max_DD"),
      .fns = ~ .x - get("World_DCA_USD_Base_Max_DD"),
      .names = "{.col}_vs_Base")) %>%
  filter(Span == 10) %>%
  plot_ly(type = "scatter", mode = "lines", showlegend = FALSE) %>%
  add_trace(x = ~Start_Date, y = ~World_DCA_USD_SMA_Max_DD_vs_Base, name = "World", line = list(color = "#1F77B4", width = 1)) %>%
  add_trace(x = ~Start_Date, y = ~North_America_DCA_USD_SMA_Max_DD_vs_Base, name = "North America", line = list(color = "#2CA02C", width = 1)) %>%
  add_trace(x = ~Start_Date, y = ~Europe_DCA_EUR_SMA_Max_DD_vs_Base, name = "Europe", line = list(color = "#FF7F0E", width = 1)) %>%
  add_trace(x = ~Start_Date, y = ~Pacific_DCA_USD_SMA_Max_DD_vs_Base, name = "Pacific", line = list(color = "#D62728", width = 1)) %>%
  add_trace(x = ~Start_Date, y = ~Emerging_DCA_USD_SMA_Max_DD_vs_Base, name = "Emerging", line = list(color = "#9467BD", width = 1)) %>%
  layout(xaxis = list(title = "Starting Dates"), yaxis = list(title = NULL, range = c(-0.35, 0.35), tick0 = 0, dtick = 0.1))

panel_6th <- data %>%
  mutate(
    across(
      .cols = contains("Max_DD") & !all_of("World_DCA_USD_Base_Max_DD"),
      .fns = ~ .x - get("World_DCA_USD_Base_Max_DD"),
      .names = "{.col}_vs_Base")) %>%
  filter(Span == 20) %>%
  plot_ly(type = "scatter", mode = "lines", showlegend = FALSE) %>%
  add_trace(x = ~Start_Date, y = ~World_DCA_USD_SMA_Max_DD_vs_Base, name = "World", line = list(color = "#1F77B4", width = 1)) %>%
  add_trace(x = ~Start_Date, y = ~North_America_DCA_USD_SMA_Max_DD_vs_Base, name = "North America", line = list(color = "#2CA02C", width = 1)) %>%
  add_trace(x = ~Start_Date, y = ~Europe_DCA_EUR_SMA_Max_DD_vs_Base, name = "Europe", line = list(color = "#FF7F0E", width = 1)) %>%
  add_trace(x = ~Start_Date, y = ~Pacific_DCA_USD_SMA_Max_DD_vs_Base, name = "Pacific", line = list(color = "#D62728", width = 1)) %>%
  add_trace(x = ~Start_Date, y = ~Emerging_DCA_USD_SMA_Max_DD_vs_Base, name = "Emerging", line = list(color = "#9467BD", width = 1)) %>%
  layout(xaxis = list(title = "Starting Dates"), yaxis = list(title = NULL, range = c(-0.35, 0.35), tick0 = 0, dtick = 0.1))

panel_7th <- data %>%
  mutate(
    across(
      .cols = contains("Max_DD") & !all_of("World_DCA_USD_Base_Max_DD"),
      .fns = ~ .x - get("World_DCA_USD_Base_Max_DD"),
      .names = "{.col}_vs_Base")) %>%
  filter(Span == 30) %>%
  plot_ly(type = "scatter", mode = "lines", showlegend = FALSE) %>%
  add_trace(x = ~Start_Date, y = ~World_DCA_USD_SMA_Max_DD_vs_Base, name = "World", line = list(color = "#1F77B4", width = 1)) %>%
  add_trace(x = ~Start_Date, y = ~North_America_DCA_USD_SMA_Max_DD_vs_Base, name = "North America", line = list(color = "#2CA02C", width = 1)) %>%
  add_trace(x = ~Start_Date, y = ~Europe_DCA_EUR_SMA_Max_DD_vs_Base, name = "Europe", line = list(color = "#FF7F0E", width = 1)) %>%
  add_trace(x = ~Start_Date, y = ~Pacific_DCA_USD_SMA_Max_DD_vs_Base, name = "Pacific", line = list(color = "#D62728", width = 1)) %>%
  add_trace(x = ~Start_Date, y = ~Emerging_DCA_USD_SMA_Max_DD_vs_Base, name = "Emerging", line = list(color = "#9467BD", width = 1)) %>%
  layout(xaxis = list(title = "Starting Dates"), yaxis = list(title = NULL, range = c(-0.35, 0.35), tick0 = 0, dtick = 0.1))

panel_8th <- data %>%
  mutate(
    across(
      .cols = contains("Max_DD") & !all_of("World_DCA_USD_Base_Max_DD"),
      .fns = ~ .x - get("World_DCA_USD_Base_Max_DD"),
      .names = "{.col}_vs_Base")) %>%
  filter(Span == 40) %>%
  plot_ly(type = "scatter", mode = "lines", showlegend = FALSE) %>%
  add_trace(x = ~Start_Date, y = ~World_DCA_USD_SMA_Max_DD_vs_Base, name = "World", line = list(color = "#1F77B4", width = 1)) %>%
  add_trace(x = ~Start_Date, y = ~North_America_DCA_USD_SMA_Max_DD_vs_Base, name = "North America", line = list(color = "#2CA02C", width = 1)) %>%
  add_trace(x = ~Start_Date, y = ~Europe_DCA_EUR_SMA_Max_DD_vs_Base, name = "Europe", line = list(color = "#FF7F0E", width = 1)) %>%
  add_trace(x = ~Start_Date, y = ~Pacific_DCA_USD_SMA_Max_DD_vs_Base, name = "Pacific", line = list(color = "#D62728", width = 1)) %>%
  add_trace(x = ~Start_Date, y = ~Emerging_DCA_USD_SMA_Max_DD_vs_Base, name = "Emerging", line = list(color = "#9467BD", width = 1)) %>%
  layout(xaxis = list(title = "Starting Dates"), yaxis = list(title = NULL, range = c(-0.35, 0.35), tick0 = 0, dtick = 0.1))

figure <- subplot(panel_1st, panel_2nd, panel_3rd, panel_4th, panel_5th, panel_6th, panel_7th, panel_8th, nrows = 2, shareX = TRUE, shareY = FALSE) %>%
  layout(
    title = "Moving Relative Metrics - Moving Average - DCA\n10 Years - 20 Years - 30 Years - 40 Years",
    legend = list(orientation = 'h', x = 0.5, xanchor = "center", y = -0.05), margin = list(t = 75),
    yaxis = list(title = "Absolute Differences in True Time Weighted Rate of Returns"),
    yaxis5 = list(title = "Absolute Differences in Maximum Drawdowns"))
saveWidget(figure, "Moving Average DCA.html", selfcontained = TRUE)


########################################################################################################################
# Kapitel 2: Grafiken für Produkte und Telltale-Chart
########################################################################################################################
colors <- c("World - Long x2 - Lump Sum - USD" = "#1F77B4", "World - Long x2 - DCA - USD" = "#AEC7E8",
            "North America - Long x2 - Lump Sum - USD"= "#2CA02C", "North America - Long x2 - DCA - USD"= "#98DF8A",
            "Europe - Long x2 - Lump Sum - USD"= "#FF7F0E", "Europe - Long x2 - DCA - USD" = "#FFBB78",
            "Pacific - Long x2 - Lump Sum - USD" = "#D62728", "Pacific - Long x2 - DCA - USD" = "#FF9896",
            "Emerging - Long x2 - Lump Sum - USD" = "#9467BD", "Emerging - Long x2 - DCA - USD" = "#C5B0D5")


#---- Visualisierung der Produkt-Zeitreihen
read.csv("./Project Gloverage Funds.csv") %>%
  mutate(across(-c(date), ~ .x/100)) %>%
  plot_ly(type = "scatter", mode = "lines") %>%
  add_trace(x = ~date, y = ~log(world_us_sim), line = list(width = 1, color = colors["World"]), name = "MSCI World x2 USD") %>%
  add_trace(x = ~date, y = ~log(north_america_us_sim), line = list(width = 1, color = colors["North America"]), name = "MSCI North America x2 USD") %>%
  add_trace(x = ~date, y = ~log(europe_eu_sim), line = list(width = 1, color = colors["Europe"]), name = "MSCI Europe x2 EUR") %>%
  add_trace(x = ~date, y = ~log(pacific_us_sim), line = list(width = 1, color = colors["Pacific"]), name = "MSCI Pacific x2 USD") %>%
  add_trace(x = ~date, y = ~log(emerging_us_sim), line = list(width = 1, color = colors["Emerging"]), name = "MSCI Emerging x2 USD") %>%
  layout(
    showlegend = TRUE, legend = list(orientation = 'h'),
    xaxis = list(title = "Time"),
    yaxis = list(title = "Log. Market Value"),
    title = "Statistical Simulation of Leveraged Exchange Trade Funds",
    margin = list(t = 50))


#---- Erstellung Telltale-Chart
tell_tale <- read.csv("./Project Gloverage Funds.csv") %>%
  mutate(date = as.Date(date)) %>%
  plot_ly(type = "scatter", mode = "lines") %>%
  add_trace(x = ~date, y = ~log(world_us_sim) - log(world_us_sim), line = list(width = 1, color = colors["World"]), name = "MSCI World x2 USD") %>%
  add_trace(x = ~date, y = ~log(north_america_us_sim) - log(world_us_sim), line = list(width = 1, color = colors["North America"]), name = "MSCI North America x2 USD") %>%
  add_trace(x = ~date, y = ~log(europe_eu_sim) - log(world_us_sim), line = list(width = 1, color = colors["Europe"]), name = "MSCI Europe x2 EUR") %>%
  add_trace(x = ~date, y = ~log(pacific_us_sim) - log(world_us_sim), line = list(width = 1, color = colors["Pacific"]), name = "MSCI Pacific x2 USD") %>%
  add_trace(x = ~date, y = ~log(emerging_us_sim) - log(world_us_sim), line = list(width = 1, color = colors["Emerging"]), name = "MSCI Emerging x2 USD") %>%
  add_trace(x = ~date, y = ~log(world_eu_sim) - log(world_us_sim), line = list(width = 1, color = colors["World"], dash = 'dot'), name = "MSCI World x2 EUR") %>%
  add_trace(x = ~date, y = ~log(north_america_eu_sim) - log(world_us_sim), line = list(width = 1, color = colors["North America"], dash = 'dot'), name = "MSCI North America x2 EUR") %>%
  add_trace(x = ~date, y = ~log(europe_us_sim) - log(world_us_sim), line = list(width = 1, color = colors["Europe"], dash = 'dot'), name = "MSCI Europe x2 USD") %>%
  add_trace(x = ~date, y = ~log(pacific_eu_sim) - log(world_us_sim), line = list(width = 1, color = colors["Pacific"], dash = 'dot'), name = "MSCI Pacific x2 EUR") %>%
  add_trace(x = ~date, y = ~log(emerging_eu_sim) - log(world_us_sim), line = list(width = 1, color = colors["Emerging"], dash = 'dot'), name = "MSCI Emerging x2 EUR") %>%
  layout(
    showlegend = TRUE, legend = list(orientation = "h"),
    xaxis = list(title = "Time"),
    yaxis = list(title = "Log. Excess Return"),
    title = "A Tale of Leverage in Space and Time",
    margin = list(t = 50))
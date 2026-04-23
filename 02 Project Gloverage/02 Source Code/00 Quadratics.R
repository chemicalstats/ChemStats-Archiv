########################################################################################################################
# Vorbereitung des Systems
########################################################################################################################
packages <- c("data.table", "tidyverse", "tidyquant", "imputeTS", "plotly", "httr", "jsonlite", "quadprog")
invisible(lapply(packages, require, character.only = TRUE)); rm(packages)
if(.Platform$OS.type == "windows"){Sys.setlocale("LC_ALL", "en_US.UTF-8")}

#---> Hilfsfunktion für den Abruf der Marktindizes:
scraping_index <- function(code, type, currency, start, stopp, freq){
  data <- GET(
    paste0("https://app2.msci.com/products/service/index/indexmaster/getLevelDataForGraph?currency_symbol=", 
           currency, "&index_variant=", type, "&start_date=", start, 
           "&end_date=", stopp, "&data_frequency=", freq, "&index_codes=", code))
  
  if(status_code(data) == 200){
    data <- fromJSON(content(data, "text", encoding = "utf-8"))$indexes$INDEX_LEVELS
  } else {
    print("Fehler beim Abrufen der Daten")
  }
  return(data)
}

#---> Hilfsfunktion für die Grid Search-Berechnung:
search_metrics <- function(search_data, search_grid){
  metrics <- sapply(
    list(
      median_absolute_error = function(x) median(abs(x), na.rm = TRUE),
      mean_absolute_error = function(x) mean(abs(x), na.rm = TRUE),
      mean_squared_error = function(x) mean(x^2, na.rm = TRUE),
      root_mean_squared_error = function(x) sqrt(mean(x^2, na.rm = TRUE)),
      median_absolute_percentage_error = function(x) median(abs(x / (x + 1e-8)) * 100, na.rm = TRUE),
      mean_absolute_percentage_error = function(x) mean(abs(x / (x + 1e-8) * 100), na.rm = TRUE),
      mean_squared_percentage_error = function(x) mean((x / (x + 1e-8))^2 * 100, na.rm = TRUE),
      root_mean_squared_percentage_error = function(x) sqrt(mean((x / (x + 1e-8))^2 * 100, na.rm = TRUE))),
    function(metric){search_grid[which.min(apply(search_data, 2, metric))]})
  return(metrics)
}

#---> Hilfsfunktion für das Quadratic Solving:
estimate_indices <- function(daily, monthly, base, index){
  all_results <- list()
  prev_level <- 100
  
  for(i in 1:nrow(monthly)){
    calendar <- daily %>%
      filter(date >= floor_date(monthly$date[i], "month") & (date <= ceiling_date(monthly$date[i], "month") - days(1))) %>%
      pull(date)
    
    T <- length(calendar)
    if(T == 0) next
    
    R_month <- monthly[, index][i]
    r_H_vec <- pull(daily[daily$date %in% calendar, base])
    ref_r <- r_H_vec
    
    # Quadratic Programming:
    Dmat <- 2 * diag(T)
    dvec <- 2 * ref_r
    Amat <- matrix(1, nrow=T, ncol=1)
    bvec <- R_month
    qp_solution <- solve.QP(Dmat, dvec, Amat, bvec, meq=1)
    r_t <- qp_solution$solution
    
    level_t <- prev_level * cumprod(1 + r_t)
    all_results[[i]] <- data.frame(date = calendar, r_daily = r_t, level = level_t)
    prev_level <- tail(level_t, 1)
  }
  
  bind_rows(all_results)
}


#---> Initialisierung der Monatszeitreihen:
start_date <- "1969-01-01"
stopp_date <- "2025-09-01"

msci_month <- list(
  scraping_index(code = "990100", type = "STRD", currency = "USD", freq = "END_OF_MONTH",
                 start = gsub("-", "", start_date), stopp = gsub("-", "", stopp_date)) %>%
    mutate(date = as.Date(as.character(calc_date), format = "%Y%m%d"), world = level_eod) %>%
    select(date, world),
  scraping_index(code = "990200", type = "STRD", currency = "USD", freq = "END_OF_MONTH",
                 start = gsub("-", "", start_date), stopp = gsub("-", "", stopp_date)) %>%
    mutate(date = as.Date(as.character(calc_date), format = "%Y%m%d"), north_america = level_eod) %>%
    select(date, north_america),
  scraping_index(code = "990500", type = "STRD", currency = "USD", freq = "END_OF_MONTH",
                 start = gsub("-", "", start_date), stopp = gsub("-", "", stopp_date)) %>%
    mutate(date = as.Date(as.character(calc_date), format = "%Y%m%d"), europe = level_eod) %>%
    select(date, europe),
  scraping_index(code = "990800", type = "STRD", currency = "USD", freq = "END_OF_MONTH",
                 start = gsub("-", "", start_date), stopp = gsub("-", "", stopp_date)) %>%
    mutate(date = as.Date(as.character(calc_date), format = "%Y%m%d"), pacific = level_eod) %>%
    select(date, pacific),
  scraping_index(code = "891800", type = "STRD", currency = "USD", freq = "END_OF_MONTH",
                 start = gsub("-", "", start_date), stopp = gsub("-", "", stopp_date)) %>%
    mutate(date = as.Date(as.character(calc_date), format = "%Y%m%d"), emerging = level_eod) %>%
    select(date, emerging)) %>%
  Reduce(function(x, y) left_join(x, y, by = "date"), .) %>%
  mutate(across(-date, ~ (. / lag(.) - 1), .names = "{.col}_return")) %>%
  filter(date >= "1975-01-01")


#---> Initialisierung der Tageszeitreihen:
start_date <- "1974-12-31"
stopp_date <- "2025-09-01"

msci_data <- list(
  data.frame(date = seq.Date(from = as.Date(start_date),
                             to = as.Date(paste0(year(Sys.Date()), "-12-31")),
                             by = "days")) %>%
    group_by(year = format(date, "%Y")) %>%
    mutate(days = ifelse(year != year(Sys.Date()), n(),
                         length(seq.Date(
                           as.Date(paste0(year(Sys.Date()), "-01-01")),
                           as.Date(paste0(year(Sys.Date()), "-12-31")),
                           by = "days")))) %>%
    ungroup() %>%
    select(date, days),
  tq_get("^990100-USD-STRD", from = start_date) %>%
    select(date, world_yahoo = adjusted),
  scraping_index(code = "990100", type = "STRD", currency = "USD", freq = "DAILY",
                 start = gsub("-", "", start_date), stopp = gsub("-", "", stopp_date)) %>%
    mutate(date = as.Date(as.character(calc_date), format = "%Y%m%d"), world_msci = level_eod) %>%
    select(date, world_msci),
  scraping_index(code = "990200", type = "STRD", currency = "USD", freq = "DAILY",
                 start = gsub("-", "", start_date), stopp = gsub("-", "", stopp_date)) %>%
    mutate(date = as.Date(as.character(calc_date), format = "%Y%m%d"), north_america = level_eod) %>%
    select(date, north_america),
  scraping_index(code = "990500", type = "STRD", currency = "USD", freq = "DAILY",
                 start = gsub("-", "", start_date), stopp = gsub("-", "", stopp_date)) %>%
    mutate(date = as.Date(as.character(calc_date), format = "%Y%m%d"), europe = level_eod) %>%
    select(date, europe),
  scraping_index(code = "990800", type = "STRD", currency = "USD", freq = "DAILY",
                 start = gsub("-", "", start_date), stopp = gsub("-", "", stopp_date)) %>%
    mutate(date = as.Date(as.character(calc_date), format = "%Y%m%d"), pacific = level_eod) %>%
    select(date, pacific),
  scraping_index(code = "891800", type = "STRD", currency = "USD", freq = "DAILY",
                 start = gsub("-", "", start_date), stopp = gsub("-", "", stopp_date)) %>%
    mutate(date = as.Date(as.character(calc_date), format = "%Y%m%d"), emerging = level_eod) %>%
    select(date, emerging)) %>%
  Reduce(function(x, y) left_join(x, y, by = "date"), .) %>%
  mutate(
    world = ifelse(date >= "1996-12-31", world_msci, world_yahoo),
    world = round(na_interpolation(world, "stine"), digits = 5),
    world_return = (world/lag(world) - 1),
    north_america = ifelse(date >= "1997-01-01", round(na_interpolation(north_america, "stine"), digits = 5), NA),
    north_america_return = (north_america/lag(north_america) - 1),
    europe = ifelse(date >= "1997-01-01", round(na_interpolation(europe, "stine"), digits = 5), NA),
    europe_return = (europe/lag(europe) - 1),
    pacific = ifelse(date >= "1997-01-01", round(na_interpolation(pacific, "stine"), digits = 5), NA),
    pacific_return = (pacific/lag(pacific) - 1),
    emerging = ifelse(date >= "1997-01-01", round(na_interpolation(emerging, "stine"), digits = 5), NA),
    emerging_return = (emerging/lag(emerging) - 1)) %>%
  filter(date <= stopp_date)


#---> Lösung des Quadratic Programming Problems:
america <- estimate_indices(msci_data, msci_month, "world_return", "north_america_return")
europe <- estimate_indices(msci_data, msci_month, "world_return", "europe_return")
pacific <- estimate_indices(msci_data, msci_month, "world_return", "pacific_return")
emerging <- estimate_indices(msci_data %>% filter(date >= "1988-01-01"), msci_month, "world_return", "emerging_return")


#---> Vervollständigung der Indexzeitreihen:
msci_ests <- list(
  msci_data,
  america %>% select(date, na_level = level),
  europe %>% select(date, eu_level = level),
  pacific %>% select(date, pc_level = level),
  emerging %>% select(date, em_level = level)) %>%
  Reduce(function(x, y) left_join(x, y, by = "date"), .) %>%
  filter(date >= "1975-01-01" & date <= stopp_date) %>%
  mutate(
    na_level = na_level/first(na_level),
    na_return = ifelse(date <= "1997-01-01", (na_level/lag(na_level) - 1) - 0.0297/1000, north_america_return),
    na_model = Reduce(function(values, rates){values*(1+rates)}, lead(na_return), init = 1, accumulate = TRUE)[-nrow(.)],
    eu_level = eu_level/first(eu_level),
    eu_return = ifelse(date <= "1997-01-01", (eu_level/lag(eu_level) - 1) - 0.0508/1000, europe_return),
    eu_model = Reduce(function(values, rates){values*(1+rates)}, lead(eu_return), init = 1, accumulate = TRUE)[-nrow(.)],
    pc_level = pc_level/first(pc_level),
    pc_return = ifelse(date <= "1997-01-01", (pc_level/lag(pc_level) - 1) - 0.056/1000, pacific_return),
    pc_model = Reduce(function(values, rates){values*(1+rates)}, lead(pc_return), init = 1, accumulate = TRUE)[-nrow(.)],
    em_level = em_level / first(em_level[date == as.Date("1988-01-01")]),
    em_return = ifelse(date <= "1997-01-01", (em_level/lag(em_level) - 1) - 0.049/1000, emerging_return),
    em_model = {
      row <- which(date >= "1988-01-01")
      out <- rep(NA_real_, n())
      out[row] <- Reduce(function(values, rates){values*(1+rates)}, lead(em_return[row]), init = 1, accumulate = TRUE)[-length(row)]
      out}) %>%
  filter(date <= "2025-08-31")


msci_ests %>% 
  filter(date >= "1975-01-01" & date <= stopp_date) %>%
  plot_ly(type = "scatter", mode = "lines") %>%
  add_trace(x = ~date, y = ~na_model, name = "North America", line = list(width = 1)) %>%
  add_trace(x = ~date, y = ~eu_model, name = "Europe", line = list(width = 1)) %>%
  add_trace(x = ~date, y = ~pc_model, name = "Pacific", line = list(width = 1)) %>%
  add_trace(x = ~date, y = ~em_model, name = "Emerging", line = list(width = 1)) %>%
  layout(
    showlegend = TRUE, legend = list(orientation = 'h'), 
    xaxis = list(title = "Time"),
    yaxis = list(title = "Index Value"),
    title = "MSCI Regional Indices (Simulation)",
    margin = list(t = 50))

msci_ests %>%
  select(date, na_model, eu_model, pc_model, em_model) %>%
  write.csv(., "./03 Results Data/01 Equity Indicies/Simulation Indices.csv", row.names = FALSE)


msci_month %>%
  plot_ly(type = "scatter", mode = "lines") %>%
  add_trace(x = ~date, y = ~north_america/first(north_america), name = "North America", line = list(width = 1)) %>%
  add_trace(x = ~date, y = ~europe/first(europe), name = "Europe", line = list(width = 1)) %>%
  add_trace(x = ~date, y = ~pacific/first(pacific), name = "Pacific", line = list(width = 1)) %>%
  add_trace(x = ~date, y = ~emerging/first(emerging[msci_month$date == "1987-12-31"]) * 100, name = "Emerging", line = list(width = 1)) %>%
  layout(
    showlegend = TRUE, legend = list(orientation = 'h'), 
    xaxis = list(title = "Time"),
    yaxis = list(title = "Index Value"),
    title = "MSCI Regional Indices (Monthly)",
    margin = list(t = 50))
########################################################################################################################
# Bereinigung des Workspace
########################################################################################################################
rm(list = ls())
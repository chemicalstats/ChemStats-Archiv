########################################################################################################################
# Vorbereitung des Systems
########################################################################################################################
packages <- c("tidyverse", "tidyquant", "imputeTS", "plotly")
invisible(lapply(packages, require, character.only = TRUE)); rm(packages)
if(.Platform$OS.type == "windows"){Sys.setlocale("LC_ALL", "en_US.UTF-8")}

#---> Definition des Analysehorizonts:
start_date <- "1975-01-01"
stopp_date <- "2025-08-31"


#---> Initialisierung Index-Zeitreihen:
msci_full_data <- list(
  #---> 1. Konstruktion des Kalendar-Zeitindex und Berechnung der Kalendartage pro Jahr:
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
  #---> 2. USD-Indices: 
  read.csv("./03 Results Data/01 Equity Indicies/MSCI World USD.csv") %>%
    mutate(date = as.Date(date, format = "%Y-%m-%d")) %>%
    select(date, world_us = world_us_ndtr_l2),
  read.csv("./03 Results Data/01 Equity Indicies/MSCI North America USD.csv") %>%
    mutate(date = as.Date(date, format = "%Y-%m-%d")) %>%
    select(date, north_america_us = north_america_us_ndtr_l2),
  read.csv("./03 Results Data/01 Equity Indicies/MSCI Europe USD.csv") %>%
    mutate(date = as.Date(date, format = "%Y-%m-%d")) %>%
    select(date, europe_us = europe_us_ndtr_l2),
  read.csv("./03 Results Data/01 Equity Indicies/MSCI Pacific USD.csv") %>%
    mutate(date = as.Date(date, format = "%Y-%m-%d")) %>%
    select(date, pacific_us = pacific_us_ndtr_l2),
  read.csv("./03 Results Data/01 Equity Indicies/MSCI Emerging USD.csv") %>%
    mutate(date = as.Date(date, format = "%Y-%m-%d")) %>%
    select(date, emerging_us = emerging_us_ndtr_l2),
  #---> 3. EUR-Indices: 
  read.csv("./03 Results Data/01 Equity Indicies/MSCI World EUR.csv") %>%
    mutate(date = as.Date(date, format = "%Y-%m-%d")) %>%
    select(date, world_eu = world_eu_ndtr_l2),
  read.csv("./03 Results Data/01 Equity Indicies/MSCI North America EUR.csv") %>%
    mutate(date = as.Date(date, format = "%Y-%m-%d")) %>%
    select(date, north_america_eu = north_america_eu_ndtr_l2),
  read.csv("./03 Results Data/01 Equity Indicies/MSCI Europe EUR.csv") %>%
    mutate(date = as.Date(date, format = "%Y-%m-%d")) %>%
    select(date, europe_eu = europe_eu_ndtr_l2),
  read.csv("./03 Results Data/01 Equity Indicies/MSCI Pacific EUR.csv") %>%
    mutate(date = as.Date(date, format = "%Y-%m-%d")) %>%
    select(date, pacific_eu = pacific_eu_ndtr_l2),
  read.csv("./03 Results Data/01 Equity Indicies/MSCI Emerging EUR.csv") %>%
    mutate(date = as.Date(date, format = "%Y-%m-%d")) %>%
    select(date, emerging_eu = emerging_eu_ndtr_l2),
  #---> 4. EUR-USD-Wechselkurs: 
  read.csv("./01 Source Data/02 EuroStat/Eurostat Exchange Rate EUCR.csv") %>%
    filter(Currency == "US dollar") %>%
    mutate(
      date = as.Date(TIME_PERIOD, format="%Y-%m-%d"),
      eucr = 1 / OBS_VALUE) %>%
    filter(date >= start_date & date <= stopp_date) %>%
    select(date, eucr)) %>%
  Reduce(function(x, y) left_join(x, y, by = c("date")), .) %>%
  mutate(eucr = round(na_interpolation(eucr, "stine"), digits = 5)) %>%
  filter(date >= start_date & date <= stopp_date) %>%
  #---> 5. Berechnung Leveraged Exchange Funds: 
  mutate(
    #--------> 5a. MSCI World USD:
    world_us_ter = 0.6,
    world_us_return = world_us/lag(world_us),
    world_us_sim_return = world_us_return - ((world_us_ter/100 + 1)^(1/days) - 1),
    world_us_sim = Reduce(function(values, rates){values*rates},
                       lead(world_us_sim_return), init = 100, accumulate = TRUE)[-nrow(.)],
    world_us_sim = case_when(row_number() == n() ~ round(lag(world_us_sim)*world_us_sim_return, digits = 2), TRUE ~ world_us_sim),
    world_us_sim = world_us_sim * eucr,
    world_us_sim = world_us_sim/first(world_us_sim) * 100,
    #--------> 5b. MSCI North America USD:
    north_america_us_ter = 0.5,
    north_america_us_return = north_america_us/lag(north_america_us),
    north_america_us_sim_return = north_america_us_return - ((north_america_us_ter/100 + 1)^(1/days) - 1),
    north_america_us_sim = Reduce(function(values, rates){values*rates},
                       lead(north_america_us_sim_return), init = 100, accumulate = TRUE)[-nrow(.)],
    north_america_us_sim = case_when(row_number() == n() ~ round(lag(north_america_us_sim)*north_america_us_sim_return, digits = 2), TRUE ~ north_america_us_sim),
    north_america_us_sim = north_america_us_sim * eucr,
    north_america_us_sim = north_america_us_sim/first(north_america_us_sim) * 100,
    #--------> 5c. MSCI Europe USD:
    europe_us_ter = 0.5,
    europe_us_return = europe_us/lag(europe_us),
    europe_us_sim_return = europe_us_return - ((europe_us_ter/100 + 1)^(1/days) - 1),
    europe_us_sim = Reduce(function(values, rates){values*rates},
                       lead(europe_us_sim_return), init = 100, accumulate = TRUE)[-nrow(.)],
    europe_us_sim = case_when(row_number() == n() ~ round(lag(europe_us_sim)*europe_us_sim_return, digits = 2), TRUE ~ europe_us_sim),
    europe_us_sim = europe_us_sim * eucr,
    europe_us_sim = europe_us_sim/first(europe_us_sim) * 100,
    #--------> 5d. MSCI Pacific USD:
    pacific_us_ter = 0.7,
    pacific_us_return = pacific_us/lag(pacific_us),
    pacific_us_sim_return = pacific_us_return - ((pacific_us_ter/100 + 1)^(1/days) - 1),
    pacific_us_sim = Reduce(function(values, rates){values*rates},
                       lead(pacific_us_sim_return), init = 100, accumulate = TRUE)[-nrow(.)],
    pacific_us_sim = case_when(row_number() == n() ~ round(lag(pacific_us_sim)*pacific_us_sim_return, digits = 2), TRUE ~ pacific_us_sim),
    pacific_us_sim = pacific_us_sim * eucr,
    pacific_us_sim = pacific_us_sim/first(pacific_us_sim) * 100,
    #--------> 5e. MSCI Emerging USD:
    emerging_us_ter = 0.8,
    emerging_us_return = emerging_us/lag(emerging_us),
    emerging_us_sim_return = emerging_us_return - ((emerging_us_ter/100 + 1)^(1/days) - 1),
    emerging_us_sim = Reduce(function(values, rates){values*rates},
                       lead(emerging_us_sim_return), init = 100, accumulate = TRUE)[-nrow(.)],
    emerging_us_sim = case_when(row_number() == n() ~ round(lag(emerging_us_sim)*emerging_us_sim_return, digits = 2), TRUE ~ emerging_us_sim),
    emerging_us_sim = emerging_us_sim * eucr,
    emerging_us_sim = {
      rows <- which(date >= as.Date("1988-01-01"))
      sims <- rep(NA, length(emerging_us_sim_return))
      sims[rows[1]] <- 100
      for(i in 2:length(rows)){sims[rows[i]] <- sims[rows[i-1]] * emerging_us_sim_return[rows[i]]}
      sims},
    #--------> 5f. MSCI World EUR:
    world_eu_ter = 0.6,
    world_eu_return = world_eu/lag(world_eu),
    world_eu_sim_return = world_eu_return - ((world_eu_ter/100 + 1)^(1/days) - 1),
    world_eu_sim = Reduce(function(values, rates){values*rates},
                          lead(world_eu_sim_return), init = 100, accumulate = TRUE)[-nrow(.)],
    world_eu_sim = case_when(row_number() == n() ~ round(lag(world_eu_sim)*world_eu_sim_return, digits = 2), TRUE ~ world_eu_sim),
    world_eu_sim = world_eu_sim/first(world_eu_sim) * 100,
    #--------> 5g. MSCI North America EUR:
    north_america_eu_ter = 0.5,
    north_america_eu_return = north_america_eu/lag(north_america_eu),
    north_america_eu_sim_return = north_america_eu_return - ((north_america_eu_ter/100 + 1)^(1/days) - 1),
    north_america_eu_sim = Reduce(function(values, rates){values*rates},
                                  lead(north_america_eu_sim_return), init = 100, accumulate = TRUE)[-nrow(.)],
    north_america_eu_sim = case_when(row_number() == n() ~ round(lag(north_america_eu_sim)*north_america_eu_sim_return, digits = 2), TRUE ~ north_america_eu_sim),
    north_america_eu_sim = north_america_eu_sim/first(north_america_eu_sim) * 100,
    #--------> 5h. MSCI Europe EUR:
    europe_eu_ter = 0.5,
    europe_eu_return = europe_eu/lag(europe_eu),
    europe_eu_sim_return = europe_eu_return - ((europe_eu_ter/100 + 1)^(1/days) - 1),
    europe_eu_sim = Reduce(function(values, rates){values*rates},
                           lead(europe_eu_sim_return), init = 100, accumulate = TRUE)[-nrow(.)],
    europe_eu_sim = case_when(row_number() == n() ~ round(lag(europe_eu_sim)*europe_eu_sim_return, digits = 2), TRUE ~ europe_eu_sim),
    europe_eu_sim = europe_eu_sim/first(europe_eu_sim) * 100,
    #--------> 5i. MSCI Pacific EUR:
    pacific_eu_ter = 0.7,
    pacific_eu_return = pacific_eu/lag(pacific_eu),
    pacific_eu_sim_return = pacific_eu_return - ((pacific_eu_ter/100 + 1)^(1/days) - 1),
    pacific_eu_sim = Reduce(function(values, rates){values*rates},
                            lead(pacific_eu_sim_return), init = 100, accumulate = TRUE)[-nrow(.)],
    pacific_eu_sim = case_when(row_number() == n() ~ round(lag(pacific_eu_sim)*pacific_eu_sim_return, digits = 2), TRUE ~ pacific_eu_sim),
    pacific_eu_sim = pacific_eu_sim/first(pacific_eu_sim) * 100,
    #--------> 5j. MSCI Emerging EUR:
    emerging_eu_ter = 0.8,
    emerging_eu_return = emerging_eu/lag(emerging_eu),
    emerging_eu_sim_return = emerging_eu_return - ((emerging_eu_ter/100 + 1)^(1/days) - 1),
    emerging_eu_sim = Reduce(function(values, rates){values*rates},
                             lead(emerging_eu_sim_return), init = 100, accumulate = TRUE)[-nrow(.)],
    emerging_eu_sim = case_when(row_number() == n() ~ round(lag(emerging_eu_sim)*emerging_eu_sim_return, digits = 2), TRUE ~ emerging_eu_sim),
    emerging_eu_sim = {
      rows <- which(date >= as.Date("1988-01-01"))
      sims <- rep(NA, length(emerging_eu_sim_return))
      sims[rows[1]] <- 100
      for(i in 2:length(rows)){sims[rows[i]] <- sims[rows[i-1]] * emerging_eu_sim_return[rows[i]]}
      sims})

msci_full_data %>%
  select(date, matches("_sim"), -contains("_return")) %>%
  write.csv("./Project Gloverage Funds.csv", row.names = FALSE)


#---> Visualisierung der Produkt-Zeitreihen:
msci_full_data %>%
  mutate(across(-c(date, days), ~ .x/100)) %>%
  plot_ly(type = "scatter", mode = "lines") %>%
  add_trace(x = ~date, y = ~world_us_sim, line = list(width = 1), name = "MSCI World x2 USD") %>%
  add_trace(x = ~date, y = ~north_america_us_sim, line = list(width = 1), name = "MSCI North America x2 USD") %>%
  add_trace(x = ~date, y = ~europe_us_sim, line = list(width = 1), name = "MSCI Europe x2 USD") %>%
  add_trace(x = ~date, y = ~pacific_us_sim, line = list(width = 1), name = "MSCI Pacific x2 USD") %>%
  add_trace(x = ~date, y = ~emerging_us_sim, line = list(width = 1), name = "MSCI Emerging x2 USD") %>%
  add_trace(x = ~date, y = ~world_eu_sim, line = list(width = 1), name = "MSCI World x2 EUR") %>%
  add_trace(x = ~date, y = ~north_america_eu_sim, line = list(width = 1), name = "MSCI North America x2 EUR") %>%
  add_trace(x = ~date, y = ~europe_eu_sim, line = list(width = 1), name = "MSCI Europe x2 EUR") %>%
  add_trace(x = ~date, y = ~pacific_eu_sim, line = list(width = 1), name = "MSCI Pacific x2 EUR") %>%
  add_trace(x = ~date, y = ~emerging_eu_sim, line = list(width = 1), name = "MSCI Emerging x2 EUR") %>%
  layout(
    showlegend = TRUE, legend = list(orientation = 'h'),
    xaxis = list(title = "Time"),
    yaxis = list(title = "Market Value"),
    title = "Statistical Simulation of Leveraged Exchange Trade Funds",
    margin = list(t = 50))

msci_full_data %>%
  mutate(across(-c(date, days), ~ .x/100)) %>%
  plot_ly(type = "scatter", mode = "lines") %>%
  add_trace(x = ~date, y = ~log(world_us_sim), line = list(width = 1), name = "MSCI World x2 USD") %>%
  add_trace(x = ~date, y = ~log(north_america_us_sim), line = list(width = 1), name = "MSCI North America x2 USD") %>%
  add_trace(x = ~date, y = ~log(europe_us_sim), line = list(width = 1), name = "MSCI Europe x2 USD") %>%
  add_trace(x = ~date, y = ~log(pacific_us_sim), line = list(width = 1), name = "MSCI Pacific x2 USD") %>%
  add_trace(x = ~date, y = ~log(emerging_us_sim), line = list(width = 1), name = "MSCI Emerging x2 USD") %>%
  add_trace(x = ~date, y = ~log(world_eu_sim), line = list(width = 1), name = "MSCI World x2 EUR") %>%
  add_trace(x = ~date, y = ~log(north_america_eu_sim), line = list(width = 1), name = "MSCI North America x2 EUR") %>%
  add_trace(x = ~date, y = ~log(europe_eu_sim), line = list(width = 1), name = "MSCI Europe x2 EUR") %>%
  add_trace(x = ~date, y = ~log(pacific_eu_sim), line = list(width = 1), name = "MSCI Pacific x2 EUR") %>%
  add_trace(x = ~date, y = ~log(emerging_eu_sim), line = list(width = 1), name = "MSCI Emerging x2 EUR") %>%
  layout(
    showlegend = TRUE, legend = list(orientation = 'h'),
    xaxis = list(title = "Time"),
    yaxis = list(title = "Log. Market Value"),
    title = "Statistical Simulation of Leveraged Exchange Trade Funds",
    margin = list(t = 50))
########################################################################################################################
# Bereinigung des Workspace
########################################################################################################################
rm(list = ls())
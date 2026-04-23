########################################################################################################################
# Vorbereitung des Systems
########################################################################################################################
packages <- c("tidyverse", "tidyquant", "imputeTS", "modelr", "plotly", "readxl", "mgcv", "httr", "jsonlite")
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

#---> Definition des Analysehorizonts:
start_date <- "1974-12-31"
stopp_date <- "2025-09-01"



#---> Initialisierung Index-Zeitreihen:
msci_data <- list(
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
  #---> 2. Integration der ECB-Wechselkurswerte:
  read.csv("./01 Source Data/02 EuroStat/Eurostat Exchange Rate EUCR.csv") %>%
    filter(Currency == "US dollar") %>%
    mutate(
      date = as.Date(TIME_PERIOD, format="%Y-%m-%d"),
      eucr = 1 / OBS_VALUE) %>%
    filter(date >= start_date & date <= stopp_date) %>%
    select(date, eucr),
  #---> 3. Integration der US-Interbanken-Zinssätze (Effective Federal Funds Rate und Secured Overnight Financing Rate):
  read.csv("https://fred.stlouisfed.org/graph/fredgraph.csv?id=DFF", na.strings = ".") %>%
    rename(date = 1, effr = 2) %>%
    mutate(date = as.Date(date)),
  read.csv("https://fred.stlouisfed.org/graph/fredgraph.csv?id=SOFR", na.strings = ".") %>%
    rename(date = 1, sofr = 2) %>%
    mutate(date = as.Date(date)),
  #---> 4. Integration der EU-Interbanken-Zinssätze (EONIA und ESTER):
  read.csv("./01 Source Data/01 Bundesbank/Overnight Borrowing/Bundesbank ST0101.csv", skip = 8, sep = ";") %>%
    select(date = 1, ftgr = 2) %>%
    mutate(
      date = as.Date(date, format = "%Y-%m-%d"),
      ftgr = as.numeric(gsub(",", ".", na_if(ftgr, ".")))),
  read.csv("https://fred.stlouisfed.org/graph/fredgraph.csv?id=EONIARATE", na.strings = ".") %>%
    rename(date = 1, eonia = 2) %>%
    mutate(date = as.Date(date)),
  read.csv("https://fred.stlouisfed.org/graph/fredgraph.csv?id=ECBESTRVOLWGTTRMDMNRT", na.strings = ".") %>%
    rename(date = 1, ester = 2) %>%
    mutate(date = as.Date(date)),
  #---> 5. Integration der MSCI-Indexdaten für die USD-Indexvarianten Price, Gross Total und Net Total Return:
  #--------> 5a. MSCI World:
  tq_get("^990100-USD-STRD", from = start_date) %>%
    select(date, us_world_price_yahoo = adjusted),
  scraping_index(code = "990100", type = "STRD", currency = "USD", freq = "DAILY",
                 start = gsub("-", "", start_date), stopp = gsub("-", "", stopp_date)) %>%
    mutate(
      date = as.Date(as.character(calc_date), format = "%Y%m%d"),
      us_world_price_msci = level_eod) %>%
    select(date, us_world_price_msci),
  scraping_index(code = "990100", type = "GRTR", currency = "USD", freq = "DAILY",
                 start = gsub("-", "", start_date), stopp = gsub("-", "", stopp_date)) %>%
    mutate(
      date = as.Date(as.character(calc_date), format = "%Y%m%d"),
      us_world_gdtr_l1 = level_eod) %>%
    select(date, us_world_gdtr_l1),
  scraping_index(code = "990100", type = "NETR", currency = "USD", freq = "DAILY",
                 start = gsub("-", "", start_date), stopp = gsub("-", "", stopp_date)) %>%
    mutate(
      date = as.Date(as.character(calc_date), format = "%Y%m%d"),
      us_world_ndtr_l1 = level_eod) %>%
    select(date, us_world_ndtr_l1),
  #--------> 5b. MSCI North America:
  read.csv("./03 Results Data/01 Equity Indicies/Simulation Indices.csv") %>%
    mutate(date = as.Date(date)) %>%
    select(date, us_na_price = na_model),
  scraping_index(code = "990200", type = "GRTR", currency = "USD", freq = "DAILY",
                 start = gsub("-", "", start_date), stopp = gsub("-", "", stopp_date)) %>%
    mutate(
      date = as.Date(as.character(calc_date), format = "%Y%m%d"),
      us_na_gdtr_l1 = level_eod) %>%
    select(date, us_na_gdtr_l1),
  scraping_index(code = "990200", type = "NETR", currency = "USD", freq = "DAILY",
                 start = gsub("-", "", start_date), stopp = gsub("-", "", stopp_date)) %>%
    mutate(
      date = as.Date(as.character(calc_date), format = "%Y%m%d"),
      us_na_ndtr_l1 = level_eod) %>%
    select(date, us_na_ndtr_l1),
  #--------> 5c. MSCI Europe:
  read.csv("./03 Results Data/01 Equity Indicies/Simulation Indices.csv") %>%
    mutate(date = as.Date(date)) %>%
    select(date, us_eu_price = eu_model),
  scraping_index(code = "990500", type = "GRTR", currency = "USD", freq = "DAILY",
                 start = gsub("-", "", start_date), stopp = gsub("-", "", stopp_date)) %>%
    mutate(
      date = as.Date(as.character(calc_date), format = "%Y%m%d"),
      us_eu_gdtr_l1 = level_eod) %>%
    select(date, us_eu_gdtr_l1),
  scraping_index(code = "990500", type = "NETR", currency = "USD", freq = "DAILY",
                 start = gsub("-", "", start_date), stopp = gsub("-", "", stopp_date)) %>%
    mutate(
      date = as.Date(as.character(calc_date), format = "%Y%m%d"),
      us_eu_ndtr_l1 = level_eod) %>%
    select(date, us_eu_ndtr_l1),
  #--------> 5d. MSCI Pacific:
  read.csv("./03 Results Data/01 Equity Indicies/Simulation Indices.csv") %>%
    mutate(date = as.Date(date)) %>%
    select(date, us_pc_price = pc_model),
  scraping_index(code = "990800", type = "GRTR", currency = "USD", freq = "DAILY",
                 start = gsub("-", "", start_date), stopp = gsub("-", "", stopp_date)) %>%
    mutate(
      date = as.Date(as.character(calc_date), format = "%Y%m%d"),
      us_pc_gdtr_l1 = level_eod) %>%
    select(date, us_pc_gdtr_l1),
  scraping_index(code = "990800", type = "NETR", currency = "USD", freq = "DAILY",
                 start = gsub("-", "", start_date), stopp = gsub("-", "", stopp_date)) %>%
    mutate(
      date = as.Date(as.character(calc_date), format = "%Y%m%d"),
      us_pc_ndtr_l1 = level_eod) %>%
    select(date, us_pc_ndtr_l1),
  #--------> 5e. MSCI Emerging:
  read.csv("./03 Results Data/01 Equity Indicies/Simulation Indices.csv") %>%
    mutate(date = as.Date(date)) %>%
    select(date, us_em_price = em_model),
  scraping_index(code = "891800", type = "GRTR", currency = "USD", freq = "DAILY",
                 start = gsub("-", "", start_date), stopp = gsub("-", "", stopp_date)) %>%
    mutate(
      date = as.Date(as.character(calc_date), format = "%Y%m%d"),
      us_em_gdtr_l1 = level_eod) %>%
    select(date, us_em_gdtr_l1),
  scraping_index(code = "891800", type = "NETR", currency = "USD", freq = "DAILY",
                 start = gsub("-", "", start_date), stopp = gsub("-", "", stopp_date)) %>%
    mutate(
      date = as.Date(as.character(calc_date), format = "%Y%m%d"),
      us_em_ndtr_l1 = level_eod) %>%
    select(date, us_em_ndtr_l1),
  #---> 6. Integration der MSCI-Indexdaten für die EUR-Indexvarianten Price, Gross Total und Net Total Return:
  #--------> 6a. MSCI World:
  scraping_index(code = "990100", type = "STRD", currency = "EUR", freq = "DAILY",
                 start = gsub("-", "", start_date), stopp = gsub("-", "", stopp_date)) %>%
    mutate(
      date = as.Date(as.character(calc_date), format = "%Y%m%d"),
      eu_world_price = level_eod) %>%
    select(date, eu_world_price),
  scraping_index(code = "990100", type = "GRTR", currency = "EUR", freq = "DAILY",
                 start = gsub("-", "", start_date), stopp = gsub("-", "", stopp_date)) %>%
    mutate(
      date = as.Date(as.character(calc_date), format = "%Y%m%d"),
      eu_world_gdtr_l1 = level_eod) %>%
    select(date, eu_world_gdtr_l1),
  scraping_index(code = "990100", type = "NETR", currency = "EUR", freq = "DAILY",
                 start = gsub("-", "", start_date), stopp = gsub("-", "", stopp_date)) %>%
    mutate(
      date = as.Date(as.character(calc_date), format = "%Y%m%d"),
      eu_world_ndtr_l1 = level_eod) %>%
    select(date, eu_world_ndtr_l1),
  #--------> 6b. MSCI North America:
  scraping_index(code = "990200", type = "STRD", currency = "EUR", freq = "DAILY",
                 start = gsub("-", "", start_date), stopp = gsub("-", "", stopp_date)) %>%
    mutate(
      date = as.Date(as.character(calc_date), format = "%Y%m%d"),
      eu_na_price = level_eod) %>%
    select(date, eu_na_price),
  scraping_index(code = "990200", type = "GRTR", currency = "EUR", freq = "DAILY",
                 start = gsub("-", "", start_date), stopp = gsub("-", "", stopp_date)) %>%
    mutate(
      date = as.Date(as.character(calc_date), format = "%Y%m%d"),
      eu_na_gdtr_l1 = level_eod) %>%
    select(date, eu_na_gdtr_l1),
  scraping_index(code = "990200", type = "NETR", currency = "EUR", freq = "DAILY",
                 start = gsub("-", "", start_date), stopp = gsub("-", "", stopp_date)) %>%
    mutate(
      date = as.Date(as.character(calc_date), format = "%Y%m%d"),
      eu_na_ndtr_l1 = level_eod) %>%
    select(date, eu_na_ndtr_l1),
  #--------> 6c. MSCI Europe:
  scraping_index(code = "990500", type = "STRD", currency = "EUR", freq = "DAILY",
                 start = gsub("-", "", start_date), stopp = gsub("-", "", stopp_date)) %>%
    mutate(
      date = as.Date(as.character(calc_date), format = "%Y%m%d"),
      eu_eu_price = level_eod) %>%
    select(date, eu_eu_price),
  scraping_index(code = "990500", type = "GRTR", currency = "EUR", freq = "DAILY",
                 start = gsub("-", "", start_date), stopp = gsub("-", "", stopp_date)) %>%
    mutate(
      date = as.Date(as.character(calc_date), format = "%Y%m%d"),
      eu_eu_gdtr_l1 = level_eod) %>%
    select(date, eu_eu_gdtr_l1),
  scraping_index(code = "990500", type = "NETR", currency = "EUR", freq = "DAILY",
                 start = gsub("-", "", start_date), stopp = gsub("-", "", stopp_date)) %>%
    mutate(
      date = as.Date(as.character(calc_date), format = "%Y%m%d"),
      eu_eu_ndtr_l1 = level_eod) %>%
    select(date, eu_eu_ndtr_l1),
  #--------> 6d. MSCI Pacific:
  scraping_index(code = "990800", type = "STRD", currency = "EUR", freq = "DAILY",
                 start = gsub("-", "", start_date), stopp = gsub("-", "", stopp_date)) %>%
    mutate(
      date = as.Date(as.character(calc_date), format = "%Y%m%d"),
      eu_pc_price = level_eod) %>%
    select(date, eu_pc_price),
  scraping_index(code = "990800", type = "GRTR", currency = "EUR", freq = "DAILY",
                 start = gsub("-", "", start_date), stopp = gsub("-", "", stopp_date)) %>%
    mutate(
      date = as.Date(as.character(calc_date), format = "%Y%m%d"),
      eu_pc_gdtr_l1 = level_eod) %>%
    select(date, eu_pc_gdtr_l1),
  scraping_index(code = "990800", type = "NETR", currency = "EUR", freq = "DAILY",
                 start = gsub("-", "", start_date), stopp = gsub("-", "", stopp_date)) %>%
    mutate(
      date = as.Date(as.character(calc_date), format = "%Y%m%d"),
      eu_pc_ndtr_l1 = level_eod) %>%
    select(date, eu_pc_ndtr_l1),
  #--------> 6e. MSCI Emerging:
  scraping_index(code = "891800", type = "STRD", currency = "EUR", freq = "DAILY",
                 start = gsub("-", "", start_date), stopp = gsub("-", "", stopp_date)) %>%
    mutate(
      date = as.Date(as.character(calc_date), format = "%Y%m%d"),
      eu_em_price = level_eod) %>%
    select(date, eu_em_price),
  scraping_index(code = "891800", type = "GRTR", currency = "EUR", freq = "DAILY",
                 start = gsub("-", "", start_date), stopp = gsub("-", "", stopp_date)) %>%
    mutate(
      date = as.Date(as.character(calc_date), format = "%Y%m%d"),
      eu_em_gdtr_l1 = level_eod) %>%
    select(date, eu_em_gdtr_l1),
  scraping_index(code = "891800", type = "NETR", currency = "EUR", freq = "DAILY",
                 start = gsub("-", "", start_date), stopp = gsub("-", "", stopp_date)) %>%
    mutate(
      date = as.Date(as.character(calc_date), format = "%Y%m%d"),
      eu_em_ndtr_l1 = level_eod) %>%
    select(date, eu_em_ndtr_l1),
  #---> 7. Integration der Leverage MSCI-Indexdaten für die USD- und EUR-Indexvarianten Gross Total Return:
  #--------> 7a. MSCI World:
  read.table("https://app2.msci.com/eqb/short/performance/90479.49.all.xls", sep = ",", skip = 4) %>%
    filter(grepl("\t", V1)) %>%
    separate_wider_delim(V1, delim = "\t", names = c("date", "us_world_gdtr_l2"), too_few = "align_start") %>%
    mutate(
      date = as.Date(date, format = "%m/%d/%Y"),
      us_world_gdtr_l2 = as.numeric(us_world_gdtr_l2)),
  #--------> 7b. MSCI Europe:
  read.table("https://www.msci.com/eqb/short/performance/90485.49.all.xls", sep = ",", skip = 4) %>%
    filter(grepl("\t", V1)) %>%
    separate_wider_delim(V1, delim = "\t", names = c("date", "eu_eu_gdtr_l2"), too_few = "align_start") %>%
    mutate(
      date = as.Date(date, format = "%m/%d/%Y"),
      eu_eu_gdtr_l2 = as.numeric(eu_eu_gdtr_l2)),
  #--------> 7c. MSCI Emerging:
  read.table("https://app2.msci.com/eqb/short/performance/90479.49.all.xls", sep = ",", skip = 4) %>%
    filter(grepl("\t", V1)) %>%
    separate_wider_delim(V1, delim = "\t", names = c("date", "us_em_gdtr_l2"), too_few = "align_start") %>%
    mutate(
      date = as.Date(date, format = "%m/%d/%Y"),
      us_em_gdtr_l2 = as.numeric(us_em_gdtr_l2))) %>%
  Reduce(function(x, y) left_join(x, y, by = "date"), .) %>%
  filter(date <= stopp_date) %>%
  #---> 8. Stineman-Spline-Interpolierung fehlender Werte und Berechnung der Daily Returns:
  mutate(
    #--------> 8a. MSCI World USD-Indizes:
    us_world_price = ifelse(date >= "1996-12-31", us_world_price_msci, us_world_price_yahoo),
    us_world_price = round(na_interpolation(us_world_price, "stine"), digits = 5),
    us_world_price_return = us_world_price/lag(us_world_price),
    us_world_gdtr_l1 = ifelse(date >= "1998-12-31", round(na_interpolation(us_world_gdtr_l1, "stine"), digits = 5), NA),
    us_world_gdtr_l1_return = us_world_gdtr_l1/lag(us_world_gdtr_l1),
    us_world_ndtr_l1 = ifelse(date >= "1998-12-31", round(na_interpolation(us_world_ndtr_l1, "stine"), digits = 5), NA),
    us_world_ndtr_l1_return = us_world_ndtr_l1/lag(us_world_ndtr_l1),
    us_world_gdtr_l2 = ifelse(date >= "2000-12-29", round(na_interpolation(us_world_gdtr_l2, "stine"), digits = 5), NA),
    us_world_gdtr_l2_return = us_world_gdtr_l2/lag(us_world_gdtr_l2),
    #--------> 8b. MSCI North America USD-Indizes:
    us_na_price = round(us_na_price, digits = 5),
    us_na_price_return = us_na_price/lag(us_na_price),
    us_na_gdtr_l1 = ifelse(date >= "1999-01-01", round(na_interpolation(us_na_gdtr_l1, "stine"), digits = 5), NA),
    us_na_gdtr_l1_return = us_na_gdtr_l1/lag(us_na_gdtr_l1),
    us_na_ndtr_l1 = ifelse(date >= "1999-01-01", round(na_interpolation(us_na_ndtr_l1, "stine"), digits = 5), NA),
    us_na_ndtr_l1_return = us_na_ndtr_l1/lag(us_na_ndtr_l1),
    #--------> 8c. MSCI Europe USD-Indizes:
    us_eu_price = round(us_eu_price, digits = 5),
    us_eu_price_return = us_eu_price/lag(us_eu_price),
    us_eu_gdtr_l1 = ifelse(date >= "1999-01-01", round(na_interpolation(us_eu_gdtr_l1, "stine"), digits = 5), NA),
    us_eu_gdtr_l1_return = us_eu_gdtr_l1/lag(us_eu_gdtr_l1),
    us_eu_ndtr_l1 = ifelse(date >= "1999-01-01", round(na_interpolation(us_eu_ndtr_l1, "stine"), digits = 5), NA),
    us_eu_ndtr_l1_return = us_eu_ndtr_l1/lag(us_eu_ndtr_l1),
    #--------> 8d. MSCI Pacific USD-Indizes:
    us_pc_price = round(us_pc_price, digits = 5),
    us_pc_price_return = us_pc_price/lag(us_pc_price),
    us_pc_gdtr_l1 = ifelse(date >= "1999-01-01", round(na_interpolation(us_pc_gdtr_l1, "stine"), digits = 5), NA),
    us_pc_gdtr_l1_return = us_pc_gdtr_l1/lag(us_pc_gdtr_l1),
    us_pc_ndtr_l1 = ifelse(date >= "1999-01-01", round(na_interpolation(us_pc_ndtr_l1, "stine"), digits = 5), NA),
    us_pc_ndtr_l1_return = us_pc_ndtr_l1/lag(us_pc_ndtr_l1),
    #--------> 8e. MSCI Emerging USD-Indizes:
    us_em_price = round(na_interpolation(us_em_price, "stine"), digits = 5),
    us_em_price_return = us_em_price/lag(us_em_price),
    us_em_gdtr_l1 = ifelse(date >= "1999-01-01", round(na_interpolation(us_em_gdtr_l1, "stine"), digits = 5), NA),
    us_em_gdtr_l1_return = us_em_gdtr_l1/lag(us_em_gdtr_l1),
    us_em_ndtr_l1 = ifelse(date >= "1999-01-01", round(na_interpolation(us_em_ndtr_l1, "stine"), digits = 5), NA),
    us_em_ndtr_l1_return = us_em_ndtr_l1/lag(us_em_ndtr_l1),
    us_em_gdtr_l2 = ifelse(date >= "2000-12-29", round(na_interpolation(us_em_gdtr_l2, "stine"), digits = 5), NA),
    us_em_gdtr_l2_return = us_em_gdtr_l2/lag(us_em_gdtr_l2),
    #--------> 8f. MSCI World EUR-Indizes:
    eu_world_price = ifelse(date >= "1999-01-01", round(na_interpolation(eu_world_price, "stine"), digits = 5), NA),
    eu_world_price_return = eu_world_price/lag(eu_world_price),
    eu_world_gdtr_l1 = ifelse(date >= "2000-12-29", round(na_interpolation(eu_world_gdtr_l1, "stine"), digits = 5), NA),
    eu_world_gdtr_l1_return = eu_world_gdtr_l1/lag(eu_world_gdtr_l1),
    eu_world_ndtr_l1 = ifelse(date >= "2000-12-29", round(na_interpolation(eu_world_ndtr_l1, "stine"), digits = 5), NA),
    eu_world_ndtr_l1_return = eu_world_ndtr_l1/lag(eu_world_ndtr_l1),
    #--------> 8g. MSCI North America EUR-Indizes:
    eu_na_price =  ifelse(date >= "1999-01-01", round(na_interpolation(eu_na_price, "stine"), digits = 5), NA),
    eu_na_price_return = eu_na_price/lag(eu_na_price),
    eu_na_gdtr_l1 = ifelse(date >= "2001-01-01", round(na_interpolation(eu_na_gdtr_l1, "stine"), digits = 5), NA),
    eu_na_gdtr_l1_return = eu_na_gdtr_l1/lag(eu_na_gdtr_l1),
    eu_na_ndtr_l1 = ifelse(date >= "2001-01-01", round(na_interpolation(eu_na_ndtr_l1, "stine"), digits = 5), NA),
    eu_na_ndtr_l1_return = eu_na_ndtr_l1/lag(eu_na_ndtr_l1),
    #--------> 8h. MSCI Europe EUR-Indizes:
    eu_eu_price =  ifelse(date >= "1999-01-01", round(na_interpolation(eu_eu_price, "stine"), digits = 5), NA),
    eu_eu_price_return = eu_eu_price/lag(eu_eu_price),
    eu_eu_gdtr_l1 = ifelse(date >= "2001-01-01", round(na_interpolation(eu_eu_gdtr_l1, "stine"), digits = 5), NA),
    eu_eu_gdtr_l1_return = eu_eu_gdtr_l1/lag(eu_eu_gdtr_l1),
    eu_eu_ndtr_l1 = ifelse(date >= "2001-01-01", round(na_interpolation(eu_eu_ndtr_l1, "stine"), digits = 5), NA),
    eu_eu_ndtr_l1_return = eu_eu_ndtr_l1/lag(eu_eu_ndtr_l1),
    eu_eu_gdtr_l2 = ifelse(date >= "2000-12-29", round(na_interpolation(eu_eu_gdtr_l2, "stine"), digits = 5), NA),
    eu_eu_gdtr_l2_return = eu_eu_gdtr_l2/lag(eu_eu_gdtr_l2),
    #--------> 8i. MSCI Pacific EUR-Indizes:
    eu_pc_price =  ifelse(date >= "1999-01-01", round(na_interpolation(eu_pc_price, "stine"), digits = 5), NA),
    eu_pc_price_return = eu_pc_price/lag(eu_pc_price),
    eu_pc_gdtr_l1 = ifelse(date >= "2001-01-01", round(na_interpolation(eu_pc_gdtr_l1, "stine"), digits = 5), NA),
    eu_pc_gdtr_l1_return = eu_pc_gdtr_l1/lag(eu_pc_gdtr_l1),
    eu_pc_ndtr_l1 = ifelse(date >= "2001-01-01", round(na_interpolation(eu_pc_ndtr_l1, "stine"), digits = 5), NA),
    eu_pc_ndtr_l1_return = eu_pc_ndtr_l1/lag(eu_pc_ndtr_l1),
    #--------> 8j. MSCI Emerging EUR-Indizes:
    eu_em_price = ifelse(date >= "1999-01-01", round(na_interpolation(eu_em_price, "stine"), digits = 5), NA),
    eu_em_price_return = eu_em_price/lag(eu_em_price),
    eu_em_gdtr_l1 = ifelse(date >= "2001-01-01", round(na_interpolation(eu_em_gdtr_l1, "stine"), digits = 5), NA),
    eu_em_gdtr_l1_return = eu_em_gdtr_l1/lag(eu_em_gdtr_l1),
    eu_em_ndtr_l1 = ifelse(date >= "2001-01-01", round(na_interpolation(eu_em_ndtr_l1, "stine"), digits = 5), NA),
    eu_em_ndtr_l1_return = eu_em_ndtr_l1/lag(eu_em_ndtr_l1),
    #--------> 8k. Zins- und Wechselkurse:
    us_rate = na_interpolation(ifelse(date <= "2021-07-31", effr, sofr), "stine"),
    us_rate = round(us_rate, digits = 3),
    eu_rate = na_interpolation(ifelse(date <= "2021-07-31", ifelse(date <= "1999-01-01", ftgr, eonia), ester), "stine"),
    eu_rate = round(eu_rate, digits = 3),
    eucr = round(na_interpolation(eucr, "stine"), digits = 5)) %>%
  filter(date >= "1975-01-01")



#---> Vervollständigung der Index-Zeitreihen:
msci_model <- msci_data %>%
  #--------> 1a. MSCI World USD Gross Total Return:
  add_predictions(gam(us_world_gdtr_l1_return ~ s(us_world_price_return, bs = "cr"), data = .), var = "us_world_gdtr_l1_model") %>%
  mutate(
    us_world_gdtr_l1_return = ifelse(date < "1998-12-31" | is.na(us_world_gdtr_l1_return), us_world_gdtr_l1_model, us_world_gdtr_l1_return),
    us_world_gdtr_l1 = ifelse(date < "1998-12-31",
                              rev(Reduce(function(values, rates){values/rates},
                                         rev(us_world_gdtr_l1_return), init = last(us_world_gdtr_l1), accumulate = TRUE)[-nrow(.)]),
                              us_world_gdtr_l1),
    us_world_gdtr_l1 = ifelse(row_number() == 1, round(lead(us_world_gdtr_l1)/lead(us_world_gdtr_l1_return), digits = 5), round(us_world_gdtr_l1, digits = 5))) %>%
  #--------> 1b. MSCI World USD Net Total Return:
  add_predictions(gam(us_world_ndtr_l1_return ~ s(us_world_price_return, bs = "cr"), data = .), var = "us_world_ndtr_l1_model") %>%
  mutate(
    us_world_ndtr_l1_return = ifelse(date < "1998-12-31" | is.na(us_world_ndtr_l1_return), us_world_ndtr_l1_model, us_world_ndtr_l1_return),
    us_world_ndtr_l1 = ifelse(date < "1998-12-31",
                              rev(Reduce(function(values, rates){values/rates},
                                         rev(us_world_ndtr_l1_model), init = last(us_world_ndtr_l1), accumulate = TRUE)[-nrow(.)]),
                              us_world_ndtr_l1),
    us_world_ndtr_l1 = ifelse(row_number() == 1, round(lead(us_world_ndtr_l1)/lead(us_world_ndtr_l1_return), digits = 5), round(us_world_ndtr_l1, digits = 5))) %>%
  #--------> 1c. MSCI World EUR Price Return:
  add_predictions(gam(eu_world_price/us_world_price ~ s(eucr, bs = "cr"), data = .), var = "scale_factor") %>%
  mutate(
    eu_world_price = ifelse(date <= "1999-01-01", scale_factor * us_world_price, eu_world_price),
    eu_world_price_return = eu_world_price/lag(eu_world_price),
    eu_world_price = ifelse(row_number() == 1, round(lead(eu_world_price)/lead(eu_world_price_return), digits = 5), round(eu_world_price, digits = 5))) %>%
  #--------> 1d. MSCI World EUR Gross Total Return:
  add_predictions(gam(eu_world_gdtr_l1_return ~ s(eu_world_price_return, bs = "cr"), data = .), var = "eu_world_gdtr_l1_model") %>%
  mutate(
    eu_world_gdtr_l1_return = ifelse(date < "2000-12-29" | is.na(eu_world_gdtr_l1_return), eu_world_gdtr_l1_model, eu_world_gdtr_l1_return),
    eu_world_gdtr_l1 = ifelse(date < "2000-12-29",
                              rev(Reduce(function(values, rates){values/rates},
                                         rev(eu_world_gdtr_l1_return), init = last(eu_world_gdtr_l1), accumulate = TRUE)[-nrow(.)]),
                              eu_world_gdtr_l1),
    eu_world_gdtr_l1 = ifelse(row_number() == 1, round(lead(eu_world_gdtr_l1)/lead(eu_world_gdtr_l1_return), digits = 5), round(eu_world_gdtr_l1, digits = 5))) %>%
  #--------> 1e. MSCI World EUR Net Total Return:
  add_predictions(gam(eu_world_ndtr_l1_return ~ s(eu_world_price_return, bs = "cr"), data = .), var = "eu_world_ndtr_l1_model") %>%
  mutate(
    eu_world_ndtr_l1_return = ifelse(date < "2000-12-29" | is.na(eu_world_ndtr_l1_return), eu_world_ndtr_l1_model, eu_world_ndtr_l1_return),
    eu_world_ndtr_l1 = ifelse(date < "2000-12-29",
                              rev(Reduce(function(values, rates){values/rates},
                                         rev(eu_world_ndtr_l1_model), init = last(eu_world_ndtr_l1), accumulate = TRUE)[-nrow(.)]),
                              eu_world_ndtr_l1),
    eu_world_ndtr_l1 = ifelse(row_number() == 1, round(lead(eu_world_ndtr_l1)/lead(eu_world_ndtr_l1_return), digits = 5), round(eu_world_ndtr_l1, digits = 5))) %>%
  #--------> 2a. MSCI North America USD Gross Total Return:
  add_predictions(gam(us_na_gdtr_l1_return ~ s(us_na_price_return, bs = "cr"), data = .), var = "us_na_gdtr_l1_model") %>%
  mutate(
    us_na_gdtr_l1_return = ifelse(date < "1999-01-01" | is.na(us_na_gdtr_l1_return), us_na_gdtr_l1_model, us_na_gdtr_l1_return),
    us_na_gdtr_l1 = ifelse(date < "1999-01-01",
                           rev(Reduce(function(values, rates){values/rates}, rev(us_na_gdtr_l1_return), init = last(us_na_gdtr_l1), accumulate = TRUE)[-nrow(.)]),
                           us_na_gdtr_l1),
    us_na_gdtr_l1 = ifelse(row_number() == 1, round(lead(us_na_gdtr_l1)/lead(us_na_gdtr_l1_return), digits = 5), round(us_na_gdtr_l1, digits = 5))) %>%
  #--------> 2b. MSCI North America USD Net Total Return:
  add_predictions(gam(us_na_ndtr_l1_return ~ s(us_na_price_return, bs = "cr"), data = .), var = "us_na_ndtr_l1_model") %>%
  mutate(
    us_na_ndtr_l1_return = ifelse(date < "1999-01-01" | is.na(us_na_ndtr_l1_return), us_na_ndtr_l1_model, us_na_ndtr_l1_return),
    us_na_ndtr_l1 = ifelse(date < "1999-01-01",
                           rev(Reduce(function(values, rates){values/rates}, rev(us_na_ndtr_l1_return), init = last(us_na_ndtr_l1), accumulate = TRUE)[-nrow(.)]),
                           us_na_ndtr_l1),
    us_na_ndtr_l1 = ifelse(row_number() == 1, round(lead(us_na_ndtr_l1)/lead(us_na_ndtr_l1_return), digits = 5), round(us_na_ndtr_l1, digits = 5))) %>%
  #--------> 2c. MSCI North America EUR Price Return:
  add_predictions(gam(eu_na_price/us_na_price ~ s(eucr, bs = "cr"), data = .), var = "scale_factor") %>%
  mutate(
    eu_na_price = ifelse(date <= "1999-01-01", scale_factor * us_na_price, eu_na_price),
    eu_na_price_return = eu_na_price/lag(eu_na_price),
    eu_na_price = ifelse(row_number() == 1, round(lead(eu_na_price)/lead(eu_na_price_return), digits = 5), round(eu_na_price, digits = 5))) %>%
  #--------> 2d. MSCI North America EUR Gross Total Return:
  add_predictions(gam(eu_na_gdtr_l1_return ~ s(eu_na_price_return, bs = "cr"), data = .), var = "eu_na_gdtr_l1_model") %>%
  mutate(
    eu_na_gdtr_l1_return = ifelse(date < "2001-01-01" | is.na(eu_na_gdtr_l1_return), eu_na_gdtr_l1_model, eu_na_gdtr_l1_return),
    eu_na_gdtr_l1 = ifelse(date < "2001-01-01",
                           rev(Reduce(function(values, rates){values/rates}, rev(eu_na_gdtr_l1_return), init = last(eu_na_gdtr_l1), accumulate = TRUE)[-nrow(.)]),
                           eu_na_gdtr_l1),
    eu_na_gdtr_l1 = ifelse(row_number() == 1, round(lead(eu_na_gdtr_l1)/lead(eu_na_gdtr_l1_return), digits = 5), round(eu_na_gdtr_l1, digits = 5))) %>%
  #--------> 2e. MSCI North America EUR Net Total Return:
  add_predictions(gam(eu_na_ndtr_l1_return ~ s(eu_na_price_return, bs = "cr"), data = .), var = "eu_na_ndtr_l1_model") %>%
  mutate(
    eu_na_ndtr_l1_return = ifelse(date < "2001-01-01" | is.na(eu_na_ndtr_l1_return), eu_na_ndtr_l1_model, eu_na_ndtr_l1_return),
    eu_na_ndtr_l1 = ifelse(date < "2001-01-01",
                           rev(Reduce(function(values, rates){values/rates}, rev(eu_na_ndtr_l1_return), init = last(eu_na_ndtr_l1), accumulate = TRUE)[-nrow(.)]),
                           eu_na_ndtr_l1),
    eu_na_ndtr_l1 = ifelse(row_number() == 1, round(lead(eu_na_ndtr_l1)/lead(eu_na_ndtr_l1_return), digits = 5), round(eu_na_ndtr_l1, digits = 5))) %>%
  #--------> 3a. MSCI Europe USD Gross Total Return:
  add_predictions(gam(us_eu_gdtr_l1_return ~ s(us_eu_price_return, bs = "cr"), data = .), var = "us_eu_gdtr_l1_model") %>%
  mutate(
    us_eu_gdtr_l1_return = ifelse(date < "1999-01-01" | is.na(us_eu_gdtr_l1_return), us_eu_gdtr_l1_model, us_eu_gdtr_l1_return),
    us_eu_gdtr_l1 = ifelse(date < "1999-01-01",
                           rev(Reduce(function(values, rates){values/rates}, rev(us_eu_gdtr_l1_return), init = last(us_eu_gdtr_l1), accumulate = TRUE)[-nrow(.)]),
                           us_eu_gdtr_l1),
    us_eu_gdtr_l1 = ifelse(row_number() == 1, round(lead(us_eu_gdtr_l1)/lead(us_eu_gdtr_l1_return), digits = 5), round(us_eu_gdtr_l1, digits = 5))) %>%
  #--------> 3b. MSCI Europe USD Net Total Return:
  add_predictions(gam(us_eu_ndtr_l1_return ~ s(us_eu_price_return, bs = "cr"), data = .), var = "us_eu_ndtr_l1_model") %>%
  mutate(
    us_eu_ndtr_l1_return = ifelse(date < "1999-01-01" | is.na(us_eu_ndtr_l1_return), us_eu_ndtr_l1_model, us_eu_ndtr_l1_return),
    us_eu_ndtr_l1 = ifelse(date < "1999-01-01",
                           rev(Reduce(function(values, rates){values/rates}, rev(us_eu_ndtr_l1_return), init = last(us_eu_ndtr_l1), accumulate = TRUE)[-nrow(.)]),
                           us_eu_ndtr_l1),
    us_eu_ndtr_l1 = ifelse(row_number() == 1, round(lead(us_eu_ndtr_l1)/lead(us_eu_ndtr_l1_return), digits = 5), round(us_eu_ndtr_l1, digits = 5))) %>%
  #--------> 3c. MSCI Europe EUR Price Return:
  add_predictions(gam(eu_eu_price/us_eu_price ~ s(eucr, bs = "cr"), data = .), var = "scale_factor") %>%
  mutate(
    eu_eu_price = ifelse(date <= "1999-01-01", scale_factor * us_eu_price, eu_eu_price),
    eu_eu_price_return = eu_eu_price/lag(eu_eu_price),
    eu_eu_price = ifelse(row_number() == 1, round(lead(eu_eu_price)/lead(eu_eu_price_return), digits = 5), round(eu_eu_price, digits = 5))) %>%
  #--------> 3d. MSCI Europe EUR Gross Total Return:
  add_predictions(gam(eu_eu_gdtr_l1_return ~ s(eu_eu_price_return, bs = "cr"), data = .), var = "eu_eu_gdtr_l1_model") %>%
  mutate(
    eu_eu_gdtr_l1_return = ifelse(date < "2001-01-01" | is.na(eu_eu_gdtr_l1_return), eu_eu_gdtr_l1_model, eu_eu_gdtr_l1_return),
    eu_eu_gdtr_l1 = ifelse(date < "2001-01-01",
                           rev(Reduce(function(values, rates){values/rates}, rev(eu_eu_gdtr_l1_return), init = last(eu_eu_gdtr_l1), accumulate = TRUE)[-nrow(.)]),
                           eu_eu_gdtr_l1),
    eu_eu_gdtr_l1 = ifelse(row_number() == 1, round(lead(eu_eu_gdtr_l1)/lead(eu_eu_gdtr_l1_return), digits = 5), round(eu_eu_gdtr_l1, digits = 5))) %>%
  #--------> 3e. MSCI Europe EUR Net Total Return:
  add_predictions(gam(eu_eu_ndtr_l1_return ~ s(eu_eu_price_return, bs = "cr"), data = .), var = "eu_eu_ndtr_l1_model") %>%
  mutate(
    eu_eu_ndtr_l1_return = ifelse(date < "2001-01-01" | is.na(eu_eu_ndtr_l1_return), eu_eu_ndtr_l1_model, eu_eu_ndtr_l1_return),
    eu_eu_ndtr_l1 = ifelse(date < "2001-01-01",
                           rev(Reduce(function(values, rates){values/rates}, rev(eu_eu_ndtr_l1_return), init = last(eu_eu_ndtr_l1), accumulate = TRUE)[-nrow(.)]),
                           eu_eu_ndtr_l1),
    eu_eu_ndtr_l1 = ifelse(row_number() == 1, round(lead(eu_eu_ndtr_l1)/lead(eu_eu_ndtr_l1_return), digits = 5), round(eu_eu_ndtr_l1, digits = 5))) %>%
  #--------> 4a. MSCI Pacific USD Gross Total Return:
  add_predictions(gam(us_pc_gdtr_l1_return ~ s(us_pc_price_return, bs = "cr"), data = .), var = "us_pc_gdtr_l1_model") %>%
  mutate(
    us_pc_gdtr_l1_return = ifelse(date < "1999-01-01" | is.na(us_pc_gdtr_l1_return), us_pc_gdtr_l1_model, us_pc_gdtr_l1_return),
    us_pc_gdtr_l1 = ifelse(date < "1999-01-01",
                           rev(Reduce(function(values, rates){values/rates}, rev(us_pc_gdtr_l1_return), init = last(us_pc_gdtr_l1), accumulate = TRUE)[-nrow(.)]),
                           us_pc_gdtr_l1),
    us_pc_gdtr_l1 = ifelse(row_number() == 1, round(lead(us_pc_gdtr_l1)/lead(us_pc_gdtr_l1_return), digits = 5), round(us_pc_gdtr_l1, digits = 5))) %>%
  #--------> 4b. MSCI Pacific USD Net Total Return:
  add_predictions(gam(us_pc_ndtr_l1_return ~ s(us_pc_price_return, bs = "cr"), data = .), var = "us_pc_ndtr_l1_model") %>%
  mutate(
    us_pc_ndtr_l1_return = ifelse(date < "1999-01-01" | is.na(us_pc_ndtr_l1_return), us_pc_ndtr_l1_model, us_pc_ndtr_l1_return),
    us_pc_ndtr_l1 = ifelse(date < "1999-01-01",
                           rev(Reduce(function(values, rates){values/rates}, rev(us_pc_ndtr_l1_return), init = last(us_pc_ndtr_l1), accumulate = TRUE)[-nrow(.)]),
                           us_pc_ndtr_l1),
    us_pc_ndtr_l1 = ifelse(row_number() == 1, round(lead(us_pc_ndtr_l1)/lead(us_pc_ndtr_l1_return), digits = 5), round(us_pc_ndtr_l1, digits = 5))) %>%
  #--------> 4c. MSCI Pacific EUR Price Return:
  add_predictions(gam(eu_pc_price/us_pc_price ~ s(eucr, bs = "cr"), data = .), var = "scale_factor") %>%
  mutate(
    eu_pc_price = ifelse(date <= "1999-01-01", scale_factor * us_pc_price, eu_pc_price),
    eu_pc_price_return = eu_pc_price/lag(eu_pc_price),
    eu_pc_price = ifelse(row_number() == 1, round(lead(eu_pc_price)/lead(eu_pc_price_return), digits = 5), round(eu_pc_price, digits = 5))) %>%
  #--------> 4d. MSCI Pacific EUR Gross Total Return:
  add_predictions(gam(eu_pc_gdtr_l1_return ~ s(eu_pc_price_return, bs = "cr"), data = .), var = "eu_pc_gdtr_l1_model") %>%
  mutate(
    eu_pc_gdtr_l1_return = ifelse(date < "2001-01-01" | is.na(eu_pc_gdtr_l1_return), eu_pc_gdtr_l1_model, eu_pc_gdtr_l1_return),
    eu_pc_gdtr_l1 = ifelse(date < "2001-01-01",
                           rev(Reduce(function(values, rates){values/rates}, rev(eu_pc_gdtr_l1_return), init = last(eu_pc_gdtr_l1), accumulate = TRUE)[-nrow(.)]),
                           eu_pc_gdtr_l1),
    eu_pc_gdtr_l1 = ifelse(row_number() == 1, round(lead(eu_pc_gdtr_l1)/lead(eu_pc_gdtr_l1_return), digits = 5), round(eu_pc_gdtr_l1, digits = 5))) %>%
  #--------> 4e. MSCI Pacific EUR Net Total Return:
  add_predictions(gam(eu_pc_ndtr_l1_return ~ s(eu_pc_price_return, bs = "cr"), data = .), var = "eu_pc_ndtr_l1_model") %>%
  mutate(
    eu_pc_ndtr_l1_return = ifelse(date < "2001-01-01" | is.na(eu_pc_ndtr_l1_return), eu_pc_ndtr_l1_model, eu_pc_ndtr_l1_return),
    eu_pc_ndtr_l1 = ifelse(date < "2001-01-01",
                           rev(Reduce(function(values, rates){values/rates}, rev(eu_pc_ndtr_l1_return), init = last(eu_pc_ndtr_l1), accumulate = TRUE)[-nrow(.)]),
                           eu_pc_ndtr_l1),
    eu_pc_ndtr_l1 = ifelse(row_number() == 1, round(lead(eu_pc_ndtr_l1)/lead(eu_pc_ndtr_l1_return), digits = 5), round(eu_pc_ndtr_l1, digits = 5))) %>%
  #--------> 5a. MSCI Emerging USD Gross Total Return:
  add_predictions(gam(us_em_gdtr_l1_return ~ s(us_em_price_return, bs = "cr"), data = .), var = "us_em_gdtr_l1_model") %>%
  mutate(
    us_em_gdtr_l1_return = ifelse(date < "1999-01-01" | is.na(us_em_gdtr_l1_return), us_em_gdtr_l1_model, us_em_gdtr_l1_return),
    us_em_gdtr_l1 = ifelse(date < "1999-01-01",
                           rev(Reduce(function(values, rates){values/rates}, rev(us_em_gdtr_l1_return), init = last(us_em_gdtr_l1), accumulate = TRUE)[-nrow(.)]),
                           us_em_gdtr_l1),
    us_em_gdtr_l1 = ifelse(row_number() == 1, round(lead(us_em_gdtr_l1)/lead(us_em_gdtr_l1_return), digits = 5), round(us_em_gdtr_l1, digits = 5))) %>%
  #--------> 5b. MSCI Emerging USD Net Total Return:
  add_predictions(gam(us_em_ndtr_l1_return ~ s(us_em_price_return, bs = "cr"), data = .), var = "us_em_ndtr_l1_model") %>%
  mutate(
    us_em_ndtr_l1_return = ifelse(date < "1999-01-01" | is.na(us_em_ndtr_l1_return), us_em_ndtr_l1_model, us_em_ndtr_l1_return),
    us_em_ndtr_l1 = ifelse(date < "1999-01-01",
                           rev(Reduce(function(values, rates){values/rates}, rev(us_em_ndtr_l1_return), init = last(us_em_ndtr_l1), accumulate = TRUE)[-nrow(.)]),
                           us_em_ndtr_l1),
    us_em_ndtr_l1 = ifelse(row_number() == 1, round(lead(us_em_ndtr_l1)/lead(us_em_ndtr_l1_return), digits = 5), round(us_em_ndtr_l1, digits = 5))) %>%
  #--------> 5c. MSCI Emerging EUR Price Return:
  add_predictions(gam(eu_em_price/us_em_price ~ s(eucr, bs = "cr"), data = .), var = "scale_factor") %>%
  mutate(
    eu_em_price = ifelse(date <= "1999-01-01", scale_factor * us_em_price, eu_em_price),
    eu_em_price_return = eu_em_price/lag(eu_em_price),
    eu_em_price = ifelse(row_number() == 1, round(lead(eu_em_price)/lead(eu_em_price_return), digits = 5), round(eu_em_price, digits = 5))) %>%
  #--------> 5d. MSCI Emerging EUR Gross Total Return:
  add_predictions(gam(eu_em_gdtr_l1_return ~ s(eu_em_price_return, bs = "cr"), data = .), var = "eu_em_gdtr_l1_model") %>%
  mutate(
    eu_em_gdtr_l1_return = ifelse(date < "2001-01-01" | is.na(eu_em_gdtr_l1_return), eu_em_gdtr_l1_model, eu_em_gdtr_l1_return),
    eu_em_gdtr_l1 = ifelse(date < "2001-01-01",
                           rev(Reduce(function(values, rates){values/rates}, rev(eu_em_gdtr_l1_return), init = last(eu_em_gdtr_l1), accumulate = TRUE)[-nrow(.)]),
                           eu_em_gdtr_l1),
    eu_em_gdtr_l1 = ifelse(row_number() == 1, round(lead(eu_em_gdtr_l1)/lead(eu_em_gdtr_l1_return), digits = 5), round(eu_em_gdtr_l1, digits = 5))) %>%
  #--------> 5e. MSCI Emerging EUR Net Total Return:
  add_predictions(gam(eu_em_ndtr_l1_return ~ s(eu_em_price_return, bs = "cr"), data = .), var = "eu_em_ndtr_l1_model") %>%
  mutate(
    eu_em_ndtr_l1_return = ifelse(date < "2001-01-01" | is.na(eu_em_ndtr_l1_return), eu_em_ndtr_l1_model, eu_em_ndtr_l1_return),
    eu_em_ndtr_l1 = ifelse(date < "2001-01-01",
                           rev(Reduce(function(values, rates){values/rates}, rev(eu_em_ndtr_l1_return), init = last(eu_em_ndtr_l1), accumulate = TRUE)[-nrow(.)]),
                           eu_em_ndtr_l1),
    eu_em_ndtr_l1 = ifelse(row_number() == 1, round(lead(eu_em_ndtr_l1)/lead(eu_em_ndtr_l1_return), digits = 5), round(eu_em_ndtr_l1, digits = 5))) %>%
  filter(date >= "1975-01-01") %>%
  select(-c(effr, sofr, ftgr, eonia, ester, scale_factor))



#---> Visualisierung der Index-Zeitreihen:
msci_model %>%
  select(date, us_world_price, us_world_gdtr_l1, us_world_ndtr_l1, eu_world_price, eu_world_gdtr_l1, eu_world_ndtr_l1) %>%
  mutate(across(where(is.numeric), function(x){x/first(x)})) %>%
  plot_ly(type = "scatter", mode = "lines") %>%
  add_trace(x = ~date, y = ~us_world_price, name = "Price Return  (USD)", line = list(width = 1)) %>%
  add_trace(x = ~date, y = ~us_world_gdtr_l1, name = "Gross Total Return (USD)", line = list(width = 1)) %>%
  add_trace(x = ~date, y = ~us_world_ndtr_l1, name = "Net Total Return (USD)", line = list(width = 1)) %>%
  add_trace(x = ~date, y = ~eu_world_price, name = "Price Return (EUR)", line = list(width = 1)) %>%
  add_trace(x = ~date, y = ~eu_world_gdtr_l1, name = "Gross Total Return (EUR)", line = list(width = 1)) %>%
  add_trace(x = ~date, y = ~eu_world_ndtr_l1, name = "Net Total Return (EUR)", line = list(width = 1)) %>%
  layout(
    showlegend = TRUE, legend = list(orientation = 'h'), 
    xaxis = list(title = "Time"),
    yaxis = list(title = "Index Value"),
    title = "MSCI World Indices",
    margin = list(t = 50))

msci_model %>%
  select(date,us_world_price, us_world_gdtr_l1, us_world_ndtr_l1, eu_world_price, eu_world_gdtr_l1, eu_world_ndtr_l1) %>%
  mutate(across(where(is.numeric), function(x){x/first(x)})) %>%
  plot_ly(type = "scatter", mode = "lines") %>%
  add_trace(x = ~date, y = ~log(us_world_price), name = "Price Return  (USD)", line = list(width = 1)) %>%
  add_trace(x = ~date, y = ~log(us_world_gdtr_l1), name = "Gross Total Return (USD)", line = list(width = 1)) %>%
  add_trace(x = ~date, y = ~log(us_world_ndtr_l1), name = "Net Total Return (USD)", line = list(width = 1)) %>%
  add_trace(x = ~date, y = ~log(eu_world_price), name = "Price Return (EUR)", line = list(width = 1)) %>%
  add_trace(x = ~date, y = ~log(eu_world_gdtr_l1), name = "Gross Total Return (EUR)", line = list(width = 1)) %>%
  add_trace(x = ~date, y = ~log(eu_world_ndtr_l1), name = "Net Total Return (EUR)", line = list(width = 1)) %>%
  layout(
    showlegend = TRUE, legend = list(orientation = 'h'), 
    xaxis = list(title = "Time"),
    yaxis = list(title = "Log. Index Value"),
    title = "MSCI World Indices",
    margin = list(t = 50))

msci_model %>%
  select(date, us_na_price, us_na_gdtr_l1, us_na_ndtr_l1, eu_na_price, eu_na_gdtr_l1, eu_na_ndtr_l1) %>%
  mutate(across(where(is.numeric), function(x){x/first(x)})) %>%
  plot_ly(type = "scatter", mode = "lines") %>%
  add_trace(x = ~date, y = ~us_na_price, name = "Price Return  (USD)", line = list(width = 1)) %>%
  add_trace(x = ~date, y = ~us_na_gdtr_l1, name = "Gross Total Return (USD)", line = list(width = 1)) %>%
  add_trace(x = ~date, y = ~us_na_ndtr_l1, name = "Net Total Return (USD)", line = list(width = 1)) %>%
  add_trace(x = ~date, y = ~eu_na_price, name = "Price Return (EUR)", line = list(width = 1)) %>%
  add_trace(x = ~date, y = ~eu_na_gdtr_l1, name = "Gross Total Return (EUR)", line = list(width = 1)) %>%
  add_trace(x = ~date, y = ~eu_na_ndtr_l1, name = "Net Total Return (EUR)", line = list(width = 1)) %>%
  layout(
    showlegend = TRUE, legend = list(orientation = 'h'), 
    xaxis = list(title = "Time"),
    yaxis = list(title = "Index Value"),
    title = "MSCI North America Indices",
    margin = list(t = 50))

msci_model %>%
  select(date, us_na_price, us_na_gdtr_l1, us_na_ndtr_l1, eu_na_price, eu_na_gdtr_l1, eu_na_ndtr_l1) %>%
  mutate(across(where(is.numeric), function(x){x/first(x)})) %>%
  plot_ly(type = "scatter", mode = "lines") %>%
  add_trace(x = ~date, y = ~log(us_na_price), name = "Price Return  (USD)", line = list(width = 1)) %>%
  add_trace(x = ~date, y = ~log(us_na_gdtr_l1), name = "Gross Total Return (USD)", line = list(width = 1)) %>%
  add_trace(x = ~date, y = ~log(us_na_ndtr_l1), name = "Net Total Return (USD)", line = list(width = 1)) %>%
  add_trace(x = ~date, y = ~log(eu_na_price), name = "Price Return (EUR)", line = list(width = 1)) %>%
  add_trace(x = ~date, y = ~log(eu_na_gdtr_l1), name = "Gross Total Return (EUR)", line = list(width = 1)) %>%
  add_trace(x = ~date, y = ~log(eu_na_ndtr_l1), name = "Net Total Return (EUR)", line = list(width = 1)) %>%
  layout(
    showlegend = TRUE, legend = list(orientation = 'h'), 
    xaxis = list(title = "Time"),
    yaxis = list(title = "Log. Index Value"),
    title = "MSCI North America Indices",
    margin = list(t = 50))

msci_model %>%
  select(date, us_eu_price, us_eu_gdtr_l1, us_eu_ndtr_l1, eu_eu_price, eu_eu_gdtr_l1, eu_eu_ndtr_l1) %>%
  mutate(across(where(is.numeric), function(x){x/first(x)})) %>%
  plot_ly(type = "scatter", mode = "lines") %>%
  add_trace(x = ~date, y = ~us_eu_price, name = "Price Return  (USD)", line = list(width = 1)) %>%
  add_trace(x = ~date, y = ~us_eu_gdtr_l1, name = "Gross Total Return (USD)", line = list(width = 1)) %>%
  add_trace(x = ~date, y = ~us_eu_ndtr_l1, name = "Net Total Return (USD)", line = list(width = 1)) %>%
  add_trace(x = ~date, y = ~eu_eu_price, name = "Price Return (EUR)", line = list(width = 1)) %>%
  add_trace(x = ~date, y = ~eu_eu_gdtr_l1, name = "Gross Total Return (EUR)", line = list(width = 1)) %>%
  add_trace(x = ~date, y = ~eu_eu_ndtr_l1, name = "Net Total Return (EUR)", line = list(width = 1)) %>%
  layout(
    showlegend = TRUE, legend = list(orientation = 'h'), 
    xaxis = list(title = "Time"),
    yaxis = list(title = "Index Value"),
    title = "MSCI Europe Indices",
    margin = list(t = 50))

msci_model %>%
  select(date, us_eu_price, us_eu_gdtr_l1, us_eu_ndtr_l1, eu_eu_price, eu_eu_gdtr_l1, eu_eu_ndtr_l1) %>%
  mutate(across(where(is.numeric), function(x){x/first(x)})) %>%
  plot_ly(type = "scatter", mode = "lines") %>%
  add_trace(x = ~date, y = ~log(us_eu_price), name = "Price Return  (USD)", line = list(width = 1)) %>%
  add_trace(x = ~date, y = ~log(us_eu_gdtr_l1), name = "Gross Total Return (USD)", line = list(width = 1)) %>%
  add_trace(x = ~date, y = ~log(us_eu_ndtr_l1), name = "Net Total Return (USD)", line = list(width = 1)) %>%
  add_trace(x = ~date, y = ~log(eu_eu_price), name = "Price Return (EUR)", line = list(width = 1)) %>%
  add_trace(x = ~date, y = ~log(eu_eu_gdtr_l1), name = "Gross Total Return (EUR)", line = list(width = 1)) %>%
  add_trace(x = ~date, y = ~log(eu_eu_ndtr_l1), name = "Net Total Return (EUR)", line = list(width = 1)) %>%
  layout(
    showlegend = TRUE, legend = list(orientation = 'h'), 
    xaxis = list(title = "Time"),
    yaxis = list(title = "Log. Index Value"),
    title = "MSCI Europe Indices",
    margin = list(t = 50))

msci_model %>%
  select(date, us_pc_price, us_pc_gdtr_l1, us_pc_ndtr_l1, eu_pc_price, eu_pc_gdtr_l1, eu_pc_ndtr_l1) %>%
  mutate(across(where(is.numeric), function(x){x/first(x)})) %>%
  plot_ly(type = "scatter", mode = "lines") %>%
  add_trace(x = ~date, y = ~us_pc_price, name = "Price Return  (USD)", line = list(width = 1)) %>%
  add_trace(x = ~date, y = ~us_pc_gdtr_l1, name = "Gross Total Return (USD)", line = list(width = 1)) %>%
  add_trace(x = ~date, y = ~us_pc_ndtr_l1, name = "Net Total Return (USD)", line = list(width = 1)) %>%
  add_trace(x = ~date, y = ~eu_pc_price, name = "Price Return (EUR)", line = list(width = 1)) %>%
  add_trace(x = ~date, y = ~eu_pc_gdtr_l1, name = "Gross Total Return (EUR)", line = list(width = 1)) %>%
  add_trace(x = ~date, y = ~eu_pc_ndtr_l1, name = "Net Total Return (EUR)", line = list(width = 1)) %>%
  layout(
    showlegend = TRUE, legend = list(orientation = 'h'), 
    xaxis = list(title = "Time"),
    yaxis = list(title = "Index Value"),
    title = "MSCI Pacific Indices",
    margin = list(t = 50))

msci_model %>%
  select(date, us_pc_price, us_pc_gdtr_l1, us_pc_ndtr_l1, eu_pc_price, eu_pc_gdtr_l1, eu_pc_ndtr_l1) %>%
  mutate(across(where(is.numeric), function(x){x/first(x)})) %>%
  plot_ly(type = "scatter", mode = "lines") %>%
  add_trace(x = ~date, y = ~log(us_pc_price), name = "Price Return  (USD)", line = list(width = 1)) %>%
  add_trace(x = ~date, y = ~log(us_pc_gdtr_l1), name = "Gross Total Return (USD)", line = list(width = 1)) %>%
  add_trace(x = ~date, y = ~log(us_pc_ndtr_l1), name = "Net Total Return (USD)", line = list(width = 1)) %>%
  add_trace(x = ~date, y = ~log(eu_pc_price), name = "Price Return (EUR)", line = list(width = 1)) %>%
  add_trace(x = ~date, y = ~log(eu_pc_gdtr_l1), name = "Gross Total Return (EUR)", line = list(width = 1)) %>%
  add_trace(x = ~date, y = ~log(eu_pc_ndtr_l1), name = "Net Total Return (EUR)", line = list(width = 1)) %>%
  layout(
    showlegend = TRUE, legend = list(orientation = 'h'), 
    xaxis = list(title = "Time"),
    yaxis = list(title = "Log. Index Value"),
    title = "MSCI Pacific Indices",
    margin = list(t = 50))

msci_model %>% 
  filter(date >= "1988-01-01") %>%
  select(date, us_em_price, us_em_gdtr_l1, us_em_ndtr_l1, eu_em_price, eu_em_gdtr_l1, eu_em_ndtr_l1) %>%
  mutate(across(where(is.numeric), function(x){x/first(x)})) %>%
  plot_ly(type = "scatter", mode = "lines") %>%
  add_trace(x = ~date, y = ~us_em_price, name = "Price Return  (USD)", line = list(width = 1)) %>%
  add_trace(x = ~date, y = ~us_em_gdtr_l1, name = "Gross Total Return (USD)", line = list(width = 1)) %>%
  add_trace(x = ~date, y = ~us_em_ndtr_l1, name = "Net Total Return (USD)", line = list(width = 1)) %>%
  add_trace(x = ~date, y = ~eu_em_price, name = "Price Return (EUR)", line = list(width = 1)) %>%
  add_trace(x = ~date, y = ~eu_em_gdtr_l1, name = "Gross Total Return (EUR)", line = list(width = 1)) %>%
  add_trace(x = ~date, y = ~eu_em_ndtr_l1, name = "Net Total Return (EUR)", line = list(width = 1)) %>%
  layout(
    showlegend = TRUE, legend = list(orientation = 'h'), 
    xaxis = list(title = "Time"),
    yaxis = list(title = "Index Value"),
    title = "MSCI Emerging Indices",
    margin = list(t = 50))

msci_model %>% filter(date >= "1988-01-01") %>%
  select(date, us_em_price, us_em_gdtr_l1, us_em_ndtr_l1, eu_em_price, eu_em_gdtr_l1, eu_em_ndtr_l1) %>%
  mutate(across(where(is.numeric), function(x){x/first(x)})) %>%
  plot_ly(type = "scatter", mode = "lines") %>%
  add_trace(x = ~date, y = ~log(us_em_price), name = "Price Return  (USD)", line = list(width = 1)) %>%
  add_trace(x = ~date, y = ~log(us_em_gdtr_l1), name = "Gross Total Return (USD)", line = list(width = 1)) %>%
  add_trace(x = ~date, y = ~log(us_em_ndtr_l1), name = "Net Total Return (USD)", line = list(width = 1)) %>%
  add_trace(x = ~date, y = ~log(eu_em_price), name = "Price Return (EUR)", line = list(width = 1)) %>%
  add_trace(x = ~date, y = ~log(eu_em_gdtr_l1), name = "Gross Total Return (EUR)", line = list(width = 1)) %>%
  add_trace(x = ~date, y = ~log(eu_em_ndtr_l1), name = "Net Total Return (EUR)", line = list(width = 1)) %>%
  layout(
    showlegend = TRUE, legend = list(orientation = 'h'), 
    xaxis = list(title = "Time"),
    yaxis = list(title = "Log. Index Value"),
    title = "MSCI Emerging Indices",
    margin = list(t = 50))



#---> Initialisierung des Grid-Search-Algorithmus:
search_grid <- seq(-0.1, 0.1, by = 1e-4)
search_data <- msci_data %>% filter(date >= "2000-12-29" & date <= stopp_date)

search_results <- sapply(search_grid, function(search_value){
  search_data %>%
    mutate(
      us_world_gdtr_l2_real = Reduce(function(values, rates){values*rates},
                                     lead(us_world_gdtr_l2_return), init = 100, accumulate = TRUE)[-nrow(.)],
      us_world_gdtr_l2_return_model = (2*us_world_gdtr_l1_return + (1-2)*(us_rate/100)*(1/days) - 1) + (search_value/100),
      us_world_gdtr_l2_stat = Reduce(function(values, rates){values*rates},
                                     lead(us_world_gdtr_l2_return_model), init = 100, accumulate = TRUE)[-nrow(.)],
      error = 1 - (us_world_gdtr_l2_stat/us_world_gdtr_l2_real)) %>%
    pull(error)})

search_metrics(search_results, search_grid)
rm(search_results, search_data, search_grid)


search_grid <- seq(-0.1, 0.1, by = 1e-4)
search_data <- msci_data %>% filter(date >= "2000-12-29" & date <= stopp_date)

search_results <- sapply(search_grid, function(search_value){
  search_data %>%
    mutate(
      us_em_gdtr_l2_real = Reduce(function(values, rates){values*rates},
                                  lead(us_em_gdtr_l2_return), init = 100, accumulate = TRUE)[-nrow(.)],
      us_em_gdtr_l2_return_model = (2*us_em_gdtr_l2_return + (1-2)*(us_rate/100)*(1/days) - 1) + (search_value/100),
      us_em_gdtr_l2_stat = Reduce(function(values, rates){values*rates},
                                  lead(us_em_gdtr_l2_return_model), init = 100, accumulate = TRUE)[-nrow(.)],
      error = 1 - (us_em_gdtr_l2_stat/us_em_gdtr_l2_real)) %>%
    pull(error)})

search_metrics(search_results, search_grid)
rm(search_results, search_data, search_grid)


search_grid <- seq(-0.1, 0.1, by = 1e-4)
search_data <- msci_data %>% filter(date >= "2000-12-29" & date <= stopp_date)

search_results <- sapply(search_grid, function(search_value){
  search_data %>%
    mutate(
      eu_eu_gdtr_l2_real = Reduce(function(values, rates){values*rates},
                                  lead(eu_eu_gdtr_l2_return), init = 100, accumulate = TRUE)[-nrow(.)],
      eu_eu_gdtr_l2_return_model = (2*eu_eu_gdtr_l2_return + (1-2)*(eu_rate/100)*(1/days) - 1) + (search_value/100),
      eu_eu_gdtr_l2_stat = Reduce(function(values, rates){values*rates},
                                  lead(eu_eu_gdtr_l2_return_model), init = 100, accumulate = TRUE)[-nrow(.)],
      error = 1 - (eu_eu_gdtr_l2_stat/eu_eu_gdtr_l2_real)) %>%
    pull(error)})

search_metrics(search_results, search_grid)
rm(search_results, search_data, search_grid)



#---> Finalisierung der Index-Zeitreihen:
msci_final <- list(
  #--------> 1. MSCI World:
  msci_model %>%
    mutate(
      us_world_gdtr_l2_return = ifelse(date <= "2000-12-29",
                                       ((2*us_world_gdtr_l1_return + (1-2)*(us_rate/100)*(1/days)) - 1) - (0.0015/100),
                                       us_world_gdtr_l2_return),
      us_world_gdtr_l2 = round(Reduce(function(values, rates){values*rates},
                                      lead(us_world_gdtr_l2_return), init = 100, accumulate = TRUE)[-nrow(.)], digits = 5),
      us_world_gdtr_l2 = case_when(row_number() == n() ~ round(lag(us_world_gdtr_l2)*us_world_gdtr_l2_return, digits = 2), TRUE ~ us_world_gdtr_l2),
      us_world_ndtr_l2_return = us_world_gdtr_l2_return - 2*(us_world_gdtr_l1_return - us_world_ndtr_l1_return),
      us_world_ndtr_l2 = round(Reduce(function(values, rates){values*rates},
                                      lead(us_world_ndtr_l2_return), init = 100, accumulate = TRUE)[-nrow(.)], digits = 5),
      us_world_ndtr_l2 = case_when(row_number() == n() ~ round(lag(us_world_ndtr_l2)*us_world_ndtr_l2_return, digits = 2), TRUE ~ us_world_ndtr_l2),
      us_world_price = round(us_world_price/first(us_world_price), digits = 5),
      eu_world_gdtr_l2_return = (2*eu_world_gdtr_l1_return + (1-2)*(eu_rate/100)*(1/days)) - 1 - (0.0015/100),
      eu_world_gdtr_l2 = round(Reduce(function(values, rates){values*rates},
                                      lead(eu_world_gdtr_l2_return), init = 100, accumulate = TRUE)[-nrow(.)], digits = 5),
      eu_world_gdtr_l2 = case_when(row_number() == n() ~ round(lag(eu_world_gdtr_l2)*eu_world_gdtr_l2_return, digits = 2), TRUE ~ eu_world_gdtr_l2),
      eu_world_ndtr_l2_return = eu_world_gdtr_l2_return - 2*(eu_world_gdtr_l1_return - eu_world_ndtr_l1_return),
      eu_world_ndtr_l2 = round(Reduce(function(values, rates){values*rates},
                                      lead(eu_world_ndtr_l2_return), init = 100, accumulate = TRUE)[-nrow(.)], digits = 5),
      eu_world_ndtr_l2 = case_when(row_number() == n() ~ round(lag(eu_world_ndtr_l2)*eu_world_ndtr_l2_return, digits = 2), TRUE ~ eu_world_ndtr_l2),
      eu_world_price = round(eu_world_price/first(eu_world_price), digits = 5)) %>%
    select(date, days, matches("_world_"), -ends_with("_return"), -ends_with("_model")) %>%
    mutate(across(-c(date, days), ~ .x/first(.x) * 100)),
  #--------> 2. MSCI North America:
  msci_model %>%
    mutate(
      us_na_gdtr_l2_return = ((2*us_na_gdtr_l1_return + (1-2)*(us_rate/100)*(1/days)) - 1) - (0.0015/100),
      us_na_gdtr_l2 = round(Reduce(function(values, rates){values*rates},
                                   lead(us_na_gdtr_l2_return), init = 100, accumulate = TRUE)[-nrow(.)], digits = 5),
      us_na_gdtr_l2 = case_when(row_number() == n() ~ round(lag(us_na_gdtr_l2)*us_na_gdtr_l2_return, digits = 2), TRUE ~ us_na_gdtr_l2),
      us_na_ndtr_l2_return = us_na_gdtr_l2_return - 2*(us_na_gdtr_l1_return - us_na_ndtr_l1_return),
      us_na_ndtr_l2 = round(Reduce(function(values, rates){values*rates},
                                   lead(us_na_ndtr_l2_return), init = 100, accumulate = TRUE)[-nrow(.)], digits = 5),
      us_na_ndtr_l2 = case_when(row_number() == n() ~ round(lag(us_na_ndtr_l2)*us_na_ndtr_l2_return, digits = 2), TRUE ~ us_na_ndtr_l2),
      us_na_price = round(us_na_price/first(us_na_price), digits = 5),
      eu_na_gdtr_l2_return = ((2*eu_na_gdtr_l1_return + (1-2)*(eu_rate/100)*(1/days)) - 1) - (0.0015/100),
      eu_na_gdtr_l2 = round(Reduce(function(values, rates){values*rates},
                                   lead(eu_na_gdtr_l2_return), init = 100, accumulate = TRUE)[-nrow(.)], digits = 5),
      eu_na_gdtr_l2 = case_when(row_number() == n() ~ round(lag(eu_na_gdtr_l2)*eu_na_gdtr_l2_return, digits = 2), TRUE ~ eu_na_gdtr_l2),
      eu_na_ndtr_l2_return = eu_na_gdtr_l2_return - 2*(eu_na_gdtr_l1_return - eu_na_ndtr_l1_return),
      eu_na_ndtr_l2 = round(Reduce(function(values, rates){values*rates},
                                   lead(eu_na_ndtr_l2_return), init = 100, accumulate = TRUE)[-nrow(.)], digits = 5),
      eu_na_ndtr_l2 = case_when(row_number() == n() ~ round(lag(eu_na_ndtr_l2)*eu_na_ndtr_l2_return, digits = 2), TRUE ~ eu_na_ndtr_l2),
      eu_na_price = round(eu_na_price/first(eu_na_price), digits = 5)) %>%
    select(date, days, matches("_na_"), -ends_with("_return"), -ends_with("_model")) %>%
    mutate(across(-c(date, days), ~ .x/first(.x) * 100)),
  #--------> 3. MSCI Europe:
  msci_model %>%
    mutate(
      us_eu_gdtr_l2_return = ((2*us_eu_gdtr_l1_return + (1-2)*(us_rate/100)*(1/days)) - 1) - (0.0030/100),
      us_eu_gdtr_l2 = round(Reduce(function(values, rates){values*rates},
                                   lead(us_eu_gdtr_l2_return), init = 100, accumulate = TRUE)[-nrow(.)], digits = 5),
      us_eu_gdtr_l2 = case_when(row_number() == n() ~ round(lag(us_eu_gdtr_l2)*us_eu_gdtr_l2_return, digits = 2), TRUE ~ us_eu_gdtr_l2),
      us_eu_ndtr_l2_return = us_eu_gdtr_l2_return - 2*(us_eu_gdtr_l1_return - us_eu_ndtr_l1_return),
      us_eu_ndtr_l2 = round(Reduce(function(values, rates){values*rates},
                                   lead(us_eu_ndtr_l2_return), init = 100, accumulate = TRUE)[-nrow(.)], digits = 5),
      us_eu_ndtr_l2 = case_when(row_number() == n() ~ round(lag(us_eu_ndtr_l2)*us_eu_ndtr_l2_return, digits = 2), TRUE ~ us_eu_ndtr_l2),
      us_eu_price = round(us_eu_price/first(us_eu_price), digits = 5),
      eu_eu_gdtr_l2_return = ifelse(date <= "2000-12-29", 
                                    ((2*eu_eu_gdtr_l1_return + (1-2)*(eu_rate/100)*(1/days)) - 1),
                                    eu_eu_gdtr_l2_return),
      eu_eu_gdtr_l2 = round(Reduce(function(values, rates){values*rates},
                                   lead(eu_eu_gdtr_l2_return), init = 100, accumulate = TRUE)[-nrow(.)], digits = 5),
      eu_eu_gdtr_l2 = case_when(row_number() == n() ~ round(lag(eu_eu_gdtr_l2)*eu_eu_gdtr_l2_return, digits = 2), TRUE ~ eu_eu_gdtr_l2),
      eu_eu_ndtr_l2_return = eu_eu_gdtr_l2_return - 2*(eu_eu_gdtr_l1_return - eu_eu_ndtr_l1_return),
      eu_eu_ndtr_l2 = round(Reduce(function(values, rates){values*rates},
                                   lead(eu_eu_ndtr_l2_return), init = 100, accumulate = TRUE)[-nrow(.)], digits = 5),
      eu_eu_ndtr_l2 = case_when(row_number() == n() ~ round(lag(eu_eu_ndtr_l2)*eu_eu_ndtr_l2_return, digits = 2), TRUE ~ eu_eu_ndtr_l2),
      eu_eu_price = round(eu_eu_price/first(eu_eu_price), digits = 5)) %>%
    select(date, days, matches("_eu_"), -ends_with("_return"), -ends_with("_model")) %>%
    mutate(across(-c(date, days), ~ .x/first(.x) * 100)),
  #--------> 4. MSCI Pacific:
  msci_model %>%
    mutate(
      us_pc_gdtr_l2_return = ((2*us_pc_gdtr_l1_return + (1-2)*(us_rate/100)*(1/days)) - 1) - (0.0035/100),
      us_pc_gdtr_l2 = round(Reduce(function(values, rates){values*rates},
                                   lead(us_pc_gdtr_l2_return), init = 100, accumulate = TRUE)[-nrow(.)], digits = 5),
      us_pc_gdtr_l2 = case_when(row_number() == n() ~ round(lag(us_pc_gdtr_l2)*us_pc_gdtr_l2_return, digits = 2), TRUE ~ us_pc_gdtr_l2),
      us_pc_ndtr_l2_return = us_pc_gdtr_l2_return - 2*(us_pc_gdtr_l1_return - us_pc_ndtr_l1_return),
      us_pc_ndtr_l2 = round(Reduce(function(values, rates){values*rates},
                                   lead(us_pc_ndtr_l2_return), init = 100, accumulate = TRUE)[-nrow(.)], digits = 5),
      us_pc_ndtr_l2 = case_when(row_number() == n() ~ round(lag(us_pc_ndtr_l2)*us_pc_ndtr_l2_return, digits = 2), TRUE ~ us_pc_ndtr_l2),
      us_pc_price = round(us_pc_price/first(us_pc_price), digits = 5),
      eu_pc_gdtr_l2_return = ((2*eu_pc_gdtr_l1_return + (1-2)*(eu_rate/100)*(1/days))) - 1 - (0.0035/100),
      eu_pc_gdtr_l2 = round(Reduce(function(values, rates){values*rates},
                                   lead(eu_pc_gdtr_l2_return), init = 100, accumulate = TRUE)[-nrow(.)], digits = 5),
      eu_pc_gdtr_l2 = case_when(row_number() == n() ~ round(lag(eu_pc_gdtr_l2)*eu_pc_gdtr_l2_return, digits = 2), TRUE ~ eu_pc_gdtr_l2),
      eu_pc_ndtr_l2_return = eu_pc_gdtr_l2_return - 2*(eu_pc_gdtr_l1_return - eu_pc_ndtr_l1_return),
      eu_pc_ndtr_l2 = round(Reduce(function(values, rates){values*rates},
                                   lead(eu_pc_ndtr_l2_return), init = 100, accumulate = TRUE)[-nrow(.)], digits = 5),
      eu_pc_ndtr_l2 = case_when(row_number() == n() ~ round(lag(eu_pc_ndtr_l2)*eu_pc_ndtr_l2_return, digits = 2), TRUE ~ eu_pc_ndtr_l2),
      eu_pc_price = round(eu_pc_price/first(eu_pc_price), digits = 5)) %>%
    select(date, days, matches("_pc_"), -ends_with("_return"), -ends_with("_model")) %>%
    mutate(across(-c(date, days), ~ .x/first(.x) * 100)),
  #--------> 5. MSCI Emerging:
  msci_model %>%
    filter(date >= "1988-01-01") %>%
    mutate(
      us_em_gdtr_l2_return = ifelse(date <= "2000-12-29",
                                    ((2*us_em_gdtr_l1_return + (1-2)*(us_rate/100)*(1/days)) - 1) - (0.0040/100),
                                    us_em_gdtr_l2_return),
      us_em_gdtr_l2 = round(Reduce(function(values, rates){values*rates},
                                   lead(us_em_gdtr_l2_return), init = 100, accumulate = TRUE)[-nrow(.)], digits = 5),
      us_em_gdtr_l2 = case_when(row_number() == n() ~ round(lag(us_em_gdtr_l2)*us_em_gdtr_l2_return, digits = 2), TRUE ~ us_em_gdtr_l2),
      us_em_ndtr_l2_return = us_em_gdtr_l2_return - 2*(us_em_gdtr_l1_return - us_em_ndtr_l1_return),
      us_em_ndtr_l2 = round(Reduce(function(values, rates){values*rates},
                                   lead(us_em_ndtr_l2_return), init = 100, accumulate = TRUE)[-nrow(.)], digits = 5),
      us_em_ndtr_l2 = case_when(row_number() == n() ~ round(lag(us_em_ndtr_l2)*us_em_ndtr_l2_return, digits = 2), TRUE ~ us_em_ndtr_l2),
      us_em_price = round(us_em_price/first(us_em_price), digits = 5),
      eu_em_gdtr_l2_return = ((2*eu_em_gdtr_l1_return + (1-2)*(eu_rate/100)*(1/days))) - 1 - (0.0040/100),
      eu_em_gdtr_l2 = round(Reduce(function(values, rates){values*rates},
                                   lead(eu_em_gdtr_l2_return), init = 100, accumulate = TRUE)[-nrow(.)], digits = 5),
      eu_em_gdtr_l2 = case_when(row_number() == n() ~ round(lag(eu_em_gdtr_l2)*eu_em_gdtr_l2_return, digits = 2), TRUE ~ eu_em_gdtr_l2),
      eu_em_ndtr_l2_return = eu_em_gdtr_l2_return - 2*(eu_em_gdtr_l1_return - eu_em_ndtr_l1_return),
      eu_em_ndtr_l2 = round(Reduce(function(values, rates){values*rates},
                                   lead(eu_em_ndtr_l2_return), init = 100, accumulate = TRUE)[-nrow(.)], digits = 5),
      eu_em_ndtr_l2 = case_when(row_number() == n() ~ round(lag(eu_em_ndtr_l2)*eu_em_ndtr_l2_return, digits = 2), TRUE ~ eu_em_ndtr_l2),
      eu_em_price = round(eu_em_price/first(eu_em_price), digits = 5)) %>%
    select(date, days, matches("_em_"), -ends_with("_return"), -ends_with("_model")) %>%
    mutate(across(-c(date, days), ~ .x/first(.x) * 100))) %>%
  Reduce(function(x, y) left_join(x, y, by = c("date", "days")), .) %>%
  filter(date <= "2025-08-31")



#---> Visualisierung der Index-Zeitreihen:
msci_final %>%
  select(date, us_world_price, eu_world_price,
         us_world_gdtr_l1, us_world_ndtr_l1, us_world_gdtr_l2, us_world_ndtr_l2,
         eu_world_gdtr_l1, eu_world_ndtr_l1, eu_world_gdtr_l2, eu_world_ndtr_l2) %>%
  mutate(across(where(is.numeric), function(x){x/first(x)})) %>%
  plot_ly(type = "scatter", mode = "lines") %>%
  add_trace(x = ~date, y = ~us_world_price, name = "Price Return  (USD)", line = list(width = 1)) %>%
  add_trace(x = ~date, y = ~us_world_gdtr_l1, name = "Gross Total Return (USD)", line = list(width = 1)) %>%
  add_trace(x = ~date, y = ~us_world_ndtr_l1, name = "Net Total Return (USD)", line = list(width = 1)) %>%
  add_trace(x = ~date, y = ~us_world_gdtr_l2, name = "Gross Total Return x2 (USD)", line = list(width = 1)) %>%
  add_trace(x = ~date, y = ~us_world_ndtr_l2, name = "Net Total Return x2 (USD)", line = list(width = 1)) %>%
  add_trace(x = ~date, y = ~eu_world_price, name = "Price Return (EUR)", line = list(width = 1)) %>%
  add_trace(x = ~date, y = ~eu_world_gdtr_l1, name = "Gross Total Return (EUR)", line = list(width = 1)) %>%
  add_trace(x = ~date, y = ~eu_world_ndtr_l1, name = "Net Total Return (EUR)", line = list(width = 1)) %>%
  add_trace(x = ~date, y = ~eu_world_gdtr_l2, name = "Gross Total Return x2 (EUR)", line = list(width = 1)) %>%
  add_trace(x = ~date, y = ~eu_world_ndtr_l2, name = "Net Total Return x2 (EUR)", line = list(width = 1)) %>%
  layout(
    showlegend = TRUE, legend = list(orientation = 'h'), 
    xaxis = list(title = "Time"),
    yaxis = list(title = "Index Value"),
    title = "MSCI World Indices",
    margin = list(t = 50))

msci_final %>%
  select(date, us_world_price, eu_world_price,
         us_world_gdtr_l1, us_world_ndtr_l1, us_world_gdtr_l2, us_world_ndtr_l2,
         eu_world_gdtr_l1, eu_world_ndtr_l1, eu_world_gdtr_l2, eu_world_ndtr_l2) %>%
  mutate(across(where(is.numeric), function(x){x/first(x)})) %>%
  plot_ly(type = "scatter", mode = "lines") %>%
  add_trace(x = ~date, y = ~log(us_world_price), name = "Price Return  (USD)", line = list(width = 1)) %>%
  add_trace(x = ~date, y = ~log(us_world_gdtr_l1), name = "Gross Total Return (USD)", line = list(width = 1)) %>%
  add_trace(x = ~date, y = ~log(us_world_ndtr_l1), name = "Net Total Return (USD)", line = list(width = 1)) %>%
  add_trace(x = ~date, y = ~log(us_world_gdtr_l2), name = "Gross Total Return x2 (USD)", line = list(width = 1)) %>%
  add_trace(x = ~date, y = ~log(us_world_ndtr_l2), name = "Net Total Return x2 (USD)", line = list(width = 1)) %>%
  add_trace(x = ~date, y = ~log(eu_world_price), name = "Price Return (EUR)", line = list(width = 1)) %>%
  add_trace(x = ~date, y = ~log(eu_world_gdtr_l1), name = "Gross Total Return (EUR)", line = list(width = 1)) %>%
  add_trace(x = ~date, y = ~log(eu_world_ndtr_l1), name = "Net Total Return (EUR)", line = list(width = 1)) %>%
  add_trace(x = ~date, y = ~log(eu_world_gdtr_l2), name = "Gross Total Return x2 (EUR)", line = list(width = 1)) %>%
  add_trace(x = ~date, y = ~log(eu_world_ndtr_l2), name = "Net Total Return x2 (EUR)", line = list(width = 1)) %>%
  layout(
    showlegend = TRUE, legend = list(orientation = 'h'), 
    xaxis = list(title = "Time"),
    yaxis = list(title = "Log. Index Value"),
    title = "MSCI World Indices",
    margin = list(t = 50))

msci_final %>%
  select(date, us_na_price, eu_na_price,
         us_na_gdtr_l1, us_na_ndtr_l1, us_na_gdtr_l2, us_na_ndtr_l2,
         eu_na_gdtr_l1, eu_na_ndtr_l1, eu_na_gdtr_l2, eu_na_ndtr_l2) %>%
  mutate(across(where(is.numeric), function(x){x/first(x)})) %>%
  plot_ly(type = "scatter", mode = "lines") %>%
  add_trace(x = ~date, y = ~us_na_price, name = "Price Return  (USD)", line = list(width = 1)) %>%
  add_trace(x = ~date, y = ~us_na_gdtr_l1, name = "Gross Total Return (USD)", line = list(width = 1)) %>%
  add_trace(x = ~date, y = ~us_na_ndtr_l1, name = "Net Total Return (USD)", line = list(width = 1)) %>%
  add_trace(x = ~date, y = ~us_na_gdtr_l2, name = "Gross Total Return x2 (USD)", line = list(width = 1)) %>%
  add_trace(x = ~date, y = ~us_na_ndtr_l2, name = "Net Total Return x2 (USD)", line = list(width = 1)) %>%
  add_trace(x = ~date, y = ~eu_na_price, name = "Price Return (EUR)", line = list(width = 1)) %>%
  add_trace(x = ~date, y = ~eu_na_gdtr_l1, name = "Gross Total Return (EUR)", line = list(width = 1)) %>%
  add_trace(x = ~date, y = ~eu_na_ndtr_l1, name = "Net Total Return (EUR)", line = list(width = 1)) %>%
  add_trace(x = ~date, y = ~eu_na_gdtr_l2, name = "Gross Total Return x2 (EUR)", line = list(width = 1)) %>%
  add_trace(x = ~date, y = ~eu_na_ndtr_l2, name = "Net Total Return x2 (EUR)", line = list(width = 1)) %>%
  layout(
    showlegend = TRUE, legend = list(orientation = 'h'), 
    xaxis = list(title = "Time"),
    yaxis = list(title = "Index Value"),
    title = "MSCI North America Indices",
    margin = list(t = 50))

msci_final %>%
  select(date, us_na_price, eu_na_price,
         us_na_gdtr_l1, us_na_ndtr_l1, us_na_gdtr_l2, us_na_ndtr_l2,
         eu_na_gdtr_l1, eu_na_ndtr_l1, eu_na_gdtr_l2, eu_na_ndtr_l2) %>%
  mutate(across(where(is.numeric), function(x){x/first(x)})) %>%
  plot_ly(type = "scatter", mode = "lines") %>%
  add_trace(x = ~date, y = ~log(us_na_price), name = "Price Return  (USD)", line = list(width = 1)) %>%
  add_trace(x = ~date, y = ~log(us_na_gdtr_l1), name = "Gross Total Return (USD)", line = list(width = 1)) %>%
  add_trace(x = ~date, y = ~log(us_na_ndtr_l1), name = "Net Total Return (USD)", line = list(width = 1)) %>%
  add_trace(x = ~date, y = ~log(us_na_gdtr_l2), name = "Gross Total Return x2 (USD)", line = list(width = 1)) %>%
  add_trace(x = ~date, y = ~log(us_na_ndtr_l2), name = "Net Total Return x2 (USD)", line = list(width = 1)) %>%
  add_trace(x = ~date, y = ~log(eu_na_price), name = "Price Return (EUR)", line = list(width = 1)) %>%
  add_trace(x = ~date, y = ~log(eu_na_gdtr_l1), name = "Gross Total Return (EUR)", line = list(width = 1)) %>%
  add_trace(x = ~date, y = ~log(eu_na_ndtr_l1), name = "Net Total Return (EUR)", line = list(width = 1)) %>%
  add_trace(x = ~date, y = ~log(eu_na_gdtr_l2), name = "Gross Total Return x2 (EUR)", line = list(width = 1)) %>%
  add_trace(x = ~date, y = ~log(eu_na_ndtr_l2), name = "Net Total Return x2 (EUR)", line = list(width = 1)) %>%
  layout(
    showlegend = TRUE, legend = list(orientation = 'h'), 
    xaxis = list(title = "Time"),
    yaxis = list(title = "Log. Index Value"),
    title = "MSCI North America Indices",
    margin = list(t = 50))

msci_final %>%
  select(date, us_eu_price, eu_eu_price,
         us_eu_gdtr_l1, us_eu_ndtr_l1, us_eu_gdtr_l2, us_eu_ndtr_l2,
         eu_eu_gdtr_l1, eu_eu_ndtr_l1, eu_eu_gdtr_l2, eu_eu_ndtr_l2) %>%
  mutate(across(where(is.numeric), function(x){x/first(x)})) %>%
  plot_ly(type = "scatter", mode = "lines") %>%
  add_trace(x = ~date, y = ~us_eu_price, name = "Price Return  (USD)", line = list(width = 1)) %>%
  add_trace(x = ~date, y = ~us_eu_gdtr_l1, name = "Gross Total Return (USD)", line = list(width = 1)) %>%
  add_trace(x = ~date, y = ~us_eu_ndtr_l1, name = "Net Total Return (USD)", line = list(width = 1)) %>%
  add_trace(x = ~date, y = ~us_eu_gdtr_l2, name = "Gross Total Return x2 (USD)", line = list(width = 1)) %>%
  add_trace(x = ~date, y = ~us_eu_ndtr_l2, name = "Net Total Return x2 (USD)", line = list(width = 1)) %>%
  add_trace(x = ~date, y = ~eu_eu_price, name = "Price Return (EUR)", line = list(width = 1)) %>%
  add_trace(x = ~date, y = ~eu_eu_gdtr_l1, name = "Gross Total Return (EUR)", line = list(width = 1)) %>%
  add_trace(x = ~date, y = ~eu_eu_ndtr_l1, name = "Net Total Return (EUR)", line = list(width = 1)) %>%
  add_trace(x = ~date, y = ~eu_eu_gdtr_l2, name = "Gross Total Return x2 (EUR)", line = list(width = 1)) %>%
  add_trace(x = ~date, y = ~eu_eu_ndtr_l2, name = "Net Total Return x2 (EUR)", line = list(width = 1)) %>%
  layout(
    showlegend = TRUE, legend = list(orientation = 'h'), 
    xaxis = list(title = "Time"),
    yaxis = list(title = "Index Value"),
    title = "MSCI Europe Indices",
    margin = list(t = 50))

msci_final %>%
  select(date, us_eu_price, eu_eu_price,
         us_eu_gdtr_l1, us_eu_ndtr_l1, us_eu_gdtr_l2, us_eu_ndtr_l2,
         eu_eu_gdtr_l1, eu_eu_ndtr_l1, eu_eu_gdtr_l2, eu_eu_ndtr_l2) %>%
  mutate(across(where(is.numeric), function(x){x/first(x)})) %>%
  plot_ly(type = "scatter", mode = "lines") %>%
  add_trace(x = ~date, y = ~log(us_eu_price), name = "Price Return  (USD)", line = list(width = 1)) %>%
  add_trace(x = ~date, y = ~log(us_eu_gdtr_l1), name = "Gross Total Return (USD)", line = list(width = 1)) %>%
  add_trace(x = ~date, y = ~log(us_eu_ndtr_l1), name = "Net Total Return (USD)", line = list(width = 1)) %>%
  add_trace(x = ~date, y = ~log(us_eu_gdtr_l2), name = "Gross Total Return x2 (USD)", line = list(width = 1)) %>%
  add_trace(x = ~date, y = ~log(us_eu_ndtr_l2), name = "Net Total Return x2 (USD)", line = list(width = 1)) %>%
  add_trace(x = ~date, y = ~log(eu_eu_price), name = "Price Return (EUR)", line = list(width = 1)) %>%
  add_trace(x = ~date, y = ~log(eu_eu_gdtr_l1), name = "Gross Total Return (EUR)", line = list(width = 1)) %>%
  add_trace(x = ~date, y = ~log(eu_eu_ndtr_l1), name = "Net Total Return (EUR)", line = list(width = 1)) %>%
  add_trace(x = ~date, y = ~log(eu_eu_gdtr_l2), name = "Gross Total Return x2 (EUR)", line = list(width = 1)) %>%
  add_trace(x = ~date, y = ~log(eu_eu_ndtr_l2), name = "Net Total Return x2 (EUR)", line = list(width = 1)) %>%
  layout(
    showlegend = TRUE, legend = list(orientation = 'h'), 
    xaxis = list(title = "Time"),
    yaxis = list(title = "Log. Index Value"),
    title = "MSCI Europe Indices",
    margin = list(t = 50))

msci_final %>%
  select(date, us_pc_price, eu_pc_price,
         us_pc_gdtr_l1, us_pc_ndtr_l1, us_pc_gdtr_l2, us_pc_ndtr_l2,
         eu_pc_gdtr_l1, eu_pc_ndtr_l1, eu_pc_gdtr_l2, eu_pc_ndtr_l2) %>%
  mutate(across(where(is.numeric), function(x){x/first(x)})) %>%
  plot_ly(type = "scatter", mode = "lines") %>%
  add_trace(x = ~date, y = ~us_pc_price, name = "Price Return  (USD)", line = list(width = 1)) %>%
  add_trace(x = ~date, y = ~us_pc_gdtr_l1, name = "Gross Total Return (USD)", line = list(width = 1)) %>%
  add_trace(x = ~date, y = ~us_pc_ndtr_l1, name = "Net Total Return (USD)", line = list(width = 1)) %>%
  add_trace(x = ~date, y = ~us_pc_gdtr_l2, name = "Gross Total Return x2 (USD)", line = list(width = 1)) %>%
  add_trace(x = ~date, y = ~us_pc_ndtr_l2, name = "Net Total Return x2 (USD)", line = list(width = 1)) %>%
  add_trace(x = ~date, y = ~eu_pc_price, name = "Price Return (EUR)", line = list(width = 1)) %>%
  add_trace(x = ~date, y = ~eu_pc_gdtr_l1, name = "Gross Total Return (EUR)", line = list(width = 1)) %>%
  add_trace(x = ~date, y = ~eu_pc_ndtr_l1, name = "Net Total Return (EUR)", line = list(width = 1)) %>%
  add_trace(x = ~date, y = ~eu_pc_gdtr_l2, name = "Gross Total Return x2 (EUR)", line = list(width = 1)) %>%
  add_trace(x = ~date, y = ~eu_pc_ndtr_l2, name = "Net Total Return x2 (EUR)", line = list(width = 1)) %>%
  layout(
    showlegend = TRUE, legend = list(orientation = 'h'), 
    xaxis = list(title = "Time"),
    yaxis = list(title = "Index Value"),
    title = "MSCI Pacific Indices",
    margin = list(t = 50))

msci_final %>%
  select(date, us_pc_price, eu_pc_price,
         us_pc_gdtr_l1, us_pc_ndtr_l1, us_pc_gdtr_l2, us_pc_ndtr_l2,
         eu_pc_gdtr_l1, eu_pc_ndtr_l1, eu_pc_gdtr_l2, eu_pc_ndtr_l2) %>%
  mutate(across(where(is.numeric), function(x){x/first(x)})) %>%
  plot_ly(type = "scatter", mode = "lines") %>%
  add_trace(x = ~date, y = ~log(us_pc_price), name = "Price Return  (USD)", line = list(width = 1)) %>%
  add_trace(x = ~date, y = ~log(us_pc_gdtr_l1), name = "Gross Total Return (USD)", line = list(width = 1)) %>%
  add_trace(x = ~date, y = ~log(us_pc_ndtr_l1), name = "Net Total Return (USD)", line = list(width = 1)) %>%
  add_trace(x = ~date, y = ~log(us_pc_gdtr_l2), name = "Gross Total Return x2 (USD)", line = list(width = 1)) %>%
  add_trace(x = ~date, y = ~log(us_pc_ndtr_l2), name = "Net Total Return x2 (USD)", line = list(width = 1)) %>%
  add_trace(x = ~date, y = ~log(eu_pc_price), name = "Price Return (EUR)", line = list(width = 1)) %>%
  add_trace(x = ~date, y = ~log(eu_pc_gdtr_l1), name = "Gross Total Return (EUR)", line = list(width = 1)) %>%
  add_trace(x = ~date, y = ~log(eu_pc_ndtr_l1), name = "Net Total Return (EUR)", line = list(width = 1)) %>%
  add_trace(x = ~date, y = ~log(eu_pc_gdtr_l2), name = "Gross Total Return x2 (EUR)", line = list(width = 1)) %>%
  add_trace(x = ~date, y = ~log(eu_pc_ndtr_l2), name = "Net Total Return x2 (EUR)", line = list(width = 1)) %>%
  layout(
    showlegend = TRUE, legend = list(orientation = 'h'), 
    xaxis = list(title = "Time"),
    yaxis = list(title = "Log. Index Value"),
    title = "MSCI Pacific Indices",
    margin = list(t = 50))

msci_final %>%
  filter(date >= "1988-01-01") %>%
  select(date, us_em_price, eu_em_price,
         us_em_gdtr_l1, us_em_ndtr_l1, us_em_gdtr_l2, us_em_ndtr_l2,
         eu_em_gdtr_l1, eu_em_ndtr_l1, eu_em_gdtr_l2, eu_em_ndtr_l2) %>%
  mutate(across(where(is.numeric), function(x){x/first(x)})) %>%
  plot_ly(type = "scatter", mode = "lines") %>%
  add_trace(x = ~date, y = ~us_em_price, name = "Price Return  (USD)", line = list(width = 1)) %>%
  add_trace(x = ~date, y = ~us_em_gdtr_l1, name = "Gross Total Return (USD)", line = list(width = 1)) %>%
  add_trace(x = ~date, y = ~us_em_ndtr_l1, name = "Net Total Return (USD)", line = list(width = 1)) %>%
  add_trace(x = ~date, y = ~us_em_gdtr_l2, name = "Gross Total Return x2 (USD)", line = list(width = 1)) %>%
  add_trace(x = ~date, y = ~us_em_ndtr_l2, name = "Net Total Return x2 (USD)", line = list(width = 1)) %>%
  add_trace(x = ~date, y = ~eu_em_price, name = "Price Return (EUR)", line = list(width = 1)) %>%
  add_trace(x = ~date, y = ~eu_em_gdtr_l1, name = "Gross Total Return (EUR)", line = list(width = 1)) %>%
  add_trace(x = ~date, y = ~eu_em_ndtr_l1, name = "Net Total Return (EUR)", line = list(width = 1)) %>%
  add_trace(x = ~date, y = ~eu_em_gdtr_l2, name = "Gross Total Return x2 (EUR)", line = list(width = 1)) %>%
  add_trace(x = ~date, y = ~eu_em_ndtr_l2, name = "Net Total Return x2 (EUR)", line = list(width = 1)) %>%
  layout(
    showlegend = TRUE, legend = list(orientation = 'h'), 
    xaxis = list(title = "Time"),
    yaxis = list(title = "Index Value"),
    title = "MSCI Emerging Indices",
    margin = list(t = 50))

msci_final %>%
  filter(date >= "1988-01-01") %>%
  select(date, us_em_price, eu_em_price,
         us_em_gdtr_l1, us_em_ndtr_l1, us_em_gdtr_l2, us_em_ndtr_l2,
         eu_em_gdtr_l1, eu_em_ndtr_l1, eu_em_gdtr_l2, eu_em_ndtr_l2) %>%
  mutate(across(where(is.numeric), function(x){x/first(x)})) %>%
  plot_ly(type = "scatter", mode = "lines") %>%
  add_trace(x = ~date, y = ~log(us_em_price), name = "Price Return  (USD)", line = list(width = 1)) %>%
  add_trace(x = ~date, y = ~log(us_em_gdtr_l1), name = "Gross Total Return (USD)", line = list(width = 1)) %>%
  add_trace(x = ~date, y = ~log(us_em_ndtr_l1), name = "Net Total Return (USD)", line = list(width = 1)) %>%
  add_trace(x = ~date, y = ~log(us_em_gdtr_l2), name = "Gross Total Return x2 (USD)", line = list(width = 1)) %>%
  add_trace(x = ~date, y = ~log(us_em_ndtr_l2), name = "Net Total Return x2 (USD)", line = list(width = 1)) %>%
  add_trace(x = ~date, y = ~log(eu_em_price), name = "Price Return (EUR)", line = list(width = 1)) %>%
  add_trace(x = ~date, y = ~log(eu_em_gdtr_l1), name = "Gross Total Return (EUR)", line = list(width = 1)) %>%
  add_trace(x = ~date, y = ~log(eu_em_ndtr_l1), name = "Net Total Return (EUR)", line = list(width = 1)) %>%
  add_trace(x = ~date, y = ~log(eu_em_gdtr_l2), name = "Gross Total Return x2 (EUR)", line = list(width = 1)) %>%
  add_trace(x = ~date, y = ~log(eu_em_ndtr_l2), name = "Net Total Return x2 (EUR)", line = list(width = 1)) %>%
  layout(
    showlegend = TRUE, legend = list(orientation = 'h'), 
    xaxis = list(title = "Time"),
    yaxis = list(title = "Log. Index Value"),
    title = "MSCI Emerging Indices",
    margin = list(t = 50))




#---> Separierter Export von USD- und EUR-Indexreihen:
msci_final %>%
  select(
    date, days, world_us_price = us_world_price, 
    world_us_ndtr_l1 = us_world_ndtr_l1, world_us_gdtr_l1 = us_world_gdtr_l1,
    world_us_ndtr_l2 = us_world_ndtr_l2, world_us_gdtr_l2 = us_world_gdtr_l2) %>%
  read.csv(., "./03 Results Data/01 Equity Indicies/MSCI World USD.csv", row.names = FALSE)

msci_final %>%
  select(
    date, days, world_eu_price = eu_world_price,
    world_eu_ndtr_l1 = eu_world_ndtr_l1, world_eu_gdtr_l1 = eu_world_gdtr_l1, 
    world_eu_ndtr_l2 = eu_world_ndtr_l2, world_eu_gdtr_l2 = eu_world_gdtr_l2) %>%
  read.csv(., "./03 Results Data/01 Equity Indicies/MSCI World EUR.csv", row.names = FALSE)

msci_final %>%
  select(
    date, days, north_america_us_price = us_na_price, 
    north_america_us_ndtr_l1 = us_na_ndtr_l1, north_america_us_gdtr_l1 = us_na_gdtr_l1,
    north_america_us_ndtr_l2 = us_na_ndtr_l2, north_america_us_gdtr_l2 = us_na_gdtr_l2) %>%
  read.csv(., "./03 Results Data/01 Equity Indicies/MSCI North America USD.csv", row.names = FALSE)

msci_final %>%
  select(
    date, days, north_america_eu_price = eu_na_price,
    north_america_eu_ndtr_l1 = eu_na_ndtr_l1, north_america_eu_gdtr_l1 = eu_na_gdtr_l1, 
    north_america_eu_ndtr_l2 = eu_na_ndtr_l2, north_america_eu_gdtr_l2 = eu_na_gdtr_l2) %>%
  read.csv(., "./03 Results Data/01 Equity Indicies/MSCI North America EUR.csv", row.names = FALSE)

msci_final %>%
  select(
    date, days, europe_us_price = us_eu_price, 
    europe_us_ndtr_l1 = us_eu_ndtr_l1, europe_us_gdtr_l1 = us_eu_gdtr_l1,
    europe_us_ndtr_l2 = us_eu_ndtr_l2, europe_us_gdtr_l2 = us_eu_gdtr_l2) %>%
  read.csv(., "./03 Results Data/01 Equity Indicies/MSCI Europe USD.csv", row.names = FALSE)

msci_final %>%
  select(
    date, days, europe_eu_price = eu_eu_price,
    europe_eu_ndtr_l1 = eu_eu_ndtr_l1, europe_eu_gdtr_l1 = eu_eu_gdtr_l1, 
    europe_eu_ndtr_l2 = eu_eu_ndtr_l2, europe_eu_gdtr_l2 = eu_eu_gdtr_l2) %>%
  read.csv(., "./03 Results Data/01 Equity Indicies/MSCI Europe EUR.csv", row.names = FALSE)

msci_final %>%
  select(
    date, days, pacific_us_price = us_pc_price, 
    pacific_us_ndtr_l1 = us_pc_ndtr_l1, pacific_us_gdtr_l1 = us_pc_gdtr_l1,
    pacific_us_ndtr_l2 = us_pc_ndtr_l2, pacific_us_gdtr_l2 = us_pc_gdtr_l2) %>%
  read.csv(., "./03 Results Data/01 Equity Indicies/MSCI Pacific USD.csv", row.names = FALSE)

msci_final %>%
  select(
    date, days, pacific_eu_price = eu_pc_price,
    pacific_eu_ndtr_l1 = eu_pc_ndtr_l1, pacific_eu_gdtr_l1 = eu_pc_gdtr_l1, 
    pacific_eu_ndtr_l2 = eu_pc_ndtr_l2, pacific_eu_gdtr_l2 = eu_pc_gdtr_l2) %>%
  read.csv(., "./03 Results Data/01 Equity Indicies/MSCI Pacific EUR.csv", row.names = FALSE)

msci_final %>%
  select(
    date, days, emerging_us_price = us_em_price, 
    emerging_us_ndtr_l1 = us_em_ndtr_l1, emerging_us_gdtr_l1 = us_em_gdtr_l1,
    emerging_us_ndtr_l2 = us_em_ndtr_l2, emerging_us_gdtr_l2 = us_em_gdtr_l2) %>%
  read.csv(., "./03 Results Data/01 Equity Indicies/MSCI Emerging USD.csv", row.names = FALSE)

msci_final %>%
  select(
    date, days, emerging_eu_price = eu_em_price,
    emerging_eu_ndtr_l1 = eu_em_ndtr_l1, emerging_eu_gdtr_l1 = eu_em_gdtr_l1, 
    emerging_eu_ndtr_l2 = eu_em_ndtr_l2, emerging_eu_gdtr_l2 = eu_em_gdtr_l2) %>%
  read.csv(., "./03 Results Data/01 Equity Indicies/MSCI Emerging EUR.csv", row.names = FALSE)


########################################################################################################################
# 
# #---> Berechnung ungehebelter Referenz:
# msci_full_data <- list(
#   read.csv("./03 Results Data/01 Equity Indicies/MSCI World USD.csv") %>%
#     mutate(date = as.Date(date, format = "%Y-%m-%d")) %>%
#     select(date, days, world_us_ndtr_l1),
#   read.csv("./01 Source Data/03 Data Services/Onvista iShares Core MSCI World.csv", sep = ";") %>%
#     mutate(
#       date = as.Date(Datum, format = "%d.%m.%Y"),
#       ishares_l1_us_in_eu = as.numeric(gsub(",", ".", Schluss))) %>%
#     select(date, ishares_l1_us_in_eu),
#   read.csv("./01 Source Data/02 EuroStat/Eurostat Exchange Rate EUCR.csv") %>%
#     filter(Currency == "US dollar") %>%
#     mutate(
#       date = as.Date(TIME_PERIOD, format="%Y-%m-%d"),
#       eucr = 1 / OBS_VALUE) %>%
#     filter(date >= start_date & date <= stopp_date) %>%
#     select(date, eucr)) %>%
#   Reduce(function(x, y) left_join(x, y, by = c("date")), .) %>%
#   mutate(eucr = round(na_interpolation(eucr, "stine"), digits = 5)) %>%
#   filter(date >= start_date & date <= stopp_date) %>%
#   mutate(
#     ex_rate = eucr/first(eucr),
#     ishares_l1_us_in_eu = ifelse(date >= "2009-10-20", na_interpolation(ishares_l1_us_in_eu, "stine"), NA),
#     ishares_l1_us_in_us = ishares_l1_us_in_eu/ex_rate)
#   
# 
# search_grid <- seq(-0.1, 0.1, by = 1e-4)
# search_data <- sapply(search_grid, function(search_value){
#   msci_full_data %>% 
#     filter(date >= "2009-10-20") %>% # <- Erster Handelstag realer ETF
#     mutate(
#       expense = 0.2, # <- Hier: Angabe TER
#       msci_return = world_us_ndtr_l1/lag(world_us_ndtr_l1),  # <- Basisindex
#       sims_return = (msci_return - (((expense/100 + 1)^(1/days) - 1) + (search_value/100))),
#       sims_fonds = Reduce(function(values, rates){values * rates}, 
#                           lead(sims_return), init = 100, accumulate = TRUE)[-nrow(.)],
#       ishares_l1_us_in_us = ishares_l1_us_in_us/first(ishares_l1_us_in_us) * 100,
#       error = (1 - sims_fonds/ishares_l1_us_in_us)) %>%
#     pull(error)})
# 
# search_metrics(search_data, search_grid)
# rm(search_data, search_grid)
# 
# 
# #---> Simulation ungehebelter Referenz:
# msci_sims_data <- msci_full_data %>%
#   mutate(
#     ter_l1 = 0.2,
#     index_l1_return = world_us_ndtr_l1/lag(world_us_ndtr_l1),
#     fonds_l1_return = ishares_l1_us_in_us/lag(ishares_l1_us_in_us),
#     sim_l1_return = ifelse(date <= "2009-10-20",
#                            index_l1_return - ((ter_l1/100 + 1)^(1/days) - 1) - 0.0003/100,
#                            fonds_l1_return),
#     sim_l1 = Reduce(function(values, rates){values*rates},
#                     lead(sim_l1_return), init = 100, accumulate = TRUE)[-nrow(.)],
#     sim_l1 = case_when(row_number() == n() ~ round(lag(sim_l1)*sim_l1_return, digits = 2), TRUE ~ sim_l1),
#     world_sim_l1 = sim_l1*ex_rate) %>%
#   select(date, world_sim_l1) %>%
#   filter(date <= stopp_date)
# 
# write.csv(msci_sims_data, "./03 Results Data/01 Equity Indicies/Reference World.csv", row.names =FALSE)
# ########################################################################################################################
# # Bereinigung des Workspace
# ########################################################################################################################
# rm(list = ls())

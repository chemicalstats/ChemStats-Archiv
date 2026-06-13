########################################################################################################################
# Vorbereitung des Systems
########################################################################################################################
packages <- c("tidyverse", "imputeTS", "openxlsx", "modelr", "plotly", "mgcv", "httr", "jsonlite", "htmlwidgets")
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
start_date <- "1987-12-29"
stopp_date <- "2026-05-30"


########################################################################################################################
# Backcast des MSCI All-Country World Price Return Index
########################################################################################################################
#---> 1. Tägliche Price Return Indices MSCI World und MSCI Emerging Markets:
world_em <- left_join(
  read.csv("https://raw.githubusercontent.com/chemicalstats/ChemStats-Archiv/refs/heads/main/02%20Project%20Gloverage/03%20Results%20Data/01%20Equity%20Indicies/MSCI%20World%20USD.csv") %>%
    mutate(date = as.Date(date), world_price = world_us_price),
  read.csv("https://raw.githubusercontent.com/chemicalstats/ChemStats-Archiv/refs/heads/main/02%20Project%20Gloverage/03%20Results%20Data/01%20Equity%20Indicies/MSCI%20Emerging%20USD.csv") %>%
    mutate(date = as.Date(date), em_price = emerging_us_price),
  by = "date") %>%
  filter(date >= "1987-12-31")

#---> 2. Monatliche ACWI-Stände für die Gewichtsschätzung (MSCI-Endpunkt, STRD USD):
monthly_acwi <- read.csv("https://raw.githubusercontent.com/NandayDev/MSCI-Historical-Data/main/indexes_gross/MSCI%20ACWI.csv") %>%
  rename(ym = Date, acwi_price = Price) %>%
  filter(ym <= "2001-11")

#---> 3. Implizites EM-Gewicht via Varying-Coefficient GAM:
weights_monthly <- world_em %>%
  group_by(ym = format(date, "%Y-%m")) %>%
  slice_tail(n = 1) %>%
  ungroup() %>%
  inner_join(monthly_acwi, by = "ym") %>%
  mutate(
    t = as.numeric(date - first(date)) / 365.25,
    d_acwi = (acwi_price/lag(acwi_price) - 1) - (world_price/lag(world_price) - 1),
    d_em = (em_price/lag(em_price) - 1) - (world_price/lag(world_price) - 1))

w_gam <- gam(d_acwi ~ 0 + s(t, by = d_em, k = 12), data = weights_monthly, method = "REML")

#---> 4. Täglicher Blend-Return und Backward Chaining per ACWI-Anker:
acwi_anchor <- scraping_index(code = "892400", type = "STRD", currency = "USD", freq = "DAILY",
                              start = "19970101", stopp = "19970110") %>%
  mutate(date = as.Date(as.character(calc_date), format = "%Y%m%d")) %>%
  slice_min(date)

acwi_blend <- world_em %>%
  filter(date <= acwi_anchor$date) %>%
  mutate(
    t = as.numeric(date - first(weights_monthly$date)) / 365.25,
    w = pmax(predict(w_gam, newdata = data.frame(t = t, d_em = 1)), 0),
    ret = (1 - w) * (world_price/lag(world_price)) + w * (em_price/lag(em_price)),
    ret = replace_na(ret, 1),
    blend_price = acwi_anchor$level_eod / rev(cumprod(rev(c(ret[-1], 1))))) %>%
  select(date, blend_price)


########################################################################################################################
# Initialisierung Index-Zeitreihen
########################################################################################################################
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
  read.csv("./01 Source Data/EuroStat Historic Bilateral Exchange Rates.csv") %>%
    filter(Currency == "US dollar") %>%
    mutate(
      date = as.Date(TIME_PERIOD, format="%Y-%m-%d"),
      eucr = 1 / OBS_VALUE) %>%
    filter(date >= start_date & date <= stopp_date) %>%
    select(date, eucr),
  #---> 3. Integration der US-Interbanken-Zinssätze (Effective Federal Funds Rate und Secured Overnight Financing Rate):
  read.xlsx("./01 Source Data/FRED Effective Fedral Funds Rate RIFSPFFNB.xlsx", sheet = 2) %>%
    rename(date = observation_date, effr = RIFSPFFNB) %>%
    mutate(date = as.Date(date, origin = "1899-12-30")),
  read.xlsx("./01 Source Data/FRED Secured Overnight Financing Rate SOFR.xlsx", sheet = 2) %>%
    rename(date = observation_date, sofr = SOFR) %>%
    mutate(date = as.Date(date, origin = "1899-12-30")),
  #---> 4. Integration des MSCI All-Country World in den USD-Varianten Price, Gross Total und Net Total Return:
  list(
   data.frame(date = seq.Date(from = as.Date(start_date),
                             to = as.Date(paste0(year(Sys.Date()), "-12-31")),
                             by = "days")),
    acwi_blend %>% select(date, price_external = blend_price),
    scraping_index(code = "892400", type = "STRD", currency = "USD", freq = "DAILY",
                  start = gsub("-", "", "19970101"), stopp = gsub("-", "", stopp_date)) %>%
      mutate(date = as.Date(as.character(calc_date), format = "%Y%m%d"), price_internal = level_eod) %>%
      select(date, price_internal)) %>%
   Reduce(function(x, y) left_join(x, y, by = "date"), .) %>%
    mutate(real_price = ifelse(!is.na(price_internal), price_internal, price_external)) %>%
    select(date, real_price),
  scraping_index(code = "892400", type = "GRTR", currency = "USD", freq = "DAILY",
                 start = gsub("-", "", "19970101"), stopp = gsub("-", "", stopp_date)) %>%
    mutate(date = as.Date(as.character(calc_date), format = "%Y%m%d"), real_gdtr_l1 = level_eod) %>%
    select(date, real_gdtr_l1),
  scraping_index(code = "892400", type = "NETR", currency = "USD", freq = "DAILY",
                 start = gsub("-", "", "19970101"), stopp = gsub("-", "", stopp_date)) %>%
    mutate(date = as.Date(as.character(calc_date), format = "%Y%m%d"), real_ndtr_l1 = level_eod) %>%
    select(date, real_ndtr_l1),
   #---> 5. Integration des Leverage MSCI All-Country World Index für den USD-Gross Total Return:
  read.table("https://app2.msci.com/eqb/short/performance/90481.49.all.xls", sep = ",", skip = 4) %>%
    filter(grepl("\t", V1)) %>%
    separate_wider_delim(V1, delim = "\t", names = c("date", "real_gdtr_l2"), too_few = "align_start") %>%
    mutate(
      date = as.Date(date, format = "%m/%d/%Y"),
      real_gdtr_l2 = as.numeric(real_gdtr_l2))) %>%
  Reduce(function(x, y) left_join(x, y, by = "date"), .) %>%
  filter(date <= stopp_date) %>% 
  #---> 6. Berechnung der Indexrenditen und Erweiterung der Simulationen:
  mutate(
    real_price =  ifelse(date  >= "1997-01-01", na_interpolation(real_price, "stine"), real_price),
    real_price_return = real_price/lag(real_price),
    real_gdtr_l1 = ifelse(date  >= "2000-12-29", na_interpolation(real_gdtr_l1, "stine"), NA),
    real_gdtr_l1_return = real_gdtr_l1/lag(real_gdtr_l1),
    real_ndtr_l1 = ifelse(date >= "2000-12-29", na_interpolation(real_ndtr_l1, "stine"), NA),
    real_ndtr_l1_return = real_ndtr_l1/lag(real_ndtr_l1),
    real_gdtr_l2 = ifelse(date >= "2000-12-29", na_interpolation(real_gdtr_l2, "stine"), NA),
    real_gdtr_l2_return = real_gdtr_l2/lag(real_gdtr_l2)) %>%
  #--------> 8. Zins- und Wechselkurse:
  mutate(
    us_rate = na_interpolation(ifelse(date <= "2021-07-31", effr, sofr), "stine"),
    us_rate = round(us_rate, digits = 3),
    eucr = round(na_interpolation(eucr, "stine"), digits = 5)) %>%
  filter(date >= "1988-01-01")


########################################################################################################################
# Vervollständigung der Indexvarianten
########################################################################################################################
msci_model <- msci_data %>%
  #---> 1. USD Gross Total Return:
  add_predictions(gam(real_gdtr_l1_return ~ s(real_price_return), data = .), var = "sim_gdtr_l1_return") %>%
  mutate(
    sim_gdtr_l1_return = ifelse(date < "2000-12-29" | is.na(real_gdtr_l1_return), sim_gdtr_l1_return, real_gdtr_l1_return),
    sim_gdtr_l1 = ifelse(date < "2000-12-29",
                        rev(Reduce(function(values, rates){values/rates}, rev(sim_gdtr_l1_return), init = last(real_gdtr_l1), accumulate = TRUE)[-nrow(.)]),
                        real_gdtr_l1),
    sim_gdtr_l1 = ifelse(row_number() == 1, round(lead(sim_gdtr_l1)/lead(sim_gdtr_l1_return), digits = 5), round(sim_gdtr_l1, digits = 5))) %>%
  #---> 2. USD Net Total Return:
  add_predictions(gam(real_ndtr_l1_return ~ s(real_price_return), data = .), var = "sim_ndtr_l1_return") %>%
  mutate(
    sim_ndtr_l1_return = ifelse(date < "2000-12-29" | is.na(real_ndtr_l1_return), sim_ndtr_l1_return, real_ndtr_l1_return),
    sim_ndtr_l1 = ifelse(date < "2000-12-29",
                        rev(Reduce(function(values, rates){values/rates}, rev(sim_ndtr_l1_return), init = last(real_ndtr_l1), accumulate = TRUE)[-nrow(.)]),
                        real_ndtr_l1),
    sim_ndtr_l1 = ifelse(row_number() == 1, round(lead(sim_ndtr_l1)/lead(sim_ndtr_l1_return), digits = 5), round(sim_ndtr_l1, digits = 5)),
  #---> 3. USD Price Return:
    sim_price = real_price,
    sim_price_return = real_price_return) %>%
  select(date, days, us_rate, eucr, sim_price, sim_price_return, 
         sim_gdtr_l1, sim_gdtr_l1_return, real_gdtr_l2, real_gdtr_l2_return, 
         sim_ndtr_l1, sim_ndtr_l1_return) %>%
  filter(date >= start_date)


#---> Initialisierung des Grid-Search-Algorithmus:
search_grid <- seq(-0.1, 0.1, by = 1e-4)
search_data <- msci_model %>% filter(date >= "2000-12-29" & date <= stopp_date)

search_results <- sapply(search_grid, function(search_value){
  search_data %>%
    mutate(
      real_gdtr_l2 = Reduce(function(values, rates){values*rates},
                            lead(real_gdtr_l2_return), init = 100, accumulate = TRUE)[-nrow(.)],
      model_gdtr_l2_return = (2*sim_gdtr_l1_return + (1-2)*(us_rate/100)*(1/days) - 1) + (search_value/100),
      real_gdtr_l2_stat = Reduce(function(values, rates){values*rates},
                                 lead(model_gdtr_l2_return), init = 100, accumulate = TRUE)[-nrow(.)],
      error = 1 - (real_gdtr_l2_stat/real_gdtr_l2)) %>%
    pull(error)})

search_metrics(search_results, search_grid)
rm(search_results, search_data, search_grid)


#---> Finalisierung der Index-Zeitreihen:
msci_final <- msci_model %>%
  mutate(
    sim_gdtr_l2_return = ifelse(date <= "2000-12-29",
                                ((2*sim_gdtr_l1_return + (1-2)*(us_rate/100)*(1/days)) - 1) - (0.0015/100),
                                real_gdtr_l2_return),
    sim_gdtr_l2 = round(Reduce(function(values, rates){values*rates}, 
                        lead(sim_gdtr_l2_return), init = 100, accumulate = TRUE)[-nrow(.)], digits = 5),
    sim_gdtr_l2 = case_when(row_number() == n() ~ round(lag(sim_gdtr_l2)*sim_gdtr_l2_return, digits = 2), TRUE ~ sim_gdtr_l2),
    sim_ndtr_l2_return = ((2*sim_ndtr_l1_return + (1-2)*(us_rate/100)*(1/days)) - 1) - (0.0015/100),
    sim_ndtr_l2 = round(Reduce(function(values, rates){values*rates},
                        lead(sim_ndtr_l2_return), init = 100, accumulate = TRUE)[-nrow(.)], digits = 5),
    sim_ndtr_l2 = case_when(row_number() == n() ~ round(lag(sim_ndtr_l2)*sim_ndtr_l2_return, digits = 2), TRUE ~ sim_ndtr_l2)) %>%
    select(date, days, eucr, starts_with("sim_"), -ends_with("_return")) %>%
    mutate(across(-c(date, days, eucr), ~ .x/first(.x) * 100))


########################################################################################################################
# Visualisierung der Indexvarianten
########################################################################################################################
msci_final %>%
  select(date, sim_price, sim_gdtr_l1, sim_ndtr_l1, sim_gdtr_l2, sim_ndtr_l2) %>%
  mutate(across(where(is.numeric), function(x){x/first(x)})) %>%
  plot_ly(type = "scatter", mode = "lines") %>%
  add_trace(x = ~date, y = ~log(sim_price), name = "Price Return", line = list(width = 1)) %>%
  add_trace(x = ~date, y = ~log(sim_gdtr_l1), name = "Gross Total Return", line = list(width = 1)) %>%
  add_trace(x = ~date, y = ~log(sim_ndtr_l1), name = "Net Total Return", line = list(width = 1)) %>%
  add_trace(x = ~date, y = ~log(sim_gdtr_l2), name = "Gross Total Return x2", line = list(width = 1)) %>%
  add_trace(x = ~date, y = ~log(sim_ndtr_l2), name = "Net Total Return x2", line = list(width = 1)) %>%
  layout(
    showlegend = TRUE, legend = list(orientation = 'h'), 
    xaxis = list(title = "Time"),
    yaxis = list(title = "Log. Index Value (USD)", range = c(0, 5)),
    title = "MSCI All-Country World",
    margin = list(t = 50))


########################################################################################################################
# Export der Modellierung
########################################################################################################################
msci_final %>%
  mutate(
    letf_acwi_td = 0.5,
    letf_acwi_ter = 0.7,
    letf_acwi_return = sim_ndtr_l2/lag(sim_ndtr_l2),
    letf_acwi_return = letf_acwi_return - (((letf_acwi_td + letf_acwi_ter)/100 + 1)^(1/days) - 1),
    letf_acwi_usd_sim = Reduce(function(values, rates){values*rates}, lead(letf_acwi_return), init = 100, accumulate = TRUE)[-nrow(.)],
    letf_acwi_usd_sim = case_when(row_number() == n() ~ round(lag(letf_acwi_usd_sim)*letf_acwi_return, digits = 2), TRUE ~ letf_acwi_usd_sim),
    letf_acwi_eur_sim = letf_acwi_usd_sim * eucr,
    letf_acwi_usd_sim = letf_acwi_usd_sim/first(letf_acwi_usd_sim) * 100,
    letf_acwi_eur_sim = letf_acwi_eur_sim/first(letf_acwi_eur_sim) * 100) %>%
  select(-c(eucr, days, letf_acwi_td, letf_acwi_ter, letf_acwi_return)) %>%
  write.csv("./All-Country World Data.csv", row.names = FALSE)


########################################################################################################################
# Analyse der Risikoklassifizierung gemäß EU-Verordnung Nr. 1286/2014
########################################################################################################################
#---> 1. MRM-Tabelle (Anhang II, Ziffer 2)
vev_to_mrm <- function(vev){
  case_when(
    is.na(vev)  ~ NA,
    vev <  0.005 ~ 1L,
    vev <  0.05  ~ 2L,
    vev <  0.12  ~ 3L,
    vev <  0.20  ~ 4L,
    vev <  0.30  ~ 5L,
    vev <  0.80  ~ 6L,
    TRUE          ~ 7L
  )
}

#---> 2. VEV-Berechnung aus täglichen Log-Renditen (Anhang II, Ziffern 11–12)
calc_vev <- function(r, N = 252){
  r <- r[!is.na(r)]

  # Ziffer 11: Momente täglicher Renditeverteilung
  sigma <- sd(r)
  r_std <- (r - mean(r)) / sigma
  skew  <- mean(r_std^3)
  kurt  <- mean(r_std^4) - 3

  # Ziffer 11: Cornish-Fisher-VaR (97,5%-Niveau, linksseitig)
  z_cf <- -1.96 + (0.474  * skew  / sqrt(N)) - (0.0687 * kurt  / N) + (0.146  * skew^2 / N)
  var_cf <- sigma * sqrt(N) * z_cf - 0.5 * sigma^2 * N

  # Ziffer 12: VEV aus quadratischer Gleichung
  T_years <- N / 252
  inner <- 3.8416 - 2 * var_cf
  
  vev <- if(is.na(inner) || inner < 0){
    sigma * sqrt(252)
  } else {
    (sqrt(inner) - 1.96) / sqrt(T_years)
  }

  list(vev = vev, var_cf = var_cf, sigma = sigma, skew = skew, kurt = kurt)
}

#---> 3. Rollierende Market Risk Measures
mrm_rolling <- function(data, window = 1260, N = 252, step_days = 21){

  daily <- data %>%
    arrange(date) %>%
    filter(!is.na(price), price > 0) %>%
    mutate(log_ret = log(price / lag(price))) %>%
    filter(!is.na(log_ret))

  n <- nrow(daily)

  if(n < window){
    warning(sprintf("Nur %d Handelstage, Minimum %d benötigt.", n, window))
    return(tibble())
  }

  calc_indices <- seq(window, n, by = step_days)

  map_dfr(calc_indices, function(i){
    r_win <- daily$log_ret[(i - window + 1):i]
    res   <- calc_vev(r_win, N = N)

    data.frame(
      date = daily$date[i],
      vev = res$vev,
      mrm_class = vev_to_mrm(res$vev),
      sigma_ann = res$sigma * sqrt(252),
      skew = res$skew,
      kurt = res$kurt,
      n_obs = sum(!is.na(r_win))
    )
  })
}

#---> 4. Anwendung auf Simulationsdaten
msci_input <- read.csv("./All-Country World Data.csv") %>%
  mutate(date = as.Date(date)) %>%
  filter(!weekdays(date) %in% c("Saturday", "Sunday")) %>%
  select(date, price = letf_acwi_usd_sim) %>%
  filter(!is.na(price))

mrm_output <- mrm_rolling(data = msci_input, window = 1260, N = 1, step_days = 1)

#---> 5. Diagnose
mrm_output %>%
  plot_ly(x = ~date) %>%
   reduce(c(0.5, 5, 12, 20, 30, 80), function(p, val) {
    p %>% add_segments(
      x = min(mrm_output$date), xend = max(mrm_output$date),
      y = val, yend = val, yaxis = "y1",
      line = list(color = "black", width = 0.5),
      showlegend = FALSE)
  }, .init = .) %>%
  add_lines(y = ~vev * 100,  name = "VEV (%)",
            line = list(color = "steelblue", width = 1.5),
            yaxis = "y1") %>%
  add_lines(y = ~mrm_class, name = "MRM-Klasse",
            line = list(color = "firebrick", width = 2),
            yaxis = "y2") %>%
   layout(
    title = "Market Risk Measure (Daily Data): Leveraged MSCI ACWI Daily Swap Proxy\nAssumed Leverage Factor: x2 - Total Expense Ration: 0.7% - Additional Costs: 0.5%",
    xaxis  = list(title = "", nticks = 10),
    yaxis  = list(title = "VEV (%)", side = "left", showgrid = FALSE),
    yaxis2 = list(title = "MRM Class", side = "right",
                  overlaying = "y", tickvals = 1:7, range = c(0.5, 7.5), showgrid = FALSE),
    legend = list(orientation = "h"),
    margin = list(t = 50, r = 50))


########################################################################################################################
# Adaptiver Hebelfaktor für MRM-Klasse 5-Ziel
########################################################################################################################
vev_of_leverage <- function(L, sigma, skew, kurt, N = 1, ter = 0.7, td = 0.5, fin_rate = 0.04){
  sigma_L <- L * sigma
  cost_daily <- (ter/100 + td/100 + fin_rate * max(L - 1, 0)) / 252
  
  z_cf <- -1.96 + (0.474 * skew / sqrt(N)) -
          (0.0687 * kurt / N) + (0.146 * skew^2 / N)
  var_cf <- sigma_L * sqrt(N) * z_cf - 0.5 * sigma_L^2 * N - cost_daily * N
  
  T_years <- N / 252
  inner <- 3.8416 - 2 * var_cf
  if(is.na(inner) || inner < 0) return(NA)
  (sqrt(inner) - 1.96) / sqrt(T_years)
}


solve_leverage <- function(target_vev, sigma, skew, kurt, N = 1, ter = 0.7, td = 0.5, fin_rate = 0.04, L_range = c(0.1, 10)){
  f <- function(L) vev_of_leverage(L, sigma, skew, kurt, N, ter = ter, td = td, fin_rate = fin_rate) - target_vev
  tryCatch(
    uniroot(f, interval = L_range, tol = 1e-6)$root,
    error = function(e) NA)
}

leverage_for_mrm5 <- function(data, window = 1260, N = 1, step_days = 21, ter = 0.007, td = 0.005){
  daily <- data %>%
    arrange(date) %>%
    filter(!is.na(price), price > 0) %>%
    mutate(log_ret = log(price / lag(price))) %>%
    filter(!is.na(log_ret))

  n <- nrow(daily)
  if(n < window){ warning("Zu wenig Historie."); return(tibble())}

  calc_indices <- seq(window, n, by = step_days)

  map_dfr(calc_indices, function(i){
    r <- daily$log_ret[(i - window + 1):i]
    r <- r[!is.na(r)]
    
    sigma <- sd(r)
    r_std <- (r - mean(r)) / sigma
    skew <- mean(r_std^3)
    kurt <- mean(r_std^4) - 3
    
    fin_rate_window <- mean(daily$us_rate[(i - window + 1):i], na.rm = TRUE) / 100

    data.frame(
      date = daily$date[i],
      sigma_ann = sigma * sqrt(252),
      fin_rate = fin_rate_window,
      L_max_rk5 = solve_leverage(0.30, sigma, skew, kurt, N, ter = ter, td = td, fin_rate = fin_rate_window)
    )
  })
}

unleveraged_input <- list(
  read.csv("./All-Country World Data.csv") %>%
    mutate(date = as.Date(date)),
  read.xlsx("./01 Source Data/FRED Effective Fedral Funds Rate RIFSPFFNB.xlsx", sheet = 2) %>%
    rename(date = observation_date, effr = RIFSPFFNB) %>%
    mutate(date = as.Date(date, origin = "1899-12-30")),
  read.xlsx("./01 Source Data/FRED Secured Overnight Financing Rate SOFR.xlsx", sheet = 2) %>%
    rename(date = observation_date, sofr = SOFR) %>%
    mutate(date = as.Date(date, origin = "1899-12-30"))) %>%
  Reduce(function(x, y) left_join(x, y, by = "date"), .) %>%
  mutate(
    us_rate = na_interpolation(ifelse(date <= "2021-07-31", effr, sofr), "stine"),
    date = as.Date(date)) %>%
  filter(!weekdays(date) %in% c("Saturday", "Sunday")) %>%
  select(date, price = sim_ndtr_l1, us_rate) %>%
  filter(!is.na(price))

lev_corridor <- leverage_for_mrm5(unleveraged_input, window = 1260, N = 1, step_days = 1)

lev_corridor %>%
  plot_ly(x = ~date) %>%
  add_ribbons(ymin = ~0, ymax = ~L_max_rk5,
              name = "Zulässiger Hebel",
              fillcolor = "rgba(70,130,180,0.25)",
              line = list(color = "transparent")) %>%
  add_lines(y = ~L_max_rk5, name = "Max. L (VEV = 30%)",
            line = list(color = "firebrick", width = 1)) %>%
  add_segments(x = ~min(date), xend = ~max(date), y = 2, yend = 2,
               line = list(color = "gray40", dash = "dash", width = 1),
               name = "Konstanter Hebel 2x") %>%
  layout(
    title = "Adaptiver Hebelkorridor für Risikoklasse 5",
    yaxis = list(title = "Hebelfaktor L"),
    xaxis = list(title = ""),legend = list(orientation = "h"))
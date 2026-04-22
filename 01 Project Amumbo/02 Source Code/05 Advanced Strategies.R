########################################################################################################################
# Vorbereitung des Systems
########################################################################################################################
packages <- c("tidyverse", "tidyquant", "runner", "imputeTS", "foreach", "parallel", "doParallel", "doFuture", "data.table", "Rcpp", "myLeverage")
invisible(lapply(packages, library, character.only = TRUE)); rm(packages)

if(.Platform$OS.type == "windows"){Sys.setlocale("LC_ALL", "en_US.UTF-8")}

#---> Definition des Analysehorizonts:
start_date <- "1975-01-01"
stopp_date <- "2024-12-31"

#---> Vorbereitung der Analysedaten:
msci_letf <- list(
  read.csv("./Project Amumbo UCITS Funds.csv") %>%
    mutate(date = as.Date(date)),
  read.csv("./Project Amumbo Bond Yields.csv") %>%
    mutate(date = as.Date(date, format = "%Y-%m-%d")) %>%
    filter(!weekdays(date) %in% c("Saturday", "Sunday"),
           month(date) == 1,
           day(date) != 1) %>% 
    group_by(year = year(date)) %>%
    slice_min(date) %>%
    ungroup() %>%
    filter(date >= start_date & date <= stopp_date) %>%
    select(date, rate = m15)) %>%
  Reduce(function(x, y) left_join(x, y, by = "date"), .) %>%
  mutate(rate = na_locf(rate)) %>%
  filter(date >= start_date & date <= stopp_date)

configs <- list(
  list(name = "No Taxes", tax_mode = "none", spread = 0.5),
  list(name = "German Taxes", tax_mode = "person", spread = 0.5),
  list(name = "Fund Fees", tax_mode = "funds", spread = 0)
)

no_cores <- detectCores() - 1


########################################################################################################################
# Long Lump Sum Simple Moving Average-Strategien USD Index
########################################################################################################################
strategy <- list(
  letf = list(
    asset_share = 1,
    asset_class = "etf", asset_bonus = 0.3,
    action_type = "sma", action_dcas = "hold",
    signal_buy = "buy", signal_sell = "sell"
  )
)

params <- expand.grid(sma = seq(10, 600, by = 10), span = seq(10, 40, by = 10))
params <- params[order(params$span, params$sma), ]

sim_clust <- makeCluster(no_cores)
registerDoParallel(sim_clust)
#---> Long x2
for(row in 1:nrow(params)){
  date_ranges <- create_sequences(as.character(msci_letf$date), span = params[row, "span"], signal_a = params[row, "sma"])
  
  for(config in configs){
    results <- foreach(n = 1:nrow(date_ranges), .combine = rbind, .packages = c("tidyverse", "tidyquant", "imputeTS", "myLeverage"),
                       .options.future = list(chunk.size = ceiling(nrow(date_ranges)/no_cores * 1.5))) %dopar% {
      data <- msci_letf %>%
        mutate(signal = SMA(us_index_l1, params[row, "sma"])) %>%
        filter(date >= date_ranges[n, 1] & date <= date_ranges[n, 2]) %>%
        mutate(
          signal = signal / first(us_index_l1) * 100,
          index = us_index_l1 / first(us_index_l1) * 100,
          letf = sim_l2,
          buy = index >= signal,
          sell = index < signal) %>%
        select(date, letf, buy, sell, rate)
                         
      sim_results <- simulation(data, strategy,
                                start_value = 1000, spread = config$spread, details = FALSE, liquidate = FALSE,
                                dca_mode = FALSE, dca_value = NULL, dca_span = NULL, dca_day = NULL, dca_unit = "month",
                                balance_mode = FALSE, balance_span = NULL, balance_day = NULL, balance_unit = "month",
                                balance_dca = FALSE, tax_mode = config$tax_mode, tax_rate = 0.26375,
                                base_rate = NULL, base_rate_flex = TRUE, base_rate_data = "rate",
                                fractions = TRUE, split_mode = FALSE, split_tresh = NULL, funds_fee = 1, bonus_fee = 5)
                         
      c(date_ranges[n, 1], date_ranges[n, 2], params[row, "sma"], sim_results$ttwror, sim_results$statistics$mean, sim_results$statistics$sd, sim_results$statistics$cv,
        sim_results$statistics$skewness, sim_results$statistics$kurtosis, sim_results$statistics$lpm, sim_results$statistics$hpm,
        quantile(sim_results$drawdowns, probs = seq(0, 1, by = 0.1)))}
    
    results <- as.data.frame(results)
    colnames(results) <- c("Start_Date", "Stopp_Date", "SMA", "TTWROR", "Return_Mean", "Return_Std", "Return_CV",
                           "Return_Skewness", "Return_Kurtosis", "Return_LPM", "Return_HPM",
                           paste0(c("Min", seq(10, 90, by = 10), "Max"), "_DD"))
    results <- transform(results, Start_Date = as.Date(Start_Date), Stopp_Date = as.Date(Stopp_Date))
    
    fwrite(results, paste0("./03 Results Data/05 Moving Average - Alt Signal/Lump Sum - Long x2 - USD - SMA ", params[row, "sma"], " - ", config$name, " - ", params[row, "span"], " Years.csv"), row.names = FALSE)
  }
}
stopCluster(sim_clust)


########################################################################################################################
# Long Dollar Cost Averaging Exponential Moving Average-Strategien USD Index
########################################################################################################################
strategy <- list(
  letf = list(
    asset_share = 1,
    asset_class = "etf", asset_bonus = 0.3,
    action_type = "sma", action_dcas = "hold",
    signal_buy = "buy", signal_sell = "sell"
  )
)

params <- expand.grid(sma = seq(10, 600, by = 10), span = seq(10, 40, by = 10))
params <- params[order(params$span, params$sma), ]

sim_clust <- makeCluster(no_cores)
registerDoParallel(sim_clust)
#---> Long x2
for(row in 1:nrow(params)){
  date_ranges <- create_sequences(as.character(msci_letf$date), span = params[row, "span"], signal_a = params[row, "sma"])
  
  for(config in configs){
    results <- foreach(n = 1:nrow(date_ranges), .combine = rbind, .packages = c("tidyverse", "tidyquant", "imputeTS", "myLeverage"),
                       .options.future = list(chunk.size = ceiling(nrow(date_ranges)/no_cores * 1.5))) %dopar% {
      data <- msci_letf %>%
        mutate(signal = SMA(us_index_l1, params[row, "sma"])) %>%
        filter(date >= date_ranges[n, 1] & date <= date_ranges[n, 2]) %>%
        mutate(
          signal = signal / first(us_index_l1) * 100,
          index = us_index_l1 / first(us_index_l1) * 100,
          letf = sim_l2,
          buy = index >= signal,
          sell = index < signal) %>%
        select(date, letf, buy, sell, rate)
                         
      sim_results <- simulation(data, strategy,
                                start_value = 1000, spread = config$spread, details = FALSE, liquidate = FALSE,
                                dca_mode = TRUE, dca_value = 1000, dca_span = 1, dca_day = 1, dca_unit = "month",
                                balance_mode = FALSE, balance_span = NULL, balance_day = NULL, balance_unit = "month",
                                balance_dca = FALSE, tax_mode = config$tax_mode, tax_rate = 0.26375,
                                base_rate = NULL, base_rate_flex = TRUE, base_rate_data = "rate",
                                fractions = TRUE, split_mode = FALSE, split_tresh = NULL, funds_fee = 1, bonus_fee = 5)
                         
      c(date_ranges[n, 1], date_ranges[n, 2], params[row, "sma"], sim_results$ttwror, sim_results$statistics$mean, sim_results$statistics$sd, sim_results$statistics$cv,
        sim_results$statistics$skewness, sim_results$statistics$kurtosis, sim_results$statistics$lpm, sim_results$statistics$hpm,
        quantile(sim_results$drawdowns, probs = seq(0, 1, by = 0.1)))}
    
    results <- as.data.frame(results)
    colnames(results) <- c("Start_Date", "Stopp_Date", "SMA", "TTWROR", "Return_Mean", "Return_Std", "Return_CV",
                           "Return_Skewness", "Return_Kurtosis", "Return_LPM", "Return_HPM",
                           paste0(c("Min", seq(10, 90, by = 10), "Max"), "_DD"))
    results <- transform(results, Start_Date = as.Date(Start_Date), Stopp_Date = as.Date(Stopp_Date))
    
    fwrite(results, paste0("./03 Results Data/05 Moving Average - Alt Signal/DCA Hold - Long x2 - USD - SMA ", params[row, "sma"], " - ", config$name, " - ", params[row, "span"], " Years.csv"), row.names = FALSE)
  }
}
stopCluster(sim_clust)


########################################################################################################################
# Short Lump Sum Simple Moving Average-Strategien EUR Index
########################################################################################################################
strategy <- list(
  letf = list(
    asset_share = 1,
    asset_class = "etf", asset_bonus = 0.3,
    action_type = "sma", action_dcas = "hold",
    signal_buy = "buy", signal_sell = "sell"
  )
)

params <- expand.grid(sma = seq(10, 600, by = 10), span = seq(10, 40, by = 10))
params <- params[order(params$span, params$sma), ]

sim_clust <- makeCluster(no_cores)
registerDoParallel(sim_clust)
#---> Short x2
for(row in 1:nrow(params)){
  date_ranges <- create_sequences(as.character(msci_letf$date), span = params[row, "span"], signal_a = params[row, "sma"])
  
  for(config in configs){
    results <- foreach(n = 1:nrow(date_ranges), .combine = rbind, .packages = c("tidyverse", "tidyquant", "imputeTS", "myLeverage"),
                       .options.future = list(chunk.size = ceiling(nrow(date_ranges)/no_cores * 1.5))) %dopar% {
      data <- msci_letf %>%
        mutate(signal = SMA(eu_index_l1, params[row, "sma"])) %>%
        filter(date >= date_ranges[n, 1] & date <= date_ranges[n, 2]) %>%
        mutate(
          signal = signal / first(eu_index_l1) * 100,
          index = eu_index_l1 / first(eu_index_l1) * 100,
          letf = sim_s2,
           buy = index < signal,
          sell = index >= signal) %>%
        select(date, letf, buy, sell, rate)
                         
      sim_results <- simulation(data, strategy,
                                start_value = 1000, spread = config$spread, details = FALSE, liquidate = FALSE,
                                dca_mode = FALSE, dca_value = NULL, dca_span = NULL, dca_day = NULL, dca_unit = "month",
                                balance_mode = FALSE, balance_span = NULL, balance_day = NULL, balance_unit = "month",
                                balance_dca = FALSE, tax_mode = config$tax_mode, tax_rate = 0.26375,
                                base_rate = NULL, base_rate_flex = TRUE, base_rate_data = "rate",
                                fractions = TRUE, split_mode = FALSE, split_tresh = NULL, funds_fee = 1, bonus_fee = 5)
                         
      c(date_ranges[n, 1], date_ranges[n, 2], params[row, "sma"], sim_results$ttwror, sim_results$statistics$mean, sim_results$statistics$sd, sim_results$statistics$cv,
        sim_results$statistics$skewness, sim_results$statistics$kurtosis, sim_results$statistics$lpm, sim_results$statistics$hpm,
        quantile(sim_results$drawdowns, probs = seq(0, 1, by = 0.1)))}
    
    results <- as.data.frame(results)
    colnames(results) <- c("Start_Date", "Stopp_Date", "SMA", "TTWROR", "Return_Mean", "Return_Std", "Return_CV",
                           "Return_Skewness", "Return_Kurtosis", "Return_LPM", "Return_HPM",
                           paste0(c("Min", seq(10, 90, by = 10), "Max"), "_DD"))
    results <- transform(results, Start_Date = as.Date(Start_Date), Stopp_Date = as.Date(Stopp_Date))
    
    fwrite(results, paste0("./03 Results Data/05 Moving Average - Alt Signal/Lump Sum - Short x2 - EUR - SMA ", params[row, "sma"], " - ", config$name, " - ", params[row, "span"], " Years.csv"), row.names = FALSE)
  }
}
stopCluster(sim_clust)


########################################################################################################################
# Short Dollar Cost Averaging Exponential Moving Average-Strategien EUR Index
########################################################################################################################
strategy <- list(
  letf = list(
    asset_share = 1,
    asset_class = "etf", asset_bonus = 0.3,
    action_type = "sma", action_dcas = "hold",
    signal_buy = "buy", signal_sell = "sell"
  )
)

params <- expand.grid(sma = seq(10, 600, by = 10), span = seq(10, 40, by = 10))
params <- params[order(params$span, params$sma), ]

sim_clust <- makeCluster(no_cores)
registerDoParallel(sim_clust)
#---> Short x2
for(row in 1:nrow(params)){
  date_ranges <- create_sequences(as.character(msci_letf$date), span = params[row, "span"], signal_a = params[row, "sma"])
  
  for(config in configs){
    results <- foreach(n = 1:nrow(date_ranges), .combine = rbind, .packages = c("tidyverse", "tidyquant", "imputeTS", "myLeverage"),
                       .options.future = list(chunk.size = ceiling(nrow(date_ranges)/no_cores * 1.5))) %dopar% {
      data <- msci_letf %>%
        mutate(signal = SMA(eu_index_l1, params[row, "sma"])) %>%
        filter(date >= date_ranges[n, 1] & date <= date_ranges[n, 2]) %>%
        mutate(
          signal = signal / first(eu_index_l1) * 100,
          index = eu_index_l1 / first(eu_index_l1) * 100,
          letf = sim_s2,
          buy = index < signal,
          sell = index >= signal) %>%
        select(date, letf, buy, sell, rate)
                         
      sim_results <- simulation(data, strategy,
                                start_value = 1000, spread = config$spread, details = FALSE, liquidate = FALSE,
                                dca_mode = TRUE, dca_value = 1000, dca_span = 1, dca_day = 1, dca_unit = "month",
                                balance_mode = FALSE, balance_span = NULL, balance_day = NULL, balance_unit = "month",
                                balance_dca = FALSE, tax_mode = config$tax_mode, tax_rate = 0.26375,
                                base_rate = NULL, base_rate_flex = TRUE, base_rate_data = "rate",
                                fractions = TRUE, split_mode = FALSE, split_tresh = NULL, funds_fee = 1, bonus_fee = 5)
                         
      c(date_ranges[n, 1], date_ranges[n, 2], params[row, "sma"], sim_results$ttwror, sim_results$statistics$mean, sim_results$statistics$sd, sim_results$statistics$cv,
        sim_results$statistics$skewness, sim_results$statistics$kurtosis, sim_results$statistics$lpm, sim_results$statistics$hpm,
        quantile(sim_results$drawdowns, probs = seq(0, 1, by = 0.1)))}
    
    results <- as.data.frame(results)
    colnames(results) <- c("Start_Date", "Stopp_Date", "SMA", "TTWROR", "Return_Mean", "Return_Std", "Return_CV",
                           "Return_Skewness", "Return_Kurtosis", "Return_LPM", "Return_HPM",
                           paste0(c("Min", seq(10, 90, by = 10), "Max"), "_DD"))
    results <- transform(results, Start_Date = as.Date(Start_Date), Stopp_Date = as.Date(Stopp_Date))
    
    fwrite(results, paste0("./03 Results Data/05 Moving Average - Alt Signal/DCA Hold - Short x2 - EUR - SMA ", params[row, "sma"], " - ", config$name, " - ", params[row, "span"], " Years.csv"), row.names = FALSE)
  }
}
stopCluster(sim_clust)


########################################################################################################################
# Long Lump Sum Exponential Moving Average-Strategien USD Index
########################################################################################################################
strategy <- list(
  letf = list(
    asset_share = 1,
    asset_class = "etf", asset_bonus = 0.3,
    action_type = "sma", action_dcas = "hold",
    signal_buy = "buy", signal_sell = "sell"
  )
)

params <- expand.grid(ema = seq(10, 600, by = 10), span = seq(10, 40, by = 10))
params <- params[order(params$span, params$ema), ]

sim_clust <- makeCluster(no_cores)
registerDoParallel(sim_clust)
#---> Long x2
for(row in 1:nrow(params)){
  date_ranges <- create_sequences(as.character(msci_letf$date), span = params[row, "span"], signal_a = params[row, "ema"])
  
  for(config in configs){
    results <- foreach(n = 1:nrow(date_ranges), .combine = rbind, .packages = c("tidyverse", "tidyquant", "imputeTS", "myLeverage"),
                       .options.future = list(chunk.size = ceiling(nrow(date_ranges)/no_cores * 1.5))) %dopar% {
      data <- msci_letf %>%
        mutate(signal = EMA(us_index_l1, params[row, "ema"])) %>%
        filter(date >= date_ranges[n, 1] & date <= date_ranges[n, 2]) %>%
        mutate(
          signal = signal / first(us_index_l1) * 100,
          index = us_index_l1 / first(us_index_l1) * 100,
          letf = sim_l2,
          buy = index >= signal,
          sell = index < signal) %>%
        select(date, letf, buy, sell, rate)
                         
      sim_results <- simulation(data, strategy,
                                start_value = 1000, spread = config$spread, details = FALSE, liquidate = FALSE,
                                dca_mode = FALSE, dca_value = NULL, dca_span = NULL, dca_day = NULL, dca_unit = "month",
                                balance_mode = FALSE, balance_span = NULL, balance_day = NULL, balance_unit = "month",
                                balance_dca = FALSE, tax_mode = config$tax_mode, tax_rate = 0.26375,
                                base_rate = NULL, base_rate_flex = TRUE, base_rate_data = "rate",
                                fractions = TRUE, split_mode = FALSE, split_tresh = NULL, funds_fee = 1, bonus_fee = 5)
                         
      c(date_ranges[n, 1], date_ranges[n, 2], params[row, "ema"], sim_results$ttwror, sim_results$statistics$mean, sim_results$statistics$sd, sim_results$statistics$cv,
        sim_results$statistics$skewness, sim_results$statistics$kurtosis, sim_results$statistics$lpm, sim_results$statistics$hpm,
        quantile(sim_results$drawdowns, probs = seq(0, 1, by = 0.1)))}
    
    results <- as.data.frame(results)
    colnames(results) <- c("Start_Date", "Stopp_Date", "EMA", "TTWROR", "Return_Mean", "Return_Std", "Return_CV",
                           "Return_Skewness", "Return_Kurtosis", "Return_LPM", "Return_HPM",
                           paste0(c("Min", seq(10, 90, by = 10), "Max"), "_DD"))
    results <- transform(results, Start_Date = as.Date(Start_Date), Stopp_Date = as.Date(Stopp_Date))
    
    fwrite(results, paste0("./03 Results Data/05 Moving Average - Alt Signal/Lump Sum - Long x2 - USD - EMA ", params[row, "ema"], " - ", config$name, " - ", params[row, "span"], " Years.csv"), row.names = FALSE)
  }
}
stopCluster(sim_clust)


########################################################################################################################
# Long Dollar Cost Averaging Exponential Moving Average-Strategien USD Index
########################################################################################################################
strategy <- list(
  letf = list(
    asset_share = 1,
    asset_class = "etf", asset_bonus = 0.3,
    action_type = "sma", action_dcas = "hold",
    signal_buy = "buy", signal_sell = "sell"
  )
)

params <- expand.grid(ema = seq(10, 600, by = 10), span = seq(10, 40, by = 10))
params <- params[order(params$span, params$ema), ]

sim_clust <- makeCluster(no_cores)
registerDoParallel(sim_clust)
#---> Long x2
for(row in 1:nrow(params)){
  date_ranges <- create_sequences(as.character(msci_letf$date), span = params[row, "span"], signal_a = params[row, "ema"])
  
  for(config in configs){
    results <- foreach(n = 1:nrow(date_ranges), .combine = rbind, .packages = c("tidyverse", "tidyquant", "imputeTS", "myLeverage"),
                       .options.future = list(chunk.size = ceiling(nrow(date_ranges)/no_cores * 1.5))) %dopar% {
      data <- msci_letf %>%
        mutate(signal = EMA(us_index_l1, params[row, "ema"])) %>%
        filter(date >= date_ranges[n, 1] & date <= date_ranges[n, 2]) %>%
        mutate(
          signal = signal / first(us_index_l1) * 100,
          index = us_index_l1 / first(us_index_l1) * 100,
          letf = sim_l2,
          buy = index >= signal,
          sell = index < signal) %>%
        select(date, letf, buy, sell, rate)
                         
      sim_results <- simulation(data, strategy,
                                start_value = 1000, spread = config$spread, details = FALSE, liquidate = FALSE,
                                dca_mode = TRUE, dca_value = 1000, dca_span = 1, dca_day = 1, dca_unit = "month",
                                balance_mode = FALSE, balance_span = NULL, balance_day = NULL, balance_unit = "month",
                                balance_dca = FALSE, tax_mode = config$tax_mode, tax_rate = 0.26375,
                                base_rate = NULL, base_rate_flex = TRUE, base_rate_data = "rate",
                                fractions = TRUE, split_mode = FALSE, split_tresh = NULL, funds_fee = 1, bonus_fee = 5)
                         
      c(date_ranges[n, 1], date_ranges[n, 2], params[row, "ema"], sim_results$ttwror, sim_results$statistics$mean, sim_results$statistics$sd, sim_results$statistics$cv,
        sim_results$statistics$skewness, sim_results$statistics$kurtosis, sim_results$statistics$lpm, sim_results$statistics$hpm,
        quantile(sim_results$drawdowns, probs = seq(0, 1, by = 0.1)))}
    
    results <- as.data.frame(results)
    colnames(results) <- c("Start_Date", "Stopp_Date", "EMA", "TTWROR", "Return_Mean", "Return_Std", "Return_CV",
                           "Return_Skewness", "Return_Kurtosis", "Return_LPM", "Return_HPM",
                           paste0(c("Min", seq(10, 90, by = 10), "Max"), "_DD"))
    results <- transform(results, Start_Date = as.Date(Start_Date), Stopp_Date = as.Date(Stopp_Date))
    
    fwrite(results, paste0("./03 Results Data/05 Moving Average - Alt Signal/DCA Hold - Long x2 - USD - EMA ", params[row, "ema"], " - ", config$name, " - ", params[row, "span"], " Years.csv"), row.names = FALSE)
  }
}
stopCluster(sim_clust)


########################################################################################################################
# Short Lump Sum Exponential Moving Average-Strategien EUR Index
########################################################################################################################
strategy <- list(
  letf = list(
    asset_share = 1,
    asset_class = "etf", asset_bonus = 0.3,
    action_type = "sma", action_dcas = "hold",
    signal_buy = "buy", signal_sell = "sell"
  )
)

params <- expand.grid(ema = seq(10, 600, by = 10), span = seq(10, 40, by = 10))
params <- params[order(params$span, params$ema), ]

sim_clust <- makeCluster(no_cores)
registerDoParallel(sim_clust)
#---> Short x2
for(row in 1:nrow(params)){
  date_ranges <- create_sequences(as.character(msci_letf$date), span = params[row, "span"], signal_a = params[row, "ema"])
  
  for(config in configs){
    results <- foreach(n = 1:nrow(date_ranges), .combine = rbind, .packages = c("tidyverse", "tidyquant", "imputeTS", "myLeverage"),
                       .options.future = list(chunk.size = ceiling(nrow(date_ranges)/no_cores * 1.5))) %dopar% {
      data <- msci_letf %>%
        mutate(signal = EMA(eu_index_l1, params[row, "ema"])) %>%
        filter(date >= date_ranges[n, 1] & date <= date_ranges[n, 2]) %>%
        mutate(
          signal = signal / first(eu_index_l1) * 100,
          index = eu_index_l1 / first(eu_index_l1) * 100,
          letf = sim_s2,
           buy = index < signal,
          sell = index >= signal) %>%
        select(date, letf, buy, sell, rate)
                         
      sim_results <- simulation(data, strategy,
                                start_value = 1000, spread = config$spread, details = FALSE, liquidate = FALSE,
                                dca_mode = FALSE, dca_value = NULL, dca_span = NULL, dca_day = NULL, dca_unit = "month",
                                balance_mode = FALSE, balance_span = NULL, balance_day = NULL, balance_unit = "month",
                                balance_dca = FALSE, tax_mode = config$tax_mode, tax_rate = 0.26375,
                                base_rate = NULL, base_rate_flex = TRUE, base_rate_data = "rate",
                                fractions = TRUE, split_mode = FALSE, split_tresh = NULL, funds_fee = 1, bonus_fee = 5)
                         
      c(date_ranges[n, 1], date_ranges[n, 2], params[row, "ema"], sim_results$ttwror, sim_results$statistics$mean, sim_results$statistics$sd, sim_results$statistics$cv,
        sim_results$statistics$skewness, sim_results$statistics$kurtosis, sim_results$statistics$lpm, sim_results$statistics$hpm,
        quantile(sim_results$drawdowns, probs = seq(0, 1, by = 0.1)))}
    
    results <- as.data.frame(results)
    colnames(results) <- c("Start_Date", "Stopp_Date", "EMA", "TTWROR", "Return_Mean", "Return_Std", "Return_CV",
                           "Return_Skewness", "Return_Kurtosis", "Return_LPM", "Return_HPM",
                           paste0(c("Min", seq(10, 90, by = 10), "Max"), "_DD"))
    results <- transform(results, Start_Date = as.Date(Start_Date), Stopp_Date = as.Date(Stopp_Date))
    
    fwrite(results, paste0("./03 Results Data/05 Moving Average - Alt Signal/Lump Sum - Short x2 - EUR - EMA ", params[row, "ema"], " - ", config$name, " - ", params[row, "span"], " Years.csv"), row.names = FALSE)
  }
}
stopCluster(sim_clust)


########################################################################################################################
# Short Dollar Cost Averaging Exponential Moving Average-Strategien EUR Index
########################################################################################################################
strategy <- list(
  letf = list(
    asset_share = 1,
    asset_class = "etf", asset_bonus = 0.3,
    action_type = "sma", action_dcas = "hold",
    signal_buy = "buy", signal_sell = "sell"
  )
)

params <- expand.grid(ema = seq(10, 600, by = 10), span = seq(10, 40, by = 10))
params <- params[order(params$span, params$ema), ]

sim_clust <- makeCluster(no_cores)
registerDoParallel(sim_clust)
#---> Short x2
for(row in 1:nrow(params)){
  date_ranges <- create_sequences(as.character(msci_letf$date), span = params[row, "span"], signal_a = params[row, "ema"])
  
  for(config in configs){
    results <- foreach(n = 1:nrow(date_ranges), .combine = rbind, .packages = c("tidyverse", "tidyquant", "imputeTS", "myLeverage"),
                       .options.future = list(chunk.size = ceiling(nrow(date_ranges)/no_cores * 1.5))) %dopar% {
      data <- msci_letf %>%
        mutate(signal = EMA(eu_index_l1, params[row, "ema"])) %>%
        filter(date >= date_ranges[n, 1] & date <= date_ranges[n, 2]) %>%
        mutate(
          signal = signal / first(eu_index_l1) * 100,
          index = eu_index_l1 / first(eu_index_l1) * 100,
          letf = sim_s2,
          buy = index < signal,
          sell = index >= signal) %>%
        select(date, letf, buy, sell, rate)
                         
      sim_results <- simulation(data, strategy,
                                start_value = 1000, spread = config$spread, details = FALSE, liquidate = FALSE,
                                dca_mode = TRUE, dca_value = 1000, dca_span = 1, dca_day = 1, dca_unit = "month",
                                balance_mode = FALSE, balance_span = NULL, balance_day = NULL, balance_unit = "month",
                                balance_dca = FALSE, tax_mode = config$tax_mode, tax_rate = 0.26375,
                                base_rate = NULL, base_rate_flex = TRUE, base_rate_data = "rate",
                                fractions = TRUE, split_mode = FALSE, split_tresh = NULL, funds_fee = 1, bonus_fee = 5)
                         
      c(date_ranges[n, 1], date_ranges[n, 2], params[row, "ema"], sim_results$ttwror, sim_results$statistics$mean, sim_results$statistics$sd, sim_results$statistics$cv,
        sim_results$statistics$skewness, sim_results$statistics$kurtosis, sim_results$statistics$lpm, sim_results$statistics$hpm,
        quantile(sim_results$drawdowns, probs = seq(0, 1, by = 0.1)))}
    
    results <- as.data.frame(results)
    colnames(results) <- c("Start_Date", "Stopp_Date", "EMA", "TTWROR", "Return_Mean", "Return_Std", "Return_CV",
                           "Return_Skewness", "Return_Kurtosis", "Return_LPM", "Return_HPM",
                           paste0(c("Min", seq(10, 90, by = 10), "Max"), "_DD"))
    results <- transform(results, Start_Date = as.Date(Start_Date), Stopp_Date = as.Date(Stopp_Date))
    
    fwrite(results, paste0("./03 Results Data/05 Moving Average - Alt Signal/DCA Hold - Short x2 - EUR - EMA ", params[row, "ema"], " - ", config$name, " - ", params[row, "span"], " Years.csv"), row.names = FALSE)
  }
}
stopCluster(sim_clust)


########################################################################################################################
# Long Lump Sum Moving Deciles-Strategien
########################################################################################################################
strategy <- list(
  letf = list(
    asset_share = 1,
    asset_class = "etf", asset_bonus = 0.3,
    action_type = "sma", action_dcas = "hold",
    signal_buy = "buy", signal_sell = "sell"
  )
)

params <- expand.grid(window = seq(10, 600, by = 10), thresh = seq(0, 1, by = 0.1), span = seq(10, 40, by = 10))
params <- params[order(params$span, params$window), ]

sim_clust <- makeCluster(no_cores)
registerDoParallel(sim_clust)
#---> Long x2
for(row in 1:nrow(params)){
  date_ranges <- create_sequences(as.character(msci_letf$date), span = params[row, "span"], signal_a = params[row, "window"])

  msci_data <- msci_letf %>%
    mutate(signal = runner(.data$eu_index_l1, k = params[row, "window"], f = function(x) quantile(x, probs = params[row, "thresh"], na.rm = TRUE), lag = 0))
  
  for(config in configs){
    results <- foreach(n = 1:nrow(date_ranges), .combine = rbind, .packages = c("tidyverse", "tidyquant", "runner", "imputeTS", "myLeverage"),
                       .options.future = list(chunk.size = ceiling(nrow(date_ranges)/no_cores * 1.5))) %dopar% {
       
      data <- msci_data[msci_data$date >= date_ranges[n, 1] & msci_data$date <= date_ranges[n, 2], c("date", "sim_l2", "eu_index_l1", "signal", "rate"), drop = FALSE] %>%
        mutate(
          letf     = sim_l2,
          buy      = eu_index_l1 >= signal,
          sell     = eu_index_l1 < signal) %>%
        select(date, letf, buy, sell, rate)
                         
      sim_results <- simulation(data, strategy,
                                start_value = 1000, spread = config$spread, details = FALSE, liquidate = FALSE,
                                dca_mode = FALSE, dca_value = NULL, dca_span = NULL, dca_day = NULL, dca_unit = "month",
                                balance_mode = FALSE, balance_span = NULL, balance_day = NULL, balance_unit = "month",
                                balance_dca = FALSE, tax_mode = config$tax_mode, tax_rate = 0.26375,
                                base_rate = NULL, base_rate_flex = TRUE, base_rate_data = "rate",
                                fractions = TRUE, split_mode = FALSE, split_tresh = NULL, funds_fee = 1, bonus_fee = 5)
      
      c(date_ranges[n, 1], date_ranges[n, 2], params[row, "window"], params[row, "thresh"], sim_results$ttwror, sim_results$statistics$mean, sim_results$statistics$sd, sim_results$statistics$cv,
        sim_results$statistics$skewness, sim_results$statistics$kurtosis, sim_results$statistics$lpm, sim_results$statistics$hpm,
                         quantile(sim_results$drawdowns, probs = seq(0, 1, by = 0.1)))}
    
    results <- as.data.frame(results)
    colnames(results) <- c("Start_Date", "Stopp_Date", "Windows_Size", "Threshold", "TTWROR", "Return_Mean", "Return_Std", "Return_CV",
                           "Return_Skewness", "Return_Kurtosis", "Return_LPM", "Return_HPM", paste0(c("Min", seq(10, 90, by = 10), "Max"), "_DD"))
    results <- transform(results, Start_Date = as.Date(Start_Date), Stopp_Date = as.Date(Stopp_Date))
    
    fwrite(results, paste0("./03 Results Data/06 Moving Metrics - Lump Sum/Moving Deciles - Lump Sum - Long x2 - Window ", params[row, "window"], " - ", params[row, "thresh"], " - ", config$name, " - ", params[row, "span"], " Years.csv"), row.names = FALSE)
  }
}
stopCluster(sim_clust)

########################################################################################################################
# Long Dollar Cost Averaging Moving Deciles-Strategien
########################################################################################################################
strategy <- list(
  letf = list(
    asset_share = 1,
    asset_class = "etf", asset_bonus = 0.3,
    action_type = "sma", action_dcas = "hold",
    signal_buy = "buy", signal_sell = "sell"
  )
)

params <- expand.grid(window = seq(10, 600, by = 10), thresh = seq(0, 1, by = 0.1), span = seq(10, 40, by = 10))
params <- params[order(params$span, params$window), ]

sim_clust <- makeCluster(no_cores)
registerDoParallel(sim_clust)
#---> Long x2
for(row in 1:nrow(params)){
  date_ranges <- create_sequences(as.character(msci_letf$date), span = params[row, "span"], signal_a = params[row, "window"])

  msci_data <- msci_letf %>%
    mutate(signal = runner(.data$eu_index_l1, k = params[row, "window"], f = function(x) quantile(x, probs = params[row, "thresh"], na.rm = TRUE), lag = 0))

  for(config in configs){
    results <- foreach(n = 1:nrow(date_ranges), .combine = rbind, .packages = c("tidyverse", "tidyquant", "runner","imputeTS", "myLeverage"),
                       .options.future = list(chunk.size = ceiling(nrow(date_ranges)/no_cores * 1.5))) %dopar% {
       
      data <- msci_data[msci_data$date >= date_ranges[n, 1] & msci_data$date <= date_ranges[n, 2], c("date", "sim_l2", "eu_index_l1", "signal", "rate"), drop = FALSE] %>%
        mutate(
          letf     = sim_l2,
          buy      = eu_index_l1 >= signal,
          sell     = eu_index_l1 < signal) %>%
        select(date, letf, buy, sell, rate)
                         
      sim_results <- simulation(data, strategy,
                                start_value = 1000, spread = config$spread, details = FALSE, liquidate = FALSE,
                                dca_mode = TRUE, dca_value = 1000, dca_span = 1, dca_day = 1, dca_unit = "month",
                                balance_mode = FALSE, balance_span = NULL, balance_day = NULL, balance_unit = "month",
                                balance_dca = FALSE, tax_mode = config$tax_mode, tax_rate = 0.26375,
                                base_rate = NULL, base_rate_flex = TRUE, base_rate_data = "rate",
                                fractions = TRUE, split_mode = FALSE, split_tresh = NULL, funds_fee = 1, bonus_fee = 5)
                         
      c(date_ranges[n, 1], date_ranges[n, 2], params[row, "window"], params[row, "thresh"], sim_results$ttwror, sim_results$statistics$mean, sim_results$statistics$sd, sim_results$statistics$cv,
        sim_results$statistics$skewness, sim_results$statistics$kurtosis, sim_results$statistics$lpm, sim_results$statistics$hpm,
                         quantile(sim_results$drawdowns, probs = seq(0, 1, by = 0.1)))}
    
    results <- as.data.frame(results)
    colnames(results) <- c("Start_Date", "Stopp_Date", "Windows_Size", "Threshold", "TTWROR", "Return_Mean", "Return_Std", "Return_CV",
                           "Return_Skewness", "Return_Kurtosis", "Return_LPM", "Return_HPM", paste0(c("Min", seq(10, 90, by = 10), "Max"), "_DD"))
    results <- transform(results, Start_Date = as.Date(Start_Date), Stopp_Date = as.Date(Stopp_Date))
    
    fwrite(results, paste0("./03 Results Data/07 Moving Metrics - DCA Hold/Moving Deciles - DCA Hold - Long x2 - Window ", params[row, "window"], " - ", params[row, "thresh"], " - ", config$name, " - ", params[row, "span"], " Years.csv"), row.names = FALSE)
  }
}
stopCluster(sim_clust)


########################################################################################################################
# Short Lump Sum Moving Deciles-Strategien
########################################################################################################################
strategy <- list(
  letf = list(
    asset_share = 1,
    asset_class = "etf", asset_bonus = 0.3,
    action_type = "sma", action_dcas = "hold",
    signal_buy = "buy", signal_sell = "sell"
  )
)

params <- expand.grid(window = seq(10, 600, by = 10), thresh = seq(0, 1, by = 0.1), span = seq(10, 40, by = 10))
params <- params[order(params$span, params$window), ]

sim_clust <- makeCluster(no_cores)
registerDoParallel(sim_clust)
#---> Short x2
for(row in 1:nrow(params)){
  date_ranges <- create_sequences(as.character(msci_letf$date), span = params[row, "span"], signal_a = params[row, "window"])

  msci_data <- msci_letf %>%
    mutate(signal = runner(.data$us_index_l1, k = params[row, "window"], f = function(x) quantile(x, probs = params[row, "thresh"], na.rm = TRUE), lag = 0))

  for(config in configs){
    results <- foreach(n = 1:nrow(date_ranges), .combine = rbind, .packages = c("tidyverse", "tidyquant", "runner","imputeTS", "myLeverage"),
                       .options.future = list(chunk.size = ceiling(nrow(date_ranges)/no_cores * 1.5))) %dopar% {
          
      data <- msci_data[msci_data$date >= date_ranges[n, 1] & msci_data$date <= date_ranges[n, 2], c("date", "sim_s2", "us_index_l1", "signal", "rate"), drop = FALSE] %>%
        mutate(
          letf     = sim_s2,
          buy      = us_index_l1 >= signal,
          sell     = us_index_l1 < signal) %>%
        select(date, letf, buy, sell, rate)
            
      sim_results <- simulation(data, strategy,
                                start_value = 1000, spread = config$spread, details = FALSE, liquidate = FALSE,
                                dca_mode = FALSE, dca_value = NULL, dca_span = NULL, dca_day = NULL, dca_unit = "month",
                                balance_mode = FALSE, balance_span = NULL, balance_day = NULL, balance_unit = "month",
                                balance_dca = FALSE, tax_mode = config$tax_mode, tax_rate = 0.26375,
                                base_rate = NULL, base_rate_flex = TRUE, base_rate_data = "rate",
                                fractions = TRUE, split_mode = FALSE, split_tresh = NULL, funds_fee = 1, bonus_fee = 5)
                         
      c(date_ranges[n, 1], date_ranges[n, 2], params[row, "window"], params[row, "thresh"], sim_results$ttwror, sim_results$statistics$mean, sim_results$statistics$sd, sim_results$statistics$cv,
        sim_results$statistics$skewness, sim_results$statistics$kurtosis, sim_results$statistics$lpm, sim_results$statistics$hpm,
                         quantile(sim_results$drawdowns, probs = seq(0, 1, by = 0.1)))}
    
    results <- as.data.frame(results)
    colnames(results) <- c("Start_Date", "Stopp_Date", "Windows_Size", "Threshold", "TTWROR", "Return_Mean", "Return_Std", "Return_CV",
                           "Return_Skewness", "Return_Kurtosis", "Return_LPM", "Return_HPM", paste0(c("Min", seq(10, 90, by = 10), "Max"), "_DD"))
    results <- transform(results, Start_Date = as.Date(Start_Date), Stopp_Date = as.Date(Stopp_Date))
    
    fwrite(results, paste0("./03 Results Data/06 Moving Metrics - Lump Sum/Moving Deciles - Lump Sum - Short x2 - Window ", params[row, "window"], " - ", params[row, "thresh"], " - ", config$name, " - ", params[row, "span"], " Years.csv"), row.names = FALSE)
  }
}
stopCluster(sim_clust)

########################################################################################################################
# Short Dollar Cost Averaging Moving Deciles-Strategien
########################################################################################################################
strategy <- list(
  letf = list(
    asset_share = 1,
    asset_class = "etf", asset_bonus = 0.3,
    action_type = "sma", action_dcas = "hold",
    signal_buy = "buy", signal_sell = "sell"
  )
)

params <- expand.grid(window = seq(10, 600, by = 10), thresh = seq(0, 1, by = 0.1), span = seq(10, 40, by = 10))
params <- params[order(params$span, params$window), ]

sim_clust <- makeCluster(no_cores)
registerDoParallel(sim_clust)
#---> Short x2
for(row in 1:nrow(params)){
  date_ranges <- create_sequences(as.character(msci_letf$date), span = params[row, "span"], signal_a = params[row, "window"])

  msci_data <- msci_letf %>%
    mutate(signal = runner(.data$us_index_l1, k = params[row, "window"], f = function(x) quantile(x, probs = params[row, "thresh"], na.rm = TRUE), lag = 0))

  for(config in configs){
    results <- foreach(n = 1:nrow(date_ranges), .combine = rbind, .packages = c("tidyverse", "tidyquant","runner", "imputeTS", "myLeverage"),
                       .options.future = list(chunk.size = ceiling(nrow(date_ranges)/no_cores * 1.5))) %dopar% {
    
      data <- msci_data[msci_data$date >= date_ranges[n, 1] & msci_data$date <= date_ranges[n, 2], c("date", "sim_s2", "us_index_l1", "signal", "rate"), drop = FALSE] %>%
        mutate(
          letf     = sim_s2,
          buy      = us_index_l1 >= signal,
          sell     = us_index_l1 < signal) %>%
        select(date, letf, buy, sell, rate)
                         
      sim_results <- simulation(data, strategy,
                                start_value = 1000, spread = config$spread, details = FALSE, liquidate = FALSE,
                                dca_mode = TRUE, dca_value = 1000, dca_span = 1, dca_day = 1, dca_unit = "month",
                                balance_mode = FALSE, balance_span = NULL, balance_day = NULL, balance_unit = "month",
                                balance_dca = FALSE, tax_mode = config$tax_mode, tax_rate = 0.26375,
                                base_rate = NULL, base_rate_flex = TRUE, base_rate_data = "rate",
                                fractions = TRUE, split_mode = FALSE, split_tresh = NULL, funds_fee = 1, bonus_fee = 5)
                         
      c(date_ranges[n, 1], date_ranges[n, 2], params[row, "window"], params[row, "thresh"], sim_results$ttwror, sim_results$statistics$mean, sim_results$statistics$sd, sim_results$statistics$cv,
        sim_results$statistics$skewness, sim_results$statistics$kurtosis, sim_results$statistics$lpm, sim_results$statistics$hpm,
                         quantile(sim_results$drawdowns, probs = seq(0, 1, by = 0.1)))}
    
    results <- as.data.frame(results)
    colnames(results) <- c("Start_Date", "Stopp_Date", "Windows_Size", "Threshold", "TTWROR", "Return_Mean", "Return_Std", "Return_CV",
                           "Return_Skewness", "Return_Kurtosis", "Return_LPM", "Return_HPM", paste0(c("Min", seq(10, 90, by = 10), "Max"), "_DD"))
    results <- transform(results, Start_Date = as.Date(Start_Date), Stopp_Date = as.Date(Stopp_Date))
    
    fwrite(results, paste0("./03 Results Data/07 Moving Metrics - DCA Hold/Moving Deciles - DCA Hold - Short x2 - Window ", params[row, "window"], " - ", params[row, "thresh"], " - ", config$name, " - ", params[row, "span"], " Years.csv"), row.names = FALSE)
  }
}
stopCluster(sim_clust)


########################################################################################################################
# Long Lump Sum Moving Normals-Strategien
########################################################################################################################
strategy <- list(
  letf = list(
    asset_share = 1,
    asset_class = "etf", asset_bonus = 0.3,
    action_type = "sma", action_dcas = "hold",
    signal_buy = "buy", signal_sell = "sell"
  )
)

params <- expand.grid(window = seq(10, 600, by = 10), thresh = seq(0.1, 0.9, by = 0.1), span = seq(10, 40, by = 10))
params <- params[order(params$span, params$window), ]

sim_clust <- makeCluster(no_cores)
registerDoParallel(sim_clust)
#---> Long x2
for(row in 1:nrow(params)){
  date_ranges <- create_sequences(as.character(msci_letf$date), span = params[row, "span"], signal_a = params[row, "window"])

  msci_data <- msci_letf %>%
    mutate(
      max_level = runner(.data$eu_index_l1, k = params[row, "window"], f = function(x) max(x, na.rm = TRUE), na_pad = TRUE),
      min_level = runner(.data$eu_index_l1, k = params[row, "window"], f = function(x) min(x, na.rm = TRUE), na_pad = TRUE))
  
  for(config in configs){
    results <- foreach(n = 1:nrow(date_ranges), .combine = rbind, .packages = c("tidyverse", "tidyquant", "runner", "imputeTS", "myLeverage"),
                       .options.future = list(chunk.size = ceiling(nrow(date_ranges)/no_cores * 1.5))) %dopar% {
                      
      data <- msci_data[msci_data$date >= date_ranges[n, 1] & msci_data$date <= date_ranges[n, 2], c("date", "sim_l2", "eu_index_l1", "max_level", "min_level", "rate"), drop = FALSE] %>%
        mutate(
          signal = (eu_index_l1 - min_level) / (max_level - min_level),
          letf   = sim_l2,
          buy    = signal >= params[row, "thresh"],
          sell   = signal <  params[row, "thresh"]) %>%
        select(date, letf, buy, sell, rate)
      
      sim_results <- simulation(data, strategy,
                                start_value = 1000, spread = config$spread, details = FALSE, liquidate = FALSE,
                                dca_mode = FALSE, dca_value = NULL, dca_span = NULL, dca_day = NULL, dca_unit = "month",
                                balance_mode = FALSE, balance_span = NULL, balance_day = NULL, balance_unit = "month",
                                balance_dca = FALSE, tax_mode = config$tax_mode, tax_rate = 0.26375,
                                base_rate = NULL, base_rate_flex = TRUE, base_rate_data = "rate",
                                fractions = TRUE, split_mode = FALSE, split_tresh = NULL, funds_fee = 1, bonus_fee = 5)
      
      c(date_ranges[n, 1], date_ranges[n, 2], params[row, "window"], params[row, "thresh"], sim_results$ttwror, sim_results$statistics$mean, sim_results$statistics$sd, sim_results$statistics$cv,
        sim_results$statistics$skewness, sim_results$statistics$kurtosis, sim_results$statistics$lpm, sim_results$statistics$hpm,
        quantile(sim_results$drawdowns, probs = seq(0, 1, by = 0.1)))}
    
    results <- as.data.frame(results)
    colnames(results) <- c("Start_Date", "Stopp_Date", "Window_Size", "Threshold","TTWROR", "Return_Mean", "Return_Std", "Return_CV",
                           "Return_Skewness", "Return_Kurtosis", "Return_LPM", "Return_HPM",
                           paste0(c("Min", seq(10, 90, by = 10), "Max"), "_DD"))
    results <- transform(results, Start_Date = as.Date(Start_Date), Stopp_Date = as.Date(Stopp_Date))
    
    fwrite(results, paste0("./03 Results Data/07 Moving Deciles - Lump Sum/Moving Normals - Lump Sum - Long x2 - SMA ", params[row, "window"], " - ", params[row, "thresh"], " - ", config$name, " - ", params[row, "span"], " Years.csv"), row.names = FALSE)
  }
}
stopCluster(sim_clust)

########################################################################################################################
# Long Dollar Cost Averaging Moving Normals-Strategien
########################################################################################################################
strategy <- list(
  letf = list(
    asset_share = 1,
    asset_class = "etf", asset_bonus = 0.3,
    action_type = "sma", action_dcas = "hold",
    signal_buy = "buy", signal_sell = "sell"
  )
)

params <- expand.grid(window = seq(10, 600, by = 10), thresh = seq(0.1, 0.9, by = 0.1), span = seq(10, 40, by = 10))
params <- params[order(params$span, params$window), ]

sim_clust <- makeCluster(no_cores)
registerDoParallel(sim_clust)
#---> Long x2
for(row in 1:nrow(params)){
  date_ranges <- create_sequences(as.character(msci_letf$date), span = params[row, "span"], signal_a = params[row, "window"])

  msci_data <- msci_letf %>%
    mutate(
      max_level = runner(.data$eu_index_l1, k = params[row, "window"], f = function(x) max(x, na.rm = TRUE), na_pad = TRUE),
      min_level = runner(.data$eu_index_l1, k = params[row, "window"], f = function(x) min(x, na.rm = TRUE), na_pad = TRUE))
  
  for(config in configs){
    results <- foreach(n = 1:nrow(date_ranges), .combine = rbind, .packages = c("tidyverse", "tidyquant", "runner", "imputeTS", "myLeverage"),
                       .options.future = list(chunk.size = ceiling(nrow(date_ranges)/no_cores * 1.5))) %dopar% {
                      
      data <- msci_data[msci_data$date >= date_ranges[n, 1] & msci_data$date <= date_ranges[n, 2], c("date", "sim_l2", "eu_index_l1", "max_level", "min_level", "rate"), drop = FALSE] %>%
        mutate(
          signal = (eu_index_l1 - min_level) / (max_level - min_level),
          letf   = sim_l2,
          buy    = signal >= params[row, "thresh"],
          sell   = signal <  params[row, "thresh"]) %>%
        select(date, letf, buy, sell, rate)
                         
      sim_results <- simulation(data, strategy,
                                start_value = 1000, spread = config$spread, details = FALSE, liquidate = FALSE,
                                dca_mode = TRUE, dca_value = 1000, dca_span = 1, dca_day = 1, dca_unit = "month",
                                balance_mode = FALSE, balance_span = NULL, balance_day = NULL, balance_unit = "month",
                                balance_dca = FALSE, tax_mode = config$tax_mode, tax_rate = 0.26375,
                                base_rate = NULL, base_rate_flex = TRUE, base_rate_data = "rate",
                                fractions = TRUE, split_mode = FALSE, split_tresh = NULL, funds_fee = 1, bonus_fee = 5)
                         
      
      c(date_ranges[n, 1], date_ranges[n, 2], params[row, "window"], params[row, "thresh"], sim_results$ttwror, sim_results$statistics$mean, sim_results$statistics$sd, sim_results$statistics$cv,
        sim_results$statistics$skewness, sim_results$statistics$kurtosis, sim_results$statistics$lpm, sim_results$statistics$hpm,
        quantile(sim_results$drawdowns, probs = seq(0, 1, by = 0.1)))}
    
    results <- as.data.frame(results)
    colnames(results) <- c("Start_Date", "Stopp_Date", "Window_Size", "Threshold","TTWROR", "Return_Mean", "Return_Std", "Return_CV",
                           "Return_Skewness", "Return_Kurtosis", "Return_LPM", "Return_HPM",
                           paste0(c("Min", seq(10, 90, by = 10), "Max"), "_DD"))
    results <- transform(results, Start_Date = as.Date(Start_Date), Stopp_Date = as.Date(Stopp_Date))
    
    fwrite(results, paste0("./03 Results Data/08 Moving Deciles - DCA Hold/Moving Normals - DCA Hold - Long x2 - Window ", params[row, "window"], " - ", params[row, "thresh"], " - ", config$name, " - ", params[row, "span"], " Years.csv"), row.names = FALSE)
  }
}
stopCluster(sim_clust)


########################################################################################################################
# Short Lump Sum Moving Normals-Strategien
########################################################################################################################
strategy <- list(
  letf = list(
    asset_share = 1,
    asset_class = "etf", asset_bonus = 0.3,
    action_type = "sma", action_dcas = "hold",
    signal_buy = "buy", signal_sell = "sell"
  )
)

params <- expand.grid(window = seq(10, 600, by = 10), thresh = seq(0.1, 0.9, by = 0.1), span = seq(10, 40, by = 10))
params <- params[order(params$span, params$window), ]

sim_clust <- makeCluster(no_cores)
registerDoParallel(sim_clust)
#---> Short x2
for(row in 1:nrow(params)){
  date_ranges <- create_sequences(as.character(msci_letf$date), span = params[row, "span"], signal_a = params[row, "window"])

  msci_data <- msci_letf %>%
    mutate(
      max_level = runner(.data$us_index_l1, k = params[row, "window"], f = function(x) max(x, na.rm = TRUE), na_pad = TRUE),
      min_level = runner(.data$us_index_l1, k = params[row, "window"], f = function(x) min(x, na.rm = TRUE), na_pad = TRUE))
  
  for(config in configs){
    results <- foreach(n = 1:nrow(date_ranges), .combine = rbind, .packages = c("tidyverse", "tidyquant", "runner", "imputeTS", "myLeverage"),
                       .options.future = list(chunk.size = ceiling(nrow(date_ranges)/no_cores * 1.5))) %dopar% {
                      
      data <- msci_data[msci_data$date >= date_ranges[n, 1] & msci_data$date <= date_ranges[n, 2], c("date", "sim_s2", "us_index_l1", "max_level", "min_level", "rate"), drop = FALSE] %>%
        mutate(
          signal = (us_index_l1 - min_level) / (max_level - min_level),
          letf   = sim_s2,
          buy    = signal >= params[row, "thresh"],
          sell   = signal <  params[row, "thresh"]) %>%
        select(date, letf, buy, sell, rate)
                         
      sim_results <- simulation(data, strategy,
                                start_value = 1000, spread = config$spread, details = FALSE, liquidate = FALSE,
                                dca_mode = FALSE, dca_value = NULL, dca_span = NULL, dca_day = NULL, dca_unit = "month",
                                balance_mode = FALSE, balance_span = NULL, balance_day = NULL, balance_unit = "month",
                                balance_dca = FALSE, tax_mode = config$tax_mode, tax_rate = 0.26375,
                                base_rate = NULL, base_rate_flex = TRUE, base_rate_data = "rate",
                                fractions = TRUE, split_mode = FALSE, split_tresh = NULL, funds_fee = 1, bonus_fee = 5)
                         
      
      c(date_ranges[n, 1], date_ranges[n, 2], params[row, "window"], params[row, "thresh"], sim_results$ttwror, sim_results$statistics$mean, sim_results$statistics$sd, sim_results$statistics$cv,
        sim_results$statistics$skewness, sim_results$statistics$kurtosis, sim_results$statistics$lpm, sim_results$statistics$hpm,
        quantile(sim_results$drawdowns, probs = seq(0, 1, by = 0.1)))}
    
    results <- as.data.frame(results)
    colnames(results) <- c("Start_Date", "Stopp_Date", "Window_Size", "Threshold","TTWROR", "Return_Mean", "Return_Std", "Return_CV",
                           "Return_Skewness", "Return_Kurtosis", "Return_LPM", "Return_HPM",
                           paste0(c("Min", seq(10, 90, by = 10), "Max"), "_DD"))
    results <- transform(results, Start_Date = as.Date(Start_Date), Stopp_Date = as.Date(Stopp_Date))
    
    fwrite(results, paste0("./03 Results Data/07 Moving Deciles - Lump Sum/Moving Normals - Lump Sum - Short x2 - Window ", params[row, "window"], " - ", params[row, "thresh"], " - ", config$name, " - ", params[row, "span"], " Years.csv"), row.names = FALSE)
  }
}
stopCluster(sim_clust)

########################################################################################################################
# Short Dollar Cost Averaging Moving Normals-Strategien
########################################################################################################################
strategy <- list(
  letf = list(
    asset_share = 1,
    asset_class = "etf", asset_bonus = 0.3,
    action_type = "sma", action_dcas = "hold",
    signal_buy = "buy", signal_sell = "sell"
  )
)

params <- expand.grid(window = seq(10, 600, by = 10), thresh = seq(0.1, 0.9, by = 0.1), span = seq(10, 40, by = 10))
params <- params[order(params$span, params$window), ]

sim_clust <- makeCluster(no_cores)
registerDoParallel(sim_clust)
#---> Short x2
for(row in 1:nrow(params)){
  date_ranges <- create_sequences(as.character(msci_letf$date), span = params[row, "span"], signal_a = params[row, "window"])

  msci_data <- msci_letf %>%
    mutate(
      max_level = runner(.data$us_index_l1, k = params[row, "window"], f = function(x) max(x, na.rm = TRUE), na_pad = TRUE),
      min_level = runner(.data$us_index_l1, k = params[row, "window"], f = function(x) min(x, na.rm = TRUE), na_pad = TRUE))
  
  for(config in configs){
    results <- foreach(n = 1:nrow(date_ranges), .combine = rbind, .packages = c("tidyverse", "tidyquant", "runner", "imputeTS", "myLeverage"),
                       .options.future = list(chunk.size = ceiling(nrow(date_ranges)/no_cores * 1.5))) %dopar% {
                         
      data <- msci_data[msci_data$date >= date_ranges[n, 1] & msci_data$date <= date_ranges[n, 2], c("date", "sim_s2", "us_index_l1", "max_level", "min_level", "rate"), drop = FALSE] %>%
        mutate(
          signal = (us_index_l1 - min_level) / (max_level - min_level),
          letf   = sim_s2,
          buy    = signal >= params[row, "thresh"],
          sell   = signal <  params[row, "thresh"]) %>%
        select(date, letf, buy, sell, rate)
                         
      sim_results <- simulation(data, strategy,
                                start_value = 1000, spread = config$spread, details = FALSE, liquidate = FALSE,
                                dca_mode = TRUE, dca_value = 1000, dca_span = 1, dca_day = 1, dca_unit = "month",
                                balance_mode = FALSE, balance_span = NULL, balance_day = NULL, balance_unit = "month",
                                balance_dca = FALSE, tax_mode = config$tax_mode, tax_rate = 0.26375,
                                base_rate = NULL, base_rate_flex = TRUE, base_rate_data = "rate",
                                fractions = TRUE, split_mode = FALSE, split_tresh = NULL, funds_fee = 1, bonus_fee = 5)
      
      c(date_ranges[n, 1], date_ranges[n, 2], params[row, "window"], params[row, "thresh"], sim_results$ttwror, sim_results$statistics$mean, sim_results$statistics$sd, sim_results$statistics$cv,
        sim_results$statistics$skewness, sim_results$statistics$kurtosis, sim_results$statistics$lpm, sim_results$statistics$hpm,
        quantile(sim_results$drawdowns, probs = seq(0, 1, by = 0.1)))}
    
    results <- as.data.frame(results)
    colnames(results) <- c("Start_Date", "Stopp_Date", "Window_Size", "Threshold","TTWROR", "Return_Mean", "Return_Std", "Return_CV",
                           "Return_Skewness", "Return_Kurtosis", "Return_LPM", "Return_HPM",
                           paste0(c("Min", seq(10, 90, by = 10), "Max"), "_DD"))
    results <- transform(results, Start_Date = as.Date(Start_Date), Stopp_Date = as.Date(Stopp_Date))
    
    fwrite(results, paste0("./03 Results Data/08 Moving Deciles - DCA Hold/Moving Normals - DCA Hold - Short x2 - Window ", params[row, "window"], " - ", params[row, "thresh"], " - ", config$name, " - ", params[row, "span"], " Years.csv"), row.names = FALSE)
  }
}
stopCluster(sim_clust)


########################################################################################################################
# Bereinigung des Workspace
########################################################################################################################
rm(list = ls())
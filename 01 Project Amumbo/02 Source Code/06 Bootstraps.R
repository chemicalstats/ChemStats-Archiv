########################################################################################################################
# Vorbereitung des Systems
########################################################################################################################
packages <- c("tidyverse", "tidyquant", "Rcpp", "myLeverage", "foreach", "parallel", "rugarch", "MSGARCH", "doParallel",
              "doFuture", "data.table")
invisible(lapply(packages, library, character.only = TRUE)); rm(packages)
if(.Platform$OS.type == "windows"){Sys.setlocale("LC_ALL", "en_US.UTF-8")}

#---> Kompilierung von C++ Dateien:
sourceCpp("./00 Bootstraps/boot_helper.cpp")
sourceCpp("./00 Bootstraps/boot_raw.cpp")
sourceCpp("./00 Bootstraps/boot_stationary.cpp")
sourceCpp("./00 Bootstraps/boot_block.cpp")
sourceCpp("./00 Bootstraps/boot_wild.cpp")
sourceCpp("./00 Bootstraps/boot_regime.cpp")
sourceCpp("./00 Bootstraps/boot_gpd.cpp")
sourceCpp("./00 Bootstraps/boot_tails.cpp")
sourceCpp("./00 Bootstraps/boot_reset.cpp")
sourceCpp("./00 Bootstraps/boot_garch.cpp")
sourceCpp("./00 Bootstraps/boot_gjr_garch.cpp")
sourceCpp("./00 Bootstraps/boot_ms_garch.cpp")
sourceCpp("./00 Bootstraps/boot_ms_ar_garch_m.cpp")
sourceCpp("./00 Bootstraps/boot_tvtp_ms_garch.cpp")

#---> Initialisierung von R-Funktionen:
source("./00 Bootstraps/boot_helper.R")

#---> Vorbereitung der Analysedaten:
msci_data <- read.csv("./Project Amumbo UCITS Funds.csv") %>%
  mutate(
    eu_index_l1_return = eu_index_l1/lag(eu_index_l1),
    us_index_l1_return = us_index_l1/lag(us_index_l1),
    fx_return = eu_index_l1_return / us_index_l1_return
  ) %>%
  select(eu_index_l1_return, us_index_l1_return) %>%
  drop_na()

#---> Vorbereitung der Bootstrap-Konfiguration:
config <- create_config(
  indices = c(us = "us_index_l1_return", eu = "eu_index_l1_return"), regime_index = "us",
  letfs = list(list(base = "eu", leverage = 2, finance = 3.5, expense = 0.5))
)

full_dates <- seq.Date(as.Date("1975-01-01"), as.Date("2024-12-31"), by = "days")
keep_dates <- full_dates >= as.Date("1977-01-01")
min_path_rows <- length(full_dates)

#---> Vorbereitung der Bootstrap-Speicher:
chunk_path <- "./03 Results Data/08 Strategy Bootstrap Analysis/Chunks/"
dir.create(chunk_path, showWarnings = FALSE)
store_path <- "./03 Results Data/08 Strategy Bootstrap Analysis/boot_paths/"
dir.create(store_path, showWarnings = FALSE)
output_path <- "./03 Results Data/08 Strategy Bootstrap Analysis/"
dir.create(output_path, showWarnings = FALSE, recursive = TRUE)

#---> Vorbereitung der Parallelisierung-Cluster:
no_boot <- 100000
no_cores <- detectCores() - 2
registerDoParallel(no_cores)


########################################################################################################################
# Initialisierung von Hilfsfunktionen
########################################################################################################################
#---> Hilfsfunktion zur Speicherung der Bootstrappfade in Chunks:
save_bootstrap_chunks <- function(result, method_name, store_path, no_cores){  
  result <- validate_bootstrap(result)
  
  n_paths <- length(result$paths)
  cat(sprintf("  → %d valide Pfade\n", n_paths))
  
  chunk_size <- max(1, ceiling(n_paths / no_cores))
  no_chunks <- ceiling(n_paths / chunk_size)
  
  for(chunk_id in seq_len(no_chunks)){
    idx_start <- (chunk_id - 1) * chunk_size + 1
    idx_end <- min(chunk_id * chunk_size, n_paths)
    if(idx_start > n_paths) break
    idx_global <- idx_start:idx_end
    
    saveRDS(
      list(
        paths = result$paths[idx_global],
        path_id = idx_global,
        weights = if (!is.null(result$weights)) result$weights[idx_global] else rep(1, length(idx_global))
      ),
      file = sprintf("%s%s_paths_%04d.rds", store_path, method_name, chunk_id),
      compress = FALSE
    )
  }
  
  cat(sprintf("  → %d Chunks gespeichert\n", no_chunks))
  invisible(no_chunks)
}

#---> Hilfsfunktion zur Simulation auf Chuck-Speicher:
run_strategy_simulation <- function(method_name, strategy_name, strategy, store_path, chunk_path, output_path,
                                    signal_fn = NULL, dca_mode = FALSE, keep_dates, full_dates){
  chunk_files <- list.files(store_path, pattern = sprintf("^%s_paths_.*\\.rds$", method_name), full.names = TRUE)
  no_chunks <- length(chunk_files)
  
  if(no_chunks == 0){
    warning(sprintf("Keine Chunks für %s gefunden!", method_name))
    return(NULL)
  }
  
  cat(sprintf("  Verarbeite %d Chunks für %s - %s\n", no_chunks, method_name, strategy_name))
  
  foreach(chunk_id = seq_len(no_chunks), .packages = c("data.table", "myLeverage", "TTR"),
          .export = c("strategy", "keep_dates", "full_dates", "store_path", "chunk_path", "signal_fn", "dca_mode"),
          .errorhandling = "pass") %dopar% {
    
    chunk_file <- sprintf("%s%s_paths_%04d.rds", store_path, method_name, chunk_id)
  
    if(!file.exists(chunk_file)) return(NULL)
    
    shard <- readRDS(chunk_file)
    paths <- shard$paths
    path_ids <- shard$path_id
    
    if(length(paths) == 0) return(NULL)
    
    buy_static <- c(TRUE, rep(FALSE, sum(keep_dates) - 1))
    sell_static <- rep(FALSE, sum(keep_dates))
    
    results <- lapply(seq_along(paths), function(i){
      path <- paths[[i]]
      
      if(is.null(path) || !is.matrix(path) || nrow(path) < nrow(msci_data)){return(NULL)}
      
      if(is.null(signal_fn)){
        buy <- buy_static
        sell <- sell_static
      } else {
        signals <- tryCatch({signal_fn(path)}, error = function(e) NULL)
        
        if (is.null(signals)) return(NULL)
        
        buy <- signals$buy[keep_dates]
        sell <- signals$sell[keep_dates]
        
        buy[is.na(buy)] <- FALSE
        sell[is.na(sell)] <- FALSE
      }
      
      data <- tryCatch({
        data.frame(
          date = full_dates[keep_dates],
          letf = path[keep_dates, 3],
          buy = buy,
          sell = sell
        )
      }, error = function(e) NULL)
      
      if (is.null(data)) return(NULL)
      
      sim_results <- tryCatch({
        simulation(data, strategy,
                   start_value = 1000, spread = 0.5, details = FALSE, liquidate = FALSE,
                   dca_mode = dca_mode, dca_value = 1000, dca_span = 1, dca_day = 1, dca_unit = "month",
                   balance_mode = FALSE, balance_span = NULL, balance_day = NULL, balance_unit = "month",
                   balance_dca = FALSE, tax_mode = "none", tax_rate = 0.26375,
                   base_rate = 0, base_rate_flex = TRUE, base_rate_data = "rate",
                   fractions = TRUE, split_mode = FALSE, split_tresh = NULL, funds_fee = 1, bonus_fee = 5)
      }, error = function(e) NULL)
      
      if(is.null(sim_results)) return(NULL)
      
      c(path_ids[i], sim_results$ttwror, sim_results$statistics$mean, sim_results$statistics$sd, 
        sim_results$statistics$cv, sim_results$statistics$skewness, sim_results$statistics$kurtosis, 
        sim_results$statistics$lpm, sim_results$statistics$hpm, quantile(sim_results$drawdowns, probs = seq(0, 1, by = 0.1)))
    })
    
    results <- Filter(Negate(is.null), results)
    
    if(length(results) == 0) return(NULL)
    
    chunk_data <- as.data.table(do.call(rbind, results))
    
    setnames(chunk_data,
             c("Path", "TTWROR", "Return_Mean", "Return_Std", "Return_CV", 
               "Return_Skewness", "Return_Kurtosis", "Return_LPM", "Return_HPM",
               paste0(c("Min", seq(10, 90, 10), "Max"), "_DD")))
    
    out_file <- sprintf("%s/%s_%s_chunk_%04d.csv", chunk_path, method_name, strategy_name, chunk_id)
    fwrite(chunk_data, out_file)
  }
  
  result_pattern <- sprintf("^%s_%s_chunk.*\\.csv$", method_name, strategy_name)
  result_files <- list.files(chunk_path, pattern = result_pattern, full.names = TRUE)
  
  if(length(result_files) == 0){
    warning(sprintf("Keine Ergebnisse für %s - %s!", method_name, strategy_name))
    return(NULL)
  }
  
  final_data <- rbindlist(lapply(result_files, fread))

  output_file <- sprintf("%s%s Bootstraps - %s.csv", output_path, tools::toTitleCase(method_name), strategy_name)
  fwrite(final_data, output_file)
  
  unlink(result_files)
  cat(sprintf("  → %d Ergebnisse gespeichert: %s\n", nrow(final_data), basename(output_file)))
  invisible(final_data)
}


########################################################################################################################
# Vorbereitung von Signalen und Strategien
########################################################################################################################
sma_eur_signal <- function(path, n = 310){
  index <- path[, 1]
  signal <- SMA(index, n = n)
  list(
    buy = index >= signal,
    sell = index < signal
  )
}

sma_usd_signal <- function(path, n = 430){
  index <- path[, 2]
  signal <- SMA(index, n = n)
  list(
    buy = index >= signal,
    sell = index < signal
  )
}

strategy_bnh_ls <- list(
  letf = list(
    asset_share = 1,
    asset_class = "etf", asset_bonus = 0.3,
    action_type = "bnh", action_dcas = "hold",
    signal_buy = "buy", signal_sell = "sell"
  )
)

strategy_bnh_dca <- list(
  letf = list(
    asset_share = 1,
    asset_class = "etf", asset_bonus = 0.3,
    action_type = "bnh", action_dcas = "trade",
    signal_buy = "buy", signal_sell = "sell"
  )
)

strategy_sma <- list(
  letf = list(
    asset_share = 1,
    asset_class = "etf", asset_bonus = 0.3,
    action_type = "sma", action_dcas = "hold",
    signal_buy = "buy", signal_sell = "sell"
  )
)


########################################################################################################################
# Vorbereitung der Bootstrap-Methoden
########################################################################################################################
bootstrap_configs <- list(
  raw = list(ess = FALSE, ess_grid = NULL, params = list()),
  block = list(ess = TRUE, ess_grid = list(block_length = c(seq(5, 100, by = 5), seq(110, 200, by = 10), seq(225, 365, by = 25))), params = list()),
  stationary = list(ess = TRUE, ess_grid = list(L = c(seq(5, 100, by = 5), seq(110, 200, by = 10), seq(225, 365, by = 25))), params = list()),
  wild = list(ess = TRUE, ess_grid = list(wild_type = c(0, 1, 2)), params = list()),
  regime = list(ess = TRUE, ess_grid = list(n_regimes = c(2, 3, 4), vol_window = c(30, 60, 90, 120, 150, 180)), params = list()),
  evt = list(ess = TRUE, ess_grid = list(tail_prob = seq(0.01, 0.10, by = 0.005)), params = list(both_tails = TRUE)),
  tails = list(ess = TRUE, ess_grid = list(tail_prob = seq(0.01, 0.10, by = 0.005)), params = list()),
  reset = list(ess = TRUE, ess_grid = list(p_break = seq(0.01, 0.10, by = 0.005)), params = list()),
  garch = list(ess = FALSE, ess_grid = NULL, params = list(garch_order = c(1, 1))),
  gjr_garch = list(ess = FALSE, ess_grid = NULL, params = list(garch_order = c(1, 1))),
  ms_garch = list(ess = TRUE, ess_grid = list(ms_n_regimes = c(2, 3)), params = list(ms_garch_model = "gjrGARCH")),
  ms_ar_garch_m = list(ess = TRUE, ess_grid = list(ms_ar_n_regimes = c(2, 3)), params = list(ms_ar_garch_model = "gjrGARCH")),
  tvtp_ms_garch = list(ess    = TRUE, ess_grid = list(tvtp_n_regimes = c(2, 3)), params = list(tvtp_garch_model = "gjrGARCH"))
)

#---> Hauptschleife über alle Bootstrap-Methoden
for(method_name in names(bootstrap_configs)){  
  cat(sprintf("\n========== %s ==========\n", toupper(method_name)))
  
  cfg <- bootstrap_configs[[method_name]]
  
  cat("Generiere Bootstrap-Pfade...\n")  
  result <- bootstrap(msci_data, config, method_name, n = no_boot, ess = cfg$ess, ess_grid = cfg$ess_grid, params = cfg$params)
  
  cat("Speichere Chunks...\n")
  save_bootstrap_chunks(result, method_name, store_path, no_cores)
  rm(result); gc()
  
  cat("Simuliere Strategien...\n")  
  run_strategy_simulation(
    method_name, "Buy and Hold - Lump Sum", strategy_bnh_ls, store_path, chunk_path, output_path,
    signal_fn = NULL, dca_mode = FALSE, keep_dates, full_dates)
  
  run_strategy_simulation(
    method_name, "Buy and Hold - DCA", strategy_bnh_dca, store_path, chunk_path, output_path,
    signal_fn = NULL, dca_mode = TRUE, keep_dates, full_dates)
  
  run_strategy_simulation(
    method_name, "Simple Moving Average - Lump Sum - EUR", strategy_sma, store_path, chunk_path, output_path,
    signal_fn = sma_eur_signal, dca_mode = FALSE, keep_dates, full_dates)
  
  run_strategy_simulation(
    method_name, "Simple Moving Average - DCA - EUR", strategy_sma, store_path, chunk_path, output_path,
    signal_fn = sma_eur_signal, dca_mode = TRUE, keep_dates, full_dates)
  
  run_strategy_simulation(
    method_name, "Simple Moving Average - Lump Sum - USD", strategy_sma, store_path, chunk_path, output_path,
    signal_fn = sma_usd_signal, dca_mode = FALSE, keep_dates, full_dates)
  
  run_strategy_simulation(
    method_name, "Simple Moving Average - DCA - USD", strategy_sma, store_path, chunk_path, output_path,
    signal_fn = sma_usd_signal, dca_mode = TRUE, keep_dates, full_dates)
  
  unlink(list.files(store_path, pattern = sprintf("^%s_paths_", method_name), full.names = TRUE))  
  cat(sprintf("✓ %s abgeschlossen\n", toupper(method_name)))
}

########################################################################################################################
# Aufräumen und Bereinigung des Workspace
########################################################################################################################
unlink(chunk_path, recursive = TRUE, force = TRUE)
unlink(store_path, recursive = TRUE, force = TRUE)
stopImplicitCluster()


########################################################################################################################
# Aufbereitung der Ergebnisse
########################################################################################################################
methods <- c(
  "Raw", "Block", "Stationary", "Wild", "Regime", "Reset",
  "EVT", "Tails", "GARCH", "GJR-GARCH", "MS-GARCH",
  "MS-AR-GARCH-M", "TVTP-MS-GARCH"
)

thresholds <- list(
  BH_LS = c(R0 = 0.1313580, D0 = 0.9451193), BH_DCA = c(R0 = 0.1310293, D0 = 0.9434559),
  SMA_EUR_LS = c(R0 = 0.09882045, D0 = 0.5506584), SMA_EUR_DCA = c(R0 = 0.09717894, D0 = 0.5386724),
  SMA_USD_LS = c(R0 = 0.09957663, D0 = 0.4972163), SMA_USD_DCA = c(R0 = 0.09914811, D0 = 0.4781713)
)

calc_metrics <- function(file, R0, D0){
  daten <- read.csv(file)
  
  ttwror <- mean(daten$TTWROR >= R0, na.rm = TRUE)
  maxdd  <- mean(daten$Max_DD <= D0, na.rm = TRUE)
  joint  <- mean(daten$TTWROR >= R0 & daten$Max_DD <= D0, na.rm = TRUE)
  
  return(c(TTWROR = ttwror, MaxDD = maxdd, Joint = joint))
}

results <- array(NA, dim = c(length(methods), 6, 3),
                 dimnames = list(
                   methods,
                   c("BH_LS", "SMA_EUR_LS", "SMA_USD_LS", "BH_DCA", "SMA_EUR_DCA", "SMA_USD_DCA"),
                   c("TTWROR", "MaxDD", "Joint")
                 )
                )

for(m in methods){
  files <- list(
    BH_LS = paste0(output_path, m, " Bootstraps - Buy and Hold - Lump Sum.csv"),
    SMA_EUR_LS = paste0(output_path, m, " Bootstraps - Simple Moving Average - Lump Sum - EUR.csv"),
    SMA_USD_LS = paste0(output_path, m, " Bootstraps - Simple Moving Average - Lump Sum - USD.csv"),
    
    BH_DCA = paste0(output_path, m, " Bootstraps - Buy and Hold - DCA.csv"),
    SMA_EUR_DCA = paste0(output_path, m, " Bootstraps - Simple Moving Average - DCA - EUR.csv"),
    SMA_USD_DCA = paste0(output_path, m, " Bootstraps - Simple Moving Average - DCA - USD.csv")
  )
  
  for(name in names(files)){
    if(file.exists(files[[name]])){
      R0 <- thresholds[[name]]["R0"]
      D0 <- thresholds[[name]]["D0"]
      
      results[m, name, ] <- calc_metrics(files[[name]], R0, D0)
    } else {
      warning(paste("Datei fehlt:", files[[name]]))
    }
  }
}


make_block <- function(metric_index){
  mat <- results[, , metric_index]
  
  df <- data.frame(
    Method = rownames(mat),
    mat[,1], mat[,2], mat[,3],
    mat[,4], mat[,5], mat[,6]
  )
  
  colnames(df) <- c("", "Buy and Hold", "SMA EUR", "SMA USD", "Buy and Hold", "SMA EUR", "SMA USD")
  
  return(df)
}

final_table <- cbind(
  make_block("TTWROR"),
  make_block("MaxDD")[,-1],
  make_block("Joint")[,-1]
)
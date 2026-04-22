######################################################################
#' Helper functions for bootstrap analysis
######################################################################
#' Null-Coalescing Operator
#'
#' @details
#' Returns x if not NULL, otherwise returns fallback value y.
#' Provides a simple mechanism for default parameter handling
#' in configuration objects and model specifications.
#'
#' This operator is used extensively in configuration construction
#' to avoid explicit NULL checks.
#' @export
if(!exists("%||%")){
 `%||%` <- function(x, y) if (is.null(x)) y else x
}


#' Configuration Builder for Bootstrap System
#'
#' @details
#' Constructs a validated and structured configuration object
#' for bootstrap and simulation procedures.
#'
#' Responsibilities:
#' - Validates and normalizes index definitions
#' - Constructs LETF specifications with defaults
#' - Ensures consistency between LETFs and base indices
#' - Defines regime reference index for regime-dependent methods
#'
#' Index structure:
#' Each index is mapped as:
#'   list(name = ..., col = ...)
#'
#' LETF structure:
#' Each leveraged ETF is defined with:
#' - base asset mapping
#' - leverage factor
#' - financing and expense parameters
#' - derived naming convention if not provided
#'
#' Regime handling:
#' - If unspecified, first index is used as regime reference
#' - Ensures regime_index exists in index set
#'
#' Output:
#' Returns an object of class 'bootstrap_config' which is used
#' as the central specification object for all bootstrap methods.
#'
#' Design role:
#' This function defines the model specification layer of the system,
#' separating configuration from simulation logic.
#' @export
create_config <- function(indices, letfs = list(), regime_index = NULL){
 
 if(is.null(names(indices)) || any(names(indices) == "")){
   stop("indices muss vollständig benannt sein: c(name1 = 'spalte1', ...)")
 }
 
 if(is.character(indices) || is.list(indices)){
   index_list <- lapply(names(indices), function(nm){
     list(name = nm, col = indices[[nm]])
   })
 } else {
   stop("indices muss ein benannter Vektor oder eine benannte Liste sein")
 }
 
 index_names <- sapply(index_list, function(x) x$name)
 
 if(any(duplicated(index_names))){
   stop("Duplizierte Index-Namen: ",
        paste(index_names[duplicated(index_names)], collapse = ", "))
 }
 
 letf_list <- lapply(seq_along(letfs), function(i){
   letf <- letfs[[i]]
   
   if(is.null(letf$base)){
     stop(sprintf("LETF %d: 'base' muss angegeben werden", i))
   }
   
   if(!letf$base %in% index_names){
     stop(sprintf("LETF %d: base '%s' nicht in indices gefunden. Verfügbar: %s",
                  i, letf$base, paste(index_names, collapse = ", ")))
   }
   
   leverage <- letf$leverage %||% 2
   if(leverage == 0) stop(sprintf("LETF %d: leverage darf nicht 0 sein", i))
   
   finance <- letf$finance %||% 3.5
   expense <- letf$expense %||% 0.5
   if(finance < 0 || expense < 0){
     stop(sprintf("LETF %d: finance und expense müssen >= 0 sein", i))
   }
   
   name <- letf$name %||% {
     if(leverage >= 0) paste0(letf$base, "_l", leverage)
     else paste0(letf$base, "_inv", abs(leverage))
   }
   
   list(name = name, base = letf$base, leverage = leverage,
        finance = finance, expense = expense)
 })
 
 if(is.null(regime_index)){
   regime_index <- index_names[1]
 } else if(!regime_index %in% index_names){
   stop(sprintf("regime_index '%s' nicht in indices gefunden", regime_index))
 }
 
 letf_names <- if(length(letf_list) > 0){
   sapply(letf_list, function(x) x$name)
 } else {
   character(0)
 }
 
 structure(
   list(
     indices = index_list,
     letfs = letf_list,
     regime_index = regime_index,
     n_indices = length(index_list),
     n_letfs = length(letf_list),
     index_names = index_names,
     letf_names = letf_names
   ),
   class = "bootstrap_config"
 )
}


#' Unified Bootstrap Execution Engine
#'
#' @details
#' Central dispatcher for all bootstrap and simulation methods.
#'
#' This function:
#' - Extracts return data from raw input using configuration
#' - Routes execution to appropriate bootstrap engine
#' - Supports both standard and ESS-weighted sampling schemes
#'
#' Supported methods include:
#' IID, block-based, volatility-based, regime-switching,
#' EVT-based, and GARCH-family bootstraps.
#'
#' ESS mode:
#' If ess = TRUE, performs Effective Sample Size adjusted bootstrap,
#' modifying sampling weights according to ESS grid structure.
#'
#' Output:
#' Returns an object of class 'bootstrap_result' containing:
#' - simulated paths
#' - optional weights
#' - parameter traces (if applicable)
#'
#' Design role:
#' Acts as the execution layer dispatcher between model specification
#' (create_config) and numerical simulation engines (C++ / Rcpp backend).
#' @export
bootstrap <- function(data, config, method = "raw", n = 1000, params = list(), ess = FALSE, ess_grid = NULL, progress = TRUE){
 if(!inherits(config, "bootstrap_config")){
   stop("config muss mit create_config() erstellt werden")
 }
 
 valid_methods <- c("raw", "stationary", "block", "wild", "regime", "evt",
                    "tails", "reset", "garch", "gjr_garch", "ms_garch",
                    "ms_ar_garch_m", "tvtp_ms_garch")
 if(!method %in% valid_methods){
   stop("Unbekannte Methode '", method, "'. Verfügbar: ",
        paste(valid_methods, collapse = ", "))
 }
 
 if(!is.numeric(n) || length(n) != 1 || n < 1){
   stop("n muss eine positive Zahl sein")
 }
 n <- as.integer(n)
 
 returns <- .extract_returns(data, config)
 
 if(ess){
   result <- .run_ess_bootstrap(returns, config, method, n, params, ess_grid,
                                show_progress = progress)
 } else {
   result <- .run_base_bootstrap(returns, config, method, n, params,
                                 show_progress = progress)
 }
 
 structure(result, class = "bootstrap_result")
}


#' Bootstrap Output Validation and Cleaning
#'
#' @details
#' Performs structural and numerical validation of bootstrap output paths.
#'
#' Validation steps:
#' 1. Removes NULL paths
#' 2. Ensures matrix/data.frame structure
#' 3. Checks for empty, NA, or infinite values
#' 4. Enforces consistent path length (mode-based reference length)
#' 5. Applies optional minimum row constraint
#'
#' Statistical role:
#' Ensures integrity of simulated sample paths before:
#' - aggregation
#' - risk estimation
#' - density estimation
#'
#' Weight handling:
#' If present, bootstrap weights are renormalized after filtering
#' to preserve correct relative importance.
#'
#' Failure mode:
#' If no valid paths remain, execution is aborted.
#'
#' Design role:
#' This function represents the data integrity layer of the bootstrap
#' pipeline, ensuring downstream estimators operate on valid samples.
#' @export
validate_bootstrap <- function(result, min_rows = NULL, verbose = TRUE){
  
  if(!inherits(result, "bootstrap_result")){
    stop("result muss ein bootstrap_result Objekt sein")
  }
  
  if(length(result$paths) == 0){
    stop("Keine Pfade im Ergebnis vorhanden")
  }
  
  n_original <- length(result$paths)
  valid_idx <- rep(TRUE, n_original)
  
  is_null <- sapply(result$paths, is.null)
  if(any(is_null)){
    if (verbose) warning(sprintf("%d NULL-Pfade gefunden", sum(is_null)))
    valid_idx[is_null] <- FALSE
  }
  
  for(i in which(valid_idx)){
    path <- result$paths[[i]]
    
    if(!is.matrix(path) && !is.data.frame(path)){
      if (verbose) warning(sprintf("Pfad %d: Keine Matrix/DataFrame", i))
      valid_idx[i] <- FALSE
      next
    }
    
    if(nrow(path) == 0){
      if (verbose) warning(sprintf("Pfad %d: 0 Zeilen", i))
      valid_idx[i] <- FALSE
      next
    }
    
    if(any(is.na(path))){
      if (verbose) warning(sprintf("Pfad %d: Enthält NA-Werte", i))
      valid_idx[i] <- FALSE
      next
    }
    
    if(any(is.infinite(path))){
      if (verbose) warning(sprintf("Pfad %d: Enthält Inf-Werte", i))
      valid_idx[i] <- FALSE
      next
    }
  }
  
  valid_paths <- result$paths[valid_idx]
  if(length(valid_paths) > 0){
    lengths <- sapply(valid_paths, nrow)
    expected_length <- as.numeric(names(sort(table(lengths), decreasing = TRUE))[1])
    
    wrong_length <- lengths != expected_length
    if(any(wrong_length)){
      if(verbose){
        warning(sprintf("%d Pfade mit falscher Länge (erwartet: %d)", 
                        sum(wrong_length), expected_length))
      }
      valid_idx_positions <- which(valid_idx)
      valid_idx[valid_idx_positions[wrong_length]] <- FALSE
    }
  }
  
  if(!is.null(min_rows)){
    for(i in which(valid_idx)){
      if(nrow(result$paths[[i]]) < min_rows){
        if(verbose){
          warning(sprintf("Pfad %d: Nur %d Zeilen (min: %d)", 
                          i, nrow(result$paths[[i]]), min_rows))
        }
        valid_idx[i] <- FALSE
      }
    }
  }
  
  n_valid <- sum(valid_idx)
  n_removed <- n_original - n_valid
  
  if(n_valid == 0){
    stop("Keine gültigen Pfade nach Validierung übrig")
  }
  
  result$paths <- result$paths[valid_idx]
  
  if(!is.null(result$weights)){
    result$weights <- result$weights[valid_idx]
    result$weights <- result$weights / sum(result$weights) * length(result$weights)
  }
  
  if(!is.null(result$param_values)){
    result$param_values <- result$param_values[valid_idx]
  }
  
  if(verbose){
    if(n_removed > 0){
      cat(sprintf("⚠ %d von %d Pfaden entfernt (%.1f%%)\n", 
                  n_removed, n_original, 100 * n_removed / n_original))
    }
    cat(sprintf("✓ %d valide Pfade, je %d Zeilen\n", 
                n_valid, nrow(result$paths[[1]])))
  }
  
  result
}


#' Console Progress Bar Generator
#'
#' @details
#' Creates a stateful progress tracking object for long-running
#' bootstrap simulations.
#'
#' Features:
#' - Incremental update mechanism
#' - ETA estimation based on elapsed time
#' - Dynamic ASCII progress bar rendering
#' - Finalization with success reporting
#'
#' Time model:
#' ETA is estimated linearly based on average processing time per step.
#'
#' Design role:
#' Implements the user interaction layer of the simulation engine,
#' decoupled from statistical logic.
#' @keywords internal
.create_progress <- function(total, width = 40, title = "Fortschritt"){
 env <- new.env()
 env$current <- 0
 env$total <- total
 env$width <- width
 env$title <- title
 env$start_time <- Sys.time()
 env$last_pct <- -1
 
 cat(sprintf("%s:\n", title))
 
 list(
   update = function(i = NULL){
     if(!is.null(i)) env$current <- i
     else env$current <- env$current + 1
     
     pct <- floor(100 * env$current / env$total)
     
     if (pct > env$last_pct || env$current == env$total){
       env$last_pct <- pct
       
       filled <- round(env$width * env$current / env$total)
       bar <- paste0(
         "[",
         strrep("=", max(0, filled - 1)),
         ifelse(filled > 0 && filled < env$width, ">",
                ifelse(filled > 0, "=", "")),
         strrep(" ", max(0, env$width - filled)),
         "]"
       )
       
       elapsed <- as.numeric(difftime(Sys.time(), env$start_time, units = "secs"))
       
       if(env$current > 0 && env$current < env$total){
         eta <- elapsed / env$current * (env$total - env$current)
         time_str <- sprintf("ETA: %s", .format_time(eta))
       } else if(env$current == env$total){
         time_str <- sprintf("Dauer: %s", .format_time(elapsed))
       } else {
         time_str <- ""
       }
       
       cat(sprintf("\r%s %3d%% | %d/%d | %s",
                   bar, pct, env$current, env$total, time_str))
       cat(strrep(" ", 10))
       
       if (env$current == env$total) cat("\n")
       flush.console()
     }
   },
   
   finish = function(success = NULL, extra_msg = NULL){
     elapsed <- as.numeric(difftime(Sys.time(), env$start_time, units = "secs"))
     bar <- paste0("[", strrep("=", env$width), "]")
     
     if(!is.null(success)){
       cat(sprintf("\r%s 100%% | %d/%d erfolgreich | Dauer: %s",
                   bar, success, env$total, .format_time(elapsed)))
     } else {
       cat(sprintf("\r%s 100%% | %d/%d | Dauer: %s",
                   bar, env$total, env$total, .format_time(elapsed)))
     }
     
     if (!is.null(extra_msg)) cat(sprintf(" | %s", extra_msg))
     cat(strrep(" ", 10))
     cat("\n")
     flush.console()
   }
 )
}


#' Time Formatting Utility
#'
#' @details
#' Converts raw duration in seconds into human-readable format:
#' - seconds (< 60s)
#' - minutes + seconds (< 1h)
#' - hours + minutes (≥ 1h)
#'
#' Used for:
#' - progress reporting
#' - simulation runtime diagnostics
#'
#' Design role:
#' Low-level presentation utility for user-facing diagnostics.
#' @keywords internal
.format_time <- function(seconds){
 if(is.na(seconds) || seconds < 0) return("?")
 if(seconds < 60) {
   sprintf("%.0fs", seconds)
 } else if(seconds < 3600){
   sprintf("%dm %ds", floor(seconds / 60), round(seconds %% 60))
 } else {
   sprintf("%dh %dm", floor(seconds / 3600), floor((seconds %% 3600) / 60))
 }
}


#' Return Extraction Layer
#'
#' @details
#' Maps raw input data (data.frame or matrix) into a structured
#' return matrix aligned with the bootstrap configuration.
#'
#' This function performs:
#' - Column validation against configuration mapping
#' - Extraction of gross return series per index
#' - Standardization into fixed-dimension matrix format
#'
#' Output structure:
#'   ret[t, i] = return of index i at time t
#'
#' Preconditions:
#' - All indices defined in config must exist in data
#' - Returns are assumed to be gross returns (> 0)
#'
#' Diagnostics:
#' - Warns if NA values are present (data quality issue)
#' - Warns if non-positive values occur (violates gross return assumption)
#'
#' Design role:
#' Acts as the data normalization layer between raw input data
#' and all stochastic bootstrap models.
#' @keywords internal
.extract_returns <- function(data, config){
 if(!is.data.frame(data) && !is.matrix(data)){
   stop("data muss ein data.frame oder eine Matrix sein")
 }
 
 if(nrow(data) == 0){
   stop("data darf nicht leer sein")
 }
 
 n <- nrow(data)
 n_idx <- config$n_indices
 
 ret <- matrix(NA_real_, nrow = n, ncol = n_idx)
 colnames(ret) <- config$index_names
 
 for(i in seq_along(config$indices)){
   col <- config$indices[[i]]$col
   
   if(is.data.frame(data)){
     if(!col %in% names(data)){
       stop(sprintf("Spalte '%s' nicht gefunden. Verfügbar: %s",
                    col, paste(names(data), collapse = ", ")))
     }
     ret[, i] <- data[[col]]
   } else {
     if(!col %in% colnames(data)){
       stop(sprintf("Spalte '%s' nicht gefunden. Verfügbar: %s",
                    col, paste(colnames(data), collapse = ", ")))
     }
     ret[, i] <- data[, col]
   }
 }
 
 if(any(is.na(ret))) warning("NA-Werte in Returns gefunden")
 if(any(ret <= 0, na.rm = TRUE)) warning("Returns <= 0 gefunden (erwartet: Gross Returns > 0)")
 
 ret
}


#' Core Bootstrap Execution Engine (Standard Mode)
#'
#' @details
#' Executes Monte Carlo bootstrap simulations for a given method
#' without parameter-space expansion (non-ESS mode).
#'
#' Pipeline:
#' 1. Precompute method-specific structures (regimes, GARCH states, etc.)
#' 2. Extract base parameters for simulation
#' 3. Iteratively generate bootstrap paths
#' 4. Validate and collect successful simulations
#'
#' Failure model:
#' - Individual path failures return NULL (ignored)
#' - Entire run fails only if no valid paths are produced
#'
#' Knockout concept:
#' The knockout rate measures structural simulation failure
#' due to invalid paths (e.g. numerical instability, regime collapse).
#'
#' Output:
#' - list of valid simulated price paths
#' - equal weights (IID assumption in standard mode)
#' - diagnostic statistics (success rate, knockout rate)
#'
#' Design role:
#' Implements the primary Monte Carlo simulation loop
#' for all bootstrap methods except ESS expansion.
#' @keywords internal
.run_base_bootstrap <- function(returns, config, method, n, params, show_progress = TRUE){
  
  n_obs <- nrow(returns)
  
  precomputed <- tryCatch({
    .prepare_method_info(returns, config, method, params)
  }, error = function(e) {
    stop(sprintf("Preprocessing-Fehler: %s", e$message))
  })
  
  p <- .get_base_params(method, params, n_obs)
  
  paths <- vector("list", n)
  success <- 0
  null_count <- 0
  
  pb <- NULL
  if (show_progress && n >= 10){
    title <- sprintf("Bootstrap '%s' (n=%d)", method, n)
    pb <- .create_progress(n, title = title)
  }
  
  for(i in seq_len(n)){
    result <- tryCatch({
      .generate_path(returns, config, method, p, precomputed)
    }, error = function(e) {
      NULL
    })
    
    if(!is.null(result)){
      success <- success + 1
      paths[[success]] <- result
    } else {
      null_count <- null_count + 1
    }
    
    if (!is.null(pb)) pb$update(i)
  }
  
  knockout_rate <- 100 * null_count / n
  
  if(!is.null(pb)){
    extra_msg <- sprintf("%d Pfade (%.1f%% Knockout)", success, knockout_rate)
    pb$finish(success = success, extra_msg = extra_msg)
  }
  
  if(success == 0){
    stop(sprintf("Keine erfolgreichen Simulationen. Versuche: %d, NULL: %d", n, null_count))
  }
  
  paths <- paths[1:success]
  
  list(
    paths = paths,
    weights = rep(1, success),
    method = method,
    config = config,
    params = p,
    ess = FALSE,
    knockout_rate = knockout_rate,
    stats = list(
      attempts = n,
      success = success,
      null = null_count,
      knockout_rate = null_count / n
    )
  )
}


#' Effective Sample Size (ESS) Bootstrap Engine
#'
#' @details
#' Extends base bootstrap by introducing parameter-space sampling
#' with explicit control of effective sample size (ESS).
#'
#' Core idea:
#' Instead of uniform simulation, parameter combinations are weighted
#' such that each configuration contributes a controlled amount of
#' effective statistical information.
#'
#' Pipeline:
#' 1. Construct parameter grid (design space)
#' 2. Estimate ESS per configuration
#' 3. Allocate simulation budget proportionally
#' 4. Run stratified bootstrap simulations
#' 5. Aggregate results with ESS-based weighting
#'
#' Key properties:
#' - Balances exploration of parameter space and statistical efficiency
#' - Prevents over-representation of high-dimensional configurations
#' - Introduces adaptive weighting scheme for heterogeneous models
#'
#' Weight structure:
#' weights ∝ (target ESS / realized ESS per configuration)
#'
#' Design role:
#' Implements the experimental design layer on top of Monte Carlo
#' simulation (stratified + adaptive sampling).
#' @keywords internal
.run_ess_bootstrap <- function(returns, config, method, budget, params, grid, show_progress = TRUE){
  n_obs <- nrow(returns)
  
  if(is.null(grid)){
    grid <- .get_ess_grid(method, n_obs)
  }
  
  if(is.null(grid) || length(grid) == 0){
    if(show_progress) message("Keine Hyperparameter für ESS - nutze Standard-Bootstrap")
    return(.run_base_bootstrap(returns, config, method, budget, params, show_progress))
  }
  
  ess_params <- c("L", "block_length", "n_regimes", "tail_prob", "ms_n_regimes")
  non_ess_params <- c("vol_window", "wild_type", "both_tails", "p_break", "garch_order", "ms_garch_model")
  
  param_names <- names(grid)
  
  if(length(grid) == 1){
    design <- data.frame(value = grid[[1]])
    names(design) <- param_names
  } else {
    design <- expand.grid(grid, stringsAsFactors = FALSE)
  }
  
  design$ess_per_boot <- apply(design[, param_names, drop = FALSE], 1, function(row){
    row_list <- as.list(row)
    ess_row <- row_list[names(row_list) %in% ess_params]
    .calculate_ess(n_obs, method, ess_row, returns, config)
  })
  
  if (any(param_names %in% non_ess_params)){
    ess_cols <- param_names[param_names %in% ess_params]
    
    if (length(ess_cols) > 0){
      design$ess_group <- apply(design[, ess_cols, drop = FALSE], 1, paste, collapse = "_")
    } else {
      design$ess_group <- "all"
    }
    
    group_counts <- table(design$ess_group)
    design$n_variants <- as.numeric(group_counts[design$ess_group])
    design$weight_alloc <- (1 / design$ess_per_boot) / design$n_variants
  } else {
    design$ess_group <- seq_len(nrow(design))
    design$n_variants <- 1
    design$weight_alloc <- 1 / design$ess_per_boot
  }
  
  design$n_sims <- pmax(1, round(budget * design$weight_alloc / sum(design$weight_alloc)))
  
  while(sum(design$n_sims) > budget){
    idx <- which.max(design$n_sims)
    design$n_sims[idx] <- design$n_sims[idx] - 1
  }
  
  total_sims <- sum(design$n_sims)
  n_combos <- nrow(design)
  
  pb <- NULL
  if(show_progress && total_sims >= 10){
    title <- sprintf("ESS-Bootstrap '%s' (%d Kombinationen, %d Simulationen)",
                     method, n_combos, total_sims)
    pb <- .create_progress(total_sims, title = title)
  }
  
  all_paths <- list()
  all_params <- list()
  completed <- 0
  total_attempts <- 0
  total_success <- 0
  total_null <- 0
  
  for(i in seq_len(n_combos)){
    n_sim <- design$n_sims[i]
    if (n_sim == 0) next
    
    grid_params <- as.list(design[i, param_names, drop = FALSE])
    
    grid_params <- lapply(grid_params, function(x){
      if(is.factor(x)) as.numeric(as.character(x)) else x
    })
    
    current_params <- modifyList(params, grid_params)
    p <- .get_base_params(method, current_params, n_obs)
    
    precomputed <- tryCatch({
      .prepare_method_info(returns, config, method, current_params)
    }, error = function(e) {
      if (show_progress) {
        warning(sprintf("Preprocessing-Fehler für Kombination %d: %s", i, e$message))
      }
      NULL
    })
    
    if(is.null(precomputed)){
      completed <- completed + n_sim
      if (!is.null(pb)) pb$update(completed)
      next
    }
    
    for(j in seq_len(n_sim)){
      total_attempts <- total_attempts + 1
      
      result <- tryCatch({
        .generate_path(returns, config, method, p, precomputed)
      }, error = function(e) {
        NULL
      })
      
      if(!is.null(result)){
        total_success <- total_success + 1
        all_paths[[length(all_paths) + 1]] <- result
        all_params[[length(all_params) + 1]] <- current_params
      } else {
        total_null <- total_null + 1
      }
      
      completed <- completed + 1
      if (!is.null(pb)) pb$update(completed)
    }
  }
  
  if(!is.null(pb)){
    knockout_rate <- if (total_attempts > 0) 100 * total_null / total_attempts else 0
    extra_msg <- sprintf("%d Pfade (%.1f%% Knockout)", length(all_paths), knockout_rate)
    pb$finish(success = length(all_paths), extra_msg = extra_msg)
  }
  
  if(length(all_paths) == 0){
    stop(sprintf("Keine erfolgreichen Simulationen. Versuche: %d, NULL: %d", 
                 total_attempts, total_null))
  }
  
  design$n_realized <- sapply(seq_len(n_combos), function(i){
    target <- as.list(design[i, param_names, drop = FALSE])
    sum(sapply(all_params, function(p){
      all(sapply(param_names, function(nm){
        isTRUE(all.equal(as.numeric(p[[nm]]), as.numeric(target[[nm]])))
      }))
    }))
  })
  
  design$total_ESS <- design$ess_per_boot * design$n_realized
  
  valid_ess <- design$total_ESS[design$total_ESS > 0]
  if(length(valid_ess) == 0){
    design$weight <- rep(1, n_combos)
  } else {
    target_ESS <- median(valid_ess)
    design$weight <- ifelse(design$total_ESS > 0, target_ESS / design$total_ESS, 0)
  }
  
  weights <- sapply(all_params, function(p){
    for(i in seq_len(n_combos)){
      target <- as.list(design[i, param_names, drop = FALSE])
      match <- all(sapply(param_names, function(nm){
        isTRUE(all.equal(as.numeric(p[[nm]]), as.numeric(target[[nm]])))
      }))
      if (match) return(design$weight[i])
    }
    1
  })
  
  weights <- weights / sum(weights) * length(weights)
  
  if(show_progress){
    message(sprintf("Gesamt: %d Pfade, %d Kombinationen, %.1f%% Knockout-Rate",
                    length(all_paths), sum(design$n_realized > 0), 
                    100 * total_null / total_attempts))
  }
  
  list(
    paths = all_paths,
    weights = weights,
    method = method,
    config = config,
    params = params,
    ess = TRUE,
    ess_design = design,
    param_values = all_params,
    stats = list(
      attempts = total_attempts,
      success = total_success,
      null = total_null,
      knockout_rate = total_null / total_attempts
    )
  )
}


#' Unified Path Generation Interface
#'
#' @details
#' Dispatch layer that generates a single bootstrap path
#' depending on the selected model specification.
#'
#' Supported model classes:
#' - IID resampling (raw)
#' - Block / stationary bootstrap
#' - Wild bootstrap
#' - Regime-switching models
#' - EVT / tail-conditioned models
#' - GARCH-family stochastic volatility models
#' - Markov-switching GARCH variants (MS, TVTP)
#'
#' Pipeline:
#' 1. Generate bootstrap returns using selected method
#' 2. Validate dimensional consistency
#' 3. Construct leverage ETF returns if configured
#' 4. Convert returns into cumulative price paths
#' 5. Apply knockout and validity constraints
#'
#' Failure semantics:
#' - Any structural inconsistency → NULL (path rejection)
#' - Numerical instability → NULL
#'
#' Important invariant:
#' All returned paths must satisfy:
#' - consistent dimensions (n × variables)
#' - positivity constraints for price series
#' - finite numeric values
#'
#' Design role:
#' Acts as the model abstraction layer, unifying all stochastic
#' processes into a single output format.
#' @keywords internal
.generate_path <- function(returns, config, method, params, precomputed){
  n <- nrow(returns)
  n_idx <- ncol(returns)
  
  boot_ret <- tryCatch({
    switch(method,
      "raw" = .boot_raw(returns),
      "stationary" = .boot_stationary(returns, params$L),
      "block" = .boot_block(returns, params$block_length),
      "wild" = .boot_wild(returns, params$wild_type),
      "regime" = .boot_regime(returns, precomputed$regimes, precomputed$trans_mat),
      "evt" = .boot_evt(returns, precomputed),
      "tails" = .boot_tails_wrapper(returns, precomputed),
      "reset" = .boot_reset(returns, params$p_break),
      "garch" = .boot_garch_wrapper(returns, precomputed),
      "gjr_garch" = .boot_gjr_garch_wrapper(returns, precomputed),
      "ms_garch"  = .boot_ms_garch_wrapper(returns, precomputed),
      "ms_ar_garch_m" = .boot_ms_ar_garch_m_wrapper(returns, precomputed),
      "tvtp_ms_garch" = .boot_tvtp_ms_garch_wrapper(returns, precomputed),
      stop(sprintf("Unbekannte Methode: %s", method))
    )
  }, error = function(e){
    warning(sprintf("Bootstrap-Fehler (%s): %s", method, e$message))
    NULL
  })
  
  if(is.null(boot_ret)) return(NULL)
  
  if(!is.matrix(boot_ret) || nrow(boot_ret) != n || ncol(boot_ret) != n_idx){
    warning(sprintf("Ungültige Bootstrap-Dimensionen: %s (erwartet: %dx%d)",
                    paste(dim(boot_ret), collapse = "x"), n, n_idx))
    return(NULL)
  }
  
  if(any(is.na(boot_ret)) || any(is.infinite(boot_ret)) || any(boot_ret <= 0)){
    return(NULL)
  }
  
  if(config$n_letfs > 0){
    prod_ret <- matrix(NA_real_, nrow = n, ncol = config$n_letfs)
    colnames(prod_ret) <- config$letf_names
    
    for(i in seq_along(config$letfs)){
      letf <- config$letfs[[i]]
      base_idx <- which(config$index_names == letf$base)
      
      if(length(base_idx) == 0){
        warning(sprintf("LETF base '%s' nicht gefunden", letf$base))
        return(NULL)
      }
      
      prod_ret[, i] <- .compute_product(
        boot_ret[, base_idx], letf$leverage, letf$finance, letf$expense
      )
    }
    
    if(any(is.na(prod_ret)) || any(is.infinite(prod_ret))) return(NULL)
    
    all_ret <- cbind(boot_ret, prod_ret)
    colnames(all_ret) <- c(config$index_names, config$letf_names)
  } else {
    all_ret <- boot_ret
    colnames(all_ret) <- config$index_names
  }
  
  idx_cols <- seq_len(config$n_indices) - 1L
  letf_cols <- if(config$n_letfs > 0){
    seq(config$n_indices, config$n_indices + config$n_letfs - 1L, by = 1L)
  } else integer(0)
  
  prices <- .compute_prices(all_ret, as.integer(idx_cols), as.integer(letf_cols))
  if(is.null(prices)) return(NULL)
  
  expected_rows <- n + 1
  if(nrow(prices) != expected_rows) return(NULL)
  if(any(is.na(prices)) || any(is.infinite(prices))) return(NULL)
  if(any(prices[, seq_len(config$n_indices), drop = FALSE] <= 0)) return(NULL)
  
  colnames(prices) <- colnames(all_ret)
  prices
}


#' Method-Specific Default Parameter Resolver
#'
#' @details
#' Constructs a complete parameter set for a given bootstrap method
#' by merging user-specified parameters with method-specific defaults.
#'
#' Mechanism:
#' - Defines canonical default parameter values for all supported methods
#' - Overwrites defaults with user-provided values if present
#' - Ensures all downstream components receive complete parameter sets
#'
#' Role in system:
#' This function defines the parameter normalization layer,
#' guaranteeing consistency across heterogeneous bootstrap methods.
#'
#' Important:
#' - No statistical computation is performed here
#' - Only parameter completion and standardization
#' @keywords internal
.get_base_params <- function(method, params, n){
 defaults <- list(
   L = 20,
   block_length = 20,
   wild_type = 0,
   n_regimes = 2,
   vol_window = 20,
   tail_prob = 0.05,
   both_tails = TRUE,
   p_break = 0.02,
   garch_order = c(1, 1),
   ms_n_regimes = 2,
   ms_garch_model = "gjrGARCH",
   ms_ar_n_regimes = 2,
   ms_ar_garch_model = "gjrGARCH",
   tvtp_n_regimes = 2,
   tvtp_garch_model = "gjrGARCH"
 )
 
 for(nm in names(defaults)){
   if(is.null(params[[nm]])){
     params[[nm]] <- defaults[[nm]]
   }
 }
 
 params
}


#' ESS Parameter Grid Definition Layer
#'
#' @details
#' Defines the discrete hyperparameter space used in ESS (Effective Sample Size)
#' based bootstrap simulations.
#'
#' Each bootstrap method is mapped to a method-specific parameter grid
#' that controls simulation diversity.
#'
#' Examples:
#' - block methods → block_length grid
#' - stationary bootstrap → L grid
#' - EVT methods → tail probability grid
#' - MS models → regime count grid
#'
#' Constraint handling:
#' - Automatically restricts block lengths to ≤ n/2
#' - Ensures minimum viable segment size (n/4 fallback rule)
#'
#' Role in system:
#' Defines the experimental design space for structured Monte Carlo
#' exploration of parameter uncertainty.
#' @keywords internal
.get_ess_grid <- function(method, n){
 grids <- list(
   raw = NULL,
   stationary = list(L = c(5, 10, 20, 30, 50, 75, 100)),
   block = list(block_length = c(5, 10, 20, 30, 50, 75, 100)),
   wild = list(wild_type = c(0, 1, 2)),
   regime = list(n_regimes = c(2, 3, 4)),
   evt = list(tail_prob = c(0.01, 0.025, 0.05, 0.10)),
   tails = list(tail_prob = c(0.01, 0.025, 0.05, 0.10)),
   reset = list(p_break = c(0.01, 0.02, 0.05, 0.10)),
   garch = NULL,
   gjr_garch = NULL,
   ms_garch = list(ms_n_regimes = c(2, 3)),
   ms_ar_garch_m = list(ms_ar_n_regimes = c(2, 3)),
   tvtp_ms_garch = list(tvtp_n_regimes = c(2, 3))
 )
 
 grid <- grids[[method]]
 
 if(!is.null(grid)){
   for(nm in c("L", "block_length")){
     if(!is.null(grid[[nm]])){
       grid[[nm]] <- grid[[nm]][grid[[nm]] <= n / 2]
       if (length(grid[[nm]]) == 0) {
         grid[[nm]] <- min(5, floor(n / 4))
       }
     }
   }
 }
 
 grid
}


#' Effective Sample Size (ESS) Estimator
#'
#' @details
#' Computes the effective sample size contributed by a single bootstrap
#' configuration, depending on model structure.
#'
#' Core idea:
#' ESS measures the statistical information content of a simulation run
#' relative to IID sampling.
#'
#' Method-dependent approximations:
#' - IID / wild / GARCH → ESS ≈ n
#' - block / stationary → reduced by dependence structure
#' - regime-switching → reduced by regime persistence
#' - EVT → tail truncation adjustment
#'
#' Special case (regime models):
#' Incorporates expected regime duration derived from transition matrix
#' to adjust for temporal dependence.
#'
#' Role in system:
#' This function defines the statistical efficiency model used in ESS
#' allocation and experimental design.
#' @keywords internal
.calculate_ess <- function(n, method, params, returns = NULL, config = NULL){
 ess <- switch(method,
   "raw" = n, "stationary" = n / (params$L %||% 20),
   "block" = n / (params$block_length %||% 20), "wild" = n,
   "regime" = {
     n_reg <- params$n_regimes %||% 2; ms <- 1
     if(!is.null(returns) && !is.null(config)) tryCatch({
       ri <- .prepare_regime_info(returns, config, params$vol_window %||% 20, n_reg)
       tr <- ri$trans_mat
       st <- sapply(seq_len(n_reg), function(r) 1 / max(1e-6, 1 - tr[r, r]))
       ms <- mean(st)
     }, error = function(e) NULL)
     n / (n_reg * ms)
   },
   "evt" = n * (1 - 2 * (params$tail_prob %||% 0.05)),
   "tails" = n * (1 - 2 * (params$tail_prob %||% 0.05)),
   "reset" = n,
   "garch" = n,
   "gjr_garch" = n,
   "ms_garch" = {
     n_reg <- params$ms_n_regimes %||% 2
     n / (n_reg * 2)
   },
   "ms_ar_garch_m" = {
     n_reg <- params$ms_ar_n_regimes %||% 2
     n / (n_reg * 2)
   },
   "tvtp_ms_garch" = {
     n_reg <- params$tvtp_n_regimes %||% 2
     n / (n_reg * 2)  
    },  
   n)
 max(1, ess)
   }


#' Method-Specific Preprocessing Layer
#'
#' @details
#' Constructs auxiliary model structures required for bootstrap generation
#' depending on the selected method class.
#'
#' Responsibilities:
#' - Computes regime states and transition matrices (MS models)
#' - Extracts extreme value structure (EVT models)
#' - Prepares tail-conditioned empirical distributions
#' - Fits GARCH-family latent volatility processes
#'
#' Output:
#' A method-specific structured object containing all latent state
#' variables required for simulation.
#'
#' Design role:
#' Acts as the latent state construction layer of the system,
#' transforming observed returns into model-specific internal state spaces.
#' @keywords internal
.prepare_method_info <- function(returns, config, method, params){
  p <- .get_base_params(method, params, nrow(returns))
  info <- list()
  
  if(method == "regime"){
    regime_info <- .prepare_regime_info(returns, config, p$vol_window, p$n_regimes)
    info$regimes <- regime_info$regimes
    info$trans_mat <- regime_info$trans_mat
    info$base_idx <- regime_info$base_idx
    info$vol <- regime_info$vol
    info$regime_indices <- lapply(seq_len(p$n_regimes), function(r){
      which(info$regimes == r)
    })
  }
  
  if(method == "evt"){
    evt_info <- .prepare_evt_info(returns, config, p$tail_prob, p$both_tails)
    info$left <- evt_info$left; info$right <- evt_info$right
    info$both_tails <- evt_info$both_tails; info$base_idx <- evt_info$base_idx
  }
  
  if (method == "tails") {
    info <- .prepare_tails_info(returns, config, p$tail_prob)
  }
  
  if(method == "garch"){
    garch_info <- .prepare_garch_info(returns, config, p$garch_order)
    for(nm in names(garch_info)) info[[nm]] <- garch_info[[nm]]
  }
  
  if(method == "gjr_garch"){
    gjr_info <- .prepare_gjr_garch_info(returns, config, p$garch_order)
    for(nm in names(gjr_info)) info[[nm]] <- gjr_info[[nm]]
  }
  
  if(method == "ms_garch"){
    ms_info <- .prepare_ms_garch_info(returns, config, p$ms_n_regimes, p$ms_garch_model)
    for(nm in names(ms_info)) info[[nm]] <- ms_info[[nm]]
  }
  
  if(method == "ms_ar_garch_m"){
    info <- .prepare_ms_ar_garch_m_info(returns, config, p$ms_ar_n_regimes, p$ms_ar_garch_model)
  }
  
  if(method == "tvtp_ms_garch"){
    info <- .prepare_tvtp_ms_garch_info(returns, config, p$tvtp_n_regimes, p$tvtp_garch_model)
  }          
  
  info
}


#' Volatility Regime Construction Layer
#'
#' @details
#' Constructs discrete regime states from a continuous volatility process.
#'
#' Pipeline:
#' 1. Extract base asset returns (regime reference index)
#' 2. Compute rolling volatility (Bessel-corrected)
#' 3. Discretize volatility via quantile-based thresholds
#' 4. Assign regime states
#' 5. Estimate Markov transition matrix
#'
#' Mathematical interpretation:
#' Volatility is treated as a latent state variable S_t, discretized via:
#'
#'   S_t = r  if τ_r ≤ σ_t < τ_{r+1}
#'
#' Role in system:
#' Provides the Markov state construction layer for all regime-based
#' bootstrap models (MS-GARCH, TVTP, regime bootstrap).
#' @keywords internal
.prepare_regime_info <- function(returns, config, vol_window, n_regimes){
 base_idx <- which(config$index_names == config$regime_index)
 base_ret <- returns[, base_idx]
 
 vol <- .rolling_vol(base_ret, vol_window)
 thresh <- quantile(vol, probs = seq(0, 1, length.out = n_regimes + 1))
 thresh[length(thresh)] <- thresh[length(thresh)] + 1e-10
 
 regimes <- .assign_regimes(vol, thresh)
 trans_mat <- .estimate_trans_mat(regimes, n_regimes)
 
 list(regimes = regimes, trans_mat = trans_mat, vol = vol, base_idx = base_idx)
}


#' Extreme Value Theory (EVT) Preprocessing Layer
#'
#' @details
#' Extracts and structures tail events relative to a base return series.
#'
#' Pipeline:
#' - Identifies base index (regime reference asset)
#' - Delegates tail fitting to .fit_tail (left/right)
#' - Constructs conditional FX sampling pools
#'
#' Statistical role:
#' Separates bulk behavior from extreme deviations and prepares
#' conditional distributions for tail modeling.
#'
#' Role in system:
#' Acts as the extreme event conditioning layer of the bootstrap system.
#' @keywords internal
.prepare_evt_info <- function(returns, config, tail_prob, both_tails){
  base_idx <- which(config$index_names == config$regime_index)
  base_ret <- returns[, base_idx]
  list(base_idx = base_idx,
    left = .fit_tail(returns, base_ret, tail_prob, "left"),
    right = if(both_tails) .fit_tail(returns, base_ret, tail_prob, "right") else NULL,
    both_tails = both_tails)
}


#' Tail Distribution Estimation Layer (EVT Hybrid)
#'
#' @details
#' Estimates the tail distribution of returns using a hierarchical
#' estimation strategy:
#'
#' 1. Parametric EVT (GPD MLE via evd package)
#' 2. Method of moments approximation
#' 3. Empirical fallback estimator
#' 4. Default heuristic model (low-data regime)
#'
#' Outputs:
#' - Tail threshold
#' - GPD scale and shape parameters
#' - FX conditional sampling pool
#' - Method identifier used
#'
#' Statistical interpretation:
#' Models exceedances over threshold using Generalized Pareto
#' Distribution when sufficient data is available.
#'
#' Important:
#' - Shape parameter controls tail heaviness
#' - shape ≥ 1 implies infinite mean
#' - shape ≥ 0.5 implies infinite variance
#'
#' Role in system:
#' Implements the tail law estimation layer of EVT-based bootstrap.
#' @keywords internal
.fit_tail <- function(returns, base_ret, prob, side){
  n_idx <- ncol(returns)
  
  if(side == "left"){
    thresh <- as.numeric(quantile(base_ret, prob, na.rm = TRUE))
    mask <- base_ret < thresh
    exceedances <- thresh - base_ret[mask]
  } else {
    thresh <- as.numeric(quantile(base_ret, 1 - prob, na.rm = TRUE))
    mask <- base_ret > thresh
    exceedances <- base_ret[mask] - thresh
  }
  
  n_exc <- length(exceedances)
  scale <- NULL
  shape <- NULL
  method_used <- "none"
  
  if(n_exc >= 30 && requireNamespace("evd", quietly = TRUE)){
    tryCatch({
      fit <- evd::gpd.fit(exceedances, threshold = 0, show = FALSE)
      scale <- fit$mle[1]
      shape <- fit$mle[2]
      method_used <- "MLE"
    }, error = function(e) NULL)
  }
  
  if(is.null(scale) && n_exc >= 20){
    tryCatch({
      exc_mean <- mean(exceedances)
      exc_var <- var(exceedances)
      if(exc_var > 0 && exc_mean > 0){
        ratio <- exc_mean^2 / exc_var
        shape <- max(-0.5, min(1.0, 0.5 * (1 - ratio)))
        scale <- max(0.001, 0.5 * exc_mean * (1 + ratio))
        method_used <- "Moments"
      }
    }, error = function(e) NULL)
  }
  
  if(is.null(scale) && n_exc >= 5){
    scale <- sd(exceedances)
    shape <- 0.1
    if (is.na(scale) || scale <= 0) scale <- mean(abs(exceedances))
    scale <- max(0.001, scale)
    method_used <- "Empirical"
  }
  
  if(is.null(scale)){
    overall_vol <- sd(base_ret - 1, na.rm = TRUE)
    scale <- max(0.005, overall_vol * 2)
    shape <- 0.1
    method_used <- "Default"
    warning(sprintf("Tail-Fit: Verwende Default-Parameter (nur %d Tail-Beobachtungen)", n_exc))
  }
  
  if(!is.null(shape) && shape >= 1.0){
    warning(sprintf("GPD shape=%.3f (%s): infinite mean", shape, side))
  } else if (!is.null(shape) && shape >= 0.5) {
    warning(sprintf("GPD shape=%.3f (%s): infinite variance", shape, side))
  }
  
  eur_idx <- which(config$index_names != config$regime_index)[1]
  fx_ret <- returns[, eur_idx] / base_ret
  fx_pool <- fx_ret[mask]
  if(length(fx_pool) < 5){
    warning(sprintf("EVT %s: nur %d FX im Tail, verwende Gesamt-Pool", side, length(fx_pool)))
    fx_pool <- fx_ret
  }
  
  list(prob = prob, thresh = thresh, scale = scale, shape = shape,
    fx_pool = fx_pool, method = method_used, n_tail = n_exc)
}


#' Empirical Tail Stratification Layer
#'
#' @details
#' Partitions return space into three disjoint regimes:
#' - left tail (extreme losses)
#' - bulk (central distribution)
#' - right tail (extreme gains)
#'
#' Based on quantile thresholds of a reference index:
#'
#'   left  = {r_t < q_α}
#'   right = {r_t > q_{1-α}}
#'   bulk  = complement
#'
#' Role in system:
#' Provides a non-parametric conditioning structure for bootstrap
#' methods without EVT assumptions.
#'
#' Key property:
#' Preserves empirical joint structure within each regime.
#' @keywords internal
.prepare_tails_info <- function(returns, config, tail_prob){
  base_idx <- which(config$index_names == config$regime_index)
  base_ret <- returns[, base_idx]
  
  left_thresh <- as.numeric(quantile(base_ret, tail_prob, na.rm = TRUE))
  right_thresh <- as.numeric(quantile(base_ret, 1 - tail_prob, na.rm = TRUE))
  
  left_mask <- base_ret < left_thresh
  right_mask <- base_ret > right_thresh
  
  left_idx <- which(left_mask)
  right_idx <- which(right_mask)
  bulk_idx <- which(!left_mask & !right_mask)
  
  if(length(bulk_idx) == 0){
    warning("Keine Bulk-Beobachtungen - verwende alle")
    bulk_idx <- seq_len(nrow(returns))
  }
  
  list(
    base_idx = base_idx,
    p_l = tail_prob, p_r = tail_prob,
    left_idx = as.integer(left_idx),
    right_idx = as.integer(right_idx),
    bulk_idx = as.integer(bulk_idx)
  )
}


#' Tail Bootstrap Dispatch Wrapper
#'
#' @details
#' Thin interface layer that forwards precomputed tail partitions
#' to the underlying C++ or low-level bootstrap implementation.
#'
#' Role:
#' - Decouples preprocessing from simulation engine
#' - Ensures consistent interface across bootstrap variants
#'
#' Design role:
#' Serves as the adapter layer between R preprocessing and
#' core bootstrap execution engine.
#' @keywords internal
.boot_tails_wrapper <- function(returns, info){
  .boot_tails(
    returns, info$p_l, info$p_r,
    info$bulk_idx, info$left_idx, info$right_idx
  )
}


#' FX Volatility Preprocessing Layer (GARCH(1,1))
#'
#' @details
#' Constructs a conditional FX return volatility model based on
#' a single cross-rate derived from the system’s base regime index.
#'
#' Pipeline:
#' 1. Identify base asset index (regime reference currency)
#' 2. Select secondary currency index (first non-base asset)
#' 3. Construct FX return series:
#'
#'    FX_t = R_t^EUR / R_t^BASE
#'    FX_exc_t = FX_t - 1
#'
#' 4. Estimate GARCH(1,1) parameters:
#'    - MLE via rugarch if available
#'    - fallback: moment-based initialization
#'
#' 5. Recursively compute conditional variance:
#'
#'    σ²_t = ω + α ε²_{t-1} + β σ²_{t-1}
#'
#' Statistical role:
#' Models FX return volatility as a conditionally heteroskedastic
#' process aligned with the base asset regime dynamics.
#'
#' Design role:
#' Acts as a cross-asset volatility coupling layer between
#' FX dynamics and regime-based equity processes.
#'
#' Output:
#' - FX GARCH parameters (ω, α, β, μ)
#' - standardized FX residuals (z_t)
#' - selected FX index mapping
#'
#' System role:
#' Provides a foreign exchange volatility state channel
#' for multi-asset bootstrap consistency.
#' @keywords internal
.fit_fx_garch <- function(returns, config){
  base_idx <- which(config$index_names == config$regime_index)
  eur_idx  <- which(config$index_names != config$regime_index)[1]
  fx_ret <- returns[, eur_idx] / returns[, base_idx]
  fx_exc <- fx_ret - 1.0
  n <- length(fx_exc)
  fx_mu <- mean(fx_exc)
  fx_omega <- NULL; fx_alpha <- NULL; fx_beta <- NULL
  if(requireNamespace("rugarch", quietly = TRUE)){
    tryCatch({
      fx_spec <- rugarch::ugarchspec(
        variance.model = list(model = "sGARCH", garchOrder = c(1, 1)),
        mean.model = list(armaOrder = c(0, 0), include.mean = TRUE),
        distribution.model = "norm")
      fx_fit <- rugarch::ugarchfit(spec = fx_spec, data = fx_exc, solver = "hybrid")
      fc <- rugarch::coef(fx_fit)
      fx_mu <- as.numeric(fc["mu"]); fx_omega <- as.numeric(fc["omega"])
      fx_alpha <- as.numeric(fc["alpha1"]); fx_beta <- as.numeric(fc["beta1"])
    }, error = function(e) NULL)
  }
  if(is.null(fx_omega)){
    fx_var <- var(fx_exc); fx_alpha <- 0.05; fx_beta <- 0.90
    fx_omega <- fx_var * (1 - fx_alpha - fx_beta)
    if(fx_omega <= 0) fx_omega <- fx_var * 0.05
  }
  fx_sigma2 <- numeric(n); fx_sigma2[1] <- var(fx_exc); fx_e <- fx_exc - fx_mu
  for(t in 2:n){
    fx_sigma2[t] <- fx_omega + fx_alpha * fx_e[t-1]^2 + fx_beta * fx_sigma2[t-1]
    if(fx_sigma2[t] < 1e-12) fx_sigma2[t] <- 1e-12
  }
  fx_sigma <- sqrt(fx_sigma2)
  fx_std_resid <- fx_e / fx_sigma
  valid <- is.finite(fx_std_resid)
  fx_std_resid <- fx_std_resid[valid]
  if(length(fx_std_resid) > 1 && sd(fx_std_resid) > 0)
    fx_std_resid <- (fx_std_resid - mean(fx_std_resid)) / sd(fx_std_resid)
  message(sprintf("  FX-GARCH(1,1): mu=%.6f, omega=%.2e, alpha=%.4f, beta=%.4f",
                  fx_mu, fx_omega, fx_alpha, fx_beta))
  list(eur_idx = eur_idx, fx_mu = fx_mu, fx_omega = fx_omega,
       fx_alpha = fx_alpha, fx_beta = fx_beta, fx_std_resid = fx_std_resid)
}


#' Single-Regime GARCH Latent Volatility Construction Layer
#'
#' @details
#' Constructs a conditional volatility model for the base asset
#' within a single-regime framework.
#'
#' Pipeline:
#' 1. Extract base regime return series
#' 2. Compute excess returns:
#'
#'    ε_t = R_t - 1
#'
#' 3. Estimate GARCH(1,1) parameters via:
#'    - MLE (rugarch)
#'    - numerical optimization (fallback)
#'    - moment-based heuristic (last resort)
#'
#' 4. Construct conditional variance process:
#'
#'    σ²_t = ω + α ε²_{t-1} + β σ²_{t-1}
#'
#' 5. Standardize residuals:
#'
#'    z_t = ε_t / σ_t
#'
#' Statistical interpretation:
#' Models volatility clustering under a stationary GARCH(1,1)
#' assumption with optional MLE calibration.
#'
#' Persistence measure:
#'    ρ = α + β
#'
#' where:
#' - ρ ≈ 1 indicates near-IGARCH behavior
#' - ρ < 1 ensures covariance stationarity
#'
#' Role in system:
#' Acts as the single-regime volatility state extractor,
#' providing latent volatility structure for bootstrap generation.
#'
#' Output:
#' - GARCH parameters (μ, ω, α, β)
#' - standardized residual process
#' - persistence diagnostic
#' - FX volatility sub-model (via .fit_fx_garch)
#' @keywords internal
.prepare_garch_info <- function(returns, config, garch_order = c(1, 1)){
  base_idx <- which(config$index_names == config$regime_index)
  base_ret <- returns[, base_idx]
  n <- length(base_ret)
  k <- ncol(returns)
  
  exc <- base_ret - 1.0
  mu <- mean(exc)
  
  omega <- NULL; alpha <- NULL; beta <- NULL
  sigma2_vec <- NULL
  fit_method <- "none"
  
  if(requireNamespace("rugarch", quietly = TRUE)){
    tryCatch({
      spec <- rugarch::ugarchspec(
        variance.model = list(model = "sGARCH", garchOrder = garch_order),
        mean.model = list(armaOrder = c(0, 0), include.mean = TRUE),
        distribution.model = "norm"
      )
      fit <- rugarch::ugarchfit(spec = spec, data = exc, solver = "hybrid")
      
      coefs <- rugarch::coef(fit)
      mu    <- coefs["mu"]
      omega <- coefs["omega"]
      alpha <- coefs["alpha1"]
      beta  <- coefs["beta1"]
      sigma2_vec <- as.numeric(rugarch::sigma(fit))^2
      fit_method <- "rugarch"
    }, error = function(e) NULL)
  }
  
  if(is.null(omega)){
    tryCatch({
      garch_nll <- function(theta){
        om <- exp(theta[1])
        al <- 1 / (1 + exp(-theta[2])) * 0.5
        be <- 1 / (1 + exp(-theta[3])) * 0.999
        if (al + be >= 0.9999) return(1e10)
        s2 <- om / (1 - al - be)
        nll <- 0
        e <- exc - mu
        for (t in seq_along(e)) {
          nll <- nll + 0.5 * (log(s2) + e[t]^2 / s2)
          s2 <- om + al * e[t]^2 + be * s2
          if (s2 < 1e-12) s2 <- 1e-12
        }
        nll
      }
      
      sv <- var(exc)
      opt <- optim(c(log(sv * 0.05), 0, 2), garch_nll, method = "Nelder-Mead",
                   control = list(maxit = 5000))
      
      omega <- exp(opt$par[1])
      alpha <- 1 / (1 + exp(-opt$par[2])) * 0.5
      beta  <- 1 / (1 + exp(-opt$par[3])) * 0.999
      
      sigma2_vec <- numeric(n)
      s2 <- omega / (1 - alpha - beta)
      e <- exc - mu
      for (t in seq_len(n)) {
        sigma2_vec[t] <- s2
        s2 <- omega + alpha * e[t]^2 + beta * s2
        if (s2 < 1e-12) s2 <- 1e-12
      }
      fit_method <- "optim"
    }, error = function(e) NULL)
  }
  
  if(is.null(omega)){
    sv <- var(exc)
    alpha <- 0.08; beta <- 0.88
    omega <- sv * (1 - alpha - beta)
    
    sigma2_vec <- numeric(n)
    s2 <- sv
    e <- exc - mu
    for(t in seq_len(n)){
      sigma2_vec[t] <- s2
      s2 <- omega + alpha * e[t]^2 + beta * s2
      if (s2 < 1e-12) s2 <- 1e-12
    }
    fit_method <- "moments"
    warning("GARCH: rugarch und optim fehlgeschlagen, verwende Moment-Schätzer")
  }
  
  sigma_vec <- sqrt(pmax(sigma2_vec, 1e-12))
  std_resid <- (exc - mu) / sigma_vec
  std_resid <- (std_resid - mean(std_resid)) / sd(std_resid)
  
  fx <- .fit_fx_garch(returns, config)
  
  persistence <- alpha + beta
  if(persistence >= 0.999){
    warning(sprintf("GARCH: alpha+beta = %.4f (IGARCH/non-stationary)", persistence))
  }
  
  list(
    mu = mu, omega = omega, alpha = alpha, beta = beta,
    std_resid = std_resid, base_idx = base_idx,
    eur_idx = fx$eur_idx, fx_mu = fx$fx_mu, fx_omega = fx$fx_omega,
    fx_alpha = fx$fx_alpha, fx_beta = fx$fx_beta, fx_std_resid = fx$fx_std_resid,
    fit_method = fit_method, persistence = persistence
  )
}


#' GARCH Bootstrap Dispatch Layer
#'
#' @details
#' Thin interface layer between R-side model preprocessing and
#' low-level bootstrap simulation engine.
#'
#' Responsibilities:
#' - Validates base index integrity
#' - Converts R indexing (1-based) → C++ indexing (0-based)
#' - Forwards:
#'   * GARCH parameters
#'   * standardized residuals
#'   * FX volatility state
#'
#' Design role:
#' Acts as the execution boundary adapter between
#' statistical model layer and simulation kernel.
#'
#' Important:
#' No statistical computation is performed here.
#' This is purely a deterministic data marshaling layer.
#' @keywords internal
.boot_garch_wrapper <- function(returns, info){
  base_idx <- info$base_idx
  if(is.null(base_idx) || base_idx < 1 || base_idx > ncol(returns)){
    stop("GARCH: ungültiger base_idx (", base_idx, ")")
  }
  .boot_garch(
    returns, as.integer(base_idx - 1), as.integer(info$eur_idx - 1),
    info$mu, info$omega, info$alpha, info$beta, info$std_resid,
    info$fx_mu, info$fx_omega, info$fx_alpha, info$fx_beta, info$fx_std_resid
  )
}


#' Asymmetric Volatility State Construction Layer (GJR-GARCH)
#'
#' @details
#' Extends the standard GARCH framework by incorporating
#' leverage effects (asymmetry in volatility response).
#'
#' Pipeline:
#' 1. Extract base asset excess returns:
#'
#'    ε_t = R_t - 1
#'
#' 2. Estimate GJR-GARCH parameters:
#'
#'    σ²_t = ω + (α + γ I_{t-1}) ε²_{t-1} + β σ²_{t-1}
#'
#'    where:
#'    I_{t-1} = 1 if ε_{t-1} < 0 else 0
#'
#' 3. Parameter estimation hierarchy:
#'    - MLE via rugarch (preferred)
#'    - moment-based structural estimator (fallback)
#'
#' 4. Compute conditional variance path σ²_t
#'
#' Statistical interpretation:
#' Captures leverage effect:
#' negative shocks increase volatility more than positive shocks.
#'
#' Key parameter:
#' - γ (gamma): asymmetry coefficient
#'
#'   γ > 0 → negative returns amplify volatility
#'
#' Role in system:
#' Serves as the asymmetric volatility regime layer
#' within the bootstrap state construction hierarchy.
#'
#' Output:
#' - GJR-GARCH parameters (ω, α, β, γ)
#' - standardized residuals
#' - persistence: α + β + γ/2
#' - FX volatility coupling (via .fit_fx_garch)
#' @keywords internal
.prepare_gjr_garch_info <- function(returns, config, garch_order){
  base_idx <- which(config$index_names == config$regime_index)
  base_ret <- returns[, base_idx]
  n <- length(base_ret)
  k <- ncol(returns)

  excess <- base_ret - 1.0

  mu <- NULL; omega <- NULL; alpha <- NULL; beta <- NULL; gamma <- NULL
  sigma2_t <- NULL
  method_used <- "none"

  if(requireNamespace("rugarch", quietly = TRUE)){
    tryCatch({
      spec <- rugarch::ugarchspec(
        variance.model = list(model = "gjrGARCH",
                              garchOrder = as.integer(garch_order)),
        mean.model = list(armaOrder = c(0, 0), include.mean = TRUE),
        distribution.model = "norm"
      )
      fit <- rugarch::ugarchfit(spec = spec, data = excess, solver = "hybrid")

      coefs <- rugarch::coef(fit)
      mu    <- as.numeric(coefs["mu"])
      omega <- as.numeric(coefs["omega"])
      alpha <- as.numeric(coefs["alpha1"])
      beta  <- as.numeric(coefs["beta1"])
      gamma <- as.numeric(coefs["gamma1"])
      sigma2_t <- as.numeric(rugarch::sigma(fit))^2
      method_used <- "MLE (rugarch)"
    }, error = function(e) {
      warning(sprintf("GJR-GARCH rugarch fit failed: %s – using moment estimator", e$message))
    })
  }

  if(is.null(mu)){
    mu <- mean(excess)
    resid <- excess - mu
    resid_sq <- resid^2
    sample_var <- mean(resid_sq)

    neg_mask <- resid < 0
    var_neg <- mean(resid_sq[neg_mask])
    var_pos <- mean(resid_sq[!neg_mask])

    gamma_ratio <- max(0, (var_neg - var_pos) / max(var_pos, 1e-10))
    gamma <- min(0.3, gamma_ratio * 0.15)

    acf_sq <- acf(resid_sq, lag.max = 2, plot = FALSE)$acf
    rho1 <- max(0.01, acf_sq[2])
    rho2 <- max(0.001, acf_sq[3])

    beta <- min(0.98, max(0.5, rho2 / rho1))
    alpha <- min(0.2, max(0.01, rho1 * (1 - beta^2)))

    persistence <- alpha + beta + gamma / 2
    if (persistence >= 0.9999) {
      beta <- 0.80; alpha <- 0.08; gamma <- 0.10
    }

    omega <- sample_var * (1 - (alpha + beta + gamma / 2))
    if (omega <= 0) omega <- 1e-8

    sigma2_t <- numeric(n)
    sigma2_t[1] <- sample_var
    for (t in 2:n) {
      ind <- if (resid[t-1] < 0) 1.0 else 0.0
      sigma2_t[t] <- omega + (alpha + gamma * ind) * resid[t-1]^2 + beta * sigma2_t[t-1]
    }

    method_used <- "Momenten-Schätzer"
    warning("GJR-GARCH via Momenten-Schätzer (rugarch nicht verfügbar)")
  }

  sigma_t <- sqrt(pmax(sigma2_t, 1e-12))
  std_resid <- (excess - mu) / sigma_t

  valid <- is.finite(std_resid)
  if(sum(valid) < n * 0.9){
    warning(sprintf("GJR-GARCH: %d/%d standardisierte Residuen ungültig", sum(!valid), n))
  }
  std_resid <- std_resid[valid]

  fx <- .fit_fx_garch(returns, config)

  message(sprintf(
    "GJR-GARCH(%d,%d) [%s]: mu=%.6f, omega=%.2e, alpha=%.4f, beta=%.4f, gamma=%.4f, persistence=%.4f",
    garch_order[1], garch_order[2], method_used,
    mu, omega, alpha, beta, gamma, alpha + beta + gamma / 2
  ))

  list(
    mu = mu, omega = omega, alpha = alpha, beta = beta, gamma = gamma,
    std_resid = std_resid, base_idx = base_idx,
    eur_idx = fx$eur_idx, fx_mu = fx$fx_mu, fx_omega = fx$fx_omega,
    fx_alpha = fx$fx_alpha, fx_beta = fx$fx_beta, fx_std_resid = fx$fx_std_resid
  )
}


#' Asymmetric GARCH Bootstrap Dispatch Layer
#'
#' @details
#' Adapter layer between R-side GJR-GARCH preprocessing
#' and C++ bootstrap simulation engine.
#'
#' Responsibilities:
#' - Converts parameter space into simulation-ready structure
#' - Ensures consistency of asymmetry parameter γ
#' - Forwards FX state augmentation
#'
#' System role:
#' Acts as the asymmetric volatility execution bridge
#' between statistical modeling and Monte Carlo kernel.
#' @keywords internal
.boot_gjr_garch_wrapper <- function(returns, info){
  .boot_gjr_garch(
    returns, as.integer(info$base_idx - 1), as.integer(info$eur_idx - 1),
    info$mu, info$omega, info$alpha, info$beta, info$gamma, info$std_resid,
    info$fx_mu, info$fx_omega, info$fx_alpha, info$fx_beta, info$fx_std_resid
  )
}


#' MS-GARCH Information Construction Layer
#'
#' @details
#' This function implements the *full latent state construction pipeline*
#' for Markov-switching GARCH-family models prior to bootstrap execution.
#'
#' It transforms observed return data into a structured hierarchical
#' state-space representation consisting of:
#'
#' - regime-dependent conditional means
#' - regime-specific GARCH volatility parameters
#' - hidden Markov state sequence (filtered or smoothed)
#' - stationary distribution of regime process
#' - conditional variance path reconstruction
#' - standardized residual distributions per regime
#' - FX-linked auxiliary volatility process
#'
#' Model decomposition:
#' The system assumes a hidden state representation:
#'
#'   S_t ∈ {1, ..., K}   (latent regime process)
#'
#'   r_t | S_t = k  ~  μ_k + ε_t
#'   ε_t = σ_t z_t
#'   σ_t^2 follows regime-dependent GARCH dynamics
#'
#' where regime switching is governed by a Markov transition matrix:
#'
#'   P(S_t = j | S_{t-1} = i) = P_ij
#'
#' Core estimation stages:
#'
#' 1. Model specification via MSGARCH::CreateSpec
#' 2. Maximum likelihood estimation (FitML)
#' 3. Extraction of regime-specific parameters:
#'    - ω_k (omega_vec)
#'    - α_k (alpha_vec)
#'    - β_k (beta_vec)
#'    - γ_k (gamma_vec, if GJR-GARCH)
#'
#' 4. Reconstruction of transition dynamics:
#'    - empirical transition matrix
#'    - stationary distribution via power iteration
#'
#' 5. State inference:
#'    - Viterbi path (hard classification)
#'    - or smoothing probabilities (soft classification)
#'    - fallback to trivial regime if inference fails
#'
#' 6. Conditional variance reconstruction:
#'    - direct extraction from MSGARCH if available
#'    - fallback to recursive GARCH filtering equation:
#'
#'      σ_t^2 = ω_k + (α_k + γ_k I_{ε<0}) ε_{t-1}^2 + β_k σ_{t-1}^2
#'
#' 7. Standardized residual construction:
#'    - regime-adjusted mean subtraction
#'    - variance scaling
#'    - per-regime normalization
#'
#' 8. FX volatility coupling:
#'    - independent FX-GARCH process estimation
#'    - used for cross-asset bootstrap coupling
#'
#' System role:
#' This function defines the complete latent regime inference layer
#' of the MS-GARCH bootstrap architecture.
#'
#' It acts as a transformation pipeline from:
#'
#'   observed returns → hidden regime structure → stochastic simulation state
#'
#' Important design properties:
#' - fully deterministic given inputs and MSGARCH fit
#' - robust fallback mechanisms for numerical instability
#' - regime-consistent normalization of residual distributions
#' - separation of inference (state estimation) and simulation (bootstrap)
#'
#' Failure handling hierarchy:
#' 1. MSGARCH maximum likelihood estimation
#' 2. fallback conditional variance recursion
#' 3. uniform regime approximation (degenerate model)
#'
#' Output structure:
#' A fully resolved MS-GARCH state object containing:
#' - regime parameters (μ, ω, α, β, γ)
#' - transition matrix and stationary distribution
#' - standardized residual pools per regime
#' - FX-GARCH auxiliary process
#' - base index mapping for simulation alignment
#' @keywords internal
.prepare_ms_garch_info <- function(returns, config, n_regimes, garch_model){
  if(!requireNamespace("MSGARCH", quietly = TRUE)) {
    stop("MS-GARCH Bootstrap erfordert das MSGARCH-Paket. ",
         "Installieren mit: install.packages('MSGARCH')")
  }

  base_idx <- which(config$index_names == config$regime_index)
  base_ret <- returns[, base_idx]
  n <- length(base_ret)
  k <- ncol(returns)
  K <- n_regimes

  excess <- base_ret - 1.0

  spec <- MSGARCH::CreateSpec(
    variance.spec = list(model = rep(garch_model, K)),
    distribution.spec = list(distribution = rep("norm", K)),
    switch.spec = list(do.mix = FALSE)
  )

  fit <- tryCatch({
    MSGARCH::FitML(spec = spec, data = excess)
  }, error = function(e){
    stop(sprintf("MS-GARCH(%d, %s) Fitting fehlgeschlagen: %s",
                 K, garch_model, e$message))
  })

  coefs <- fit$par
  omega_vec <- numeric(K)
  alpha_vec <- numeric(K)
  beta_vec  <- numeric(K)
  gamma_vec <- numeric(K)

  for(r in seq_len(K)){
    omega_vec[r] <- coefs[paste0("alpha0_", r)]
    alpha_vec[r] <- coefs[paste0("alpha1_", r)]
    beta_vec[r]  <- coefs[paste0("beta_", r)]
    if (garch_model == "gjrGARCH") {
      gamma_vec[r] <- coefs[paste0("alpha2_", r)]
    }
  }

  trans_mat <- MSGARCH::TransMat(fit)

  pi_vec <- rep(1 / K, K)
  P <- trans_mat
  for(i in 1:1000){
    pi_new <- as.numeric(pi_vec %*% P)
    if (max(abs(pi_new - pi_vec)) < 1e-10) break
    pi_vec <- pi_new
  }
  stationary_prob <- pi_vec / sum(pi_vec)
  state_out <- MSGARCH::State(fit)

  if(!is.null(state_out$Viterbi)){
    viterbi <- state_out$Viterbi
    if(is.matrix(viterbi) || is.array(viterbi)){
      regimes <- as.integer(viterbi[, 1])
    } else {
      regimes <- as.integer(viterbi)
    }
    if(length(regimes) != n){
      warning(sprintf("MS-GARCH: Viterbi-Länge %d != n=%d, schneide ab", length(regimes), n))
      regimes <- regimes[seq_len(n)]
    }
  } else if(!is.null(state_out$SmoothProb)){
    sp <- state_out$SmoothProb
    sp_mat <- sp[, 1, , drop = TRUE]
    sp_mat <- sp_mat[-1, , drop = FALSE]
    regimes <- apply(sp_mat, 1, which.max)
  } else {
    regimes <- rep(1, n)
    warning("MS-GARCH: Weder Viterbi noch SmoothProb verfügbar")
  }

  mu_global <- mean(excess)
  mu_vec <- numeric(K)
  for(r in seq_len(K)){
    idx <- which(regimes == r)
    mu_vec[r] <- if (length(idx) >= 10) mean(excess[idx]) else mu_global
  }

  cond_var <- tryCatch({
    vol <- MSGARCH::Volatility(fit)
    vol^2
  }, error = function(e){
    sigma2_t <- numeric(n)
    sigma2_t[1] <- var(excess)
    resid <- excess - mu_global
    for(t in 2:n){
      r_regime <- regimes[t]
      ind <- if (resid[t-1] < 0) 1.0 else 0.0
      sigma2_t[t] <- omega_vec[r_regime] +
        (alpha_vec[r_regime] + gamma_vec[r_regime] * ind) * resid[t-1]^2 +
        beta_vec[r_regime] * sigma2_t[t-1]
      if (sigma2_t[t] < 1e-12) sigma2_t[t] <- 1e-12
    }
    sigma2_t
  })

  sigma_t <- sqrt(pmax(cond_var, 1e-12))
  mu_per_obs <- mu_vec[regimes]
  all_std_resid <- (excess - mu_per_obs) / sigma_t

  std_resid_list <- lapply(seq_len(K), function(r){
    idx <- which(regimes == r)
    if(length(idx) < 10){
      warning(sprintf("MS-GARCH: Regime %d hat nur %d Beobachtungen, verwende Gesamt-Pool",
                      r, length(idx)))
      all_std_resid[is.finite(all_std_resid)]
    } else {
      res <- all_std_resid[idx]
      res[is.finite(res)]
    }
  })

  fx <- .fit_fx_garch(returns, config)

  msg_parts <- sprintf(
    "  Regime %d: mu=%.6f, omega=%.2e, alpha=%.4f, beta=%.4f, gamma=%.4f, P(stay)=%.3f, n=%d",
    seq_len(K), mu_vec, omega_vec, alpha_vec, beta_vec, gamma_vec,
    diag(trans_mat), sapply(seq_len(K), function(r) sum(regimes == r))
  )
  message(sprintf("MS-GARCH(%d, %s):\n%s\n  Stationär: %s",
                  K, garch_model,
                  paste(msg_parts, collapse = "\n"),
                  paste(sprintf("%.3f", stationary_prob), collapse = ", ")))

  list(
    n_regimes = K, mu_vec = mu_vec,
    omega_vec = omega_vec, alpha_vec = alpha_vec,
    beta_vec = beta_vec, gamma_vec = gamma_vec,
    trans_mat = trans_mat, stationary_prob = stationary_prob,
    std_resid_list = std_resid_list, base_idx = base_idx,
    eur_idx = fx$eur_idx, fx_mu = fx$fx_mu, fx_omega = fx$fx_omega,
    fx_alpha = fx$fx_alpha, fx_beta = fx$fx_beta, fx_std_resid = fx$fx_std_resid
  )
}


#' MS-GARCH Bootstrap Dispatch Layer
#'
#' @details
#' Bridges regime-switching volatility model with
#' low-level simulation engine.
#'
#' Responsibilities:
#' - Encodes regime paths
#' - Aligns regime-dependent parameter vectors
#' - Ensures consistency of transition dynamics
#'
#' System role:
#' Acts as the Markov-state simulation interface layer
#' between stochastic regime model and bootstrap kernel.
#' @keywords internal
.boot_ms_garch_wrapper <- function(returns, info){
  .boot_ms_garch(
    returns, as.integer(info$base_idx - 1), as.integer(info$eur_idx - 1),
    as.integer(info$n_regimes),
    info$mu_vec, info$omega_vec, info$alpha_vec,
    info$beta_vec, info$gamma_vec,
    info$trans_mat, info$std_resid_list, info$stationary_prob,
    info$fx_mu, info$fx_omega, info$fx_alpha, info$fx_beta, info$fx_std_resid
  )
}


#' Extreme Value Theory Bootstrap Dispatch Layer (Bulk + Tail Mixture)
#'
#' @details
#' Implements a hybrid bootstrap mechanism that separates the empirical
#' distribution of returns into three structural components:
#'
#'   1. Left tail  (extreme losses)
#'   2. Bulk       (central empirical distribution)
#'   3. Right tail (extreme gains)
#'
#' Pipeline:
#'
#' 1. Identify base regime index (reference asset)
#' 2. Construct bulk region using threshold filtering:
#'
#'    bulk = { r_t ≥ left.thresh } ∩ { r_t ≤ right.thresh }
#'
#' 3. Extract extreme value structures:
#'    - left tail: GPD parameters (prob, threshold, scale, shape)
#'    - right tail: optional mirrored GPD structure
#'
#' 4. Construct FX sampling pools for tail substitution:
#'    - left.fx_pool
#'    - right.fx_pool
#'
#' 5. Delegate full bootstrap generation to C++ EVT engine:
#'
#'    .boot_gpd(...)
#'
#' Statistical interpretation:
#' Combines:
#' - Empirical bulk resampling
#' - Generalized Pareto tail extrapolation
#' - FX-conditioned tail augmentation
#'
#' This results in a semi-parametric extreme value bootstrap system.
#'
#' Role in system:
#' Acts as the distribution decomposition and tail coupling layer
#' for extreme event simulation.
#'
#' Important design property:
#' Ensures continuity between:
#'   empirical core distribution ↔ asymptotic tail law
#' @keywords internal
.boot_evt <- function(returns, info){
  base_idx <- info$base_idx
  eur_idx  <- info$eur_idx %||% (if(base_idx == 1) 2 else 1)
  
  if(is.null(base_idx) || base_idx < 1 || base_idx > ncol(returns)){
    stop("base_idx ungültig (", base_idx, "), erwartet 1-", ncol(returns))
  }
  
  left <- info$left
  right <- info$right
  
  base_ret <- returns[, base_idx]
  bulk_mask <- base_ret >= left$thresh
  
  if(!is.null(right) && !is.null(right$thresh) && is.finite(right$thresh)){
    bulk_mask <- bulk_mask & base_ret <= right$thresh
  }
  
  bulk_idx <- which(bulk_mask)
  
  if(length(bulk_idx) == 0){
    warning("Keine Bulk-Beobachtungen - verwende alle")
    bulk_idx <- seq_len(nrow(returns))
  }
  
  fx_pool_left  <- if(!is.null(left$fx_pool))  left$fx_pool  else rep(1, 10)
  fx_pool_right <- if(!is.null(right) && !is.null(right$fx_pool)) right$fx_pool else rep(1, 10)
  
  right_prob   <- if (!is.null(right)) right$prob   else 0
  right_thresh <- if (!is.null(right)) right$thresh else Inf
  right_scale  <- if (!is.null(right)) right$scale  else 0
  right_shape  <- if (!is.null(right)) right$shape  else 0
  
  .boot_gpd(
    returns, as.integer(base_idx - 1), as.integer(eur_idx - 1),
    left$prob, left$thresh, left$scale, left$shape, fx_pool_left,
    right_prob, right_thresh, right_scale, right_shape, fx_pool_right,
    as.integer(bulk_idx)
  )
}


#' Markov-Switching AR(1)-GJR-GARCH-M State Construction Layer
#'
#' @details
#' Extends the MS-GARCH framework by embedding:
#'
#'   - Autoregressive dynamics (AR(1))
#'   - Volatility feedback into mean (GARCH-in-Mean)
#'
#' Full conditional structure per regime r:
#'
#'   ε_t = R_t - 1
#'
#'   σ²_t = ω_r + (α_r + γ_r I_{t-1}) ε²_{t-1} + β_r σ²_{t-1}
#'
#'   μ_t = μ_r + φ_r ε_{t-1} + λ_r σ_t
#'
#' Pipeline:
#'
#' 1. Fit MS-GARCH via maximum likelihood (MSGARCH)
#' 2. Extract regime-specific volatility parameters:
#'    (ω_r, α_r, β_r, γ_r)
#' 3. Infer hidden regime path S_t via:
#'    - Viterbi decoding OR
#'    - Smoothed posterior mode
#' 4. Estimate regime-conditional means μ_r
#' 5. Reconstruct conditional variance process σ²_t
#'
#' 6. Estimate AR(1) dynamics per regime:
#'
#'    φ_r from OLS:
#'       ε_t ~ ε_{t-1}
#'
#' 7. Estimate GARCH-in-Mean effect:
#'
#'    λ_r from regression:
#'       ε_t - μ_r - φ_r ε_{t-1} ~ σ_t
#'
#' Statistical interpretation:
#' This model combines three dependency structures:
#'
#'   (i) Markov regime switching (macro structure)
#'   (ii) Autoregressive mean dynamics (micro memory)
#'   (iii) Volatility feedback into returns (risk premium channel)
#'
#' Resulting system:
#'
#'   Fully coupled state-space model:
#'   S_t → (μ_t, σ_t) → ε_t
#'
#' Role in system:
#' Represents the *highest-order nonlinear regime-dependent
#' stochastic volatility + mean feedback system*.
#'
#' Output:
#' - regime-specific AR parameters (φ_r)
#' - volatility feedback parameters (λ_r)
#' - full MS-GARCH structure
#' - standardized residual system per regime
#' @keywords internal
.prepare_ms_ar_garch_m_info <- function(returns, config, n_regimes, garch_model){

  if(!requireNamespace("MSGARCH", quietly = TRUE)) {
    stop("MS-AR-GARCH-M Bootstrap erfordert das MSGARCH-Paket. ",
         "Installieren mit: install.packages('MSGARCH')")
  }

  base_idx <- which(config$index_names == config$regime_index)
  base_ret <- returns[, base_idx]
  n <- length(base_ret)
  k <- ncol(returns)
  K <- n_regimes

  excess <- base_ret - 1.0

  spec <- MSGARCH::CreateSpec(
    variance.spec = list(model = rep(garch_model, K)),
    distribution.spec = list(distribution = rep("norm", K)),
    switch.spec = list(do.mix = FALSE)
  )

  fit <- tryCatch({
    MSGARCH::FitML(spec = spec, data = excess)
  }, error = function(e){
    stop(sprintf("MS-AR-GARCH-M(%d, %s) Fitting fehlgeschlagen: %s",
                 K, garch_model, e$message))
  })

  coefs <- fit$par
  omega_vec <- numeric(K)
  alpha_vec <- numeric(K)
  beta_vec  <- numeric(K)
  gamma_vec <- numeric(K)

  for(r in seq_len(K)){
    omega_vec[r] <- coefs[paste0("alpha0_", r)]
    alpha_vec[r] <- coefs[paste0("alpha1_", r)]
    beta_vec[r]  <- coefs[paste0("beta_", r)]
    if (garch_model == "gjrGARCH") {
      gamma_vec[r] <- coefs[paste0("alpha2_", r)]
    }
  }

  trans_mat <- MSGARCH::TransMat(fit)

  pi_vec <- rep(1 / K, K)
  P <- trans_mat
  for(i in 1:1000){
    pi_new <- as.numeric(pi_vec %*% P)
    if (max(abs(pi_new - pi_vec)) < 1e-10) break
    pi_vec <- pi_new
  }
  stationary_prob <- pi_vec / sum(pi_vec)

  state_out <- MSGARCH::State(fit)

  if(!is.null(state_out$Viterbi)){
    viterbi <- state_out$Viterbi
    if(is.matrix(viterbi) || is.array(viterbi)){
      regimes <- as.integer(viterbi[, 1])
    } else {
      regimes <- as.integer(viterbi)
    }
    if(length(regimes) != n){
      warning(sprintf("MS-AR-GARCH-M: Viterbi-Länge %d != n=%d", length(regimes), n))
      regimes <- regimes[seq_len(n)]
    }
  } else if(!is.null(state_out$SmoothProb)){
    sp <- state_out$SmoothProb
    sp_mat <- sp[, 1, , drop = TRUE]
    sp_mat <- sp_mat[-1, , drop = FALSE]
    regimes <- apply(sp_mat, 1, which.max)
  } else {
    regimes <- rep(1, n)
    warning("MS-AR-GARCH-M: Weder Viterbi noch SmoothProb verfügbar")
  }

  mu_global <- mean(excess)
  mu_vec <- numeric(K)
  for(r in seq_len(K)){
    idx <- which(regimes == r)
    mu_vec[r] <- if (length(idx) >= 10) mean(excess[idx]) else mu_global
  }

  cond_var <- tryCatch({
    vol <- MSGARCH::Volatility(fit)
    vol^2
  }, error = function(e){
    sigma2_t <- numeric(n)
    sigma2_t[1] <- var(excess)
    resid <- excess - mu_global
    for(t in 2:n){
      r_regime <- regimes[t]
      ind <- if (resid[t-1] < 0) 1.0 else 0.0
      sigma2_t[t] <- omega_vec[r_regime] +
        (alpha_vec[r_regime] + gamma_vec[r_regime] * ind) * resid[t-1]^2 +
        beta_vec[r_regime] * sigma2_t[t-1]
      if (sigma2_t[t] < 1e-12) sigma2_t[t] <- 1e-12
    }
    sigma2_t
  })

  sigma_t <- sqrt(pmax(cond_var, 1e-12))

  phi_vec <- numeric(K)
  lag_excess <- c(0, excess[-n])

  for(r in seq_len(K)){
    idx <- which(regimes == r)
    if(length(idx) < 30){
      phi_vec[r] <- 0.0
      next
    }
    tryCatch({
      y <- excess[idx]
      x <- lag_excess[idx]
      fit_ar <- lm.fit(cbind(1, x), y)
      phi_est <- fit_ar$coefficients[2]
      if(is.finite(phi_est)){
        phi_vec[r] <- max(-0.5, min(0.5, phi_est))
      }
    }, error = function(e){
      phi_vec[r] <<- 0.0
    })
  }

  lambda_vec <- numeric(K)

  for(r in seq_len(K)){
    idx <- which(regimes == r)
    if(length(idx) < 30){
      lambda_vec[r] <- 0.0
      next
    }
    tryCatch({
      y_adj <- excess[idx] - mu_vec[r] - phi_vec[r] * lag_excess[idx]
      x_sigma <- sigma_t[idx]
      fit_lm <- lm.fit(cbind(x_sigma), y_adj)
      lambda_est <- fit_lm$coefficients[1]
      if(is.finite(lambda_est)){
        lambda_vec[r] <- max(-5.0, min(5.0, lambda_est))
      }
    }, error = function(e){
      lambda_vec[r] <<- 0.0
    })
  }

  cond_mean <- mu_vec[regimes] + phi_vec[regimes] * lag_excess + lambda_vec[regimes] * sigma_t

  all_std_resid <- (excess - cond_mean) / sigma_t

  std_resid_list <- lapply(seq_len(K), function(r){
    idx <- which(regimes == r)
    if(length(idx) < 10){
      warning(sprintf("MS-AR-GARCH-M: Regime %d hat nur %d Beobachtungen, verwende Gesamt-Pool",
                      r, length(idx)))
      res <- all_std_resid[is.finite(all_std_resid)]
    } else {
      res <- all_std_resid[idx]
      res <- res[is.finite(res)]
    }

    if(length(res) > 1 && sd(res) > 0){
      res <- (res - mean(res)) / sd(res)
    }
    res
  })

  fx <- .fit_fx_garch(returns, config)

  msg_parts <- sprintf(
    paste0("  Regime %d: mu=%.6f, phi=%.4f, lambda=%.4f, ",
           "omega=%.2e, alpha=%.4f, beta=%.4f, gamma=%.4f, ",
           "P(stay)=%.3f, n=%d"),
    seq_len(K), mu_vec, phi_vec, lambda_vec,
    omega_vec, alpha_vec, beta_vec, gamma_vec,
    diag(trans_mat), sapply(seq_len(K), function(r) sum(regimes == r))
  )

  ar_info  <- sprintf("phi=[%s]",
    paste(sprintf("%.4f", phi_vec), collapse=", "))
  gm_info  <- sprintf("lambda=[%s]",
    paste(sprintf("%.4f", lambda_vec), collapse=", "))

  message(sprintf(
    "MS-AR(1)-GJR-GARCH-M(%d, %s):\n%s\n  Stationär: [%s]\n  AR(1): %s\n  GARCH-M: %s",
    K, garch_model,
    paste(msg_parts, collapse = "\n"),
    paste(sprintf("%.3f", stationary_prob), collapse = ", "),
    ar_info, gm_info
  ))

  list(
    n_regimes      = K,
    mu_vec         = mu_vec,
    omega_vec      = omega_vec,
    alpha_vec      = alpha_vec,
    beta_vec       = beta_vec,
    gamma_vec      = gamma_vec,
    phi_vec        = phi_vec,
    lambda_vec     = lambda_vec,
    trans_mat      = trans_mat,
    stationary_prob = stationary_prob,
    std_resid_list = std_resid_list,
    base_idx       = base_idx,
    eur_idx = fx$eur_idx, fx_mu = fx$fx_mu, fx_omega = fx$fx_omega,
    fx_alpha = fx$fx_alpha, fx_beta = fx$fx_beta, fx_std_resid = fx$fx_std_resid
  )
}


#' MS-AR-GARCH-M Bootstrap Execution Layer
#'
#' @details
#' Interface layer between R-side regime/AR/GARCH-M preprocessing
#' and the low-level C++ simulation engine.
#'
#' Responsibilities:
#' - Encodes regime-dependent mean-volatility coupling
#' - Transfers AR(1) + GARCH-M parameters
#' - Preserves regime transition structure and stationarity vector
#'
#' Design role:
#' Acts as the complete stochastic state serialization layer
#' for the MS-AR-GARCH-M bootstrap system.
#'
#' Important:
#' No inference is performed here.
#' Only structural transport of already-estimated state objects.
#' @keywords internal
.boot_ms_ar_garch_m_wrapper <- function(returns, info){
  .boot_ms_ar_garch_m(
    returns,
    as.integer(info$base_idx - 1),
    as.integer(info$eur_idx - 1),
    as.integer(info$n_regimes),
    info$mu_vec, info$omega_vec, info$alpha_vec,
    info$beta_vec, info$gamma_vec, info$phi_vec, info$lambda_vec,
    info$trans_mat, info$std_resid_list, info$stationary_prob,
    info$fx_mu, info$fx_omega, info$fx_alpha, info$fx_beta, info$fx_std_resid
  )
}


#' Time-Varying Transition Probability MS-GARCH State Layer (TVTP-MS-GARCH)
#'
#' @details
#' Extends standard MS-GARCH by allowing transition probabilities
#' to depend on endogenous volatility and regime-specific variance dynamics.
#'
#' Core idea:
#'
#'   P(S_t = j | S_{t-1} = i, σ²_t) ≠ constant
#'
#' Instead:
#'
#'   logit(P_{ij}) = δ_{ij} * (σ²_t / σ²̄_i - 1)
#'
#' Pipeline:
#'
#' 1. Fit baseline MS-GARCH model via MSGARCH
#' 2. Extract regime-specific volatility parameters:
#'    (ω_r, α_r, β_r, γ_r)
#'
#' 3. Compute unconditional regime variances:
#'
#'    σ²̄_r = ω_r / (1 - α_r - β_r - γ_r/2)
#'
#' 4. Estimate AR(1) structure per regime:
#'    φ_r via OLS
#'
#' 5. Estimate GARCH-in-Mean structure:
#'    λ_r via regression
#'
#' 6. Construct volatility deviation signal:
#'
#'    x_t = σ²_t / σ²̄_{S_t} - 1
#'
#' 7. Estimate transition sensitivity matrix δ:
#'
#'    logit(P_{ij}) ~ x_t
#'
#' Statistical interpretation:
#' Introduces feedback loop:
#'
#'   volatility level → transition dynamics → regime switching
#'
#' This transforms the Markov chain into a endogenously modulated 
#' stochastic process.
#'
#' Role in system:
#' Represents the fully endogenous regime-switching layer
#' where volatility not only evolves within regimes,
#' but also drives regime transitions.
#'
#' Output:
#' - base transition matrix P
#' - volatility sensitivity matrix δ
#' - regime-dependent AR and GARCH-M parameters
#' - conditional residual structure
#'
#' System role:
#' Extends MS-GARCH into a feedback-coupled hidden Markov system
#' with state-dependent transition intensities.
#' @keywords internal
.prepare_tvtp_ms_garch_info <- function(returns, config, n_regimes, garch_model){

  if(!requireNamespace("MSGARCH", quietly = TRUE)) {
    stop("TVTP-MS-GARCH Bootstrap erfordert das MSGARCH-Paket.")
  }

  base_idx <- which(config$index_names == config$regime_index)
  base_ret <- returns[, base_idx]
  n <- length(base_ret)
  k <- ncol(returns)
  K <- n_regimes

  excess <- base_ret - 1.0

  spec <- MSGARCH::CreateSpec(
    variance.spec = list(model = rep(garch_model, K)),
    distribution.spec = list(distribution = rep("norm", K)),
    switch.spec = list(do.mix = FALSE)
  )

  fit <- tryCatch({
    MSGARCH::FitML(spec = spec, data = excess)
  }, error = function(e){
    stop(sprintf("TVTP-MS-GARCH(%d, %s) Fitting fehlgeschlagen: %s",
                 K, garch_model, e$message))
  })

  coefs <- fit$par
  omega_vec <- numeric(K)
  alpha_vec <- numeric(K)
  beta_vec  <- numeric(K)
  gamma_vec <- numeric(K)

  for(r in seq_len(K)){
    omega_vec[r] <- coefs[paste0("alpha0_", r)]
    alpha_vec[r] <- coefs[paste0("alpha1_", r)]
    beta_vec[r]  <- coefs[paste0("beta_", r)]
    if (garch_model == "gjrGARCH") {
      gamma_vec[r] <- coefs[paste0("alpha2_", r)]
    }
  }

  base_trans_mat <- MSGARCH::TransMat(fit)

  pi_vec <- rep(1 / K, K)
  P <- base_trans_mat
  for(i in 1:1000){
    pi_new <- as.numeric(pi_vec %*% P)
    if (max(abs(pi_new - pi_vec)) < 1e-10) break
    pi_vec <- pi_new
  }
  stationary_prob <- pi_vec / sum(pi_vec)

  state_out <- MSGARCH::State(fit)

  if(!is.null(state_out$Viterbi)){
    viterbi <- state_out$Viterbi
    if(is.matrix(viterbi) || is.array(viterbi)){
      regimes <- as.integer(viterbi[, 1])
    } else {
      regimes <- as.integer(viterbi)
    }
    if(length(regimes) != n){
      warning(sprintf("TVTP: Viterbi-Länge %d != n=%d", length(regimes), n))
      regimes <- regimes[seq_len(n)]
    }
  } else if(!is.null(state_out$SmoothProb)){
    sp <- state_out$SmoothProb
    sp_mat <- sp[, 1, , drop = TRUE]
    sp_mat <- sp_mat[-1, , drop = FALSE]
    regimes <- apply(sp_mat, 1, which.max)
  } else {
    regimes <- rep(1, n)
    warning("TVTP: Weder Viterbi noch SmoothProb verfügbar")
  }

  mu_global <- mean(excess)
  mu_vec <- numeric(K)
  for(r in seq_len(K)){
    idx <- which(regimes == r)
    mu_vec[r] <- if (length(idx) >= 10) mean(excess[idx]) else mu_global
  }

  cond_var <- tryCatch({
    vol <- MSGARCH::Volatility(fit)
    vol^2
  }, error = function(e){
    sigma2_t <- numeric(n)
    sigma2_t[1] <- var(excess)
    resid <- excess - mu_global
    for(t in 2:n){
      r_regime <- regimes[t]
      ind <- if (resid[t-1] < 0) 1.0 else 0.0
      sigma2_t[t] <- omega_vec[r_regime] +
        (alpha_vec[r_regime] + gamma_vec[r_regime] * ind) * resid[t-1]^2 +
        beta_vec[r_regime] * sigma2_t[t-1]
      if (sigma2_t[t] < 1e-12) sigma2_t[t] <- 1e-12
    }
    sigma2_t
  })

  sigma_t <- sqrt(pmax(cond_var, 1e-12))

  unc_var_vec <- numeric(K)
  for(r in seq_len(K)){
    pers <- alpha_vec[r] + beta_vec[r] + gamma_vec[r] / 2.0
    if(pers < 0.9999 && omega_vec[r] > 0){
      unc_var_vec[r] <- omega_vec[r] / (1.0 - pers)
    } else {
      idx <- which(regimes == r)
      unc_var_vec[r] <- if(length(idx) >= 10) var(excess[idx]) else var(excess)
    }
  }

  phi_vec <- numeric(K)
  lag_excess <- c(0, excess[-n])

  for(r in seq_len(K)){
    idx <- which(regimes == r)
    if(length(idx) < 30) next
    tryCatch({
      y <- excess[idx]
      x <- lag_excess[idx]
      fit_ar <- lm.fit(cbind(1, x), y)
      phi_est <- fit_ar$coefficients[2]
      if(is.finite(phi_est)) phi_vec[r] <- max(-0.5, min(0.5, phi_est))
    }, error = function(e) NULL)
  }

  lambda_vec <- numeric(K)

  for(r in seq_len(K)){
    idx <- which(regimes == r)
    if(length(idx) < 30) next
    tryCatch({
      y_adj <- excess[idx] - mu_vec[r] - phi_vec[r] * lag_excess[idx]
      x_sigma <- sigma_t[idx]
      fit_lm <- lm.fit(cbind(x_sigma), y_adj)
      lambda_est <- fit_lm$coefficients[1]
      if(is.finite(lambda_est)) lambda_vec[r] <- max(-5.0, min(5.0, lambda_est))
    }, error = function(e) NULL)
  }

  delta_mat <- matrix(0.0, nrow = K, ncol = K)

  for(i in seq_len(K)){
    from_idx <- which(regimes[-n] == i)
    if(length(from_idx) < 50){
      next
    }

    to_regimes <- regimes[from_idx + 1]
    sigma2_std <- cond_var[from_idx] / unc_var_vec[i] - 1.0

    for(j in seq_len(K)){
      if(j == i) next

      n_transitions <- sum(to_regimes == j)
      if(n_transitions < 5){
        next
      }

      tryCatch({
        y <- as.integer(to_regimes == j)
        x <- sigma2_std

        fit_glm <- glm(y ~ x, family = binomial(link = "logit"))
        delta_est <- coef(fit_glm)["x"]

        if(is.finite(delta_est)){
          delta_mat[i, j] <- max(-3.0, min(3.0, delta_est))
        }
      }, error = function(e) NULL)
    }
  }

  cond_mean <- mu_vec[regimes] +
               phi_vec[regimes] * lag_excess +
               lambda_vec[regimes] * sigma_t

  all_std_resid <- (excess - cond_mean) / sigma_t

  std_resid_list <- lapply(seq_len(K), function(r){
    idx <- which(regimes == r)
    if(length(idx) < 10){
      warning(sprintf("TVTP: Regime %d hat nur %d Beobachtungen", r, length(idx)))
      res <- all_std_resid[is.finite(all_std_resid)]
    } else {
      res <- all_std_resid[idx]
      res <- res[is.finite(res)]
    }
    if(length(res) > 1 && sd(res) > 0){
      res <- (res - mean(res)) / sd(res)
    }
    res
  })

  fx <- .fit_fx_garch(returns, config)

  msg_regime <- sprintf(
    paste0("  Regime %d: mu=%.6f, phi=%.4f, lambda=%.4f, ",
           "omega=%.2e, alpha=%.4f, beta=%.4f, gamma=%.4f, ",
           "P(stay)=%.3f, unc_var=%.2e, n=%d"),
    seq_len(K), mu_vec, phi_vec, lambda_vec,
    omega_vec, alpha_vec, beta_vec, gamma_vec,
    diag(base_trans_mat), unc_var_vec,
    sapply(seq_len(K), function(r) sum(regimes == r))
  )

  msg_delta <- character(0)
  for(i in seq_len(K)){
    for(j in seq_len(K)){
      if(i != j && abs(delta_mat[i,j]) > 1e-4){
        msg_delta <- c(msg_delta, sprintf(
          "  delta[%d→%d] = %+.4f (%s)",
          i, j, delta_mat[i,j],
          if(delta_mat[i,j] > 0) "Varianz treibt Übergang" else "Varianz bremst Übergang"
        ))
      }
    }
  }
  if(length(msg_delta) == 0) msg_delta <- "  (keine signifikanten TVTP-Effekte)"

  tvtp_active <- any(abs(delta_mat) > 1e-4)

  message(sprintf(
    paste0("TVTP-MS-AR(1)-GJR-GARCH-M(%d, %s):\n",
           "%s\n",
           "  Stationär: [%s]\n",
           "  AR(1): [%s]\n",
           "  GARCH-M: [%s]\n",
           "  TVTP: %s\n%s"),
    K, garch_model,
    paste(msg_regime, collapse = "\n"),
    paste(sprintf("%.3f", stationary_prob), collapse = ", "),
    paste(sprintf("%.4f", phi_vec), collapse = ", "),
    paste(sprintf("%.4f", lambda_vec), collapse = ", "),
    if(tvtp_active) "AKTIV" else "inaktiv (alle delta ≈ 0)",
    paste(msg_delta, collapse = "\n")
  ))

  list(
    n_regimes       = K,
    mu_vec          = mu_vec,
    omega_vec       = omega_vec,
    alpha_vec       = alpha_vec,
    beta_vec        = beta_vec,
    gamma_vec       = gamma_vec,
    phi_vec         = phi_vec,
    lambda_vec      = lambda_vec,
    base_trans_mat  = base_trans_mat,
    delta_mat       = delta_mat,
    unc_var_vec     = unc_var_vec,
    stationary_prob = stationary_prob,
    std_resid_list  = std_resid_list,
    base_idx        = base_idx,
    eur_idx = fx$eur_idx, fx_mu = fx$fx_mu, fx_omega = fx$fx_omega,
    fx_alpha = fx$fx_alpha, fx_beta = fx$fx_beta, fx_std_resid = fx$fx_std_resid
  )
}


#' TVTP-MS-GARCH Bootstrap Dispatch Layer
#'
#' @details
#' This function acts as the *execution interface layer* between the
#' high-level TVTP-MS-GARCH model specification and the low-level
#' C++ bootstrap engine.
#'
#' It performs no statistical estimation or transformation itself.
#' Instead, it enforces strict structural serialization of all
#' precomputed model components into a compact, index-aligned format
#' required by the simulation backend.
#'
#' Pipeline role:
#' 1. Extract structural identifiers (base asset index, FX index)
#' 2. Convert R-based indexing (1-based) to C++ indexing (0-based)
#' 3. Forward regime-specific parameter tensors
#' 4. Forward transition dynamics (baseline + TVTP adjustment matrix)
#' 5. Forward volatility normalization structure
#' 6. Forward standardized residual distributions per regime
#' 7. Forward FX-GARCH state representation
#'
#' Structural inputs:
#' - Regime-level conditional means (mu_vec)
#' - GARCH state parameters (omega, alpha, beta, gamma)
#' - AR(1) dynamics (phi_vec)
#' - Volatility scaling effects (lambda_vec)
#' - Baseline Markov transition matrix (base_trans_mat)
#' - TVTP sensitivity matrix (delta_mat)
#' - Unconditional variance normalization (unc_var_vec)
#' - Regime-specific standardized residual pools
#' - Stationary regime probabilities
#'
#' System role:
#' This function defines the *final orchestration boundary* between
#' statistical model space and stochastic simulation engine.
#'
#' It ensures that all regime-switching, time-varying transition
#' effects, and conditional volatility structures are fully resolved
#' prior to Monte Carlo execution.
#'
#' Important:
#' - No randomness is introduced here
#' - No parameter estimation occurs here
#' - No numerical optimization occurs here
#' - Only deterministic model serialization is performed
#'
#' Design interpretation:
#' This layer acts as a *state-space compiler*, translating a
#' hierarchical econometric model into a flat simulation tensor
#' suitable for high-performance bootstrap execution.
#'
#' @keywords internal
.boot_tvtp_ms_garch_wrapper <- function(returns, info){
  .boot_tvtp_ms_garch(
    returns,
    as.integer(info$base_idx - 1),
    as.integer(info$eur_idx - 1),
    as.integer(info$n_regimes),
    info$mu_vec, info$omega_vec, info$alpha_vec,
    info$beta_vec, info$gamma_vec,
    info$phi_vec, info$lambda_vec,
    info$base_trans_mat, info$delta_mat, info$unc_var_vec,
    info$std_resid_list, info$stationary_prob,
    info$fx_mu, info$fx_omega, info$fx_alpha, info$fx_beta, info$fx_std_resid
  )
}
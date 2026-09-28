#--------> Hilfsfunktion zur Erstellung von Datumssequenzen:
create_date_sequence <- function(span, unit, day, start, stopp){
  date_sequence <- seq.Date(
    from = as.Date(format(start, "%Y-%m-01")),
    to = as.Date(format(stopp, "%Y-%m-01")),
    by = paste(span, unit)
  )

  years <- as.integer(format(date_sequence, "%Y"))
  months <- as.integer(format(date_sequence, "%m"))
  last_days <- as.integer(format(as.Date(paste(years, months, 1, sep = "-")) + months(1) - days(1), "%d"))

  adjusted_days <- pmin(day, last_days)
  adjusted_dates <- as.Date(paste(years, months, adjusted_days, sep = "-"))

  return(adjusted_dates)
}

#--------> Hilfsfunktion zur Erstellung von Rebalance- und DCA-Flags:
calculate_dates_flags <- function(mode, span, unit, days, dates, value = NULL, anchor, start_date, skip_start, liquidate){
  if(!mode || is.null(span) || is.null(unit) || is.null(days) || (!is.null(value) && value <= 0)){
    return(rep(FALSE, length(dates)))
  }

  unit   <- match.arg(unit,   c("month", "quarter", "year"))
  anchor <- match.arg(anchor, c("start", "end"))

  start_date <- if(is.null(start_date)) min(dates) else as.Date(start_date)
  schedule <- c()

  if(unit == "month"){
    base_seq <- seq(
      from = as.Date(format(start_date, "%Y-%m-01")),
      to   = max(dates),
      by   = paste(span, "months")
    )

    schedule <- if(is.null(days)){
      base_seq
    } else {
      as.Date(unlist(lapply(base_seq, function(m){
        yr  <- as.integer(format(m, "%Y"))
        mon <- as.integer(format(m, "%m"))

        if(anchor == "start"){
          as.Date(paste(yr, mon, days, sep = "-"), format = "%Y-%m-%d")
        } else {
          month_end <- as.Date(format(m + 1, "%Y-%m-01")) - 1
          month_end - (days - 1)
        }
      })))
    }
  }

  if(unit == "quarter"){
    base_seq <- seq(
      from = as.Date(format(start_date, "%Y-%m-01")),
      to   = max(dates),
      by   = paste(span * 3, "months")
    )

    schedule <- if(is.null(days)){
      base_seq
    } else {
      as.Date(unlist(lapply(base_seq, function(q){
        if(anchor == "start"){
          yr  <- as.integer(format(q, "%Y"))
          mon <- as.integer(format(q, "%m"))
          as.Date(paste(yr, mon, days, sep = "-"), format = "%Y-%m-%d")
        } else {
          quarter_end <- as.Date(format(q + 3, "%Y-%m-01")) - 1
          quarter_end - (days - 1)
        }
      })))
    }
  }

  if(unit == "year"){
    base_seq <- seq(
      from = as.Date(format(start_date, "%Y-01-01")),
      to   = max(dates),
      by   = paste(span, "years")
    )

    schedule <- if(is.null(days)){
      base_seq
    } else {
      as.Date(unlist(lapply(base_seq, function(y){
        yr <- as.integer(format(y, "%Y"))

        if(anchor == "start"){
          as.Date(paste(yr, 1, days, sep = "-"), format = "%Y-%m-%d")
        } else {
          year_end <- as.Date(paste0(yr, "-12-31"))
          year_end - (days - 1)
        }
      })))
    }
  }

  schedule <- schedule[schedule %in% dates]

  if(skip_start){
    schedule <- schedule[schedule != min(dates)]
  }

  if(liquidate){
    schedule <- schedule[schedule != max(dates)]
  }

  dates %in% schedule
}

#--------> Hilfsfunktion zur Erstellung der Split-Flags:
calculate_split_flags <- function(input, base, mode, dates){
  if(!mode || is.null(split_thresh)){
    return(rep(FALSE, length(dates)))
  }

  split_price <- do.call(cbind, lapply(input[[3]], function(x) x[[3]]))
  flag_split <- matrix(FALSE, nrow = nrow(split_price), ncol = ncol(split_price))

  for(i in seq_len(nrow(split_price))){
    for(j in seq_len(ncol(split_price))){
      if(flag_split[i, j]) next

      current_price <- split_price[i, j]

      if(current_price > split_thresh[[2]]){
        flag_split[i, j] <- TRUE
        split_ratio <- current_price / base
        split_price[i:nrow(split_price), j] <- split_price[i:nrow(split_price), j] / split_ratio 
      } else if(current_price < split_thresh[[1]]){
        flag_split[i, j] <- TRUE
        split_ratio <- base / current_price
        split_price[i:nrow(split_price), j] <- split_price[i:nrow(split_price), j] * split_ratio
      }
    }
  }

  return(rowSums(flag_split) > 0)
}

#--------> Hilfsfunktion zur Evaluation von Kaufsignalen:
calculate_buy_signal <- function(input, name, index){
  signal_buy <- FALSE

  if(input[[1]][[name]][[2]] == "sma" && input[[3]][[name]][[4]][index] && input[[2]][[name]][[4]] > 0 && input[[2]][[name]][[1]] == 0){
      signal_buy <- TRUE
  }

  if(input[[1]][[name]][[2]] == "bnh" && input[[2]][[name]][[4]] > 0){
    signal_buy <- TRUE
  }

  return(signal_buy)
}

#--------> Hilfsfunktion zur Evaluation von Verkaufssignalen:
calculate_sell_signal <- function(input, name, index){
  signal_sell <- FALSE

  if(input[[1]][[name]][[2]] == "sma" && input[[3]][[name]][[5]][index] && input[[2]][[name]][[1]] > 0){
    signal_sell <- TRUE
  }

  if(input[[1]][[name]][[2]] == "bnh"){
    signal_sell <- FALSE
  }

  return(signal_sell)
}

#--------> Hilfsfunktion zur Berechnung des FIFO-Kaufpreises:
calculate_fifo_price <- function(trades, units, front_index = 1){
  units_trade <- units
  total_price <- 0
  current_index <- front_index

  while(units_trade > 0 && current_index <= length(trades)){
    buy <- trades[[current_index]]

    if(is.null(buy) || length(buy) == 0){
      break
    }

    units_remain <- buy[[5]]

    if(units_remain > 0){
      units_sell <- min(units_remain, units_trade)
      total_price <- total_price + units_sell * buy[[4]]
      units_trade <- units_trade - units_sell
    }

    current_index <- current_index + 1
  }

  fifo_price <- if(units > 0){total_price / units} else {0}

  return(fifo_price)
}

#--------> Hilfsfunktion zur Lot-Wise Steuerberechnung:
calculate_private_sale_tax <- function(input, name, trade_count, sell_price, current_date, marginal_tax_rate){
  trades <- input[[4]][[name]][[1]]
  front_index <- input[[4]][[name]][["fifo_front"]]
  
  units_remaining <- trade_count
  current_index <- front_index
  
  exempt_gain <- 0
  exempt_loss <- 0
  taxable_gain <- 0
  taxable_loss <- 0
  
  lot_details <- list()
  
  while(units_remaining > 0 && current_index <= length(trades)){
    buy <- trades[[current_index]]
    
    if(is.null(buy) || length(buy) == 0){
      break
    }
    
    units_available <- buy[[5]]
    
    if (units_available > 0) {
      units_to_sell <- min(units_available, units_remaining)
      buy_date <- as.Date(buy[[1]])
      buy_price <- buy[[4]]
      holding_days <- as.numeric(difftime(current_date, buy_date, units = "days"))
      
      lot_gain <- units_to_sell * (sell_price - buy_price)
      
      if(holding_days >= 365){
        if(lot_gain >= 0){
          exempt_gain <- exempt_gain + lot_gain
        } else {
          exempt_loss <- exempt_loss + abs(lot_gain)
        }
      } else {
        if(lot_gain >= 0){
          taxable_gain <- taxable_gain + lot_gain
        } else {
          taxable_loss <- taxable_loss + abs(lot_gain)
        }
      }
      
      lot_details[[length(lot_details) + 1]] <- list(
        units = units_to_sell,
        buy_date = buy_date,
        holding_days = holding_days,
        gain = lot_gain,
        taxable = (holding_days < 365)
      )
      
      units_remaining <- units_remaining - units_to_sell
    }
    
    current_index <- current_index + 1
  }
  
  return(list(
    exempt_gain = exempt_gain,
    exempt_loss = exempt_loss,
    taxable_gain = taxable_gain,
    taxable_loss = taxable_loss,
    total_gain = exempt_gain - exempt_loss + taxable_gain - taxable_loss,
    lot_details = lot_details
  ))
}

#--------> Hilfsfunktion zur Prüfung und Verarbeitung des Jahreswechsels:
handle_year_change <- function(input, current_date, marginal_tax_rate, 
                                private_sale_threshold, sparer_pauschbetrag,
                                use_sparer_pauschbetrag, details) {
  
  current_year <- as.integer(format(current_date, "%Y"))
  stored_year <- input[[6]][["current_year"]]
  
  if(current_year != stored_year){    
    if(details){
      cat(sprintf("\n=== Year Change: %d → %d ===\n", stored_year, current_year))
    }
    
    ytd_gains <- input[[6]][["private_sale_gains_ytd"]]
    ytd_losses <- input[[6]][["private_sale_losses_ytd"]]
    net_gain <- ytd_gains - ytd_losses
    
    if(net_gain > private_sale_threshold){
      if(!is.null(marginal_tax_rate)){
        tax_due <- net_gain * marginal_tax_rate * 1.055
        input[[6]][["total_taxes"]] <- input[[6]][["total_taxes"]] + tax_due
        
        if(details){
          cat(sprintf("  § 23 EStG: Gains %.2f > threshold %.2f → Tax: %.2f\n", net_gain, private_sale_threshold, tax_due))
        }
      }
    } else if(net_gain < 0){
      input[[6]][["loss_private_sales"]] <- input[[6]][["loss_private_sales"]] + abs(net_gain)
    }
    
    spb_used_this_year <- input[[6]][["sparer_pauschbetrag_annual"]] - input[[6]][["sparer_pauschbetrag_remaining"]]
    
    if(details && use_sparer_pauschbetrag){
      cat(sprintf("  Sparerpauschbetrag used: %.2f of %.2f\n",
                  spb_used_this_year, input[[6]][["sparer_pauschbetrag_annual"]]))
    }
    
    input[[6]][["private_sale_gains_ytd"]] <- 0
    input[[6]][["private_sale_losses_ytd"]] <- 0
    
    if(use_sparer_pauschbetrag){
      input[[6]][["sparer_pauschbetrag_remaining"]] <- sparer_pauschbetrag
    }
    
    input[[6]][["current_year"]] <- current_year
  }
  
  return(input)
}

#--------> Hilfsfunktion zur Berechnung des FIFO-Grenzindex:
update_fifo_front <- function(trades, front_index){
  while(front_index <= length(trades)){
    buy <- trades[[front_index]]

    if(is.null(buy) || length(buy) == 0){
      break
    }

    if(buy[[5]] > 0){
      return(front_index)
    }

    front_index <- front_index + 1
  }

  return(front_index)
}

#--------> Hilfsfunktion zur Berechnung von Bisection-Searches:
calculate_bisection_search <- function(f, lower, upper, f_lower, f_upper, tol = 1e-6, max_iter = 30){
  if (abs(f_lower) < tol) return(lower)
  if (abs(f_upper) < tol) return(upper)
  if (f_lower * f_upper > 0) {
    return(if (abs(f_lower) < abs(f_upper)) lower else upper)
  }

  for (i in seq_len(max_iter)){
    mid <- (lower + upper) * 0.5
    f_mid <- f(mid)

    if(abs(f_mid) < tol || (upper - lower) < tol){
      return(mid)
    }

    if(f_mid * f_lower < 0){
      upper <- mid
      f_upper <- f_mid
    } else {
      lower <- mid
      f_lower <- f_mid
    }
  }

  return((lower + upper) * 0.5)
}

#--------> Hilfsfunktion zur Berechnung der Vorabpauschale:
calculate_flat_rate <- function(input, name, index, dates){
  if(!(input[[1]][[name]][["tax_regime"]] == "investment_fund" || input[[1]][[name]][["bonus"]] > 0)){
    return(0)
  }

  date_index <- dates[index]

  if(format(date_index, "%m-%d") != "12-31"){
    return(0)
  }

  start_of_year <- as.Date(paste0(format(date_index, "%Y"), "-01-01"))
  end_of_year <- as.Date(paste0(format(date_index, "%Y"), "-12-31"))
  days_in_year <- ifelse(as.numeric(format(date_index, "%Y")) %% 4 == 0 &
                           (as.numeric(format(date_index, "%Y")) %% 100 != 0 |
                              as.numeric(format(date_index, "%Y")) %% 400 == 0), 366, 365)

  base_rate <- input[[3]][[name]][[2]][index] / 100
  market_price <- input[[3]][[name]][[3]][index]

  year_start_index <- which(dates == start_of_year)
  if(length(year_start_index) == 0){
    year_start_index <- 1
  }

  year_start_price <- input[[3]][[name]][[3]][year_start_index]

  active_buys <- Filter(function(buy) buy[[5]] > 0, input[[4]][[name]][[1]])

  flat_rates <- sapply(active_buys, function(buy){
    buy_date <- buy[[1]]
    holding_start <- max(buy_date, start_of_year)
    holding_end <- min(date_index, end_of_year)
    holding_days <- as.numeric(difftime(holding_end, holding_start, units = "days")) + 1

    if(holding_days <= 0){
      return(0)
    }

    if(buy_date < start_of_year){
      reference_value <- buy[[5]] * year_start_price
    } else {
      reference_value <- buy[[5]] * buy[[4]]
    }

    base_worth <- reference_value * base_rate * 0.7 * (holding_days / days_in_year)
    market_worth <- buy[[5]] * market_price
    growth <- max(0, market_worth - reference_value)

    return(max(0, min(base_worth, growth)))
  })

  flat_rate_total <- sum(flat_rates, na.rm = TRUE)

  return(flat_rate_total)
}

#--------> Hilfsfunktion zur Berechnung der Fongsgebühren:
calculate_fund_fees <- function(input, index, dates, assets, funds_fee, bonus_fee, details){
  event_date <- as.Date(paste0(format(dates[index], "%Y"), "-01-01"))
  dates_index <- which(dates >= event_date & dates <= dates[index])

  if(length(dates_index) == 0){
    return(c(total_fees = 0, total_value = input[[6]][[1]]))
  }

  asset_totals <- sapply(assets, function(x) input[[5]][[x]][[4]][dates_index], simplify = "array")

  daily_rate <- (funds_fee / 100 + 1)^(1 / length(dates_index)) - 1
  basic_value <- sum(asset_totals * daily_rate, na.rm = TRUE)

  total_value <- input[[6]][[1]]
  market_value <- sum(sapply(input[[2]], function(x) x[[5]]), na.rm = TRUE)

  if(market_value > total_value){
    bonus_value <- (market_value - total_value) * (bonus_fee / 100)
    total_value <- market_value
  } else {
    bonus_value <- 0
  }

  total_fees <- basic_value + bonus_value

  if(details){
    cat(sprintf("Funds Event:\tPaying funds fees of $%.2f on %s\n\t\t=> Basis fee: $%.2f; Bonus fee: $%.2f\n", total_fees, dates[index], basic_value, bonus_value))
  }

  return(c(total_fees = total_fees, total_value = total_value))
}

#--------> Hilfsfunktion zur Berechnung zu verkaufender Anteile:
calculate_sell_count <- function(input, name, target, index, spread, fractions, tax_mode, tax_rate, marginal_tax_rate = 0.42){
  trade_price <- input[[3]][[name]][[3]][index] * (1 - spread / 100 / 2)
  total_shares <- input[[2]][[name]][[1]]

  if(total_shares <= 0) return(list(sell_count = 0, fifo_price = 0))
  if(target <= 0) return(list(sell_count = 0, fifo_price = 0))
  
    objective_function <- function(sell_count){
    if (sell_count <= 0) return(-target)
    if (sell_count > total_shares) sell_count <- total_shares
  
    fifo_price <- calculate_fifo_price(
      trades = input[[4]][[name]][[1]], 
      units = sell_count, 
      front_index = input[[4]][[name]][["fifo_front"]]
    )
    trade_gain <- (trade_price - fifo_price) * sell_count

    if(tax_mode == "person"){
      tax_regime <- input[[1]][[name]][["tax_regime"]]
      
      if(tax_regime == "investment_fund"){
        bonus <- input[[1]][[name]][["bonus"]]
        adjusted_gain <- trade_gain * (1 - bonus)
        tax_gain <- max(adjusted_gain - input[[6]][["loss_capital_gains"]], 0)
        capital_gains_tax <- tax_gain * tax_rate
        
      } else if(tax_regime == "capital_gains"){
        tax_gain <- max(trade_gain - input[[6]][["loss_capital_gains"]], 0)
        capital_gains_tax <- tax_gain * tax_rate
        
      } else if(tax_regime == "private_sale"){
        if(!is.null(marginal_tax_rate) && trade_gain > 0){
          capital_gains_tax <- trade_gain * marginal_tax_rate * 1.055
        } else {
          capital_gains_tax <- 0
        }
      } else {
        capital_gains_tax <- 0
      }
    } else {
      capital_gains_tax <- 0
    }

    net_worth <- sell_count * trade_price - capital_gains_tax
    return(net_worth - target)
  }

  initial_guess <- target / trade_price
  
  lower_bound <- max(1e-6, initial_guess * 0.1)
  upper_bound <- min(initial_guess * 3.0, total_shares)

  f_lower <- objective_function(lower_bound)
  f_upper <- objective_function(upper_bound)
  
  if(f_lower >= 0){
    sell_count <- lower_bound
  } else if(f_upper <= 0){
    sell_count <- upper_bound
  } else {
    sell_count <- calculate_bisection_search(
      f = objective_function,
      lower = lower_bound,
      upper = upper_bound,
      f_lower = f_lower,
      f_upper = f_upper,
      tol = if (fractions) 1e-6 else 0.5,
      max_iter = 30
    )
  }
  
  if(!fractions){
    test_lower <- floor(sell_count)
    test_upper <- ceiling(sell_count)
    
    if (test_lower < 1) test_lower <- 1
    if (test_upper > total_shares) test_upper <- total_shares
    
    diff_lower <- abs(objective_function(test_lower))
    diff_upper <- abs(objective_function(test_upper))
    
    sell_count <- if (diff_lower <= diff_upper) test_lower else test_upper
  }
  
  final_fifo_price <- calculate_fifo_price(
    trades = input[[4]][[name]][[1]], 
    units = sell_count, 
    front_index = input[[4]][[name]][["fifo_front"]]
  )
  
  return(list(sell_count = sell_count, fifo_price = final_fifo_price))
}

#--------> Hilfsfunktion zur Berechnung von Partial Moments:
calculate_partials <- function(returns, exp = 1, type = c("lower", "higher")){
  if(type == "lower"){
    mean(pmax(0, -returns)^exp, na.rm = TRUE)
  } else {
    mean(pmax(0, returns)^exp, na.rm = TRUE)
  }
}

#--------> Hilfsfunktion zur Berechnung der Skewness:
calculate_skewness <- function(x, na.rm = TRUE){
  if(na.rm){
    x <- x[!is.na(x)]
  }

  n <- length(x)
  if(n < 3){
    return(NA)
  }

  mean_x <- mean(x)
  sd_x <- sd(x)

  if(sd_x == 0){
    return(NA)
  }

  skew <- (n / ((n - 1) * (n - 2))) * sum((x - mean_x)^3) / (sd_x^3)

  return(skew)
}

#--------> Hilfsfunktion zur Berechnung der Kurtosis:
calculate_kurtosis <- function(x, na.rm = TRUE, excess = TRUE){
  if(na.rm){
    x <- x[!is.na(x)]
  }

  n <- length(x)
  if(n < 4){
    return(NA)
  }

  mean_x <- mean(x)
  sd_x <- sd(x)

  if(sd_x == 0){
    return(NA)
  }

  kurt <- (n * (n + 1)) / ((n - 1) * (n - 2) * (n - 3)) * 
          sum((x - mean_x)^4) / (sd_x^4)

  if(excess){
    kurt <- kurt - (3 * (n - 1)^2) / ((n - 2) * (n - 3))
  }

  return(kurt)
}

#--------> Hilfsfunktion für Forward Asset-Splits:
forward_asset_split <- function(input, name, ratio, index){
  split_worth <- input[[2]][[name]][[3]] / ratio
  split_count <- input[[2]][[name]][[1]] * ratio
  split_price <- input[[2]][[name]][[2]] / ratio

  if(!fractions && split_count %% 1 != 0){
    split_fract <- split_count %% 1
    split_count <- floor(split_count)
    input[[2]][[name]][[4]] <- input[[2]][[name]][[4]] + (split_fract * split_price)
  }

  input[[4]][[name]][[1]] <- lapply(input[[4]][[name]][[1]], function(buy){
    if(buy[[5]] > 0){
      buy[[3]] <- buy[[3]] * ratio
      buy[[4]] <- buy[[4]] / ratio
      buy[[5]] <- buy[[5]] * ratio
      if(!fractions && buy[[3]] %% 1 != 0){
        fract <- buy[[3]] %% 1
        buy[[3]] <- floor(buy[[3]])
        buy[[5]] <- floor(buy[[5]])
        input[[2]][[name]][[4]] <- input[[2]][[name]][[4]] + (fract * buy[[4]])
      }
      return(buy)
    } else {
      return(buy)
    }
  })

  input[[4]][[name]][["fifo_front"]] <- update_fifo_front(trades = input[[4]][[name]][[1]], front_index = 1)

  input[[2]][[name]][[1]] <- split_count
  input[[2]][[name]][[2]] <- split_price
  input[[2]][[name]][[3]] <- split_worth

  input[[3]][[name]][[3]][index:length(input[[3]][[name]][[3]])] <- input[[3]][[name]][[3]][index:length(input[[3]][[name]][[3]])] / ratio

  return(input)
}

#--------> Hilfsfunktion für Reversen Asset-Splits:
reverse_asset_split <- function(input, name, ratio, index){
  split_worth <- input[[2]][[name]][[3]] * ratio
  split_count <- input[[2]][[name]][[1]] / ratio
  split_price <- input[[2]][[name]][[2]] * ratio

  if(!fractions && split_count %% 1 != 0){
    split_fract <- split_count %% 1
    split_count <- floor(split_count)
    input[[2]][[name]][[4]] <- input[[2]][[name]][[4]] + (split_fract * split_price)
  }

  input[[4]][[name]][[1]] <- lapply(input[[4]][[name]][[1]], function(buy){
    if(buy[[5]] > 0){
      buy[[3]] <- buy[[3]] / ratio
      buy[[4]] <- buy[[4]] * ratio
      buy[[5]] <- buy[[5]] / ratio
      if(!fractions && buy[[3]] %% 1 != 0){
        fract <- buy[[3]] %% 1
        buy[[3]] <- floor(buy[[3]])
        buy[[5]] <- floor(buy[[5]])
        input[[2]][[name]][[4]] <- input[[2]][[name]][[4]] + (fract * buy[[4]])
      }
      return(buy)
    } else {
      return(buy)
    }
  })

  input[[4]][[name]][["fifo_front"]] <- update_fifo_front(trades = input[[4]][[name]][[1]], front_index = 1)

  input[[2]][[name]][[1]] <- split_count
  input[[2]][[name]][[2]] <- split_price
  input[[2]][[name]][[3]] <- split_worth

  input[[3]][[name]][[3]][index:length(input[[3]][[name]][[3]])] <- input[[3]][[name]][[3]][index:length(input[[3]][[name]][[3]])] * ratio

  return(input)
}

#--------> Hilfsfunktion zur Verwaltung von Asset-Splits:
perform_asset_split <- function(input, name, ratio, index, type){
  if(type == "forward"){
    input <- forward_asset_split(input = input, name = name, ratio = ratio, index = index)
  } else {
    input <- reverse_asset_split(input = input, name = name, ratio = ratio, index = index)
  }

  if(details){
    cat(sprintf("Split Event:\t%s %s via %s on %s\n",
                ifelse(type == "forward", "Splitting", "Reverse splitting"), name,
                ifelse(type == "forward", paste("1 :", format(ratio, digits = 5)),
                       paste(format(ratio, digits = 5), ": 1")), flag_date[time]))
    
  }

  return(input)
}

#--------> Hilfsfunktion zur Realisierung von Käufen:
perform_trade_buy <- function(input, count = NULL, name, index, reason = "", spread, fractions, details){
  market_price <- input[[3]][[name]][[3]][index]
  trade_price <- market_price * (1 + spread / 100 / 2)

  trade_count <- if(is.null(count)){
    if(fractions){
      input[[2]][[name]][[4]] / trade_price
    } else {
      floor(input[[2]][[name]][[4]] / trade_price)
    }
  } else {
    count
  }

  calculate_buy_report(input = input, name = name, index = index, trade_count = trade_count, trade_price = trade_price, market_price = market_price)

  if(details){
    cat(sprintf("%s\tBuying %.2fx %s at $%.2f per share on %s\n", reason, trade_count, name, trade_price, input[[3]][[name]][[1]][index]))
  }

  trades_entry <- list(
    event_date = input[[3]][[name]][[1]][index],
    event_type = "Buy",
    asset_count = trade_count,
    asset_price = trade_price,
    event_count = trade_count,
    event_price = trade_count * trade_price
  )

  input[[4]][[name]][["buy_count"]] <- input[[4]][[name]][["buy_count"]] + 1
  input[[4]][[name]][[1]][[input[[4]][[name]][["buy_count"]]]] <- trades_entry

  return(input)
}

#--------> Hilfsfunktion zur Realisierung von Verkäufen:
perform_trade_sell <- function(input, count = NULL, price = NULL, name, index, 
                                tax_mode, tax_rate, marginal_tax_rate = 0.42,
                                private_sale_threshold = 1000,
                                reason = "", spread, fractions, details){
  
  market_price <- input[[3]][[name]][[3]][index]
  trade_price <- market_price * (1 - spread / 100 / 2)
  current_date <- input[[3]][[name]][[1]][index]
  
  trade_count <- if(is.null(count)) input[[2]][[name]][[1]] else count
  
  fifo_price <- if(is.null(price) && tax_mode == "person"){
    calculate_fifo_price(
      trades = input[[4]][[name]][[1]], 
      units = trade_count, 
      front_index = input[[4]][[name]][["fifo_front"]]
    )
  } else {
    price %||% 0
  }
  
  trade_gain <- (trade_price - fifo_price) * trade_count
  capital_gains_tax <- 0
  
  if(tax_mode == "person"){
    tax_regime <- input[[1]][[name]][["tax_regime"]]
    
if(tax_regime == "investment_fund"){
  bonus <- input[[1]][[name]][["bonus"]]
  adjusted_gain <- trade_gain * (1 - bonus)
  
  if(adjusted_gain < 0){
    input[[6]][["loss_capital_gains"]] <- input[[6]][["loss_capital_gains"]] + abs(adjusted_gain)
    capital_gains_tax <- 0
    
  } else {
    loss_offset <- min(adjusted_gain, input[[6]][["loss_capital_gains"]])
    input[[6]][["loss_capital_gains"]] <- input[[6]][["loss_capital_gains"]] - loss_offset
    gain_after_loss <- adjusted_gain - loss_offset
    
    spb_offset <- 0
    if(use_sparer_pauschbetrag && input[[6]][["sparer_pauschbetrag_remaining"]] > 0){
      spb_offset <- min(gain_after_loss, input[[6]][["sparer_pauschbetrag_remaining"]])
      input[[6]][["sparer_pauschbetrag_remaining"]] <- input[[6]][["sparer_pauschbetrag_remaining"]] - spb_offset
      input[[6]][["sparer_pauschbetrag_used_total"]] <- input[[6]][["sparer_pauschbetrag_used_total"]] + spb_offset
      
      if(details && spb_offset > 0){
        cat(sprintf("\t\t=> Sparerpauschbetrag applied: %.2f (remaining: %.2f)\n", spb_offset, input[[6]][["sparer_pauschbetrag_remaining"]]))
      }
    }
    
    taxable_gain <- gain_after_loss - spb_offset
    capital_gains_tax <- taxable_gain * tax_rate
    input[[6]][["total_taxes"]] <- input[[6]][["total_taxes"]] + capital_gains_tax
  }
}

else if(tax_regime == "capital_gains"){
  adjusted_gain <- trade_gain
  
  if(adjusted_gain < 0){
    input[[6]][["loss_capital_gains"]] <- input[[6]][["loss_capital_gains"]] + abs(adjusted_gain)
    capital_gains_tax <- 0
    
  } else {
    loss_offset <- min(adjusted_gain, input[[6]][["loss_capital_gains"]])
    input[[6]][["loss_capital_gains"]] <- input[[6]][["loss_capital_gains"]] - loss_offset
    gain_after_loss <- adjusted_gain - loss_offset
    
    spb_offset <- 0
    if(use_sparer_pauschbetrag && input[[6]][["sparer_pauschbetrag_remaining"]] > 0){
      spb_offset <- min(gain_after_loss, input[[6]][["sparer_pauschbetrag_remaining"]])
      input[[6]][["sparer_pauschbetrag_remaining"]] <- input[[6]][["sparer_pauschbetrag_remaining"]] - spb_offset
      input[[6]][["sparer_pauschbetrag_used_total"]] <- input[[6]][["sparer_pauschbetrag_used_total"]] + spb_offset
    }
    
    taxable_gain <- gain_after_loss - spb_offset
    capital_gains_tax <- taxable_gain * tax_rate
    input[[6]][["total_taxes"]] <- input[[6]][["total_taxes"]] + capital_gains_tax
  }
}
    
    else if(tax_regime == "private_sale"){
      lot_result <- calculate_private_sale_tax(
        input = input,
        name = name,
        trade_count = trade_count,
        sell_price = trade_price,
        current_date = current_date,
        marginal_tax_rate = marginal_tax_rate
      )
      
      if(lot_result$exempt_gain > 0 && details){
        cat(sprintf("\t\t=> Tax-exempt gain (> 1 year): %.2f\n", lot_result$exempt_gain))
      }
      
      if(lot_result$exempt_loss > 0 && details){
        cat(sprintf("\t\t=> Non-deductible loss (> 1 year): %.2f\n", lot_result$exempt_loss))
      }
      
      if(lot_result$taxable_gain > 0){
        offset <- min(lot_result$taxable_gain, input[[6]][["loss_private_sales"]])
        input[[6]][["loss_private_sales"]] <- input[[6]][["loss_private_sales"]] - offset
        net_gain <- lot_result$taxable_gain - offset
        
        input[[6]][["private_sale_gains_ytd"]] <- input[[6]][["private_sale_gains_ytd"]] + net_gain
        
        if(details){
          cat(sprintf("\t\t=> Taxable gain (< 1 year): %.2f (YTD total: %.2f)\n",
                      net_gain, input[[6]][["private_sale_gains_ytd"]]))
        }
      }
      
      if(lot_result$taxable_loss > 0){
        input[[6]][["private_sale_losses_ytd"]] <- input[[6]][["private_sale_losses_ytd"]] + lot_result$taxable_loss
        
        if(details){
          cat(sprintf("\t\t=> Deductible loss (< 1 year): %.2f\n", lot_result$taxable_loss))
        }
      }
      
      capital_gains_tax <- 0
    }
  }
  
  calculate_sell_report(
    input = input, name = name, index = index,
    trade_count = trade_count, trade_price = trade_price,
    market_price = market_price, capital_gains_tax = capital_gains_tax
  )
  
  if(tax_mode == "person"){
    units_remaining <- trade_count
    current_index <- input[[4]][[name]][["fifo_front"]]
    
    while(units_remaining > 0 && current_index <= input[[4]][[name]][["buy_count"]]){
      buy <- input[[4]][[name]][[1]][[current_index]]
      
      if(!is.null(buy) && length(buy) > 0 && buy[[5]] > 0){
        units_to_reduce <- min(buy[[5]], units_remaining)
        input[[4]][[name]][[1]][[current_index]][[5]] <- buy[[5]] - units_to_reduce
        units_remaining <- units_remaining - units_to_reduce
      }
      
      current_index <- current_index + 1
    }
    
    input[[4]][[name]][["fifo_front"]] <- update_fifo_front(
      trades = input[[4]][[name]][[1]], 
      front_index = input[[4]][[name]][["fifo_front"]]
    )
  }
  
  if(details){
    cat(sprintf("%s\tSelling %.2fx %s at $%.2f per share on %s\n",
                reason, trade_count, name, trade_price, current_date))
    if(tax_mode == "person" && input[[1]][[name]][["tax_regime"]] != "private_sale"){
      cat(sprintf("\t\t=> Trade %s: $%.2f; Tax: $%.2f\n",
                  ifelse(trade_gain < 0, "loss", "gain"), trade_gain, capital_gains_tax))
    }
  }
  
  trades_entry <- list(
    event_date = current_date,
    event_type = "Sell",
    asset_count = trade_count,
    asset_price = trade_price,
    event_gain = trade_gain,
    event_taxes = capital_gains_tax
  )
  
  input[[4]][[name]][["sell_count"]] <- input[[4]][[name]][["sell_count"]] + 1
  input[[4]][[name]][[2]][[input[[4]][[name]][["sell_count"]]]] <- trades_entry
  
  return(input)
}

#--------> Hilfsfunktion zur Optimierung von Report-Updates:
perform_market_update <- function(input, assets, index){
  n_assets <- length(assets)
  total_portfolio <- 0
  asset_totals <- numeric(n_assets)
  
  for(i in seq_len(n_assets)){
    name <- assets[i]
    worth <- input[[2]][[name]][[1]] * input[[3]][[name]][[3]][index]
    money <- input[[2]][[name]][[4]]
    total <- worth + money
    
    asset_totals[i] <- total
    total_portfolio <- total_portfolio + total
    
    input[[5]][[name]][[1]][index] <- worth
    input[[5]][[name]][[2]][index] <- money
    input[[5]][[name]][[3]][index] <- 0
    input[[5]][[name]][[4]][index] <- total
  }

  if(total_portfolio > 0){
    for(i in seq_len(n_assets)){
      input[[5]][[assets[i]]][[5]][index] <- asset_totals[i] / total_portfolio
    }
  } else {
    for(i in seq_len(n_assets)){
      input[[5]][[assets[i]]][[5]][index] <- 0
    }
  }

  return(input)
}

simulation <- function(data, strategy, start_value = NULL, spread = NULL, details = FALSE, liquidate = FALSE,
                       dca_mode = FALSE, dca_value = NULL, dca_span = NULL, dca_days = NULL, dca_unit = c("month", "quarter", "year"), dca_anchor = c("start", "end"), dca_start = NULL, dca_skip = FALSE,
                       balance_mode = FALSE, balance_span = NULL, balance_days = NULL, balance_unit = c("month", "quarter", "year"), balance_anchor = c("start", "end"), balance_start = NULL, balance_skip = FALSE,
                       balance_dca = FALSE, balance_thresh = NULL, tax_mode = c("none", "person", "funds"), tax_rate = 0.26375,
                       base_rate = NULL, base_rate_flex = FALSE, base_rate_data = NULL,
                       funds_fee = 0.95, bonus_fee = 5, fractions = TRUE, split_mode = FALSE, split_thresh = NULL,
                       marginal_tax_rate = 0.42, private_sale_threshold = 1000, saver_allowance = 1000, sparer_pauschbetrag = 1000, use_sparer_pauschbetrag = TRUE){
  
  #----------------------------> Vorbereitung und Strukturierung von Datenobjekten:
  start_date <- head(data[, "date"], 1)
  stopp_date <- tail(data[, "date"], 1)

  #--------> Initialisierung der Speicher-Objekte:
  sim_mem <- list(
    assets = setNames(vector("list", length = length(strategy)), names(strategy)),
    status = setNames(vector("list", length = length(strategy)), names(strategy)),
    market = setNames(vector("list", length = length(strategy)), names(strategy)),
    trades = setNames(vector("list", length = length(strategy)), names(strategy)),
    report = setNames(vector("list", length = length(strategy)), names(strategy)),
  totals = list(
    total_value = start_value,
    total_taxes = 0,
    
    loss_capital_gains = 0,
    loss_private_sales = 0,
    
    private_sale_gains_ytd = 0,
    private_sale_losses_ytd = 0,
    sparer_pauschbetrag_annual = sparer_pauschbetrag,
    sparer_pauschbetrag_remaining = if (use_sparer_pauschbetrag) sparer_pauschbetrag else 0,
    sparer_pauschbetrag_used_total = 0,
    current_year = as.integer(format(start_date, "%Y"))
  )
  )

  for(name in names(strategy)){
    #---> Initialisierung des Assets-Objekts:
    sim_mem[["assets"]][[name]] <- list(
      class = strategy[[name]][["asset_class"]],
      style = strategy[[name]][["action_type"]],
      start = as.Date(strategy[[name]][["asset_start"]]),
      tax_regime = strategy[[name]][["tax_regime"]],
      bonus = strategy[[name]][["asset_bonus"]]
    )

    #---> Initialisierung des Status-Objekts:
    sim_mem[["status"]][[name]] <- c(
      count = 0,
      price = 0,
      worth = 0,
      money = strategy[[name]][["asset_share"]] * start_value,
      total = strategy[[name]][["asset_share"]] * start_value,
      bonus = strategy[[name]][["asset_bonus"]],
      target = strategy[[name]][["asset_share"]],
      actual = strategy[[name]][["asset_share"]],
      differ = 0
    )

    #---> Initialisierung des Market-Objekts:
    sim_mem[["market"]][[name]] <- list(
      asset_day = seq.Date(
        from = as.Date(start_date),
        to = as.Date(stopp_date),
        by = "days"),
      base_rates = if(base_rate_flex){
        data[[base_rate_data]]
      } else {
        ifelse(is.null(base_rate), 0, base_rate)
      },
      asset_price = data[[name]],
      signal_buy = data[[strategy[[name]][["signal_buy"]]]],
      signal_sell = data[[strategy[[name]][["signal_sell"]]]],
      spread_rate = strategy[[name]][["asset_spread"]]
    )

    #---> Initialisierung des Trade-Objekts:
    max_trades <- nrow(data)
    sim_mem[["trades"]][[name]] <- list(
      buys = vector("list", max_trades),
      buy_count = 0,
      sells = vector("list", max_trades),
      sell_count = 0,
      taxes = vector("list", max_trades),
      tax_count = 0,
      fees = vector("list", max_trades),
      fee_count = 0,
      fifo_front = 1
    )

    #---> Initialisierung des Report-Objekts:
    sim_mem[["report"]][[name]] <- list(
      worth = c(sim_mem[["status"]][[name]][["worth"]], rep(0, nrow(data) - 1)),
      money = c(sim_mem[["status"]][[name]][["money"]], rep(0, nrow(data) - 1)),
      flows = c(rep(0, nrow(data))),
      total = c(sim_mem[["status"]][[name]][["total"]], rep(0, nrow(data) - 1)),
      share = c(sim_mem[["status"]][[name]][["actual"]], rep(0, nrow(data) - 1))
    )
  }

  #--------> Initialisierung der Flag-Objekte:
  flag_date <- seq.Date(from = as.Date(start_date), to = as.Date(stopp_date), by = "days")
  flag_assets <- names(strategy)
  flag_liquidate <- liquidate & (flag_date == stopp_date)
  flag_rebalance <- calculate_dates_flags(mode = balance_mode, span = balance_span, unit = balance_unit, days = balance_days, dates = flag_date, anchor = balance_anchor, start_date = balance_start, skip_start = balance_skip, liquidate = liquidate)
  flag_dca <- calculate_dates_flags(mode = dca_mode, span = dca_span, unit = dca_unit, days = dca_days, dates = flag_date, value = dca_value, anchor = dca_anchor, start_date = dca_start, skip_start = dca_skip, liquidate = liquidate)
  flag_taxes <- (format(flag_date, "%m-%d") == "12-31")
  flag_trade <- !flag_rebalance & (flag_date != stopp_date)
  flag_split <- calculate_split_flags(input = sim_mem, base = 100, mode = split_mode, dates = flag_date)

  #--------> Initialisierung der Startgewichte bei Non-Tradeble Assets:
  initial_assets <- flag_assets[sapply(flag_assets, function(name){
    trade_start <- sim_mem[[1]][[name]][[3]] 
    (trade_start %||% flag_date[1]) <= flag_date[1]
  })]

  initial_weights_sum <- sum(sapply(initial_assets, function(name) sim_mem[[2]][[name]][[7]]))

  for(name in flag_assets){
    if(name %in% initial_assets){
      sim_mem[[2]][[name]][[7]] <- sim_mem[[2]][[name]][[7]] / initial_weights_sum
      sim_mem[[2]][[name]][[4]]  <- start_value * sim_mem[[2]][[name]][[7]] / initial_weights_sum
      sim_mem[[2]][[name]][[5]]  <- start_value * sim_mem[[2]][[name]][[7]] / initial_weights_sum
    } else {
      sim_mem[[2]][[name]][[8]] <- 0
      sim_mem[[2]][[name]][[4]]  <- 0
      sim_mem[[2]][[name]][[5]]  <- 0
    }
  }

  asset_starts <- sapply(flag_assets, function(name) sim_mem[[1]][[name]][[3]] %||% flag_date[1])
  flag_active <- flag_date %in% asset_starts

  active_assets_list <- vector("list", length(flag_date))
  for(i in seq_along(flag_date)){
    active_assets_list[[i]] <- flag_assets[asset_starts <= flag_date[i]]
  }

  # 1. Definitive Events (kalenderbasiert, unabhängig von Strategie)
  flag_definite <- flag_active | flag_split | flag_dca | flag_rebalance | flag_taxes | flag_liquidate

  # 2. Strategie-Typen
  strategy_types <- sapply(flag_assets, function(name) sim_mem[[1]][[name]][[2]])
  has_bnh <- any(strategy_types == "bnh")
  has_sma <- any(strategy_types == "sma")

  # 3. SMA-Signale aus Daten
  flag_sma_signal <- rep(FALSE, length(flag_date))
  if(has_sma){
    for(name in flag_assets){
      if(sim_mem[[1]][[name]][[2]] == "sma"){
        buy_signal <- sim_mem[[3]][[name]][[4]]
        sell_signal <- sim_mem[[3]][[name]][[5]]
        flag_sma_signal <- flag_sma_signal | buy_signal | sell_signal
      }
    }
  }

  # 4. BnH-Potenzial
  flag_bnh_potential <- rep(FALSE, length(flag_date))
  if(has_bnh){flag_bnh_potential[1] <- TRUE}

  # 5. Kombiniertes Slow-Path Flag
  flag_slow_path <- flag_definite | flag_sma_signal | flag_bnh_potential


  #----------------------------> Realisierung der Portfolio-Simulation:
  for(time in seq_len(nrow(data))){

    if(tax_mode == "person"){
      sim_mem <- handle_year_change(
        input = sim_mem,
        current_date = flag_date[time],
        marginal_tax_rate = marginal_tax_rate,
        private_sale_threshold = private_sale_threshold,
        saver_allowance = saver_allowance,
        details = details
      )
    }

    #--------> Implementierung Fast-Path-Simulation:
    if(!flag_slow_path[time]){
      sim_mem <- perform_market_update(sim_mem, flag_assets, time)
      next
    }
    
    #--------> Implementierung Slow-Path-Simulation:
    active_assets <- active_assets_list[[time]]
    flag_fast_report <- TRUE

    #--------> Implementierung von Asset-Aktivierung:
    if(flag_active[time]){
      for(name in setdiff(flag_assets, active_assets)){
        sim_mem[[3]][[name]][[4]][time] <- FALSE
        sim_mem[[3]][[name]][[5]][time] <- FALSE
      }

      if(balance_mode){
        current_weights_sum <- sum(sapply(active_assets, function(name) sim_mem[[2]][[name]][[7]]))

        for(name in active_assets){sim_mem[[2]][[name]][[8]] <- sim_mem[[2]][[name]][[7]] / current_weights_sum}

        if(details){
          new_assets <- flag_assets[asset_starts == flag_date[time]]
          if(length(new_assets)) cat(sprintf("Market Event:\tActive trading of %s now enabled.\n", paste(new_assets, collapse = ", ")))
        }

        flag_rebalance[time] <- TRUE
      }

      calculate_total_report(input = sim_mem, assets = flag_assets, index = time)
      flag_fast_report <- FALSE
    }

    #--------> Implementierung von Splits und Reverse Splits:
    if(flag_split[time]){
      for(name in active_assets){
        if(sim_mem[[2]][[name]][[1]] > 0){
          split_price <- sim_mem[[3]][[name]][[3]][time]

          if(split_price > split_thresh[[2]]){
            sim_mem <- perform_asset_split(input = sim_mem, name = name, ratio = split_price / 100, type = "forward", index = time)
          }

          if(split_price < split_thresh[[1]]){
            sim_mem <- perform_asset_split(input = sim_mem, name = name, ratio = 100 / split_price, type = "reverse", index = time)
          }
        }
      }

      calculate_total_report(input = sim_mem, assets = flag_assets, index = time)
      flag_fast_report <- FALSE
    }

    #--------> Implementierung von Dollar-Cost-Averaging:
    if(flag_dca[time]){
      if(balance_dca && length(active_assets) > 1){
        active_targets <- sapply(active_assets, function(name) sim_mem[[2]][[name]][[7]])
        active_targets <- active_targets / sum(active_targets, na.rm = TRUE)

        differ_weights <- active_targets - sapply(active_assets, function(name) sim_mem[[2]][[name]][[8]])
        rebalance_assets <- differ_weights[differ_weights > 0]

        if(length(rebalance_assets) > 0){
          rebalance_shares <- rebalance_assets / sum(rebalance_assets)

          for(name in names(rebalance_assets)){
            allocation_dca <- rebalance_shares[[name]] * dca_value
            dca_flows_allocation(input = sim_mem, name = name, flows = allocation_dca, index = time)
          }
        } else {
          for(name in active_assets){
            allocation_dca <- active_targets[name] * dca_value
            dca_flows_allocation(input = sim_mem, name = name, flows = allocation_dca, index = time)
          }
        }
      } else {
        total_target <- sum(sapply(active_assets, function(name) sim_mem[[2]][[name]][[8]]), na.rm = TRUE)

        for(name in active_assets){
          allocation_dca <- sim_mem[[2]][[name]][[8]] / total_target * dca_value
          dca_flows_allocation(input = sim_mem, name = name, flows = allocation_dca, index = time)
        }
      }

      if(details){
        flow_values <- sapply(active_assets, function(name) sim_mem[[5]][[name]][[3]][time])
        placeholder <- paste(sprintf("%s $%%.2f", names(flow_values)), collapse = "; ")
        format_text <- sprintf("Transfering:\tDepositing $%%.2f to brokerage account on %%s\n\t\t=> %s\n", placeholder)
        cat(do.call(sprintf, c(list(format_text, dca_value), list(flag_date[time]), as.list(flow_values))))
      }

      calculate_total_report(input = sim_mem, assets = flag_assets, index = time)
      flag_fast_report <- FALSE
    }

    #--------> Implementierung von Trading-Aktionen:
    if(flag_trade[time]){
      trade_event <- FALSE

      for(name in flag_assets){
        flag_buy <- calculate_buy_signal(input = sim_mem, name = name, index = time)
        flag_sell <- calculate_sell_signal(input = sim_mem, name = name, index = time)

        if(flag_buy){
          sim_mem <- perform_trade_buy(input = sim_mem, name = name, index = time, reason = "Trade Event:", spread = sim_mem[[3]][[name]][[6]], fractions = fractions, details = details)
          trade_event <- TRUE
        }

        if(flag_sell){
          sim_mem <- perform_trade_sell(input = sim_mem, name = name, index = time, tax_mode = tax_mode, tax_rate = tax_rate, 
            marginal_tax_rate = marginal_tax_rate,
            private_sale_threshold = private_sale_threshold,
          reason = "Trade Event:", spread = sim_mem[[3]][[name]][[6]], details = details)
          trade_event <- TRUE
        }
      }

      if(trade_event){
        calculate_total_report(input = sim_mem, assets = flag_assets, index = time)
        flag_fast_report <- FALSE
      }
    }

    #--------> Implementierung von Rebalancing-Aktionen:
    if(flag_rebalance[time]){
      active_targets <- sapply(active_assets, function(name){sim_mem[[2]][[name]][[7]]})
      active_targets <- active_targets / sum(active_targets, na.rm = TRUE)
      actual_weights <- sapply(active_assets, function(name){sim_mem[[2]][[name]][[8]]})

      new_asset <- any(asset_starts == flag_date[time])
      force_rebalance <- new_asset

      if(force_rebalance && details){
        new_assets <- flag_assets[asset_starts == flag_date[time]]
        cat(sprintf("Rebalancing:\tForcing rebalance on %s due to new asset activation: %s\n",
            flag_date[time], paste(new_assets, collapse = ", ")))
      }

      event_rebalance <- FALSE

      if(force_rebalance){
        event_rebalance <- TRUE
      } else if(is.null(balance_thresh)){
        event_rebalance <- TRUE
      } else {
        deviations <- abs(active_targets - actual_weights)
        max_deviation <- max(deviations, na.rm = TRUE)
        event_rebalance <- (max_deviation > balance_thresh)

        if(details){
          if(event_rebalance){
            cat(sprintf("Rebalancing:\tExecuting rebalancing on %s (max deviation: %.2f%% > threshold: %.2f%%)\n",
                flag_date[time], max_deviation * 100, balance_thresh * 100))

            for(i in seq_along(active_assets)){
              name <- active_assets[i]
              dev <- deviations[i]
              
              if(dev > balance_thresh){
                cat(sprintf("\t\t=> %s: target=%.1f%%, actual=%.1f%%, deviation=%.2f%%\n",
                    name, active_targets[i]*100, actual_weights[i]*100, dev*100))
              }
            }
          } else {
            cat(sprintf("Rebalancing:\tSkipping rebalancing on %s (max deviation: %.2f%% < threshold: %.2f%%)\n",
                flag_date[time], max_deviation * 100, balance_thresh * 100))
            }
          }
        }

        if(event_rebalance){
          differ_weights <- active_targets - actual_weights
          total_strategy <- sum(sapply(sim_mem[[2]][active_assets], function(x) x[[5]]), na.rm = TRUE)

          transfer_pool <- 0
          transfer_value <- abs(differ_weights * total_strategy)

          for(name in names(differ_weights[differ_weights > 0])){
            if(sim_mem[[3]][[name]][[4]][time]){
              if(sim_mem[[2]][[name]][[1]] > 0){
                sell_count <- calculate_sell_count(input = sim_mem, name = name, target = transfer_value[name], index = time, spread = sim_mem[[3]][[name]][[6]], fractions = fractions, tax_mode = tax_mode, tax_rate = tax_rate,
  marginal_tax_rate = marginal_tax_rate)
                sim_mem <- perform_trade_sell(input = sim_mem, name = name, count = sell_count[["sell_count"]], price = sell_count[["fifo_price"]], index = time, tax_mode = tax_mode, tax_rate = tax_rate, 
                marginal_tax_rate = marginal_tax_rate,
                private_sale_threshold = private_sale_threshold,
                reason = "Rebalancing:", spread = sim_mem[[3]][[name]][[6]], details = details)
              }

              if(sim_mem[[2]][[name]][[4]] < transfer_value[name]){
                transfer_value[name] <- max(0, sim_mem[[2]][[name]][[4]])
              }

              transfer_pool <- transfer_pool + transfer_value[name]
              sim_mem[[2]][[name]][[4]] <- sim_mem[[2]][[name]][[4]] - transfer_value[name]

              if(sim_mem[[2]][[name]][[1]] == 0){
                sim_mem <- perform_trade_buy(input = sim_mem, name = name, index = time, reason = "Rebalancing:", spread = sim_mem[[3]][[name]][[6]], fractions = fractions, details = details)
              }

              if(details){
                cat(sprintf("\t\tDepositing $%.2f from %s to rebalancing pool\n", transfer_value[name], name))
              }
            }

            if(sim_mem[[3]][[name]][[5]][time]){
              if(sim_mem[[2]][[name]][[1]] > 0){
                sim_mem <- perform_trade_sell(input = sim_mem, name = name, index = time, tax_mode = tax_mode, tax_rate = tax_rate, 
                  marginal_tax_rate = marginal_tax_rate,
                  private_sale_threshold = private_sale_threshold,
                reason = "Rebalancing:", spread = sim_mem[[3]][[name]][[6]], details = details)
              }

              if(sim_mem[[2]][[name]][[4]] < transfer_value[name]){
                transfer_value[name] <- max(0, sim_mem[[2]][[name]][[4]])
              }

              transfer_pool <- transfer_pool + transfer_value[name]
              sim_mem[[2]][[name]][[4]] <- sim_mem[[2]][[name]][[4]] - transfer_value[name]

              if(details){
                cat(sprintf("\t\tDepositing $%.2f from %s to rebalancing pool\n", transfer_value[name], name))
              }
            }
          }

        for(name in names(differ_weights[differ_weights < 0])){
          if(sim_mem[[3]][[name]][[4]][time]){
            transfer_pool <- transfer_pool - transfer_value[name]
            sim_mem[[2]][[name]][[4]] <- sim_mem[[2]][[name]][[4]] + transfer_value[name]

            if(details){
              cat(sprintf("Rebalancing:\tWithdrawing $%.2f from rebalancing pool to %s\n", transfer_value[name], name))
            }

            sim_mem <- perform_trade_buy(input = sim_mem, name = name, index = time, reason = "\t", spread = sim_mem[[3]][[name]][[6]], fractions = fractions, details = details)
          }

          if(sim_mem[[3]][[name]][[5]][time]){
            if(sim_mem[[2]][[name]][[1]] > 0){
              sim_mem <- perform_trade_sell(input = sim_mem, name = name, index = time, tax_mode = tax_mode, tax_rate = tax_rate, 
              marginal_tax_rate = marginal_tax_rate,
              private_sale_threshold = private_sale_threshold,
              reason = "Rebalancing:", spread = sim_mem[[3]][[name]][[6]], details = details)
            }

            transfer_pool <- transfer_pool - transfer_value[name]
            sim_mem[[2]][[name]][[4]] <- sim_mem[[2]][[name]][[4]] + transfer_value[name]

            if(details){
              cat(sprintf("\t\tWithdrawing $%.2f from rebalancing pool to %s\n", transfer_value[name], name))
            }
          }
        }

        if(transfer_pool < 0){
          transfer_pool <- 0
        }

        if(transfer_pool > 0.01){
          if(details){
            cat(sprintf("\t\tRedistributing remaining $%.2f from rebalancing pool\n", transfer_pool))
          }

          for(name in active_assets){
            redistribution <- sim_mem[[2]][[name]][[7]] * transfer_pool
            sim_mem[[2]][[name]][[4]] <- sim_mem[[2]][[name]][[4]] + redistribution

            if(details){
              cat(sprintf("\t\t=> Transfering $%.2f to %s\n", redistribution, name))
            }
          }
        }
      }

      calculate_total_report(input = sim_mem, assets = flag_assets, index = time)
      flag_fast_report <- FALSE
    }

    #--------> Implementierung von Steuer- und Gebührenkalkulation:
    if(flag_taxes[time]){
      if(!liquidate && tax_mode == "person"){
        for(name in flag_assets){
          if(sim_mem[[1]][[name]][[1]] == "etf" && sim_mem[[2]][[name]][[1]] > 0){
            flat_rate <- calculate_flat_rate(input = sim_mem, name = name, index = time, dates = flag_date)

            if(!is.null(sim_mem[[4]][[name]][[3]]) && length(sim_mem[[4]][[name]][[3]]) > 0){
              prior_flat_rates <- sum(sapply(sim_mem[[4]][[name]][[3]], function(x){
                if(identical(format(x[[1]], "%Y"), format(flag_date[time], "%Y"))){
                  return(x[[4]])
                } else {
                  return(0)
                }}), na.rm = TRUE)
              } else {
                prior_flat_rates <- 0
              }

            tax_debt <- max((flat_rate * (1 - sim_mem[[2]][[name]][[6]])) * tax_rate - prior_flat_rates, 0)
            
            if(tax_debt > 0){
              if(sim_mem[[2]][[name]][[4]] >= tax_debt){
                sim_mem[[2]][[name]][[4]] <- sim_mem[[2]][[name]][[4]] - tax_debt
                sim_mem[[6]][[2]] <- sim_mem[[6]][[2]] + tax_debt

                if(details){
                  cat(sprintf("Tax Event:\tPaying annual taxes of $%.2f for %s from available funds on %s\n", tax_debt, name, flag_date[time]))
                }
              } else {
                if(sim_mem[[2]][[name]][[4]] > 0){
                  flag_details <- TRUE
                  tax_debt <- tax_debt - sim_mem[[2]][[name]][[4]]

                  if(details){
                    cat(sprintf("Tax Event:\tDeducting $%.2f from %s‘s cash reserve for partial tax payment on %s\n", sim_mem[[2]][[name]][[4]], name, flag_date[time]))
                  }

                  sim_mem[[2]][[name]][[4]] <- 0
                } else {
                  flag_details <- FALSE
                }

                sell_count <- calculate_sell_count(input = sim_mem, name = name, target = tax_debt, index = time, spread = sim_mem[[3]][[name]][[6]], fractions = fractions, tax_mode = tax_mode, tax_rate = tax_rate,
  marginal_tax_rate = marginal_tax_rate)
                sim_mem <- perform_trade_sell(input = sim_mem, count = sell_count[["sell_count"]], price = sell_count[["fifo_price"]], name = name, index = time, tax_mode = tax_mode, tax_rate = tax_rate, 
                marginal_tax_rate = marginal_tax_rate,
                private_sale_threshold = private_sale_threshold,
                reason = "Tax Event:", spread = sim_mem[[3]][[name]][[6]], details = details)

                sim_mem[[2]][[name]][[4]] <- sim_mem[[2]][[name]][[4]] - tax_debt
                sim_mem[[6]][[2]] <- sim_mem[[6]][[2]] + tax_debt

                if(details){
                  if(flag_details){
                    cat(sprintf("\t\t=> Paying annual taxes of $%.2f for %s on %s\n", tax_debt, name, flag_date[time]))
                  } else {
                    cat(sprintf("Tax Event:\tPaying annual taxes of $%.2f for %s on %s\n", tax_debt, name, flag_date[time]))
                  }
                }

                if(sim_mem[[2]][[name]][[4]] < 0){
                  sim_mem[[2]][[name]][[4]] <- 0
                } else if(sim_mem[[2]][[name]][[4]] > 0){
                  if(details){
                    cat(sprintf("\t\t=> Transfering $%.2f taxed cash to total loss pool\n", sim_mem[[2]][[name]][[4]]))
                  }

                  sim_mem[[6]][[3]] <- sim_mem[[6]][[3]] + sim_mem[[2]][[name]][[4]]
                  sim_mem[[2]][[name]][[4]] <- 0
                }
              }

              trades_entry <- list(
                event_date = flag_date[time],
                event_type = "Taxes",
                taxes_paid = tax_debt,
                flat_rates = flat_rate
              )

              sim_mem[[4]][[name]][["tax_count"]] <- sim_mem[[4]][[name]][["tax_count"]] + 1
              sim_mem[[4]][[name]][[3]][[sim_mem[[4]][[name]][["tax_count"]]]] <- trades_entry
            }
          }
        }
      }

      if(tax_mode == "funds"){
        result_fees <- calculate_fund_fees(input = sim_mem, index = time, dates = flag_date, assets = flag_assets, funds_fee = funds_fee, bonus_fee = bonus_fee, details = details)
        sim_mem[[6]][[1]] <- result_fees[["total_value"]]

        annual_fees <- result_fees[["total_fees"]]
        asset_share <- annual_fees * sapply(sim_mem[[2]], function(x) x[[8]])
        asset_money <- sapply(sim_mem[[2]], function(x) x[[4]])

        for(name in flag_assets){
          if(asset_money[[name]] > asset_share[[name]]){
            if(sim_mem[[2]][[name]][[4]] < asset_share[[name]]){
              asset_share[[name]] <- max(0, sim_mem[[2]][[name]][[4]])
            }

            sim_mem[[2]][[name]][[4]] <- sim_mem[[2]][[name]][[4]] - asset_share[[name]]

            if(details){
              cat(sprintf("\t\t=> Deducting $%.2f from %s's cash reserve to pay fees\n", asset_share, name))
            }
          } else {
            sell_amount <- asset_share[[name]] - asset_money[[name]]
            sim_mem <- perform_trade_sell(input = sim_mem, name = name, index = time, tax_mode = tax_mode, tax_rate = tax_rate, 
            marginal_tax_rate = marginal_tax_rate,
            private_sale_threshold = private_sale_threshold,
            spread = sim_mem[[3]][[name]][[6]], details = FALSE)

            if(details){
              cat(sprintf("\t\t=> Selling $%.2f %s at $%.2f per share to cover fees\n", sell_amount, name, sim_mem[[2]][[name]][[2]]))
            }

            if(sim_mem[[2]][[name]][[4]] < asset_share[[name]]){
              asset_share[[name]] <- max(0, sim_mem[[2]][[name]][[4]])
            }

            sim_mem[[2]][[name]][[4]] <- sim_mem[[2]][[name]][[4]] - asset_share[[name]]

            if(details){
              cat(sprintf("\t\t=> Deducting $%.2f from %s's cash reserve to pay fees\n", asset_share, name))
            }

            buy_count <- sim_mem[[2]][[name]][[4]] / sim_mem[[2]][[name]][[2]]
            sim_mem <- perform_trade_buy(input = sim_mem, name = name, index = time, spread = sim_mem[[3]][[name]][[6]], fractions = fractions, details = FALSE)

            if(details){
              cat(sprintf("\t\t=> Buying %.2fx %s at $%.2f per share\n", buy_count, name, sim_mem[[2]][[name]][[2]]))
            }
          }

          for(name in flag_assets){
            trades_entry <- list(
              event_date = flag_date[time],
              event_type = "Fees",
              fees_paid = annual_fees
            )

            sim_mem[[4]][[name]][["fee_count"]] <- sim_mem[[4]][[name]][["fee_count"]] + 1
            sim_mem[[4]][[name]][[4]][[sim_mem[[4]][[name]][["fee_count"]]]] <- trades_entry
          }
        }
      }

      calculate_total_report(input = sim_mem, assets = flag_assets, index = time)
      flag_fast_report <- FALSE
    }

    #--------> Implementierung von Liquidierung, Steuer- und Gebührenkalkulation:
    if(flag_liquidate[time]){
      for(name in flag_assets){
        if(sim_mem[[2]][[name]][[1]] > 0){
          tax_type <- ifelse(tax_mode == "person", "person", "none")
          sim_mem <- perform_trade_sell(input = sim_mem, name = name, index = time, tax_mode = tax_type, tax_rate = tax_rate, 
          marginal_tax_rate = marginal_tax_rate,
          private_sale_threshold = private_sale_threshold,
          reason = "Liquidating:", spread = sim_mem[[3]][[name]][[6]], details = details)
        }
      }
      
      if(format(flag_date[time], "%m-%d") != "12-31" && tax_mode == "funds"){
        result_fees <- calculate_fund_fees(input = sim_mem, index = time, dates = flag_date, assets = flag_assets, funds_fee = funds_fee, bonus_fee = bonus_fee, details = details)
        sim_mem[[6]][[1]] <- result_fees[["total_value"]]
        
        annual_fees <- result_fees[["total_fees"]]
        asset_share <- annual_fees * sapply(sim_mem[[2]], function(x) x[[8]])
        asset_money <- sapply(sim_mem[[2]], function(x) x[[4]])
        
        for(name in flag_assets){
          sim_mem <- perform_trade_sell(input = sim_mem, name = name, index = time, tax_mode = tax_mode, tax_rate = tax_rate, 
          marginal_tax_rate = marginal_tax_rate,
          private_sale_threshold = private_sale_threshold,
          spread = sim_mem[[3]][[name]][[6]], details = details)
          
          if(sim_mem[[2]][[name]][[4]] < asset_share[[name]]){
            asset_share[[name]] <- max(0, sim_mem[[2]][[name]][[4]])
          }

          sim_mem[[2]][[name]][[4]] <- sim_mem[[2]][[name]][[4]] - asset_share[[name]]
        }
        
        tax_weights <- sapply(sim_mem[[2]], function(x) x[[8]])
        final_value <- sum(sapply(sim_mem[[2]], function(x) x[[5]]), na.rm = TRUE)
        total_gains <- final_value - start_value
        
        if(total_gains > 0){
          total_taxes <- total_gains * tax_rate
          
          for(name in flag_assets){
            tax_per_asset <- total_taxes * tax_weights[[name]]
            
            if(sim_mem[[2]][[name]][[4]] < tax_per_asset){
              tax_per_asset <- max(0, sim_mem[[2]][[name]][[4]])
            }
            
            sim_mem[[2]][[name]][[4]] <- sim_mem[[2]][[name]][[4]] - tax_per_asset
          }
          
          if(details){
            cat(sprintf("Liquidating:\tPaying taxes of $%.2f on $%.2f total gain on %s\n", total_taxes, total_gains, flag_date[time]))
          }
        }
        
        for(name in flag_assets){
          trades_entry <- list(
            event_date = flag_date[time],
            event_type = "Fees",
            fees_paid = annual_fees
          )

          sim_mem[[4]][[name]][["fee_count"]] <- sim_mem[[4]][[name]][["fee_count"]] + 1
          sim_mem[[4]][[name]][[4]][[sim_mem[[4]][[name]][["fee_count"]]]] <- trades_entry
        }
      }

      calculate_total_report(input = sim_mem, assets = flag_assets, index = time)
      flag_fast_report <- FALSE
    }

    if(flag_fast_report){
      sim_mem <- perform_market_update(input = sim_mem, assets = flag_assets, index = time)
    }
  }

  if(tax_mode == "person"){
    sim_mem <- handle_year_change(
      input = sim_mem,
      current_date = as.Date(paste0(
        as.integer(format(stopp_date, "%Y")) + 1, "-01-01"
      )),
      marginal_tax_rate = marginal_tax_rate,
      private_sale_threshold = private_sale_threshold,
      saver_allowance = saver_allowance,
      details = details
    )
  }

  #--------> Bereinigung der Zentralstruktur:
  for(name in flag_assets){
    sim_mem[["trades"]][[name]][[1]] <- sim_mem[["trades"]][[name]][[1]][1:sim_mem[["trades"]][[name]][["buy_count"]]]
    sim_mem[["trades"]][[name]][["buy_count"]] <- NULL
    sim_mem[["trades"]][[name]][[2]] <- sim_mem[["trades"]][[name]][[2]][1:sim_mem[["trades"]][[name]][["sell_count"]]]
    sim_mem[["trades"]][[name]][["sell_count"]] <- NULL
    sim_mem[["trades"]][[name]][[3]] <- sim_mem[["trades"]][[name]][[3]][1:sim_mem[["trades"]][[name]][["tax_count"]]]
    sim_mem[["trades"]][[name]][["tax_count"]] <- NULL
    sim_mem[["trades"]][[name]][[4]] <- sim_mem[["trades"]][[name]][[4]][1:sim_mem[["trades"]][[name]][["fee_count"]]]
    sim_mem[["trades"]][[name]][["fee_count"]] <- NULL
    sim_mem[["trades"]][[name]][["fifo_front"]] <- NULL
  }

  #--------> Berechnung der Endergebnisse:
  total_worth <- rowSums(sapply(sim_mem[["report"]], function(x) x[["total"]]), na.rm = TRUE)
  start_worth <- total_worth[1]
  stopp_worth <- total_worth[length(flag_date)]

  #--------> Berechnung von CAGR, TTWROR und Drawdowns:
  time <- as.numeric(difftime(stopp_date, start_date, units = "days")) / 365.25
  cagr <- ((stopp_worth / start_worth)^(1 / time) - 1)
  drawdowns <- (cummax(total_worth) - total_worth) / cummax(total_worth)

  ttwror_data <- list(
    total = rowSums(sapply(sim_mem[["report"]], function(x) x[["total"]]), na.rm = TRUE),
    flows = rowSums(sapply(sim_mem[["report"]], function(x) x[["flows"]]), na.rm = TRUE)
  )

  n <- length(ttwror_data[["total"]])
  ttwror_data[["period_change"]] <- c(NA, ttwror_data[["total"]][2:n] - ttwror_data[["total"]][1:(n-1)] - ttwror_data[["flows"]][2:n])
  ttwror_data[["period_return"]] <- c(NA, ttwror_data[["period_change"]][2:n] / ttwror_data[["total"]][1:(n-1)])
  ttwror <- prod(1 + ttwror_data[["period_return"]], na.rm = TRUE)^(1 / time) - 1

  #--------> Berechnung der Portfolio-Return-Metriken:
  portfolio_returns <- diff(total_worth) / head(total_worth, -1)

  statistics <- list(
    mean = mean(portfolio_returns, na.rm = TRUE),
    sd = sd(portfolio_returns, na.rm = TRUE),
    cv = abs(sd(portfolio_returns, na.rm = TRUE) / mean(portfolio_returns, na.rm = TRUE)),
    skewness = calculate_skewness(portfolio_returns, na.rm = TRUE),
    kurtosis = calculate_kurtosis(portfolio_returns, na.rm = TRUE),
    lpm = calculate_partials(portfolio_returns, type = "lower"),
    hpm = calculate_partials(portfolio_returns, type = "higher")
  )

  #--------> Berechnung der Handelsaktionen:
  buys <- sapply(flag_assets, function(x) length(sim_mem[["trades"]][[x]][["buys"]]) / time)
  sells <- sapply(flag_assets, function(x) length(sim_mem[["trades"]][[x]][["sells"]]) / time)

  results <- list(
  worth = total_worth,
  cagr = cagr,
  ttwror = ttwror,
  drawdowns = drawdowns,
  statistics = statistics,
  buys = buys,
  sells = sells,
  report = sim_mem[["report"]],
  
  tax_report = list(
    total_taxes_paid = sim_mem[[6]][["total_taxes"]],
    loss_carryforward_capital = sim_mem[[6]][["loss_capital_gains"]],
    loss_carryforward_private = sim_mem[[6]][["loss_private_sales"]],
    sparer_pauschbetrag_annual = sim_mem[[6]][["sparer_pauschbetrag_annual"]],
    sparer_pauschbetrag_used = sim_mem[[6]][["sparer_pauschbetrag_used_total"]],
    sparer_pauschbetrag_tax_saved = sim_mem[[6]][["sparer_pauschbetrag_used_total"]] * tax_rate
  )
)
  return(results)
}
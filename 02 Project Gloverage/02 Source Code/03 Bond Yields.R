########################################################################################################################
# Vorbereitung des Systems
########################################################################################################################
packages <- c("tidyverse", "tidyquant", "imputeTS", "plotly", "akima")
invisible(lapply(packages, require, character.only = TRUE)); rm(packages)

if(.Platform$OS.type == "windows"){Sys.setlocale("LC_ALL", "en_US.UTF-8")}

#---> Definition des Analysehorizonts:
start_date <- "1975-01-01"
stopp_date <- "2025-06-30"


########################################################################################################################
# Vorbereitung Zinsstrukturkurve
########################################################################################################################
#---> 1. Hilfsfunktion zur Identifikation des letzten Handelstages:
find_last_workday <- function(date, holidays) {
  while (date %in% holidays | weekdays(date) %in% c("Samstag", "Sonntag")) {
    date <- date - 1  # Einen Tag zurückgehen
  }
  return(date)
}

#---> 2. Konstruktion des Kalendar-Zeitindex:
calendar <- data.frame(date = seq.Date(from = as.Date("1972-01-01"), to = Sys.Date(), by = "day"))

#---> 3. Vorbereitung Feiertage Bundesrepublik Deutschland
holidays <- read.csv("./01 Source Data/02 EuroStat/Eurostat German Holidays.csv") %>%
  rename(date = Datum, holiday = Feiertag) %>%
  mutate(date = as.Date(date, format = "%d.%m.%Y")) %>%
  filter(holiday %in% c(
    "Neujahrstag", "Karfreitag", "Ostermontag", "Tag der Arbeit",
    "Heiligabend", "Erster Weihnachtstag", "Zweiter Weihnachtstag",
    "Silvester"))

#---> 4. Aufbereitung Monatsdaten Staatsanleihen
monthly_data <- list.files("./01 Source Data/01 Bundesbank/Monthly Yield Curves/", pattern = "\\.csv$", full.names = TRUE) %>%
  lapply(., function(x) {
  zinsrate <- regmatches(x, regexpr("R\\d{2}", x))
  
  read.csv(x, skip = 8, sep = ";") %>%
    rename_with(~ paste0("Zinsrate_", zinsrate), .cols = 2) %>%
    rename(Datum = 1) %>%
    mutate(across(starts_with("Zinsrate"), ~ as.numeric(gsub(",", ".", .)))) %>%
    select(Datum, starts_with("Zinsrate"))
  }) %>%
  reduce(., full_join, by = "Datum")

#---> 5. Berechnung des letzten Monatstages:
last_workday <- calendar %>%
  mutate(year = format(date, "%Y"),
         month = format(date, "%m"),
         year_month = paste0(year, "-", month),
         weekday = weekdays(date)) %>%
  group_by(year_month) %>%
  slice_max(date) %>%
  ungroup() %>%
  rowwise() %>%
  mutate(last_valid_workday = find_last_workday(date, holidays$date)) %>%
  ungroup() %>%
  select(year_month, last_valid_workday)

#---> 6. Verknüpfung letzter Monatstage und Zinsdaten:
monthly_data <- list(
  calendar,
  monthly_data %>%
    rename(year_month = Datum) %>%
    left_join(last_workday, by = "year_month") %>%
    mutate(date = last_valid_workday)) %>%
  Reduce(function(x, y) left_join(x, y, by = "date"), .) %>%
  select(-c(year_month, last_valid_workday))

#---> 7. Verknüpfung Monats- und Tageszinsdaten: 
yield_curve <- monthly_data  %>%
  filter(date <= "1997-07-31" & date >= "1972-09-30") %>%
  rbind(
    list.files(path = "./01 Source Data/01 Bundesbank/Daily Yield Curves/", pattern = "\\.csv$", full.names = TRUE) %>%
      lapply(., function(x) {
        zinsrate <- regmatches(x, regexpr("R\\d{2}", x))
        
        read.csv(x, skip = 8, sep = ";") %>%
          rename_with(~ paste0("Zinsrate_", zinsrate), .cols = 2) %>%
          rename(Datum = 1) %>%
          mutate(across(starts_with("Zinsrate"), ~ as.numeric(gsub(",", ".", .)))) %>%
          select(Datum, starts_with("Zinsrate"))
        }) %>%
      reduce(., full_join, by = "Datum") %>%
      mutate(date = as.Date(Datum, format = "%Y-m-%d")) %>%
      left_join(calendar, by = "date") %>%
      select(-c(date)) %>%
      rename(date = Datum) %>%
      mutate(date = as.Date(date, format = "%Y-%m-%d")))


########################################################################################################################
# Interpolation Zinsstrukturkurve
########################################################################################################################
#---> 1. Hilfsfunktion zur Berechnung von Svensson-Parameter: 
svensson_function <- function(t, beta0, beta1, beta2, beta3, tau1, tau2){
  term1 <- (1 - exp(-t/tau1)) / (t/tau1)
  term2 <- term1 - exp(-t/ tau1)
  term3 <- ((1 - exp(-t/tau2)) / (t/tau2)) - exp(-t/tau2)
  
  beta0 + beta1 * term1 + beta2 * term2 + beta3 * term3
}

#---> 2. Hilfsfunktion zur Optimierung der Svensson-Prediction: 
predict_svensson_optim <- function(params, maturities) {
  predicted_yields <- svensson_function(
    maturities, 
    beta0 = params[1], beta1 = params[2], beta2 = params[3], beta3 = params[4],
    tau1 = params[5], tau2 = params[6])
  
  return(predicted_yields)
}

#---> 3. Hilfsfunktion zur Berechnung der Svensson-Verlustfunktion:
loss_function <- function(params) {
  y_pred <- svensson_function(
    t,
    beta0 = params[1], beta1 = params[2], beta2 = params[3], beta3 = params[4],
    tau1 = params[5], tau2 = params[6])
  sum((y - y_pred)^2)
}

#---> 4. Vervollständigung Zinsstrukturkurven:
starting <- c(0.03, -0.02, 0.02, 0.01, 2, 5)
ergebnis <- matrix(NA, nrow = nrow(yield_curve), ncol = 32)
iterator <- which(apply(yield_curve[, -1], 1, function(x) !all(is.na(x))))
predicts <- c(0.5, seq(1, 30, by = 1), 31.5)

for(i in iterator){
  t <- which(!is.na(yield_curve[i, -1]))
  y <- unlist(yield_curve[i, -1])[t]
  
  fit <- optim(
    par = starting,
    fn = loss_function,
    lower = c(-Inf, -Inf, -Inf, -Inf, 0.1, 0.1),
    upper = c(Inf, Inf, Inf, Inf, 10, 10),
    method = "L-BFGS-B")
  
  predicted_yields <- predict_svensson_optim(fit$par, predicts)
  result_row <- rep(NA, length(predicts))
  positions <- match(t, predicts)
  
  result_row[positions] <- y
  result_row[is.na(result_row)] <- round(predicted_yields[is.na(result_row)], digits = 2)
  ergebnis[i, ] <- result_row
}

#---> 5. Akima-Extrapolation Zinsstrukturkurven:
x = rep(1:nrow(ergebnis), each=32); y = rep(1:32, nrow(ergebnis)); z = c(t(ergebnis))
valid <- !is.na(x) & !is.na(y) & !is.na(z) & is.finite(x) & is.finite(y) & is.finite(z)
akima <- list(x = x[valid], y = y[valid], z = z[valid])

extra <- interp(akima$x, akima$y, akima$z, extrap = TRUE,
                xo = seq(min(x), max(x), by = 1),
                yo = seq(min(y), max(y), by = 1))
zmin <- min(extra$z,na.rm=TRUE); zmax <- max(extra$z,na.rm=TRUE)
breaks <- pretty(c(zmin, zmax), 10)
colors <- heat.colors(length(breaks)-1)
with(extra, image (x, y, z, breaks=breaks, col=colors))
with(extra,contour(x, y, z, levels=breaks, add=TRUE))

matrix <- round(extra$z[, -c(1,32)], digits = 2)
yield_curve <- yield_curve %>%
  column_to_rownames("date")

for(i in 1:nrow(yield_curve)){
  row_check <- is.na(yield_curve[i,])
  if(any(row_check)){
    index <- which(is.na(yield_curve[i,]))
    yield_curve[i, index] <- matrix[i, index]
  }
}

yield_curve %>%
  rownames_to_column("date") %>%
  rename_with(~ gsub("Zinsrate_R", "m", .) %>% tolower()) %>%
  write.csv("./Project Gloverage Bond Yields.csv", row.names = FALSE)
########################################################################################################################
# Bereinigung des Workspace
########################################################################################################################
rm(list = ls())
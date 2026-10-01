#-----------------------------------------------------------------------------------------------------------------------
# Backcasting von USD- und EUR-Indexvarianten (Price Return, Gross Total Return und Net Total Return)
#-----------------------------------------------------------------------------------------------------------------------
# Ablauf:
# 1. Einlesen und Erkennung von Spalten und erster gültiger Werte je Indexreihe
# 2. USD Gross / Net: GAM  Return ~ s(USD Price Return)          -> Rückrechnung vor dem ersten gültigen Wert
# 3. Umrechnungskurs: USD Price / EUR Price (implizit, USD je EUR), Vergleich mit offiziellem Kurs,
#                     GAM  impliziter Kurs ~ s(offizieller Kurs) -> Rückrechnung vor dem ersten gültigen Wert
# 4. EUR Price:       USD Price / impliziter Kurs                -> Rückrechnung vor dem ersten gültigen Wert
# 5. EUR Gross / Net: GAM  Return ~ s(EUR Price Return)          -> Rückrechnung vor dem ersten gültigen Wert
#
# Grundsätze:
# - Es wird NICHT interpoliert. Genutzt werden nur Tage, an denen die jeweils benötigten Reihen echte Werte haben.
#   Fehlt eine Erklärungsreihe an einem Tag (z.B. kein offizieller Kurs an Feiertagen), bleibt die Rückrechnung
#   an diesem Tag leer.
# - Renditefaktoren = x/lag(x) über die jeweils gültigen Beobachtungen. Liegt eine Lücke vor, ist der Faktor
#   die Rendite seit dem letzten gültigen Wert; Ziel- und Erklärungsreihe beziehen sich immer auf dieselbe Spanne.
# - Rückrechnung: Ausgehend vom ersten gemeinsamen echten Wert (Anker) wird rückwärts verkettet,
#   level[t-1] = level[t] / return[t]. Offizielle Werte bleiben unverändert, es entsteht kein Sprung am Anker.
# - Alle Startdaten werden aus den Daten ausgelesen; es gibt keine fest eingetragenen Datumswerte.
# - Gemischte Frequenzen (z.B. Monatswerte bis 1972, danach Tageswerte): Das GAM wird auf Renditen je Handelstag
#   geschätzt. Umfasst ein Renditefaktor n Handelstage (Mo-Fr), wird er geometrisch auf n Tage verteilt
#   (x^(1/n)), je Tag prognostiziert und wieder verkettet (y^n). Ohne diese Korrektur würde die Dividende einer
#   Monatsrendite nur einmal statt ~21-mal angesetzt.
# - Der offizielle Kurs (Eurostat) beginnt 1974-07-01. Für eine Rückrechnung der EUR-Reihen davor kann optional
#   über config$fx_extension eine oder mehrere Proxy-Kursreihen (z.B. USD/DEM, USD/GBP) eingebunden werden.
#-----------------------------------------------------------------------------------------------------------------------
packages <- c("tidyverse", "openxlsx", "mgcv", "plotly")
lapply(packages, require, character.only = TRUE); rm(packages)

if(.Platform$OS.type == "windows"){Sys.setlocale("LC_ALL", "en_US.UTF-8")}


#-----------------------------------------------------------------------------------------------------------------------
# Konfiguration
#-----------------------------------------------------------------------------------------------------------------------
config <- list(
  index_file = "01 Input Data/MSCI World.xlsx",               # .xlsx oder .csv, eine Datumsspalte + sechs Indexspalten
  fx_file    = "01 Input Data/EuroStat Exchange Rates.csv",  # Eurostat ert_bil_eur_d (USD je EUR bzw. ECU)
  fx_filter  = c(column = "currency", value = "US dollar"),
  fx_date    = "TIME_PERIOD",
  fx_value   = "OBS_VALUE",
  gam_k      = 10,
  # Optionale Verlängerung des offiziellen Kurses vor dessen ersten Wert über Proxy-Kursreihen (NULL = keine).
  # Je Proxy: source (Datei oder URL, CSV), date/value (Spaltenname oder -nummer), invert (TRUE, wenn Fremdwährung je
  # USD notiert, z.B. DEM je USD). Geschätzt wird  offizieller Kurs ~ s(Proxy 1) + s(Proxy 2) + ...  auf der
  # Überlappung; genutzt werden nur Tage, an denen ALLE Proxies einen echten Wert haben.
  # Beispiel (FRED, Tageswerte ab 1971-01-04):
  # fx_extension = list(
  #   DEM = list(source = "https://fred.stlouisfed.org/graph/fredgraph.csv?id=DEXGEUS", date = 1, value = 2, invert = TRUE),
  #   GBP = list(source = "https://fred.stlouisfed.org/graph/fredgraph.csv?id=DEXUSUK", date = 1, value = 2, invert = FALSE)),
  fx_extension = NULL,
  # Spaltennamen der Indexdatei. NULL = automatische Erkennung über die Namensbestandteile
  # (z.B. "ACWI_Price_USD", "World Gross EUR", "NETR_EURO"); bei abweichender Benennung hier eintragen.
  columns = list(price_usd = NULL, gross_usd = NULL, net_usd = NULL,
                 price_eur = NULL, gross_eur = NULL, net_eur = NULL))

config$output_file <- paste0("02 Backcast Data/",tools::file_path_sans_ext(basename(config$index_file)), " Backcast.csv")


#-----------------------------------------------------------------------------------------------------------------------
# Hilfsfunktionen
#-----------------------------------------------------------------------------------------------------------------------
#---> Spaltenerkennung über Namensbestandteile
find_column <- function(names, variant, currency){
  tokens <- lapply(strsplit(tolower(names), "[_. -]+"), unique)
  variants   <- list(price = c("price", "pr", "strd"), gross = c("gross", "gr", "grtr", "gdtr"),
                     net = c("net", "nr", "netr", "ndtr"))
  currencies <- list(usd = c("usd", "dollar"), eur = c("eur", "euro"))
  hit <- names[sapply(tokens, function(t) any(t %in% variants[[variant]]) && any(t %in% currencies[[currency]]))]
  if(length(hit) != 1){
    stop(sprintf("Spalte für '%s %s' nicht eindeutig erkannt (Treffer: %s). Bitte in config$columns eintragen.",
                 variant, toupper(currency), ifelse(length(hit) == 0, "keine", paste(hit, collapse = ", "))))}
  hit}

#---> Erster gültiger Wert einer Reihe:
first_valid <- function(data, col){
  d <- data$date[!is.na(data[[col]])]
  if(length(d) == 0) stop("Reihe '", col, "' enthält keine gültigen Werte")
  min(d)}

#---> Erster Tag aller Reihen:
first_common <- function(data, cols){
  d <- data$date[complete.cases(data[cols])]
  if(length(d) == 0) stop("Keine gemeinsamen Beobachtungen für: ", paste(cols, collapse = ", "))
  min(d)}

#---> Renditefaktor x/lag(x) über die gültigen Beobachtungen:
valid_return <- function(x){
  r <- rep(NA_real_, length(x))
  i <- which(!is.na(x))
  if(length(i) > 1) r[i[-1]] <- x[i[-1]] / x[i[-length(i)]]
  r}

#---> Anzahl Handelstage (Mo-Fr) zwischen aufeinanderfolgenden Datumswerten, d.h. im Intervall (d[i-1], d[i]]:
trading_days <- function(d){
  if(length(d) < 2) return(rep(NA_real_, length(d)))
  calendar <- seq(min(d), max(d), by = "day")
  weekdays <- cumsum(as.integer(format(calendar, "%u")) <= 5)
  c(NA, pmax(diff(weekdays[as.integer(d - min(d)) + 1]), 1))}

#---> GAM-Backcast einer Indexreihe (Target) über eine Erklärungsreihe (Driver):
# Schätzung: Renditefaktoren je Handelstag auf allen Tagen, an denen beide Reihen echte Werte haben.
# Rückrechnung: alle Tage vor dem Anker, an denen der Driver einen echten Wert hat. Mehrtägige Renditefaktoren
# (Wochen-/Monatswerte, Lücken) werden auf Handelstage verteilt, je Tag prognostiziert und wieder verkettet.
gam_backcast <- function(data, target, driver, k = 10){
  anchor <- first_common(data, c(target, driver))

  estimation <- data %>%
    filter(!is.na(.data[[target]]), !is.na(.data[[driver]])) %>%
    mutate(days = trading_days(date)) %>%
    transmute(y = valid_return(.data[[target]])^(1/days), x = valid_return(.data[[driver]])^(1/days))
  model <- gam(y ~ s(x, bs = "cr", k = k), data = estimation, method = "REML")

  backcast <- data %>%
    filter(date <= anchor, !is.na(.data[[driver]])) %>%
    transmute(date, days = trading_days(date), x = valid_return(.data[[driver]])^(1/days))
  n <- nrow(backcast)

  if(n > 1){
    ret   <- as.numeric(predict(model, newdata = backcast))^backcast$days
    level <- data[[target]][data$date == anchor] / rev(cumprod(rev(ret[2:n])))
    idx   <- match(backcast$date[-n], data$date)
    data[[target]][idx] <- ifelse(is.na(data[[target]][idx]), level, data[[target]][idx])
  }

  cat(sprintf("%-24s Anker: %s | Schätzung: %d Returns | zurückgerechnet: %d Werte (%s bis %s), davon %d mehrtägig\n",
              target, anchor, sum(complete.cases(estimation)), max(n - 1, 0),
              if(n > 1) as.character(min(backcast$date)) else "-",
              if(n > 1) as.character(backcast$date[n - 1]) else "-",
              sum(backcast$days > 1, na.rm = TRUE)))
  structure(data, model = model, anchor = anchor)}

#---> Kennzahlen für den Vergleich zweier Reihen:
compare_series <- function(model, actual){
  e <- model - actual
  tibble(n = sum(!is.na(e)),
         mean_error = mean(e, na.rm = TRUE),
         mean_absolute_error = mean(abs(e), na.rm = TRUE),
         root_mean_squared_error = sqrt(mean(e^2, na.rm = TRUE)),
         max_absolute_error = max(abs(e), na.rm = TRUE),
         correlation = cor(model, actual, use = "complete.obs"))}


#-----------------------------------------------------------------------------------------------------------------------
# 1. Einlesen und Spaltenerkennung
#-----------------------------------------------------------------------------------------------------------------------
raw <- if(grepl("\\.csv$", config$index_file, ignore.case = TRUE)){
  read.csv(config$index_file, check.names = FALSE)
  } else {
  read.xlsx(config$index_file, detectDates = TRUE, check.names = FALSE)
}

date_col <- names(raw)[tolower(names(raw)) %in% c("date", "datum")][1]
if(is.na(date_col)) date_col <- names(raw)[1]
index_data <- raw %>%
  rename(date = all_of(date_col)) %>%
  mutate(date = if(is.numeric(date)) convertToDate(date) else as.Date(date)) %>%
  filter(!is.na(date)) %>%
  arrange(date)

cols <- config$columns
for(v in c("price", "gross", "net")) for(cur in c("usd", "eur")){
  key <- paste0(v, "_", cur)
  if(is.null(cols[[key]])) cols[[key]] <- find_column(setdiff(names(index_data), "date"), v, cur)
}
cols <- unlist(cols)
index_data <- index_data %>% mutate(across(all_of(unname(cols)), as.numeric))

#---> Ermittlung erster gültiger Werte:
start_dates <- sapply(cols, function(col) as.character(first_valid(index_data, col)))
tibble(variant = names(cols), column = unname(cols), first_valid = as.Date(start_dates),
       observations = sapply(cols, function(col) sum(!is.na(index_data[[col]])))) %>% print()
start_dates <- as.Date(start_dates) %>% setNames(names(cols))

#---> Renditefaktoren x/lag(x) der Originalreihen:
original_returns <- index_data %>%
  transmute(date, across(all_of(unname(cols)), valid_return, .names = "{.col}_Return"))


#-----------------------------------------------------------------------------------------------------------------------
# 2. Backcast der USD Gross und Net Total Return Indizes (GAM auf USD Price Return)
#-----------------------------------------------------------------------------------------------------------------------
gross_usd <- gam_backcast(index_data, cols["gross_usd"], cols["price_usd"], k = config$gam_k)
net_usd   <- gam_backcast(gross_usd,  cols["net_usd"],   cols["price_usd"], k = config$gam_k)


#-----------------------------------------------------------------------------------------------------------------------
# 3. Impliziter Umrechnungskurs, Vergleich mit dem offiziellen Kurs und Backcast
#-----------------------------------------------------------------------------------------------------------------------
# Impliziter Kurs = USD Price / EUR Price -> USD je EUR (bis auf eine Konstante aus den unterschiedlichen Basiswerten).
# Offizieller Kurs (Eurostat ert_bil_eur_d): USD je 1 EUR, vor 1999 USD je 1 ECU. Nur tatsächlich veröffentlichte
# Kurse werden genutzt (keine Feiertagsinterpolation).
# Hinweis: EZB-Referenzkurse werden um 14:15 MEZ fixiert, MSCI nutzt WM/Reuters-Schlusskurse (16:00 London)
# -> tägliche Abweichungen sind zu erwarten, die Niveaus stimmen eng überein.
fx_official <- read.csv(config$fx_file) %>%
  filter(.data[[config$fx_filter[["column"]]]] == config$fx_filter[["value"]]) %>%
  transmute(date = as.Date(.data[[config$fx_date]]), fx_official = as.numeric(.data[[config$fx_value]])) %>%
  filter(!is.na(date), !is.na(fx_official)) %>%
  mutate(fx_source = "official")

#---> Optionale Verlängerung des offiziellen Kurses über Proxy-Kursreihen (Niveau-GAM, nur echte Proxy-Tage):
if(length(config$fx_extension) > 0){
  proxy_data <- lapply(names(config$fx_extension), function(name){
    p <- config$fx_extension[[name]]
    d <- read.csv(p$source, na.strings = c("", ".", "NA"), check.names = FALSE)
    tibble(date = as.Date(d[[p$date]]), value = suppressWarnings(as.numeric(d[[p$value]]))) %>%
      filter(!is.na(date), !is.na(value), value > 0) %>%
      mutate(value = if(isTRUE(p$invert)) 1/value else value) %>%
      setNames(c("date", name))}) %>%
    Reduce(function(x, y) inner_join(x, y, by = "date"), .)
  proxy_names <- setdiff(names(proxy_data), "date")

  extension_estimation <- inner_join(fx_official, proxy_data, by = "date")
  extension_model <- gam(
    as.formula(paste("fx_official ~", paste0("s(`", proxy_names, "`, bs = 'cr', k = ", config$gam_k, ")",
                                             collapse = " + "))),
    data = extension_estimation, method = "REML")
  print(summary(extension_model))

  extension_estimation %>%
    mutate(deviation_pct = (as.numeric(predict(extension_model)) / fx_official - 1) * 100) %>%
    summarise(n = n(), from = min(date), to = max(date), mean_dev_pct = mean(deviation_pct),
              sd_dev_pct = sd(deviation_pct), max_abs_dev_pct = max(abs(deviation_pct))) %>%
    print()

  fx_extension <- proxy_data %>%
    filter(date < min(fx_official$date)) %>%
    mutate(fx_official = as.numeric(predict(extension_model, newdata = .)), fx_source = "proxy") %>%
    select(date, fx_official, fx_source)

  cat("Offizieller Kurs über Proxies verlängert:", nrow(fx_extension), "Tage",
      if(nrow(fx_extension) > 0) paste0("(", min(fx_extension$date), " bis ", max(fx_extension$date), ")"), "\n")
  fx_official <- bind_rows(fx_extension, fx_official) %>% arrange(date)
}

index_fx <- net_usd %>%
  left_join(fx_official, by = "date") %>%
  mutate(fx_implied = .data[[cols["price_usd"]]] / .data[[cols["price_eur"]]])

start_dates["fx_implied"]  <- first_valid(index_fx, "fx_implied")
start_dates["fx_official"] <- first_valid(index_fx, "fx_official")
cat("Kurs verfügbar:", format(start_dates["fx_official"]), "bis", format(max(fx_official$date)),
    "| davon offiziell ab", format(min(fx_official$date[fx_official$fx_source == "official"])), "\n")

#---> 3a. Vergleich implizit vs. offiziell:
fx_comparison <- index_fx %>%
  filter(!is.na(fx_implied), !is.na(fx_official), fx_source == "official") %>%
  mutate(fx_implied_return  = valid_return(fx_implied),
         fx_official_return = valid_return(fx_official))

# Skalierungsfaktor aus dem Median des Verhältnisses ermitteln:
fx_scale <- with(fx_comparison, median(fx_implied/fx_official))
cat("Skalierungsfaktor implizit/offiziell:", round(fx_scale, 6), "\n")

fx_comparison <- fx_comparison %>%
  mutate(fx_implied_scaled = fx_implied/fx_scale,
         deviation_pct     = (fx_implied_scaled/fx_official - 1)*100)

bind_rows(
  "Niveau (skaliert)" = with(fx_comparison, compare_series(fx_implied_scaled, fx_official)),
  "Renditefaktor"     = with(fx_comparison, compare_series(fx_implied_return, fx_official_return)),
  .id = "comparison") %>%
  print(width = Inf)

# Abweichung pro Jahr:
fx_comparison %>%
  group_by(year = as.integer(format(date, "%Y"))) %>%
  summarise(n = n(), mean_dev_pct = mean(deviation_pct), sd_dev_pct = sd(deviation_pct),
            max_abs_dev_pct = max(abs(deviation_pct))) %>%
  print(n = Inf)

#---> 3b. GAM-Backcast des impliziten Kurses auf NIVEAU-Basis:
# Bewusst nicht über Returns: Wegen der unterschiedlichen Fixing-Zeitpunkte sind die Tagesrenditen nur mässig
# korreliert. Ein Return-GAM schätzt dadurch eine gedämpfte Steigung, die sich bei der Verkettung über viele Jahre
# zu deutlichen Niveaufehlern aufsummiert. Das Niveau-Modell folgt dem offiziellen Kurs eng und driftet nicht.
fx_model <- gam(fx_implied ~ s(fx_official, bs = "cr", k = config$gam_k), data = fx_comparison, method = "REML")
summary(fx_model)

index_fx <- index_fx %>%
  mutate(
    fx_backcast = date < start_dates[["fx_implied"]] & !is.na(fx_official),
    fx_implied  = ifelse(fx_backcast, as.numeric(predict(fx_model, newdata = pick(fx_official))), fx_implied))

cat("Impliziter Kurs zurückgerechnet:", sum(index_fx$fx_backcast), "Tage;",
    sum(index_fx$date < start_dates[["fx_implied"]] & is.na(index_fx$fx_official)),
    "Tage ohne Kurs bleiben leer\n")

# Kontrolle Rückrechnungszeitraum (Verhältnis sollte ~1 sein) und Nahtstelle:
index_fx %>% filter(fx_backcast) %>%
  summarise(ratio_min = min(fx_implied/fx_scale/fx_official), ratio_max = max(fx_implied/fx_scale/fx_official)) %>%
  print()

index_fx %>%
  filter(!is.na(fx_implied)) %>%
  mutate(fx_implied_return = valid_return(fx_implied)) %>%
  filter(between(date, start_dates[["fx_implied"]] - 7, start_dates[["fx_implied"]] + 7)) %>%
  select(date, fx_official, fx_implied, fx_implied_return, fx_backcast) %>%
  print()


#-----------------------------------------------------------------------------------------------------------------------
# 4. Backcast des EUR Price Index: USD Price / impliziter Kurs
#-----------------------------------------------------------------------------------------------------------------------
# Ab dem ersten gültigen EUR-Wert entspricht das exakt dem offiziellen Wert (Definition des impliziten Kurses),
# davor wird der zurückgerechnete Kurs genutzt.
index_eur <- index_fx %>%
  mutate("{cols[['price_eur']]}" := ifelse(
    date < start_dates[["price_eur"]],
    .data[[cols["price_usd"]]] / fx_implied,
    .data[[cols["price_eur"]]]))


#-----------------------------------------------------------------------------------------------------------------------
# 5. Backcast der EUR Gross und Net Total Return Indizes (GAM auf EUR Price Return)
#-----------------------------------------------------------------------------------------------------------------------
gross_eur <- gam_backcast(index_eur, cols["gross_eur"], cols["price_eur"], k = config$gam_k)
net_eur   <- gam_backcast(gross_eur, cols["net_eur"],   cols["price_eur"], k = config$gam_k)

index_model <- net_eur

#---> Plausibilisierung: Zwischen dem ersten EUR-Price- und dem ersten EUR-Gross/Net-Wert existieren ggf. bereits
# USD Gross/Net und der implizite Kurs. USD-Reihe / impliziter Kurs dient dort als unabhängiger Vergleich
# (auf den Anker normiert). Fällt weg, wenn die EUR-Reihen gleichzeitig beginnen.
check_eur <- function(target, usd_col, anchor){
  d <- index_model %>%
    filter(date >= start_dates[["price_eur"]], date <= anchor) %>%
    filter(!is.na(.data[[target]]), !is.na(.data[[usd_col]]), !is.na(fx_implied)) %>%
    mutate(via_fx = .data[[usd_col]] / fx_implied,
           via_fx = via_fx / last(via_fx) * last(.data[[target]]),
           dev_pct = (.data[[target]] / via_fx - 1) * 100)
  if(nrow(d) < 2) return(NULL)
  tibble(series = target, from = min(d$date), to = max(d$date), n = nrow(d),
         mean_dev_pct = mean(d$dev_pct), max_abs_dev_pct = max(abs(d$dev_pct)))}

bind_rows(check_eur(cols[["gross_eur"]], cols[["gross_usd"]], attr(gross_eur, "anchor")),
          check_eur(cols[["net_eur"]],   cols[["net_usd"]],   attr(net_eur, "anchor"))) %>%
  print(width = Inf)
# Hinweis: Eine systematische Abweichung entsteht v.a. durch den Achsenabschnitt des GAM (= mittlere Tagesdividende
# im Schätzzeitraum), der in Phasen niedriger Dividendenrenditen zu hoch liegt. Alternativ können EUR Gross/Net in
# diesem Zeitraum exakt als USD Gross/Net / impliziter Kurs berechnet werden.


#-----------------------------------------------------------------------------------------------------------------------
# Export
#-----------------------------------------------------------------------------------------------------------------------
index_final <- index_model %>%
  select(date, all_of(unname(cols)), fx_implied, fx_official, fx_source, fx_backcast) %>%
  mutate(across(all_of(unname(cols)), ~ round(.x, digits = 5)),
         across(all_of(unname(cols)), valid_return, .names = "{.col}_Return"))

write.csv(index_final %>% rename(!!date_col := date) %>% select(any_of(names(raw))),
          config$output_file, row.names = FALSE)

# Kontrolle: Offizielle Werte dürfen durch die Rückrechnung nicht verändert worden sein
for(col in unname(cols)){
  i <- which(!is.na(index_data[[col]]))
  stopifnot(isTRUE(all.equal(round(index_data[[col]][i], 5), index_final[[col]][i])))
}


#-----------------------------------------------------------------------------------------------------------------------
# Visualisierung
#-----------------------------------------------------------------------------------------------------------------------
#---> Impliziter vs. offizieller Kurs (Skalierung):
index_model %>%
  filter(!is.na(fx_implied) | !is.na(fx_official)) %>%
  plot_ly(type = "scatter", mode = "lines") %>%
  add_trace(x = ~date, y = ~fx_official, name = "Offizieller Kurs", line = list(width = 1),
            connectgaps = FALSE) %>%
  add_trace(x = ~date, y = ~fx_implied/fx_scale, name = "Impliziter Kurs (skaliert)", line = list(width = 1),
            connectgaps = FALSE) %>%
  layout(legend = list(orientation = "h"), xaxis = list(title = "Time"),
         yaxis = list(title = "USD je EUR/ECU"), title = "Umrechnungskurs",
         shapes = list(list(type = "line", x0 = start_dates[["fx_implied"]], x1 = start_dates[["fx_implied"]],
                            y0 = 0, y1 = 1, yref = "paper", line = list(dash = "dot", color = "grey"))),
         margin = list(t = 50))

#---> Abweichung implizit/offiziell (Prozente):
fx_comparison %>%
  plot_ly(x = ~date, y = ~deviation_pct, type = "scatter", mode = "lines", line = list(width = 1)) %>%
  layout(xaxis = list(title = "Time"), yaxis = list(title = "Abweichung (%)"),
         title = "Impliziter vs. offizieller Kurs", margin = list(t = 50))

#---> Indexverläufe (Log. Skala; Gestrichelte Linien für erste gültige Originalwerte):
plot_indices <- function(data, keys, title, ytitle){
  p <- plot_ly(type = "scatter", mode = "lines")
  for(key in keys){
    x <- data[[cols[[key]]]]
    p <- add_trace(p, x = data$date, y = log(x / x[which(!is.na(x))[1]]), name = cols[[key]],
                   line = list(width = 1), connectgaps = FALSE)}
  shapes <- lapply(keys, function(key) list(type = "line", x0 = start_dates[[key]], x1 = start_dates[[key]],
                                            y0 = 0, y1 = 1, yref = "paper",
                                            line = list(dash = "dot", width = 1, color = "grey")))
  layout(p, legend = list(orientation = "h"), xaxis = list(title = "Time"), yaxis = list(title = ytitle),
         title = title, shapes = shapes, margin = list(t = 50))}

plot_indices(index_model, c("price_usd", "gross_usd", "net_usd"), "Indexvarianten (USD)", "Log. Index Value (USD)")
plot_indices(index_model, c("price_eur", "gross_eur", "net_eur"), "Indexvarianten (EUR)", "Log. Index Value (EUR)")

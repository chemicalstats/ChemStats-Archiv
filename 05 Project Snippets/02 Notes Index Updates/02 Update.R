#-----------------------------------------------------------------------------------------------------------------------
# Fortschreibung der Backcast-Datensätze mit aktuellen MSCI-Indexwerten
#-----------------------------------------------------------------------------------------------------------------------
# Ablauf je Datei und je Indexspalte:
# 1. Letzten gültigen Wert der Spalte im Datensatz ermitteln (Datum L, Wert V).
# 2. Aktuelle Werte über die MSCI-Schnittstelle abrufen, ab L - overlap_days bis heute.
# 3. Anker = letzter Tag <= L, an dem Datensatz und Abruf beide einen Wert haben.
# 4. Neue Werte auf den Anker skalieren:  neu_angepasst[t] = neu[t] * Datensatz[Anker] / neu[Anker]
#    Dadurch bleiben die Renditen der MSCI-Daten erhalten und die Reihe setzt ohne Sprung fort.
# 5. Kontrolle im Überlappungszeitraum: Die Tagesrenditen von Datensatz und Abruf müssen übereinstimmen.
#    Weichen sie ab (falscher Code, falsche Variante/Währung), wird die Spalte NICHT fortgeschrieben.
# 6. Nur Tage > L werden angehängt; vorhandene Werte werden nie verändert.
#
# Arbeitet direkt auf den Backcast-Ergebnissen in "02 Backcast Data" (vollständig oder auf die Originalspalten
# reduziert) und schreibt die fortgeschriebenen Reihen in dieselben Dateien zurück.
#-----------------------------------------------------------------------------------------------------------------------
packages <- c("tidyverse", "openxlsx", "httr", "jsonlite")
lapply(packages, require, character.only = TRUE); rm(packages)

if(.Platform$OS.type == "windows"){Sys.setlocale("LC_ALL", "en_US.UTF-8")}


#-----------------------------------------------------------------------------------------------------------------------
# Konfiguration
#-----------------------------------------------------------------------------------------------------------------------
config <- list(
  input_files   = Sys.glob("02 Backcast Data/* Backcast.csv"),
  output_dir    = "02 Backcast Data", # Backcast-Dateien werden direkt fortgeschrieben (überschrieben)
  stopp_date    = Sys.Date(),
  overlap_days  = 30,                 # Kalendertage vor L, die zur Kontrolle mit abgerufen werden
  tolerance     = 1e-4,               # Max. zulässige Abweichung der Tagesrenditen im Überlappungszeitraum
  pause_seconds = 1,                  # Pause zwischen den Abrufen
  # MSCI-Indexcodes. Schlüssel = Dateiname ohne "MSCI " / " Backcast" / " Updated" und Endung.
  # Bitte die Codes einmal auf der MSCI-Webseite prüfen; ein falscher Code wird über die Renditekontrolle erkannt.
  index_codes = c(
    "USA"           = "984000",
    "World"         = "990100",
    "ACWI"          = "892400",
    "EAFE"          = "990300",
    "Europe"        = "990500",
    "North America" = "990200",
    "Pacific"       = "990800"),
  variants   = c(price = "STRD", gross = "GRTR", net = "NETR"),
  currencies = c(usd = "USD", eur = "EUR"))


#-----------------------------------------------------------------------------------------------------------------------
# Hilfsfunktionen
#-----------------------------------------------------------------------------------------------------------------------
#---> Abruf der Marktindizes (gibt bei Fehlern NULL zurück statt des Response-Objekts):
scraping_index <- function(code, type, currency, start, stopp){
  response <- tryCatch(
    GET(paste0("https://app2.msci.com/products/service/index/indexmaster/getLevelDataForGraph?currency_symbol=",
               currency, "&index_variant=", type, "&start_date=", start, "&end_date=", stopp,
               "&data_frequency=DAILY&index_codes=", code)),
    error = function(e) NULL)
  if(is.null(response) || status_code(response) != 200){
    message("  Fehler beim Abrufen: ", code, " ", type, " ", currency)
    return(NULL)}
  levels <- tryCatch(fromJSON(content(response, "text", encoding = "utf-8"))$indexes$INDEX_LEVELS,
                     error = function(e) NULL)
  if(is.null(levels) || length(levels) == 0 || nrow(levels) == 0) return(NULL)
  tibble(date  = as.Date(as.character(levels$calc_date), format = "%Y%m%d"),
         value = as.numeric(levels$level_eod)) %>%
    filter(!is.na(date), !is.na(value)) %>%
    arrange(date)}

#---> Spaltenerkennung über Namensbestandteile (wie im Backcast-Skript):
find_column <- function(names, variant, currency){
  tokens <- lapply(strsplit(tolower(names), "[_. -]+"), unique)
  variants   <- list(price = c("price", "pr", "strd"), gross = c("gross", "gr", "grtr", "gdtr"),
                     net = c("net", "nr", "netr", "ndtr"))
  currencies <- list(usd = c("usd", "dollar"), eur = c("eur", "euro"))
  hit <- names[sapply(tokens, function(t) any(t %in% variants[[variant]]) && any(t %in% currencies[[currency]]) &&
                                          !"return" %in% t)]
  if(length(hit) == 1) hit else NA_character_}

#---> Indexschlüssel aus dem Dateinamen:
index_key <- function(file){
  file %>% basename() %>% tools::file_path_sans_ext() %>%
    sub("^MSCI[ _]+", "", .) %>% sub("[ _]+(Backcast|Updated)$", "", .) %>% trimws()}

#---> Renditefaktor x/lag(x) über die gültigen Beobachtungen:
valid_return <- function(x){
  r <- rep(NA_real_, length(x))
  i <- which(!is.na(x))
  if(length(i) > 1) r[i[-1]] <- x[i[-1]] / x[i[-length(i)]]
  r}

#---> Einlesen (csv oder xlsx), Datumsspalte erkennen:
read_index_file <- function(file){
  raw <- if(grepl("\\.csv$", file, ignore.case = TRUE)){
    read.csv(file, check.names = FALSE)
  } else {
    read.xlsx(file, detectDates = TRUE, check.names = FALSE)
  }
  date_col <- names(raw)[tolower(names(raw)) %in% c("date", "datum")][1]
  if(is.na(date_col)) date_col <- names(raw)[1]
  raw[[date_col]] <- if(is.numeric(raw[[date_col]])) convertToDate(raw[[date_col]]) else as.Date(raw[[date_col]])
  list(data = raw[!is.na(raw[[date_col]]), , drop = FALSE] %>% arrange(.data[[date_col]]), date_col = date_col)}

#---> Fortschreibung einer Spalte; gibt die angepassten neuen Werte (Datum > L) und ein Protokoll zurück:
update_column <- function(data, date_col, col, code, type, currency){
  valid <- !is.na(data[[col]])
  last_date  <- max(data[[date_col]][valid])
  log <- tibble(column = col, type = type, currency = currency, last_date = last_date,
                anchor = as.Date(NA), overlap_n = NA_integer_, max_return_diff = NA_real_,
                scale = NA_real_, new_rows = 0L, new_last_date = as.Date(NA), status = "")

  if(last_date >= config$stopp_date){log$status <- "aktuell"; return(list(new = NULL, log = log))}

  online <- scraping_index(code, type, currency,
                           start = format(last_date - config$overlap_days, "%Y%m%d"),
                           stopp = format(config$stopp_date, "%Y%m%d"))
  Sys.sleep(config$pause_seconds)
  if(is.null(online)){log$status <- "Abruf fehlgeschlagen"; return(list(new = NULL, log = log))}

  #---> Überlappung und Anker:
  overlap <- tibble(date = data[[date_col]][valid], local = data[[col]][valid]) %>%
    filter(date >= last_date - config$overlap_days) %>%
    inner_join(online, by = "date") %>%
    mutate(diff = valid_return(local) - valid_return(value))
  if(nrow(overlap) == 0){log$status <- "keine Überlappung"; return(list(new = NULL, log = log))}

  anchor <- max(overlap$date)
  scale  <- overlap$local[overlap$date == anchor] / overlap$value[overlap$date == anchor]
  max_diff <- suppressWarnings(max(abs(overlap$diff), na.rm = TRUE))
  log$anchor <- anchor; log$overlap_n <- nrow(overlap); log$scale <- scale
  log$max_return_diff <- ifelse(is.finite(max_diff), max_diff, NA_real_)

  if(nrow(overlap) < 2){
    log$status <- "WARNUNG: nur 1 gemeinsamer Tag, keine Renditekontrolle möglich"
  } else if(max_diff > config$tolerance){
    log$status <- "ABGELEHNT: Renditen weichen ab (Code/Variante/Währung prüfen)"
    return(list(new = NULL, log = log))
  } else {
    log$status <- "ok"
  }

  new <- online %>%
    filter(date > last_date) %>%
    transmute(date, "{col}" := value * scale)
  log$new_rows <- nrow(new)
  if(nrow(new) > 0) log$new_last_date <- max(new$date)
  list(new = new, log = log)}


#-----------------------------------------------------------------------------------------------------------------------
# Fortschreibung aller Dateien
#-----------------------------------------------------------------------------------------------------------------------
dir.create(config$output_dir, showWarnings = FALSE, recursive = TRUE)
update_log <- list()

for(file in config$input_files){
  key  <- index_key(file)
  code <- unname(config$index_codes[key])
  cat("\n==>", basename(file), "| Index:", key, "| Code:", ifelse(is.na(code), "-", code), "\n")
  if(is.na(code)){cat("  Kein Indexcode hinterlegt -> übersprungen (config$index_codes ergänzen)\n"); next}

  input    <- read_index_file(file)
  data     <- input$data
  date_col <- input$date_col

  #---> Indexspalten erkennen (Price/Gross/Net x USD/EUR); Spalten wie *_Return, fx_* werden nicht abgerufen:
  index_cols <- list()
  for(v in names(config$variants)) for(cur in names(config$currencies)){
    col <- find_column(setdiff(names(data), date_col), v, cur)
    if(!is.na(col)) index_cols[[col]] <- c(type = config$variants[[v]], currency = config$currencies[[cur]])
  }
  if(length(index_cols) == 0){cat("  Keine Indexspalten erkannt -> übersprungen\n"); next}

  #---> Abruf und Skalierung je Spalte:
  results <- lapply(names(index_cols), function(col){
    update_column(data, date_col, col, code, index_cols[[col]][["type"]], index_cols[[col]][["currency"]])})
  file_log <- bind_rows(lapply(results, `[[`, "log")) %>% mutate(file = basename(file), .before = 1)
  print(file_log %>% select(column, last_date, anchor, overlap_n, max_return_diff, scale, new_rows, status),
        width = Inf)
  update_log[[file]] <- file_log

  #---> Neue Zeilen zusammenführen und anhängen (vorhandene Werte bleiben unverändert):
  new_rows <- lapply(results, `[[`, "new") %>% Filter(Negate(is.null), .)
  if(length(new_rows) > 0){
    new_rows <- Reduce(function(x, y) full_join(x, y, by = "date"), new_rows) %>%
      rename(!!date_col := date)
    updated <- data %>%
      full_join(new_rows, by = date_col, suffix = c("", ".new")) %>%
      arrange(.data[[date_col]])
    for(col in names(index_cols)){
      new_col <- paste0(col, ".new")
      if(new_col %in% names(updated)){
        updated[[col]] <- ifelse(is.na(updated[[col]]), updated[[new_col]], updated[[col]])
        updated[[new_col]] <- NULL}
    }

    #---> Zusatzspalten aus dem Backcast-Skript, falls vorhanden, für die neuen Zeilen nachziehen:
    for(col in names(index_cols)){
      ret_col <- paste0(col, "_Return")
      if(ret_col %in% names(updated)) updated[[ret_col]] <- valid_return(updated[[col]])
    }
    price_usd <- find_column(names(index_cols), "price", "usd")
    price_eur <- find_column(names(index_cols), "price", "eur")
    if("fx_implied" %in% names(updated) && !is.na(price_usd) && !is.na(price_eur)){
      added <- updated[[date_col]] > max(data[[date_col]])
      updated$fx_implied[added] <- updated[[price_usd]][added] / updated[[price_eur]][added]
    }
  } else {
    updated <- data
  }

  #---> Kontrolle: Bisherige Werte dürfen nicht verändert worden sein:
  check <- updated[match(data[[date_col]], updated[[date_col]]), names(index_cols), drop = FALSE]
  stopifnot(isTRUE(all.equal(as.data.frame(check), as.data.frame(data[, names(index_cols), drop = FALSE]),
                             check.attributes = FALSE)))

  #---> Speichern im Eingabeformat:
  out_file <- file.path(config$output_dir, basename(file))
  if(grepl("\\.csv$", file, ignore.case = TRUE)){
    write.csv(updated, out_file, row.names = FALSE)
  } else {
    write.xlsx(updated, out_file, overwrite = TRUE)
  }
  cat("  Gespeichert:", out_file, "| Zeilen:", nrow(data), "->", nrow(updated),
      "| letzter Tag:", format(max(updated[[date_col]])), "\n")
}


#-----------------------------------------------------------------------------------------------------------------------
# Protokoll
#-----------------------------------------------------------------------------------------------------------------------
update_log <- bind_rows(update_log)
write.csv(update_log, file.path(config$output_dir, "Update Log.csv"), row.names = FALSE)

update_log %>%
  count(status) %>%
  print()

update_log %>%
  filter(status != "ok") %>%
  select(file, column, status) %>%
  print(n = Inf)

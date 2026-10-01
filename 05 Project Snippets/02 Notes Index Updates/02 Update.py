# -----------------------------------------------------------------------------------------------------------------------
# Fortschreibung der Backcast-Datensätze mit aktuellen MSCI-Indexwerten
# Python-Fassung von "02 Update.R" mit bitgleichen Ergebnissen
# -----------------------------------------------------------------------------------------------------------------------
# Ablauf je Datei und je Indexspalte:
# 1. Letzten gültigen Wert der Spalte im Datensatz ermitteln (Datum L, Wert V).
# 2. Aktuelle Werte über die MSCI-Schnittstelle abrufen, ab L - overlap_days bis heute.
# 3. Anker = letzter Tag <= L, an dem Datensatz und Abruf beide einen Wert haben.
# 4. Neue Werte auf den Anker skalieren:  neu_angepasst[t] = neu[t] * Datensatz[Anker] / neu[Anker]
# 5. Kontrolle im Überlappungszeitraum: Die Tagesrenditen von Datensatz und Abruf müssen übereinstimmen.
#    Weichen sie ab (falscher Code, falsche Variante/Währung), wird die Spalte NICHT fortgeschrieben.
# 6. Nur Tage > L werden angehängt; vorhandene Werte werden nie verändert.
#
# Arbeitet direkt auf den Backcast-Ergebnissen in "02 Backcast Data" und schreibt in dieselben Dateien zurück.
# Bitgleichheit mit R: Zahlen werden wie R read.csv eingelesen (R_strtod) und wie write.csv ausgegeben.
# Voraussetzungen: Python >= 3.9, numpy, pandas, requests, mpmath (kein R nötig).
# -----------------------------------------------------------------------------------------------------------------------
import csv
import glob
import math
import os
import re
import time
from datetime import date, timedelta

import mpmath
import numpy as np
import pandas as pd
import requests

NA = float("nan")


# -----------------------------------------------------------------------------------------------------------------------
# Konfiguration
# -----------------------------------------------------------------------------------------------------------------------
config = {
    "input_files":   sorted(glob.glob("02 Backcast Data/* Backcast.csv")),
    "output_dir":    "02 Backcast Data",   # Backcast-Dateien werden direkt fortgeschrieben (überschrieben)
    "stopp_date":    date.today(),
    "overlap_days":  30,                   # Kalendertage vor L, die zur Kontrolle mit abgerufen werden
    "tolerance":     1e-4,                 # Max. zulässige Abweichung der Tagesrenditen im Überlappungszeitraum
    "pause_seconds": 1,                    # Pause zwischen den Abrufen
    # MSCI-Indexcodes. Schlüssel = Dateiname ohne "MSCI " / " Backcast" / " Updated" und Endung.
    "index_codes": {
        "USA":           "984000",
        "World":         "990100",
        "ACWI":          "892400",
        "EAFE":          "990300",
        "Europe":        "990500",
        "North America": "990200",
        "Pacific":       "990800"},
    "variants":   {"price": "STRD", "gross": "GRTR", "net": "NETR"},
    "currencies": {"usd": "USD", "eur": "EUR"},
}


# -----------------------------------------------------------------------------------------------------------------------
# R-kompatibles Einlesen und Schreiben von CSV-Dateien (für Bitgleichheit)
# -----------------------------------------------------------------------------------------------------------------------

# Mantissenbreite von "long double" in R auf dieser Plattform (x86-64: 64 Bit, Linux-ARM: 113 Bit,
# macOS-ARM: long double = double, 53 Bit). R rechnet cumprod(), Zahlen-Einlesen und -Formatierung damit.
import platform as _platform
import sys as _sys
_machine = _platform.machine().lower()
if _machine in ("x86_64", "amd64", "i386", "i686", "x86"):
    LD_BITS = 64
elif _sys.platform == "darwin":
    LD_BITS = 53
elif _machine in ("aarch64", "arm64"):
    LD_BITS = 113
else:
    LD_BITS = 64
KP_MAX = 27 if LD_BITS > 53 else 22
_TBL = [mpmath.mpf(10) ** k for k in range(28)]


def isna(x):
    return x is None or (isinstance(x, float) and math.isnan(x))


def r_strtod(s):
    """R_strtod: Ziffern in long double akkumulieren, mit 10^k (Binärpotenzierung) in long double skalieren."""
    t = str(s).strip()
    if t in ("", "NA", "NaN"):
        return NA
    if t in ("Inf", "inf", "+Inf"):
        return float("inf")
    if t in ("-Inf", "-inf"):
        return float("-inf")
    sign, i = 1, 0
    if t[0] in "+-":
        sign, i = (-1 if t[0] == "-" else 1), 1
    digits, expn = [], 0
    while i < len(t) and t[i].isdigit():
        digits.append(t[i]); i += 1
    if i < len(t) and t[i] == ".":
        i += 1
        while i < len(t) and t[i].isdigit():
            digits.append(t[i]); i += 1; expn -= 1
    if not digits:
        raise ValueError(t)
    if i < len(t) and t[i] in "eE":
        i += 1
        esign = 1
        if i < len(t) and t[i] in "+-":
            esign, i = (-1 if t[i] == "-" else 1), i + 1
        e = 0
        while i < len(t) and t[i].isdigit():
            e = 10 * e + int(t[i]); i += 1
        expn += esign * e
    if i != len(t):
        raise ValueError(t)
    with mpmath.workprec(LD_BITS):
        ans = mpmath.mpf(0)
        for d in digits:
            ans = 10 * ans + int(d)
        if expn != 0:
            n, fac, p10 = abs(expn), mpmath.mpf(1), mpmath.mpf(10)
            while n:
                if n & 1:
                    fac = fac * p10
                n >>= 1
                p10 = p10 * p10
            ans = ans / fac if expn < 0 else ans * fac
        return sign * float(ans)


def _scientific(r, R=15):
    """R format.c scientific() (long-double-Pfad, KP_MAX = 27)."""
    kp = int(math.floor(math.log10(r))) - R + 1
    with mpmath.workprec(LD_BITS):
        rp = mpmath.mpf(r)
        if abs(kp) <= KP_MAX:
            if kp > 0:
                rp = rp / _TBL[kp]
            elif kp < 0:
                rp = rp * _TBL[-kp]
        else:
            rp = rp / mpmath.power(10, kp)
        if rp < _TBL[R - 1]:
            rp = rp * 10
            kp -= 1
        alpha = float(mpmath.nint(rp))
    nsig = R
    for _ in range(R):
        alpha /= 10.0
        if alpha == math.floor(alpha):
            nsig -= 1
        else:
            break
    if nsig == 0:
        nsig, kp = 1, kp + 1
    kpower = kp + R - 1
    rgt = min(max(R - kpower, 0), KP_MAX)
    fuzz = 0.5 / float(_TBL[rgt])
    with mpmath.workprec(LD_BITS):
        widens = 0 < kpower <= KP_MAX and mpmath.mpf(r) < _TBL[kpower] - mpmath.mpf(fuzz)
    return kpower, nsig, bool(widens)


def r_format(x):
    """Zahlenformat wie R write.csv (15 signifikante Stellen, scipen = 0)."""
    if isna(x):
        return "NA"
    if math.isinf(x):
        return "Inf" if x > 0 else "-Inf"
    if x == 0.0:
        return "0"
    neg = 1 if x < 0 else 0
    kpower, nsig, widens = _scientific(abs(x))
    left = kpower + 1 - (1 if widens else 0)
    rgt = max(0, nsig - left)
    w_fixed = neg + (1 if left <= 0 else left) + rgt + (1 if rgt else 0)
    e = 2 if abs(kpower) >= 100 else 1
    d = nsig - 1
    if w_fixed <= neg + (1 if d > 0 else 0) + d + 4 + e:
        return "%.*f" % (rgt, x)
    m, ex = ("%.*e" % (d, x)).split("e")
    return "%se%s%0*d" % (m, ex[0], e + 1, abs(int(ex)))


_LOGICAL = {"TRUE": True, "FALSE": False, "T": True, "F": False, "true": True, "false": False,
            "True": True, "False": False}


def r_read_csv(path):
    """read.csv(path, check.names = FALSE) mit R-Typerkennung: logisch, numerisch (R_strtod), sonst Text.
    Gibt DataFrame und die erkannten Spaltentypen zurück."""
    with open(path, newline="", encoding="utf-8") as f:
        rows = list(csv.reader(f))
    header, rows = rows[0], rows[1:]
    df, kinds = {}, {}
    for j, name in enumerate(header):
        raw = [r[j] if j < len(r) else "" for r in rows]
        values = [None if v == "NA" else v for v in raw]
        present = [v for v in values if v is not None]
        if all(v in _LOGICAL for v in present):
            df[name] = pd.array([None if v is None else _LOGICAL[v] for v in values], dtype="boolean")
            kinds[name] = "bool"
            continue
        try:
            nums = [NA if v is None or v == "" else r_strtod(v) for v in values]
            df[name] = np.array(nums, dtype=float)
            kinds[name] = "num"
        except ValueError:
            df[name] = pd.Series([None if v is None else v for v in values], dtype=object)
            kinds[name] = "str"
    return pd.DataFrame(df), kinds


def r_write_csv(df, path, kinds):
    """write.csv(df, path, row.names = FALSE) wie in R (Zeilenende des Betriebssystems wie R)."""
    def cell(v, kind):
        if kind == "date":
            return "NA" if pd.isna(v) else pd.Timestamp(v).strftime("%Y-%m-%d")
        if kind == "bool":
            return "NA" if pd.isna(v) else ("TRUE" if v else "FALSE")
        if kind in ("num", "int"):
            return "NA" if pd.isna(v) else r_format(float(v))
        return "NA" if pd.isna(v) else '"' + str(v).replace('"', '""') + '"'

    with open(path, "w", encoding="utf-8") as f:
        f.write(",".join('"' + str(c).replace('"', '""') + '"' for c in df.columns) + "\n")
        columns = [(df[c].tolist(), kinds[c]) for c in df.columns]
        for i in range(len(df)):
            f.write(",".join(cell(vals[i], kind) for vals, kind in columns) + "\n")


# -----------------------------------------------------------------------------------------------------------------------
# Hilfsfunktionen
# -----------------------------------------------------------------------------------------------------------------------
def scraping_index(code, type_, currency, start, stopp):
    """Abruf der Marktindizes (gibt bei Fehlern None zurück)."""
    url = ("https://app2.msci.com/products/service/index/indexmaster/getLevelDataForGraph?currency_symbol="
           + currency + "&index_variant=" + type_ + "&start_date=" + start + "&end_date=" + stopp
           + "&data_frequency=DAILY&index_codes=" + code)
    try:
        response = requests.get(url, timeout=60)
    except requests.RequestException:
        response = None
    if response is None or response.status_code != 200:
        print("  Fehler beim Abrufen: %s %s %s" % (code, type_, currency))
        return None
    try:
        levels = response.json()["indexes"]["INDEX_LEVELS"]
    except (ValueError, KeyError, TypeError):
        return None
    if not levels:
        return None
    online = pd.DataFrame({"date": pd.to_datetime([str(l["calc_date"]) for l in levels], format="%Y%m%d", errors="coerce"),
                           "value": [NA if l.get("level_eod") is None else float(l["level_eod"]) for l in levels]})
    online = online.loc[online["date"].notna() & online["value"].notna()]
    return online.sort_values("date", kind="stable").reset_index(drop=True)


def find_column(names, variant, currency):
    """Spaltenerkennung über Namensbestandteile (wie im Backcast-Skript)."""
    variants = {"price": ["price", "pr", "strd"], "gross": ["gross", "gr", "grtr", "gdtr"],
                "net": ["net", "nr", "netr", "ndtr"]}
    currencies = {"usd": ["usd", "dollar"], "eur": ["eur", "euro"]}
    hit = []
    for n in names:
        tokens = re.split(r"[_. -]+", n.lower())
        if any(t in variants[variant] for t in tokens) and any(t in currencies[currency] for t in tokens) \
                and "return" not in tokens:
            hit.append(n)
    return hit[0] if len(hit) == 1 else None


def index_key(file):
    """Indexschlüssel aus dem Dateinamen."""
    key = os.path.splitext(os.path.basename(file))[0]
    key = re.sub(r"^MSCI[ _]+", "", key)
    key = re.sub(r"[ _]+(Backcast|Updated)$", "", key)
    return key.strip()


def valid_return(x):
    """Renditefaktor x/lag(x) über die gültigen Beobachtungen."""
    x = np.asarray(x, dtype=float)
    r = np.full(len(x), NA)
    i = np.flatnonzero(~np.isnan(x))
    if len(i) > 1:
        r[i[1:]] = x[i[1:]] / x[i[:-1]]
    return r


def read_index_file(file):
    """Einlesen (csv), Datumsspalte erkennen."""
    raw, kinds = r_read_csv(file)
    date_col = next((c for c in raw.columns if c.lower() in ("date", "datum")), raw.columns[0])
    raw[date_col] = pd.to_datetime(raw[date_col], errors="coerce")
    kinds[date_col] = "date"
    raw = raw.loc[raw[date_col].notna()].sort_values(date_col, kind="stable").reset_index(drop=True)
    return raw, date_col, kinds


def update_column(data, date_col, col, code, type_, currency):
    """Fortschreibung einer Spalte; gibt die angepassten neuen Werte (Datum > L) und ein Protokoll zurück."""
    valid = data[col].notna().values
    last_date = data.loc[valid, date_col].max()
    log = {"column": col, "type": type_, "currency": currency, "last_date": last_date, "anchor": pd.NaT,
           "overlap_n": NA, "max_return_diff": NA, "scale": NA, "new_rows": 0, "new_last_date": pd.NaT, "status": ""}

    if last_date.date() >= config["stopp_date"]:
        log["status"] = "aktuell"
        return None, log

    online = scraping_index(code, type_, currency,
                            start=(last_date - timedelta(days=config["overlap_days"])).strftime("%Y%m%d"),
                            stopp=config["stopp_date"].strftime("%Y%m%d"))
    time.sleep(config["pause_seconds"])
    if online is None:
        log["status"] = "Abruf fehlgeschlagen"
        return None, log

    #---> Überlappung und Anker:
    local = pd.DataFrame({"date": data.loc[valid, date_col].values, "local": data.loc[valid, col].values})
    local = local.loc[local["date"] >= last_date - timedelta(days=config["overlap_days"])]
    overlap = local.merge(online, on="date", how="inner")
    overlap["diff"] = valid_return(overlap["local"].values) - valid_return(overlap["value"].values)
    if len(overlap) == 0:
        log["status"] = "keine Überlappung"
        return None, log

    anchor = overlap["date"].max()
    at = overlap["date"] == anchor
    scale = overlap.loc[at, "local"].values[0] / overlap.loc[at, "value"].values[0]
    diffs = np.abs(overlap["diff"].values)
    diffs = diffs[~np.isnan(diffs)]
    max_diff = diffs.max() if len(diffs) else -math.inf
    log.update(anchor=anchor, overlap_n=len(overlap), scale=scale,
               max_return_diff=max_diff if math.isfinite(max_diff) else NA)

    if len(overlap) < 2:
        log["status"] = "WARNUNG: nur 1 gemeinsamer Tag, keine Renditekontrolle möglich"
    elif max_diff > config["tolerance"]:
        log["status"] = "ABGELEHNT: Renditen weichen ab (Code/Variante/Währung prüfen)"
        return None, log
    else:
        log["status"] = "ok"

    new = online.loc[online["date"] > last_date, ["date", "value"]].copy()
    new[col] = new["value"].values * scale
    new = new[["date", col]]
    log["new_rows"] = len(new)
    if len(new) > 0:
        log["new_last_date"] = new["date"].max()
    return new, log


pd.set_option("display.width", 250)
pd.set_option("display.max_columns", 20)


# -----------------------------------------------------------------------------------------------------------------------
# Fortschreibung aller Dateien
# -----------------------------------------------------------------------------------------------------------------------
os.makedirs(config["output_dir"], exist_ok=True)
update_log = []

for file in config["input_files"]:
    key = index_key(file)
    code = config["index_codes"].get(key)
    print("\n==>", os.path.basename(file), "| Index:", key, "| Code:", code if code else "-")
    if code is None:
        print("  Kein Indexcode hinterlegt -> übersprungen (config['index_codes'] ergänzen)")
        continue

    data, date_col, kinds = read_index_file(file)

    #---> Indexspalten erkennen (Price/Gross/Net x USD/EUR); Spalten wie *_Return, fx_* werden nicht abgerufen:
    index_cols = {}
    for v in config["variants"]:
        for cur in config["currencies"]:
            col = find_column([c for c in data.columns if c != date_col], v, cur)
            if col is not None:
                index_cols[col] = (config["variants"][v], config["currencies"][cur])
    if not index_cols:
        print("  Keine Indexspalten erkannt -> übersprungen")
        continue

    #---> Abruf und Skalierung je Spalte:
    results = [update_column(data, date_col, col, code, t, c) for col, (t, c) in index_cols.items()]
    file_log = pd.DataFrame([log for _, log in results])
    file_log.insert(0, "file", os.path.basename(file))
    print(file_log[["column", "last_date", "anchor", "overlap_n", "max_return_diff", "scale", "new_rows", "status"]]
          .to_string(index=False))
    update_log.append(file_log)

    #---> Neue Zeilen zusammenführen und anhängen (vorhandene Werte bleiben unverändert):
    new_parts = [new for new, _ in results if new is not None]
    if new_parts:
        new_rows = new_parts[0]
        for part in new_parts[1:]:
            new_rows = new_rows.merge(part, on="date", how="outer")
        new_rows = new_rows.rename(columns={"date": date_col})
        updated = data.merge(new_rows, on=date_col, how="outer", suffixes=("", ".new"))
        updated = updated.sort_values(date_col, kind="stable").reset_index(drop=True)
        for col in index_cols:
            new_col = col + ".new"
            if new_col in updated.columns:
                updated[col] = np.where(updated[col].isna().values, updated[new_col].values, updated[col].values)
                updated = updated.drop(columns=new_col)

        #---> Zusatzspalten aus dem Backcast-Skript, falls vorhanden, für die neuen Zeilen nachziehen:
        for col in index_cols:
            ret_col = col + "_Return"
            if ret_col in updated.columns:
                updated[ret_col] = valid_return(updated[col].values)
        price_usd = find_column(list(index_cols), "price", "usd")
        price_eur = find_column(list(index_cols), "price", "eur")
        if "fx_implied" in updated.columns and price_usd is not None and price_eur is not None:
            added = (updated[date_col] > data[date_col].max()).values
            fx = updated["fx_implied"].values.astype(float)
            fx[added] = updated[price_usd].values[added] / updated[price_eur].values[added]
            updated["fx_implied"] = fx
    else:
        updated = data

    #---> Kontrolle: Bisherige Werte dürfen nicht verändert worden sein:
    check = updated.set_index(date_col).loc[data[date_col], list(index_cols)].values
    assert np.array_equal(check, data[list(index_cols)].values, equal_nan=True)

    #---> Speichern im Eingabeformat:
    out_file = os.path.join(config["output_dir"], os.path.basename(file))
    r_write_csv(updated, out_file, kinds)
    print("  Gespeichert:", out_file, "| Zeilen:", len(data), "->", len(updated),
          "| letzter Tag:", updated[date_col].max().date())


# -----------------------------------------------------------------------------------------------------------------------
# Protokoll
# -----------------------------------------------------------------------------------------------------------------------
if update_log:
    update_log = pd.concat(update_log, ignore_index=True)
    log_kinds = {"file": "str", "column": "str", "type": "str", "currency": "str", "last_date": "date",
                 "anchor": "date", "overlap_n": "int", "max_return_diff": "num", "scale": "num",
                 "new_rows": "int", "new_last_date": "date", "status": "str"}
    r_write_csv(update_log, os.path.join(config["output_dir"], "Update Log.csv"), log_kinds)

    print(update_log.groupby("status").size().rename("n").reset_index().to_string(index=False))
    print(update_log.loc[update_log["status"] != "ok", ["file", "column", "status"]].to_string(index=False))

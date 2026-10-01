# -----------------------------------------------------------------------------------------------------------------------
# Backcasting von USD- und EUR-Indexvarianten (Price Return, Gross Total Return und Net Total Return)
# Python-Fassung von "01 Backcast.R" mit bitgleichen Ergebnissen
# -----------------------------------------------------------------------------------------------------------------------
# Ablauf:
# 1. Einlesen und Erkennung von Spalten und erster gültiger Werte je Indexreihe
# 2. USD Gross / Net: GAM  Return ~ s(USD Price Return)          -> Rückrechnung vor dem ersten gültigen Wert
# 3. Umrechnungskurs: USD Price / EUR Price (implizit, USD je EUR), Vergleich mit offiziellem Kurs,
#                     GAM  impliziter Kurs ~ s(offizieller Kurs) -> Rückrechnung vor dem ersten gültigen Wert
# 4. EUR Price:       USD Price / impliziter Kurs                -> Rückrechnung vor dem ersten gültigen Wert
# 5. EUR Gross / Net: GAM  Return ~ s(EUR Price Return)          -> Rückrechnung vor dem ersten gültigen Wert
#
# Grundsätze: siehe R-Skript (keine Interpolation, Renditefaktoren über gültige Beobachtungen, Rückwärtsverkettung
# ab dem Anker, Startdaten aus den Daten, Renditen je Handelstag bei gemischten Frequenzen, optionale Kursverlängerung).
#
# Bitgleichheit mit R:
# - Die GAM-Schätzungen laufen über rpy2 in R/mgcv (identisches Modell, identische Prognosen).
# - Alle übrigen Rechenschritte bilden R exakt nach: round() (R >= 4.0), cumprod() in long double, x^y (R_pow),
#   Zahlen-Einlesen aus CSV (R_strtod) und Zahlenformat von write.csv (15 signifikante Stellen).
# - Voraussetzungen: Python >= 3.9, numpy, pandas, openpyxl, mpmath, rpy2, plotly; R mit Paket mgcv.
# -----------------------------------------------------------------------------------------------------------------------
import math
import os
import re
from datetime import timedelta

import mpmath
import numpy as np
import pandas as pd
import rpy2.robjects as ro
from rpy2.robjects.packages import importr

importr("mgcv")
NA = float("nan")


# -----------------------------------------------------------------------------------------------------------------------
# Konfiguration
# -----------------------------------------------------------------------------------------------------------------------
config = {
    "index_file": "01 Input Data/MSCI World.xlsx",               # .xlsx oder .csv, eine Datumsspalte + sechs Indexspalten
    "fx_file":    "01 Input Data/EuroStat Exchange Rates.csv",   # Eurostat ert_bil_eur_d (USD je EUR bzw. ECU)
    "fx_filter":  {"column": "currency", "value": "US dollar"},
    "fx_date":    "TIME_PERIOD",
    "fx_value":   "OBS_VALUE",
    "gam_k":      10,
    # Optionale Verlängerung des offiziellen Kurses vor dessen ersten Wert über Proxy-Kursreihen (None = keine).
    # Je Proxy: source (Datei oder URL, CSV), date/value (Spaltenname oder Spaltennummer ab 1 wie in R),
    # invert (True, wenn Fremdwährung je USD notiert, z.B. DEM je USD).
    # Beispiel (FRED, Tageswerte ab 1971-01-04):
    # "fx_extension": {
    #     "DEM": {"source": "https://fred.stlouisfed.org/graph/fredgraph.csv?id=DEXGEUS", "date": 1, "value": 2, "invert": True},
    #     "GBP": {"source": "https://fred.stlouisfed.org/graph/fredgraph.csv?id=DEXUSUK", "date": 1, "value": 2, "invert": False}},
    "fx_extension": None,
    # Spaltennamen der Indexdatei. None = automatische Erkennung über die Namensbestandteile
    "columns": {"price_usd": None, "gross_usd": None, "net_usd": None,
                "price_eur": None, "gross_eur": None, "net_eur": None},
    "show_plots": True,
}
config["output_file"] = ("02 Backcast Data/" + os.path.splitext(os.path.basename(config["index_file"]))[0]
                         + " Backcast.csv")


# -----------------------------------------------------------------------------------------------------------------------
# R-kompatible Grundfunktionen (für Bitgleichheit)
# -----------------------------------------------------------------------------------------------------------------------
LOG10_2 = 0.301029995663981195213738894724493027

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


def r_round(x, digits):
    """R >= 4.0.0 round(x, digits) (src/nmath/fround.c), für digits > 0."""
    if isna(x) or not math.isfinite(x) or x == 0.0:
        return x
    dig = int(math.floor(digits + 0.5))
    sgn = 1.0
    if x < 0.0:
        sgn, x = -1.0, -x
    if LOG10_2 * (0.5 + (math.frexp(x)[1] - 1)) + dig > 15:
        return sgn * x
    p10 = 10.0 ** dig
    x10 = p10 * x
    i10 = math.floor(x10)
    xd = i10 / p10
    xu = math.ceil(x10) / p10
    du, dd = xu - x, x - xd
    return sgn * (xu if (du < dd or (du == dd and math.fmod(i10, 2.0) == 1)) else xd)


def r_pow(x, y):
    """R x^y (R_pow in arithmetic.c). R nutzt unter Windows (64 Bit) powl() in long double, sonst pow() der
    System-Mathebibliothek – Python greift unter Linux/macOS auf dieselbe Bibliothek zu."""
    if y == 2.0:
        return x * x
    if x == 1.0 or y == 0.0:
        return 1.0
    if isna(x) or isna(y):
        return NA
    if y == 1.0:
        return x
    if os.name == "nt":
        with mpmath.workprec(200):
            v = mpmath.power(mpmath.mpf(x), mpmath.mpf(y))
        with mpmath.workprec(LD_BITS):
            v = +v
        return float(v)
    return math.pow(x, y)


def r_cumprod(values):
    """R cumprod(): Akkumulation in long double (64-Bit-Mantisse), Ausgabe als double."""
    out = []
    with mpmath.workprec(LD_BITS):
        p = mpmath.mpf(1)
        for v in values:
            p = mpmath.mpf("nan") if isna(v) else p * mpmath.mpf(v)
            out.append(float(p))
    return np.array(out)


def r_strtod(s):
    """R_strtod: Ziffern in long double akkumulieren, mit 10^k (Binärpotenzierung) in long double skalieren."""
    if s is None:
        return NA
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
        return NA
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
        return NA
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


def r_write_csv(df, path):
    """write.csv(df, path, row.names = FALSE) wie in R (Zeilenende des Betriebssystems wie R)."""
    def cell(v, kind):
        if kind == "date":
            return "NA" if pd.isna(v) else pd.Timestamp(v).strftime("%Y-%m-%d")
        if kind == "bool":
            return "NA" if pd.isna(v) else ("TRUE" if v else "FALSE")
        if kind == "num":
            return r_format(float(v))
        return "NA" if pd.isna(v) else '"' + str(v).replace('"', '""') + '"'

    kinds = {}
    for c in df.columns:
        s = df[c]
        if pd.api.types.is_datetime64_any_dtype(s):
            kinds[c] = "date"
        elif pd.api.types.is_bool_dtype(s) or s.dropna().map(lambda v: isinstance(v, (bool, np.bool_))).all() and s.notna().any():
            kinds[c] = "bool"
        elif pd.api.types.is_numeric_dtype(s):
            kinds[c] = "num"
        else:
            kinds[c] = "str"
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        f.write(",".join('"' + str(c).replace('"', '""') + '"' for c in df.columns) + "\n")
        cols = [(df[c].tolist(), kinds[c]) for c in df.columns]
        for i in range(len(df)):
            f.write(",".join(cell(vals[i], kind) for vals, kind in cols) + "\n")


# -----------------------------------------------------------------------------------------------------------------------
# R-Anbindung für die GAM-Schätzungen
# -----------------------------------------------------------------------------------------------------------------------
ro.r("""
.py_gam_fit <- function(formula, data) {
  data <- as.data.frame(lapply(data, function(v) { v[is.nan(v)] <- NA; v }), check.names = FALSE)
  gam(as.formula(formula), data = data, method = "REML")
}
.py_gam_predict <- function(model, newdata) {
  newdata <- as.data.frame(lapply(newdata, function(v) { v[is.nan(v)] <- NA; v }), check.names = FALSE)
  as.numeric(predict(model, newdata = newdata))
}
""")


def _r_frame(columns):
    return ro.vectors.ListVector({k: ro.vectors.FloatVector([float(v) for v in vals]) for k, vals in columns.items()})


def gam_fit(formula, columns):
    return ro.r[".py_gam_fit"](formula, _r_frame(columns))


def gam_predict(model, columns):
    return np.array(ro.r[".py_gam_predict"](model, _r_frame(columns)), dtype=float)


def gam_summary(model):
    ro.r["print"](ro.r["summary"](model))


# -----------------------------------------------------------------------------------------------------------------------
# Hilfsfunktionen
# -----------------------------------------------------------------------------------------------------------------------
def find_column(names, variant, currency):
    """Spaltenerkennung über Namensbestandteile."""
    variants = {"price": ["price", "pr", "strd"], "gross": ["gross", "gr", "grtr", "gdtr"],
                "net": ["net", "nr", "netr", "ndtr"]}
    currencies = {"usd": ["usd", "dollar"], "eur": ["eur", "euro"]}
    hit = [n for n in names
           if any(t in variants[variant] for t in re.split(r"[_. -]+", n.lower()))
           and any(t in currencies[currency] for t in re.split(r"[_. -]+", n.lower()))]
    if len(hit) != 1:
        raise ValueError("Spalte für '%s %s' nicht eindeutig erkannt (Treffer: %s). Bitte in config['columns'] eintragen."
                         % (variant, currency.upper(), ", ".join(hit) if hit else "keine"))
    return hit[0]


def first_valid(data, col):
    d = data.loc[data[col].notna(), "date"]
    if len(d) == 0:
        raise ValueError("Reihe '%s' enthält keine gültigen Werte" % col)
    return d.min()


def first_common(data, cols):
    d = data.loc[data[cols].notna().all(axis=1), "date"]
    if len(d) == 0:
        raise ValueError("Keine gemeinsamen Beobachtungen für: " + ", ".join(cols))
    return d.min()


def valid_return(x):
    """Renditefaktor x/lag(x) über die gültigen Beobachtungen."""
    x = np.asarray(x, dtype=float)
    r = np.full(len(x), NA)
    i = np.flatnonzero(~np.isnan(x))
    if len(i) > 1:
        r[i[1:]] = x[i[1:]] / x[i[:-1]]
    return r


def trading_days(d):
    """Anzahl Handelstage (Mo-Fr) im Intervall (d[i-1], d[i]]."""
    d = pd.to_datetime(pd.Series(d)).values.astype("datetime64[D]")
    if len(d) < 2:
        return np.full(len(d), NA)
    calendar = np.arange(d.min(), d.max() + np.timedelta64(1, "D"), dtype="datetime64[D]")
    weekdays = np.cumsum(pd.DatetimeIndex(calendar).dayofweek.values <= 4)
    w = weekdays[(d - d.min()).astype(int)]
    return np.concatenate([[NA], np.maximum(np.diff(w), 1).astype(float)])


def pow_vec(x, y):
    return np.array([r_pow(float(a), float(b)) for a, b in zip(x, y)])


def gam_backcast(data, target, driver, k=10):
    """GAM-Backcast einer Indexreihe (Target) über eine Erklärungsreihe (Driver)."""
    data = data.copy()
    anchor = first_common(data, [target, driver])

    est = data.loc[data[target].notna() & data[driver].notna()]
    days = trading_days(est["date"])
    inv = 1.0 / days
    y = pow_vec(valid_return(est[target].values), inv)
    x = pow_vec(valid_return(est[driver].values), inv)
    model = gam_fit("y ~ s(x, bs = 'cr', k = %s)" % repr(float(k)), {"y": y, "x": x})

    bc = data.loc[(data["date"] <= anchor) & data[driver].notna()]
    n = len(bc)
    bc_days = trading_days(bc["date"])
    if n > 1:
        bc_x = pow_vec(valid_return(bc[driver].values), 1.0 / bc_days)
        ret = pow_vec(gam_predict(model, {"x": bc_x}), bc_days)
        anchor_value = data.loc[data["date"] == anchor, target].values
        level = anchor_value[0] / r_cumprod(ret[1:][::-1])[::-1]
        idx = data.index.get_indexer(bc.index[:-1])
        current = data[target].values[idx]
        data.loc[data.index[idx], target] = np.where(np.isnan(current), level, current)

    n_est = int(np.sum(~np.isnan(y) & ~np.isnan(x)))
    print("%-24s Anker: %s | Schätzung: %d Returns | zurückgerechnet: %d Werte (%s bis %s), davon %d mehrtägig"
          % (target, anchor.date(), n_est, max(n - 1, 0),
             bc["date"].min().date() if n > 1 else "-", bc["date"].iloc[n - 2].date() if n > 1 else "-",
             int(np.nansum(bc_days > 1))))
    return data, model, anchor


def compare_series(model, actual):
    model, actual = np.asarray(model, float), np.asarray(actual, float)
    e = model - actual
    ok = ~np.isnan(model) & ~np.isnan(actual)
    return {"n": int(np.sum(~np.isnan(e))), "mean_error": np.nanmean(e), "mean_absolute_error": np.nanmean(np.abs(e)),
            "root_mean_squared_error": math.sqrt(np.nanmean(e ** 2)), "max_absolute_error": np.nanmax(np.abs(e)),
            "correlation": np.corrcoef(model[ok], actual[ok])[0, 1]}


def read_csv_like_r(source, **kwargs):
    """read.csv: alles als Text einlesen, Zahlen wie R (R_strtod) umwandeln."""
    df = pd.read_csv(source, dtype=str, keep_default_na=False, **kwargs)
    return df


def to_num(series):
    return pd.Series([r_strtod(v) for v in series], index=series.index, dtype=float)


def col_ref(df, ref):
    """Spalte über Namen oder Nummer (ab 1 wie in R)."""
    return df.iloc[:, ref - 1] if isinstance(ref, int) else df[ref]


pd.set_option("display.width", 250)
pd.set_option("display.max_columns", 20)


# -----------------------------------------------------------------------------------------------------------------------
# 1. Einlesen und Spaltenerkennung
# -----------------------------------------------------------------------------------------------------------------------
if config["index_file"].lower().endswith(".csv"):
    raw = read_csv_like_r(config["index_file"])
    for c in raw.columns[1:]:
        raw[c] = to_num(raw[c])
else:
    raw = pd.read_excel(config["index_file"], engine="openpyxl")

date_col = next((c for c in raw.columns if str(c).lower() in ("date", "datum")), raw.columns[0])
index_data = raw.rename(columns={date_col: "date"})
if pd.api.types.is_numeric_dtype(index_data["date"]):
    index_data["date"] = pd.Timestamp("1899-12-30") + pd.to_timedelta(index_data["date"], unit="D")
index_data["date"] = pd.to_datetime(index_data["date"]).dt.normalize()
index_data = index_data.loc[index_data["date"].notna()].sort_values("date", kind="stable").reset_index(drop=True)

cols = dict(config["columns"])
for v in ("price", "gross", "net"):
    for cur in ("usd", "eur"):
        key = v + "_" + cur
        if cols.get(key) is None:
            cols[key] = find_column([c for c in index_data.columns if c != "date"], v, cur)
# Reihenfolge wie in R (Reihenfolge der Einträge in config$columns)
cols = {k: cols[k] for k in ("price_usd", "gross_usd", "net_usd", "price_eur", "gross_eur", "net_eur")}
for c in cols.values():
    index_data[c] = pd.to_numeric(index_data[c], errors="coerce").astype(float)

start_dates = {k: first_valid(index_data, c) for k, c in cols.items()}
print(pd.DataFrame({"variant": list(cols), "column": list(cols.values()),
                    "first_valid": [start_dates[k].date() for k in cols],
                    "observations": [int(index_data[c].notna().sum()) for c in cols.values()]}))


# -----------------------------------------------------------------------------------------------------------------------
# 2. Backcast der USD Gross und Net Total Return Indizes (GAM auf USD Price Return)
# -----------------------------------------------------------------------------------------------------------------------
gross_usd, gross_usd_model, gross_usd_anchor = gam_backcast(index_data, cols["gross_usd"], cols["price_usd"], config["gam_k"])
net_usd, net_usd_model, net_usd_anchor = gam_backcast(gross_usd, cols["net_usd"], cols["price_usd"], config["gam_k"])


# -----------------------------------------------------------------------------------------------------------------------
# 3. Impliziter Umrechnungskurs, Vergleich mit dem offiziellen Kurs und Backcast
# -----------------------------------------------------------------------------------------------------------------------
fx_raw = read_csv_like_r(config["fx_file"])
fx_raw = fx_raw.loc[fx_raw[config["fx_filter"]["column"]] == config["fx_filter"]["value"]]
fx_official = pd.DataFrame({"date": pd.to_datetime(fx_raw[config["fx_date"]], errors="coerce"),
                            "fx_official": to_num(fx_raw[config["fx_value"]]).values})
fx_official = fx_official.loc[fx_official["date"].notna() & fx_official["fx_official"].notna()].reset_index(drop=True)
fx_official["fx_source"] = "official"

#---> Optionale Verlängerung des offiziellen Kurses über Proxy-Kursreihen (Niveau-GAM, nur echte Proxy-Tage):
if config.get("fx_extension"):
    proxy_data = None
    for name, p in config["fx_extension"].items():
        d = read_csv_like_r(p["source"])
        values = col_ref(d, p["value"]).map(lambda s: NA if s in ("", ".", "NA") else r_strtod(s))
        dates = pd.to_datetime(col_ref(d, p["date"]).where(~col_ref(d, p["date"]).isin(["", ".", "NA"])),
                               errors="coerce")
        part = pd.DataFrame({"date": dates.values, name: values.values})
        part = part.loc[part["date"].notna() & part[name].notna() & (part[name] > 0)]
        if p.get("invert"):
            part[name] = 1.0 / part[name]
        proxy_data = part if proxy_data is None else proxy_data.merge(part, on="date", how="inner")
    proxy_names = [c for c in proxy_data.columns if c != "date"]

    ext_est = fx_official.merge(proxy_data, on="date", how="inner")
    formula = "fx_official ~ " + " + ".join("s(`%s`, bs = 'cr', k = %s)" % (n, repr(float(config["gam_k"])))
                                            for n in proxy_names)
    extension_model = gam_fit(formula, {c: ext_est[c].values for c in ["fx_official"] + proxy_names})
    gam_summary(extension_model)
    dev = (gam_predict(extension_model, {c: ext_est[c].values for c in proxy_names}) / ext_est["fx_official"].values - 1) * 100
    print(pd.DataFrame({"n": [len(ext_est)], "from": [ext_est["date"].min().date()], "to": [ext_est["date"].max().date()],
                        "mean_dev_pct": [dev.mean()], "sd_dev_pct": [dev.std(ddof=1)], "max_abs_dev_pct": [np.abs(dev).max()]}))

    fx_ext = proxy_data.loc[proxy_data["date"] < fx_official["date"].min()].copy()
    fx_ext["fx_official"] = gam_predict(extension_model, {c: fx_ext[c].values for c in proxy_names})
    fx_ext["fx_source"] = "proxy"
    fx_ext = fx_ext[["date", "fx_official", "fx_source"]]
    print("Offizieller Kurs über Proxies verlängert:", len(fx_ext), "Tage",
          "(%s bis %s)" % (fx_ext["date"].min().date(), fx_ext["date"].max().date()) if len(fx_ext) else "")
    fx_official = pd.concat([fx_ext, fx_official]).sort_values("date", kind="stable").reset_index(drop=True)

index_fx = net_usd.merge(fx_official, on="date", how="left")
index_fx["fx_implied"] = index_fx[cols["price_usd"]].values / index_fx[cols["price_eur"]].values

start_dates["fx_implied"] = first_valid(index_fx, "fx_implied")
start_dates["fx_official"] = first_valid(index_fx, "fx_official")
print("Kurs verfügbar:", start_dates["fx_official"].date(), "bis", fx_official["date"].max().date(),
      "| davon offiziell ab", fx_official.loc[fx_official["fx_source"] == "official", "date"].min().date())

#---> 3a. Vergleich implizit vs. offiziell:
fx_comparison = index_fx.loc[index_fx["fx_implied"].notna() & index_fx["fx_official"].notna()
                             & (index_fx["fx_source"] == "official")].copy()
fx_comparison["fx_implied_return"] = valid_return(fx_comparison["fx_implied"].values)
fx_comparison["fx_official_return"] = valid_return(fx_comparison["fx_official"].values)

fx_scale = float(np.median(fx_comparison["fx_implied"].values / fx_comparison["fx_official"].values))
print("Skalierungsfaktor implizit/offiziell:", round(fx_scale, 6))

fx_comparison["fx_implied_scaled"] = fx_comparison["fx_implied"] / fx_scale
fx_comparison["deviation_pct"] = (fx_comparison["fx_implied_scaled"] / fx_comparison["fx_official"] - 1) * 100

print(pd.DataFrame([
    {"comparison": "Niveau (skaliert)", **compare_series(fx_comparison["fx_implied_scaled"], fx_comparison["fx_official"])},
    {"comparison": "Renditefaktor", **compare_series(fx_comparison["fx_implied_return"], fx_comparison["fx_official_return"])}]))

print(fx_comparison.assign(year=fx_comparison["date"].dt.year).groupby("year")["deviation_pct"]
      .agg(n="size", mean_dev_pct="mean", sd_dev_pct="std", max_abs_dev_pct=lambda s: s.abs().max()).to_string())

#---> 3b. GAM-Backcast des impliziten Kurses auf NIVEAU-Basis:
fx_model = gam_fit("fx_implied ~ s(fx_official, bs = 'cr', k = %s)" % repr(float(config["gam_k"])),
                   {"fx_implied": fx_comparison["fx_implied"].values, "fx_official": fx_comparison["fx_official"].values})
gam_summary(fx_model)

fx_backcast = (index_fx["date"] < start_dates["fx_implied"]).values & index_fx["fx_official"].notna().values
fx_pred = gam_predict(fx_model, {"fx_official": index_fx["fx_official"].values})
index_fx["fx_backcast"] = fx_backcast
index_fx["fx_implied"] = np.where(fx_backcast, fx_pred, index_fx["fx_implied"].values)

print("Impliziter Kurs zurückgerechnet:", int(fx_backcast.sum()), "Tage;",
      int(((index_fx["date"] < start_dates["fx_implied"]) & index_fx["fx_official"].isna()).sum()),
      "Tage ohne Kurs bleiben leer")

ratio = (index_fx.loc[fx_backcast, "fx_implied"] / fx_scale / index_fx.loc[fx_backcast, "fx_official"])
print(pd.DataFrame({"ratio_min": [ratio.min()], "ratio_max": [ratio.max()]}))

seam = index_fx.loc[index_fx["fx_implied"].notna()].copy()
seam["fx_implied_return"] = valid_return(seam["fx_implied"].values)
seam = seam.loc[(seam["date"] >= start_dates["fx_implied"] - timedelta(days=7))
                & (seam["date"] <= start_dates["fx_implied"] + timedelta(days=7))]
print(seam[["date", "fx_official", "fx_implied", "fx_implied_return", "fx_backcast"]].to_string(index=False))


# -----------------------------------------------------------------------------------------------------------------------
# 4. Backcast des EUR Price Index: USD Price / impliziter Kurs
# -----------------------------------------------------------------------------------------------------------------------
index_eur = index_fx.copy()
index_eur[cols["price_eur"]] = np.where((index_eur["date"] < start_dates["price_eur"]).values,
                                        index_eur[cols["price_usd"]].values / index_eur["fx_implied"].values,
                                        index_eur[cols["price_eur"]].values)


# -----------------------------------------------------------------------------------------------------------------------
# 5. Backcast der EUR Gross und Net Total Return Indizes (GAM auf EUR Price Return)
# -----------------------------------------------------------------------------------------------------------------------
gross_eur, gross_eur_model, gross_eur_anchor = gam_backcast(index_eur, cols["gross_eur"], cols["price_eur"], config["gam_k"])
net_eur, net_eur_model, net_eur_anchor = gam_backcast(gross_eur, cols["net_eur"], cols["price_eur"], config["gam_k"])

index_model = net_eur


def check_eur(target, usd_col, anchor):
    d = index_model.loc[(index_model["date"] >= start_dates["price_eur"]) & (index_model["date"] <= anchor)]
    d = d.loc[d[target].notna() & d[usd_col].notna() & d["fx_implied"].notna()].copy()
    if len(d) < 2:
        return None
    via_fx = d[usd_col].values / d["fx_implied"].values
    via_fx = via_fx / via_fx[-1] * d[target].values[-1]
    dev = (d[target].values / via_fx - 1) * 100
    return {"series": target, "from": d["date"].min().date(), "to": d["date"].max().date(), "n": len(d),
            "mean_dev_pct": dev.mean(), "max_abs_dev_pct": np.abs(dev).max()}


checks = [c for c in (check_eur(cols["gross_eur"], cols["gross_usd"], gross_eur_anchor),
                      check_eur(cols["net_eur"], cols["net_usd"], net_eur_anchor)) if c]
if checks:
    print(pd.DataFrame(checks).to_string(index=False))


# -----------------------------------------------------------------------------------------------------------------------
# Export
# -----------------------------------------------------------------------------------------------------------------------
index_final = index_model[["date"] + list(cols.values()) + ["fx_implied", "fx_official", "fx_source", "fx_backcast"]].copy()
for c in cols.values():
    index_final[c] = [r_round(float(v), 5) for v in index_final[c].values]
for c in cols.values():
    index_final[c + "_Return"] = valid_return(index_final[c].values)

export = index_final.rename(columns={"date": date_col})
export = export[[c for c in raw.columns if c in export.columns]]
r_write_csv(export, config["output_file"])
print("Export:", config["output_file"])

# Kontrolle: Offizielle Werte dürfen durch die Rückrechnung nicht verändert worden sein
for c in cols.values():
    i = index_data[c].notna().values
    original = np.array([r_round(float(v), 5) for v in index_data[c].values[i]])
    assert np.allclose(original, index_final[c].values[i], rtol=1.5e-8, atol=0), c


# -----------------------------------------------------------------------------------------------------------------------
# Visualisierung
# -----------------------------------------------------------------------------------------------------------------------
if config["show_plots"]:
    import plotly.graph_objects as go

    def vline(x):
        return dict(type="line", x0=x, x1=x, y0=0, y1=1, yref="paper", line=dict(dash="dot", width=1, color="grey"))

    plot_fx = index_model.loc[index_model["fx_implied"].notna() | index_model["fx_official"].notna()]
    fig = go.Figure()
    fig.add_trace(go.Scatter(x=plot_fx["date"], y=plot_fx["fx_official"], mode="lines", name="Offizieller Kurs",
                             line=dict(width=1), connectgaps=False))
    fig.add_trace(go.Scatter(x=plot_fx["date"], y=plot_fx["fx_implied"] / fx_scale, mode="lines",
                             name="Impliziter Kurs (skaliert)", line=dict(width=1), connectgaps=False))
    fig.update_layout(title="Umrechnungskurs", xaxis_title="Time", yaxis_title="USD je EUR/ECU",
                      legend=dict(orientation="h"), shapes=[vline(start_dates["fx_implied"])], margin=dict(t=50))
    fig.show()

    fig = go.Figure(go.Scatter(x=fx_comparison["date"], y=fx_comparison["deviation_pct"], mode="lines", line=dict(width=1)))
    fig.update_layout(title="Impliziter vs. offizieller Kurs", xaxis_title="Time", yaxis_title="Abweichung (%)",
                      margin=dict(t=50))
    fig.show()

    def plot_indices(data, keys, title, ytitle):
        fig = go.Figure()
        for key in keys:
            x = data[cols[key]].values
            first = x[np.flatnonzero(~np.isnan(x))[0]]
            fig.add_trace(go.Scatter(x=data["date"], y=np.log(x / first), mode="lines", name=cols[key],
                                     line=dict(width=1), connectgaps=False))
        fig.update_layout(title=title, xaxis_title="Time", yaxis_title=ytitle, legend=dict(orientation="h"),
                          shapes=[vline(start_dates[k]) for k in keys], margin=dict(t=50))
        fig.show()

    plot_indices(index_model, ["price_usd", "gross_usd", "net_usd"], "Indexvarianten (USD)", "Log. Index Value (USD)")
    plot_indices(index_model, ["price_eur", "gross_eur", "net_eur"], "Indexvarianten (EUR)", "Log. Index Value (EUR)")

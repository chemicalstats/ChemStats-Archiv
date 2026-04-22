// boot_gpd.cpp
// @brief Extreme Value Theory Bootstrap with GPD Tails (McNeil & Frey 2000)
//
// @details
// Splits observations into bulk and tail regimes.
//
// Tail regime:
// - USD returns are sampled from a fitted Generalized Pareto Distribution.
// - FX returns are drawn from an empirical pool (fx_pool_left),
//   conditioned on equity being in the left tail.
// - EUR returns are constructed deterministically as EUR = USD * FX.
//
// Bulk regime:
// - Entire observations (rows) are resampled without modification.
//
// Dependence structure:
// The GPD model assumes IID tail exceedances and does not include
// temporal dynamics (e.g. GARCH effects).
// Instead of parametric modeling, cross-asset dependence in the tail
// is preserved via the empirical conditional FX distribution:
// fx_pool_left contains historical FX returns observed on days when
// the equity index was in the left tail.
//
// This approach retains empirical tail dependence between equity and FX
// without imposing a parametric joint model.
//
// @references
// - Balkema, A.A. & de Haan, L. (1974): Residual Life Time at Great Age.
//   Annals of Probability, 2(5): 792–804.
// - McNeil, A.J. & Frey, R. (2000): Estimation of tail-related risk
//   measures for heteroscedastic financial time series: an extreme
//   value approach. Journal of Empirical Finance, 7(4): 271–300.

#include <Rcpp.h>
#include <vector>
using namespace Rcpp;

static inline double rgpd_inline(double scale, double shape) {
  double u = R::runif(0, 1);
  if (std::abs(shape) < 1e-10) return -scale * std::log(u);
  return scale * (std::pow(u, -shape) - 1.0) / shape;
}

// [[Rcpp::export(name = ".boot_gpd")]]
NumericMatrix boot_gpd(
    NumericMatrix returns, int base_idx, int eur_idx,
    double prob_l, double thresh_l, double scale_l, double shape_l,
    NumericVector fx_pool_left,
    double prob_r, double thresh_r, double scale_r, double shape_r,
    NumericVector fx_pool_right,
    IntegerVector bulk_idx
) {
  int n = returns.nrow();
  int k = returns.ncol();
  int n_bulk = bulk_idx.size();
  int n_fx_left = fx_pool_left.size();
  int n_fx_right = fx_pool_right.size();
  NumericMatrix out(n, k);

  double total_tail = prob_l + prob_r;

  if (shape_l >= 1.0) Rcpp::warning("Left GPD shape >= 1.0 (%.2f): infinite mean", shape_l);
  else if (shape_l >= 0.5) Rcpp::warning("Left GPD shape >= 0.5 (%.2f): infinite variance", shape_l);
  if (shape_r >= 1.0) Rcpp::warning("Right GPD shape >= 1.0 (%.2f): infinite mean", shape_r);
  else if (shape_r >= 0.5) Rcpp::warning("Right GPD shape >= 0.5 (%.2f): infinite variance", shape_r);

  for (int t = 0; t < n; t++) {
    double u = R::runif(0, 1);

    if (u < prob_l) {
      // Left tail: USD from GPD
      double exc = rgpd_inline(scale_l, shape_l);
      double r_usd = thresh_l - exc;
      out(t, base_idx) = r_usd;

      // FX from conditional empirical pool
      if (n_fx_left > 0) {
        double r_fx = fx_pool_left[(int)floor(R::runif(0, n_fx_left))];
        out(t, eur_idx) = r_usd * r_fx;
      } else {
        out(t, eur_idx) = r_usd;  // Fallback: no FX data
      }

    } else if (u < total_tail && prob_r > 0) {
      // Right tail: USD from GPD
      double exc = rgpd_inline(scale_r, shape_r);
      double r_usd = thresh_r + exc;
      out(t, base_idx) = r_usd;

      // FX from conditional empirical pool
      if (n_fx_right > 0) {
        double r_fx = fx_pool_right[(int)floor(R::runif(0, n_fx_right))];
        out(t, eur_idx) = r_usd * r_fx;
      } else {
        out(t, eur_idx) = r_usd;
      }

    } else {
      // Bulk: resample entire row (preserves empirical joint distribution)
      int idx = bulk_idx[(int)floor(R::runif(0, n_bulk))] - 1;
      for (int j = 0; j < k; j++) out(t, j) = returns(idx, j);
    }
  }

  return out;
}

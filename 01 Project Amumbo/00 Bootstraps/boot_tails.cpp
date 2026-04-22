// boot_empirical_tails.cpp
// @brief Empirical Tail Bootstrap (Davison & Hinkley 1997)
//
// @details
// Control method for EVT-based bootstraps. Splits the data into three
// strata (left tail, bulk, right tail) based on quantiles of a base
// index, and resamples entire observations within each stratum.
//
// Method:
// 1. Define thresholds (e.g. quantiles) on the base index to obtain
//    left tail, bulk, and right tail strata.
// 2. For each bootstrap observation:
//    - Select a stratum (typically matching the original frequency
//      or via stratified sampling).
//    - Sample one full row uniformly from that stratum.
//
// Properties:
// - Exactly preserves empirical tail frequency and tail shape.
// - Preserves cross-sectional dependence (full-row resampling).
// - Equivalent to sampling from the empirical distribution
//   conditional on the base index being in a given stratum.
//
// Comparison to EVT (GPD):
// - No extrapolation beyond observed extremes.
// - No parametric assumptions (e.g. GPD shape/scale).
// - Tail risk is bounded by the historical sample.
//
// Interpretation:
// This method reproduces the observed joint distribution within each
// regime (tail/bulk), but cannot generate unseen extreme events.
// It serves as a non-parametric benchmark for EVT-based approaches.
//
// Limitations:
// - Cannot model tail behavior outside the observed sample.
// - Sensitive to threshold (quantile) selection.
// - Ignores temporal dependence (IID within strata).
//
// @references
// - Davison, A.C. & Hinkley, D.V. (1997): Bootstrap Methods and their
//   Application. Cambridge University Press.
// - Hall, P. & Yao, Q. (2003): Inference in ARCH and GARCH Models with
//   Heavy-Tailed Errors. Econometrica, 71(1): 285–317.

#include <Rcpp.h>
using namespace Rcpp;

// [[Rcpp::export(name = ".boot_tails")]]
NumericMatrix boot_tails(
    NumericMatrix returns,
    double p_l, double p_r,
    IntegerVector bulk_idx,
    IntegerVector left_idx,
    IntegerVector right_idx
) {
  int n = returns.nrow();
  int k = returns.ncol();
  NumericMatrix out(n, k);
  
  int n_bulk  = bulk_idx.size();
  int n_left  = left_idx.size();
  int n_right = right_idx.size();
  
  if (n_bulk == 0) Rcpp::stop("No bulk observations provided");
  
  double total_tail = p_l + p_r;
  
  for (int t = 0; t < n; t++) {
    double u = R::runif(0, 1);
    int row_idx;
    
    if (u < p_l && n_left > 0) {
      row_idx = left_idx[(int)floor(R::runif(0, n_left))] - 1;
    } else if (u < total_tail && n_right > 0) {
      row_idx = right_idx[(int)floor(R::runif(0, n_right))] - 1;
    } else {
      row_idx = bulk_idx[(int)floor(R::runif(0, n_bulk))] - 1;
    }
    
    for (int j = 0; j < k; j++) {
      out(t, j) = returns(row_idx, j);
    }
  }
  
  return out;
}

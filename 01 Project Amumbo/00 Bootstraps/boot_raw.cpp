// boot_raw.cpp
// @brief IID Bootstrap (Efron 1979)
//
// @details
// Resamples observations (rows) uniformly with replacement.
//
// Each row represents a full cross-sectional observation (e.g. 
// all assets at a given time point).
//
// Properties:
// - Destroys all temporal dependence.
// - Preserves cross-sectional dependence, since entire rows are
//   resampled jointly.
// - Statistically consistent under the IID assumption (Efron 1979).
//
// Limitations:
// Not suitable for time series with serial dependence.
//
// @references
// - Efron, B. (1979): Bootstrap Methods: Another Look at the Jackknife.
//   Annals of Statistics, 7(1): 1–26.
// - Efron, B. & Tibshirani, R.J. (1993): An Introduction to the
//   Bootstrap. Chapman & Hall/CRC.

#include <Rcpp.h>
using namespace Rcpp;

// [[Rcpp::export(name = ".boot_raw")]]
NumericMatrix boot_raw(NumericMatrix returns) {
  int n = returns.nrow();
  int k = returns.ncol();
  NumericMatrix out(n, k);
  
  for (int i = 0; i < n; i++) {
    int idx = (int) floor(R::runif(0.0, n));
    for (int j = 0; j < k; j++) out(i, j) = returns(idx, j);
  }
  
  return out;
}

// boot_stationary.cpp
// @brief Stationary Bootstrap (Politis & Romano 1994)
//
// @details
// Resamples a time series using blocks of random length to generate
// a strictly stationary bootstrap sample.
//
// Method:
// At each time step t:
// - With probability p = 1/L, start a new block at a uniformly
//   sampled position in the original series.
// - Otherwise, continue the current block by moving to the next
//   observation (with circular wrap-around).
//
// This implies geometrically distributed block lengths with
//   E[length] = L.
//
// Properties:
// - Produces a strictly stationary resampled series (distribution
//   invariant under time shifts).
// - Preserves local temporal dependence within blocks.
// - Avoids fixed block boundaries of the Moving Block Bootstrap (MBB).
//
// Circularity:
// Uses wrap-around at the series boundary (original formulation),
// allowing blocks to span from end to beginning.
// This introduces artificial joins, which are typically acceptable
// for approximately stationary financial return series.
//
// Motivation:
// Stationarity of the bootstrap sample is essential for consistent
// variance estimation (Politis & Romano 1994), in contrast to
// fixed-length block bootstraps.
//
// Limitations:
// - Artificial boundary transitions due to circular sampling.
// - Choice of L (expected block length) remains critical.
//
// @references
// - Politis, D.N. & Romano, J.P. (1994): The Stationary Bootstrap.
//   Journal of the American Statistical Association, 89(428): 1303–1313.
// - Politis, D.N. (2003): The Impact of Bootstrap Methods on Time
//   Series Analysis. Statistical Science, 18(2): 219–230.
// - Lahiri, S.N. (2003): Resampling Methods for Dependent Data. Springer.

#include <Rcpp.h>
using namespace Rcpp;

// [[Rcpp::export(name = ".boot_stationary")]]
NumericMatrix boot_stationary(NumericMatrix returns, double L) {
  int n = returns.nrow();
  int k = returns.ncol();
  NumericMatrix out(n, k);
  
  double p = 1.0 / L;
  int i = 0;
  
  while (i < n) {
    int len = R::rgeom(p) + 1;
    int start = (int) floor(R::runif(0.0, n));
    len = std::min(len, n - i);
    
    for (int t = 0; t < len; t++) {
      int idx = (start + t) % n;
      for (int j = 0; j < k; j++) out(i + t, j) = returns(idx, j);
    }
    i += len;
  }
  
  return out;
}

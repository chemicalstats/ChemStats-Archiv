// boot_trend_reset.cpp
// @brief Random Trend Reset Stress Bootstrap
//
// @details
// Generates adversarial return paths by introducing stochastic trend
// reversals. This is not a classical bootstrap in the sense of Efron (1979),
// but a stress-testing transformation of the original series.
//
// Method:
// A latent binary state S_t ∈ {+1, -1} controls the return sign.
// The state follows a Random Telegraph Process:
//
//   P(S_t != S_{t-1}) = p_break
//
// i.e. with probability p_break, the trend flips; otherwise it persists.
//
// The transformed return is:
//   r_t^* = 1 + S_t * (r_t - 1)
//
// Interpretation:
// - Preserves magnitude of excess returns (r_t - 1)
// - Randomizes trend direction with persistence
//
// Properties:
// - Introduces regime-like trend persistence without resampling blocks
// - Preserves unconditional distribution of return magnitudes
// - Destroys original temporal dependence structure
//
// Parameter p_break:
// - Expected number of breaks in n observations: n * p_break
// - Expected duration between breaks: 1 / p_break
//
// Typical values:
// 0.00 : original series (no transformation; NOT a bootstrap)
// 0.02 : ~1 break per 50 observations (mild structural instability)
// 0.05 : ~1 break per 20 observations (aggressive)
// 0.10+: extreme stress scenario
//
// Return convention:
// Operates on gross returns r = 1 + excess return.
// Sign inversion is performed as:
//
//   r_inv = 2 - r = 1 + (-(r - 1))
//
// Naive negation (-r) would yield invalid negative gross returns.
//
// Important:
// For p_break = 0, the original series is returned unchanged.
// Stochasticity (and thus resampling behavior) only arises for p_break > 0.
//
// @references
// - Efron, B. (1979): Bootstrap Methods: Another Look at the Jackknife.
//   Annals of Statistics, 7(1): 1–26.
// - Mammen, E. (1993): Bootstrap and Wild Bootstrap for High Dimensional
//   Linear Models. Annals of Statistics, 21(1): 255–285.
// - Pesaran, M.H. & Timmermann, A. (2002): Market Timing and Return
//   Prediction under Model Instability. Journal of Empirical Finance,
//   9(5): 495–510.

#include <Rcpp.h>
using namespace Rcpp;

// [[Rcpp::export(name = ".boot_reset")]]
NumericMatrix boot_reset(NumericMatrix returns, double p_break) {
  int n = returns.nrow();
  int k = returns.ncol();
  NumericMatrix out(n, k);
  
  if (p_break < 0.0 || p_break > 1.0) {
    Rcpp::stop("p_break must be in [0, 1]");
  }
  
  bool flipped = false;
  
  for (int t = 0; t < n; t++) {
    if (R::runif(0, 1) < p_break) {
      flipped = !flipped;
    }
    
    if (flipped) {
      for (int j = 0; j < k; j++) {
        out(t, j) = 2.0 - returns(t, j);
      }
    } else {
      for (int j = 0; j < k; j++) {
        out(t, j) = returns(t, j);
      }
    }
  }
  
  return out;
}

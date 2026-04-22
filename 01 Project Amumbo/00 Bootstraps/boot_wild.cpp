// boot_wild.cpp
// @brief Wild Bootstrap (Wu 1986; Mammen 1993)
//
// @details
// Generates bootstrap samples by rescaling residuals with random weights,
// preserving heteroskedasticity without explicit variance modeling.
//
// Method:
// Let x_t be the observation and mu_hat_j the estimated mean for column j.
// Define residuals:
//   e_t = x_t - mu_hat_j
//
// The bootstrap sample is constructed as:
//   x*_t = mu_hat_j + e_t * w_t
//
// where w_t are IID random weights with:
//   E[w_t] = 0,  Var(w_t) = 1.
//
// Properties:
// - Preserves heteroskedasticity: the magnitude |e_t| is retained,
//   so periods of high volatility remain high-volatility after resampling.
// - Preserves cross-sectional dependence when using a common weight w_t
//   across all columns at time t.
// - Does not assume constant variance (unlike IID bootstrap).
//
// Weight distributions:
// - Rademacher:       P(w = +1) = P(w = -1) = 1/2
// - Mammen:           two-point distribution matching the third moment
// - Standard Normal:  w ~ N(0, 1)
//
// Mean handling:
// Centering via mu_hat_j ensures that residuals are defined relative to
// the empirical mean. This avoids systematic bias when the unconditional
// mean differs from 1.0 (e.g. equity drift in gross returns).
//
// Limitations:
// - Does not preserve temporal dependence.
// - Assumes correct specification of the mean structure (mu_hat_j).
//
// @references
// - Wu, C.F.J. (1986): Jackknife, Bootstrap and Other Resampling Methods
//   in Regression Analysis. Annals of Statistics, 14(4): 1261–1295.
// - Liu, R.Y. (1988): Bootstrap Procedures under some Non-I.I.D. Models.
//   Annals of Statistics, 16(4): 1696–1708.
// - Mammen, E. (1993): Bootstrap and Wild Bootstrap for High Dimensional
//   Linear Models. Annals of Statistics, 21(1): 255–285.

#include <Rcpp.h>
using namespace Rcpp;

// [[Rcpp::export(name = ".boot_wild")]]
NumericMatrix boot_wild(NumericMatrix returns, int type) {
  int n = returns.nrow();
  int k = returns.ncol();
  NumericMatrix out(n, k);
  
  NumericVector col_means(k);
  for (int j = 0; j < k; j++) {
    double s = 0.0;
    for (int i = 0; i < n; i++) s += returns(i, j);
    col_means[j] = s / n;
  }
  
  double sqrt5 = std::sqrt(5.0);
  double mam_p = (sqrt5 + 1.0) / (2.0 * sqrt5);
  double mam_neg = -(sqrt5 - 1.0) / 2.0;
  double mam_pos = (sqrt5 + 1.0) / 2.0;
  
  for (int i = 0; i < n; i++) {
    double w;
    if (type == 0)      w = (R::runif(0, 1) < 0.5) ? -1.0 : 1.0;
    else if (type == 1) w = (R::runif(0, 1) < mam_p) ? mam_neg : mam_pos;
    else                w = R::rnorm(0.0, 1.0);
    
    for (int j = 0; j < k; j++) {
      out(i, j) = col_means[j] + (returns(i, j) - col_means[j]) * w;
    }
  }
  
  return out;
}

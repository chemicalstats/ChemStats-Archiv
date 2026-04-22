// boot_gjr_garch.cpp
// @brief GJR-GARCH Bootstrap (Glosten, Jagannathan & Runkle 1993)
//
// @details
// Extension of the standard GARCH(1,1) bootstrap to incorporate
// asymmetric volatility responses (leverage effects).
//
// Model:
//   r_t = mu + sigma_t * z_t
//   sigma_t^2 = omega
//               + alpha * (r_{t-1} - mu)^2
//               + gamma * (r_{t-1} - mu)^2 * I(r_{t-1} < mu)
//               + beta  * sigma_{t-1}^2
//
// where I(.) is the indicator function.
//
// Interpretation:
// - Negative shocks (r_{t-1} < mu) increase volatility more strongly
//   via the additional gamma term.
// - Captures leverage effects commonly observed in equity returns.
//
// Algorithm:
// Same as GARCH bootstrap (Pascual et al. 2006), with the modified
// volatility recursion:
//
// 1. Fit GJR-GARCH(1,1) and estimate parameters.
// 2. Compute standardized residuals:
//      z_hat_t = (r_t - mu_hat) / sigma_hat_t
// 3. Resample innovations:
//      z*_t ~ IID sample from {z_hat_1, ..., z_hat_n}
// 4. Reconstruct recursively:
//      sigma*_t^2 = omega_hat
//                   + alpha_hat * (r*_{t-1} - mu_hat)^2
//                   + gamma_hat * (r*_{t-1} - mu_hat)^2
//                                 * I(r*_{t-1} < mu_hat)
//                   + beta_hat  * sigma*_{t-1}^2
//      r*_t = mu_hat + sigma*_t * z*_t
//
// Multivariate extension:
// - USD (base asset): GJR-GARCH(1,1) bootstrap.
// - FX: standard GARCH(1,1) bootstrap.
// - EUR: constructed deterministically as EUR = USD * FX.
//
// This setup captures asymmetric volatility in the base asset,
// but does not model dynamic cross-asset dependence.
//
// Limitations:
// - Assumes correct specification of the GJR-GARCH model.
// - Asymmetry only via threshold effect (no richer nonlinearities).
// - Cross-sectional dependence not explicitly modeled.
//
// @references
// - Glosten, L.R., Jagannathan, R. & Runkle, D.E. (1993): On the
//   Relation between the Expected Value and the Volatility of the
//   Nominal Excess Return on Stocks. Journal of Finance, 48(5):
//   1779–1801.
// - Pascual, L., Romo, J. & Ruiz, E. (2006): Bootstrap Prediction for
//   Returns and Volatilities in GARCH Models. Computational Statistics
//   & Data Analysis, 50(9): 2293–2312.

#include <Rcpp.h>
#include <cmath>
using namespace Rcpp;

// [[Rcpp::export(name = ".boot_gjr_garch")]]
NumericMatrix boot_gjr_garch(
    NumericMatrix returns,
    int base_idx,
    int eur_idx,
    double mu,
    double omega,
    double alpha,
    double beta,
    double gamma,
    NumericVector std_resid,
    double fx_mu,
    double fx_omega,
    double fx_alpha,
    double fx_beta,
    NumericVector fx_std_resid
) {
  int n = returns.nrow();
  int k = returns.ncol();
  int n_resid = std_resid.size();
  int n_fx_resid = fx_std_resid.size();
  NumericMatrix out(n, k);

  if (omega <= 0) Rcpp::stop("omega must be > 0");
  if (alpha < 0)  Rcpp::stop("alpha must be >= 0");
  if (beta < 0)   Rcpp::stop("beta must be >= 0");
  if (gamma < 0)  Rcpp::stop("gamma must be >= 0");

  double persistence = alpha + beta + gamma / 2.0;
  if (persistence >= 1.0) {
    Rcpp::warning("GJR not stationary (alpha+beta+gamma/2=%.4f >= 1)", persistence);
  }

  // USD variance init
  double sigma2;
  if (persistence < 0.9999) {
    sigma2 = omega / (1.0 - persistence);
  } else {
    double s = 0.0, s2 = 0.0;
    for (int i = 0; i < n; i++) {
      double r = returns(i, base_idx) - 1.0;
      s += r; s2 += r * r;
    }
    sigma2 = s2 / n - (s / n) * (s / n);
  }

  // FX variance init
  double fx_pers = fx_alpha + fx_beta;
  double fx_sigma2;
  if (fx_pers < 0.9999 && fx_omega > 0) {
    fx_sigma2 = fx_omega / (1.0 - fx_pers);
  } else {
    double fs = 0.0, fs2 = 0.0;
    for (int i = 0; i < n; i++) {
      double rfx = returns(i, eur_idx) / returns(i, base_idx) - 1.0;
      fs += rfx; fs2 += rfx * rfx;
    }
    fx_sigma2 = fs2 / n - (fs / n) * (fs / n);
  }

  double prev_eps = 0.0;
  double fx_prev_eps = 0.0;

  for (int t = 0; t < n; t++) {
    // GJR-GARCH(1,1) for USD
    double indicator = (prev_eps < 0.0) ? 1.0 : 0.0;
    sigma2 = omega + (alpha + gamma * indicator) * prev_eps * prev_eps + beta * sigma2;
    if (sigma2 < 1e-12) sigma2 = 1e-12;
    double sigma_t = std::sqrt(sigma2);

    int z_idx = (int)floor(R::runif(0.0, n_resid));
    double z = std_resid[z_idx];

    double eps = sigma_t * z;
    double r_base = 1.0 + mu + eps;
    out(t, base_idx) = r_base;
    prev_eps = eps;

    // FX GARCH(1,1)
    fx_sigma2 = fx_omega + fx_alpha * fx_prev_eps * fx_prev_eps + fx_beta * fx_sigma2;
    if (fx_sigma2 < 1e-12) fx_sigma2 = 1e-12;
    double fx_sigma_t = std::sqrt(fx_sigma2);

    int fx_z_idx = (int)floor(R::runif(0.0, n_fx_resid));
    double fx_z = fx_std_resid[fx_z_idx];
    double fx_eps = fx_sigma_t * fx_z;
    double r_fx = 1.0 + fx_mu + fx_eps;
    fx_prev_eps = fx_eps;

    // EUR = USD * FX
    out(t, eur_idx) = out(t, base_idx) * r_fx;
  }

  return out;
}

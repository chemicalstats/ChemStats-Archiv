// boot_garch.cpp
// @brief GARCH Bootstrap (Pascual et al. 2006)
//
// @details
// Generates bootstrap samples by combining parametric volatility dynamics
// (GARCH) with non-parametric resampling of standardized innovations.
//
// Model:
//   r_t = mu + sigma_t * z_t
//   sigma_t^2 = omega + alpha * (r_{t-1} - mu)^2 + beta * sigma_{t-1}^2
//
// Algorithm:
// 1. Fit GARCH(1,1) and estimate parameters (mu_hat, omega_hat, alpha_hat, beta_hat).
// 2. Compute standardized residuals:
//      z_hat_t = (r_t - mu_hat) / sigma_hat_t
// 3. Resample innovations:
//      z*_t ~ IID sample from {z_hat_1, ..., z_hat_n}
// 4. Reconstruct bootstrap path recursively:
//      sigma*_t^2 = omega_hat
//                   + alpha_hat * (r*_{t-1} - mu_hat)^2
//                   + beta_hat  * sigma*_{t-1}^2
//      r*_t = mu_hat + sigma*_t * z*_t
//
// Interpretation:
// - Volatility clustering is preserved via the GARCH recursion.
// - Innovation distribution is preserved empirically via resampling.
// - Separates conditional variance dynamics (parametric) from shocks (non-parametric).
//
// Multivariate extension:
// - USD (base asset): GARCH(1,1) bootstrap as above.
// - FX: independent GARCH(1,1) bootstrap.
// - EUR: constructed deterministically as EUR = USD * FX.
//
// This approach preserves marginal volatility dynamics per series,
// but does not model time-varying cross-asset correlations
// (no multivariate GARCH or copula structure).
//
// Limitations:
// - Assumes correct GARCH(1,1) specification.
// - Ignores cross-asset dependence beyond deterministic links.
// - No leverage effects unless explicitly modeled.
//
// @references
// - Bollerslev, T. (1986): Generalized Autoregressive Conditional
//   Heteroskedasticity. Journal of Econometrics, 31(3): 307–327.
// - Pascual, L., Romo, J. & Ruiz, E. (2006): Bootstrap Prediction for
//   Returns and Volatilities in GARCH Models. Computational Statistics
//   & Data Analysis, 50(9): 2293–2312.

#include <Rcpp.h>
#include <cmath>
using namespace Rcpp;

// [[Rcpp::export(name = ".boot_garch")]]
NumericMatrix boot_garch(
    NumericMatrix returns,
    int base_idx,
    int eur_idx,
    double mu,
    double omega,
    double alpha,
    double beta,
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
  if (alpha + beta >= 1.0) {
    Rcpp::warning("alpha + beta >= 1 (%.4f): non-stationary GARCH", alpha + beta);
  }

  // USD (equity) variance init
  double persistence = alpha + beta;
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

  double prev_r = mu;
  double fx_prev_eps = 0.0;

  for (int t = 0; t < n; t++) {
    // USD GARCH(1,1)
    double shock = prev_r - mu;
    sigma2 = omega + alpha * shock * shock + beta * sigma2;
    if (sigma2 < 1e-12) sigma2 = 1e-12;
    double sigma_t = std::sqrt(sigma2);

    int z_idx = (int)floor(R::runif(0.0, n_resid));
    double z = std_resid[z_idx];

    double r_base = 1.0 + mu + sigma_t * z;
    out(t, base_idx) = r_base;
    prev_r = mu + sigma_t * z;

    // FX GARCH(1,1)
    fx_sigma2 = fx_omega + fx_alpha * fx_prev_eps * fx_prev_eps + fx_beta * fx_sigma2;
    if (fx_sigma2 < 1e-12) fx_sigma2 = 1e-12;
    double fx_sigma_t = std::sqrt(fx_sigma2);

    int fx_z_idx = (int)floor(R::runif(0.0, n_fx_resid));
    double fx_z = fx_std_resid[fx_z_idx];
    double fx_eps = fx_sigma_t * fx_z;
    double r_fx = 1.0 + fx_mu + fx_eps;
    fx_prev_eps = fx_eps;

    // EUR = USD * FX (deterministic)
    out(t, eur_idx) = out(t, base_idx) * r_fx;
  }

  return out;
}

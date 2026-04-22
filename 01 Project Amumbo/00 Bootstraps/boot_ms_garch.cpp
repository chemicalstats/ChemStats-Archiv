// boot_ms_garch.cpp
// @brief Markov-Switching GARCH Bootstrap (Haas, Mittnik & Paolella 2004)
//
// @details
// Extends GARCH-based bootstrap methods by introducing a latent
// Markov regime process that governs volatility dynamics.
//
// Model structure:
//
// Latent state:
//   S_t ∈ {1, ..., K}, Markov chain with transition matrix P
//
// Observation equation:
//   r_t = mu_{S_t} + sigma_{t,S_t} * z_t
//
// State-dependent volatility (GARCH per regime):
//   sigma_{t,S_t}^2 = omega_{S_t}
//                    + alpha_{S_t} * (r_{t-1} - mu_{S_{t-1}})^2
//                    + beta_{S_t}  * sigma_{t-1,S_{t-1}}^2
//
// Algorithm:
// 1. Estimate Markov transition matrix P and regime-specific GARCH parameters.
// 2. Simulate regime path S*_t using P.
// 3. Compute standardized residuals within each regime:
//      z_hat_t = (r_t - mu_{S_t}) / sigma_{t,S_t}
// 4. Resample innovations IID from pooled residuals (or regime-conditional pool).
// 5. Reconstruct recursively conditional on simulated regime path.
//
// Multivariate setup:
// - USD (base asset): MS-GJR-GARCH bootstrap.
// - FX: independent GARCH(1,1) bootstrap.
// - EUR: deterministic coupling via EUR = USD * FX.
//
// Interpretation:
// - Captures both volatility clustering (GARCH) and structural breaks
//   in volatility regimes (Markov switching).
// - Allows abrupt changes in risk level driven by latent states.
//
// Limitations:
// - Strong parametric structure (Markov + GARCH).
// - Regime estimation error propagates into bootstrap.
// - Cross-asset dependence not explicitly modeled.
//
// @references
// - Haas, M., Mittnik, S. & Paolella, M. (2004): A New Approach to
//   Markov-Switching GARCH Models. Journal of Financial Econometrics,
//   2(4): 493–530.


#include <Rcpp.h>
#include <cmath>
using namespace Rcpp;

// [[Rcpp::export(name = ".boot_ms_garch")]]
NumericMatrix boot_ms_garch(
    NumericMatrix returns, int base_idx, int eur_idx, int n_regimes,
    NumericVector mu_vec, NumericVector omega_vec,
    NumericVector alpha_vec, NumericVector beta_vec, NumericVector gamma_vec,
    NumericMatrix trans_mat, List std_resid_list, NumericVector stationary_prob,
    double fx_mu, double fx_omega, double fx_alpha, double fx_beta,
    NumericVector fx_std_resid
) {
  int n = returns.nrow(); int K = n_regimes;
  int n_fx_resid = fx_std_resid.size();
  NumericMatrix out(n, returns.ncol());

  for (int i = 0; i < K; i++) {
    double rs = 0; for (int j = 0; j < K; j++) rs += trans_mat(i,j);
    if (std::abs(rs - 1.0) > 1e-6) Rcpp::stop("Trans row %d != 1", i+1);
  }

  double u = R::runif(0,1); int regime = 0; double cum = 0;
  for (int r = 0; r < K; r++) { cum += stationary_prob[r]; if (u <= cum) { regime = r; break; } }

  double pers = alpha_vec[regime] + beta_vec[regime];
  double sigma2 = (pers < 0.9999) ? omega_vec[regime]/(1.0-pers) : 0;
  if (sigma2 <= 0) { double s=0,s2=0; for(int i=0;i<n;i++){double r=returns(i,base_idx)-1;s+=r;s2+=r*r;} sigma2=s2/n-(s/n)*(s/n); }

  double fx_pers = fx_alpha + fx_beta;
  double fx_sigma2 = (fx_pers < 0.9999 && fx_omega > 0) ? fx_omega/(1.0-fx_pers) : 0;
  if (fx_sigma2 <= 0) { double fs=0,fs2=0; for(int i=0;i<n;i++){double r=returns(i,eur_idx)/returns(i,base_idx)-1;fs+=r;fs2+=r*r;} fx_sigma2=fs2/n-(fs/n)*(fs/n); }

  double prev_eps = 0, fx_prev_eps = 0;

  for (int t = 0; t < n; t++) {
    if (t > 0) {
      double ut = R::runif(0,1); double ct = 0; int old = regime;
      for (int r = 0; r < K; r++) { ct += trans_mat(old,r); if (ut <= ct) { regime = r; break; } }
      if (regime != old) {
        double np = alpha_vec[regime]+beta_vec[regime];
        double nu = (np<0.9999) ? omega_vec[regime]/(1.0-np) : sigma2;
        sigma2 = 0.5*sigma2 + 0.5*nu;
      }
    }

    double ind = (prev_eps < 0) ? 1.0 : 0.0;
    sigma2 = omega_vec[regime] + (alpha_vec[regime]+gamma_vec[regime]*ind)*prev_eps*prev_eps + beta_vec[regime]*sigma2;
    if (sigma2 < 1e-12) sigma2 = 1e-12;
    double sigma_t = std::sqrt(sigma2);

    NumericVector rp = std_resid_list[regime]; int np = rp.size();
    double z = rp[(int)floor(R::runif(0,np))];
    double eps = sigma_t * z;
    out(t, base_idx) = 1.0 + mu_vec[regime] + eps;
    prev_eps = eps;

    fx_sigma2 = fx_omega + fx_alpha*fx_prev_eps*fx_prev_eps + fx_beta*fx_sigma2;
    if (fx_sigma2 < 1e-12) fx_sigma2 = 1e-12;
    double fx_eps = std::sqrt(fx_sigma2) * fx_std_resid[(int)floor(R::runif(0,n_fx_resid))];
    out(t, eur_idx) = out(t, base_idx) * (1.0 + fx_mu + fx_eps);
    fx_prev_eps = fx_eps;
  }
  return out;
}

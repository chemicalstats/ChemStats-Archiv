// boot_tvtp_ms_garch.cpp
// @brief Time-Varying Transition Probability Markov-Switching
//        AR(1)-GJR-GARCH-M Bootstrap
//
// @details
// Extends Markov-Switching GARCH models by allowing the transition
// probabilities to vary over time (TVTP: Time-Varying Transition Probabilities).
//
// This allows regime persistence and switching intensity to depend
// on exogenous or lagged state variables.
//
// Model structure:
//
// Latent regime:
//   S_t ∈ {1, ..., K}
//
// Time-varying transition probabilities:
//   P_{ij,t} = P(S_t = j | S_{t-1} = i, x_t)
// where x_t may include lagged returns, volatility, or other indicators.
//
// Observation equation:
//   r_t = mu_{S_t}
//        + phi_{S_t} * r_{t-1}
//        + lambda_{S_t} * sigma_{t,S_t}
//        + sigma_{t,S_t} * z_t
//
// Volatility process (regime-dependent GJR-GARCH):
//   sigma_{t,S_t}^2 = omega_{S_t}
//                    + alpha_{S_t} * (r_{t-1}
//                    - mu_{S_{t-1}})^2
//                    + gamma_{S_t} * (r_{t-1}
//                    - mu_{S_{t-1}})^2 * I(r_{t-1} < mu_{S_{t-1}})
//                    + beta_{S_t}  * sigma_{t-1,S_{t-1}}^2
//
// Algorithm:
// 1. Estimate regime-dependent parameters and TVTP specification.
// 2. At each step, update transition matrix P_t based on state variables.
// 3. Simulate regime path S*_t using time-varying P_t.
// 4. Resample standardized residuals z_hat_t IID.
// 5. Reconstruct recursively:
//      - AR(1) dynamics
//      - GJR-GARCH volatility
//      - GARCH-in-Mean risk premium
//      - time-varying regime switching probabilities
//
// Multivariate setup:
// - USD (base asset): TVTP-MS-AR-GJR-GARCH-M bootstrap.
// - FX: standard GARCH(1,1) bootstrap.
// - EUR: deterministic coupling via EUR = USD * FX.
//
// Interpretation:
// - Extends MS-GARCH by allowing endogenous regime switching intensity.
// - Captures structural changes in both volatility AND transition dynamics.
// - Allows crisis clustering via state-dependent persistence.
//
// Limitations:
// - Extremely high parameter complexity.
// - Sensitive to specification of TVTP function.
// - Difficult to identify regime dynamics uniquely.
// - Computationally expensive simulation and estimation.
//
// @references
// - Filardo, A.J. (1994): Business-Cycle Phases and Their Transitional
//   Dynamics. Journal of Business & Economic Statistics, 12(1): 299–308.
// - Haas, M., Mittnik, S. & Paolella, M. (2004): A New Approach to
//   Markov-Switching GARCH Models. Journal of Financial Econometrics,
//   2(4): 493–530.
// - Engle, R.F., Lilien, D.M. & Robins, R.P. (1987): Estimating Time
//   Varying Risk Premia in the Term Structure: The ARCH-M Model.
//   Econometrica, 55(2): 391–407.

#include <Rcpp.h>
#include <cmath>
#include <vector>
using namespace Rcpp;

static void compute_tvtp_row(
    const NumericMatrix& base_trans, const NumericMatrix& delta_mat,
    int from, int K, double sigma2_std, std::vector<double>& prob_out
) {
  double max_score = -1e30;
  for (int j = 0; j < K; j++) {
    double bp = base_trans(from, j); if (bp < 1e-8) bp = 1e-8;
    prob_out[j] = std::log(bp) + delta_mat(from, j) * sigma2_std;
    if (prob_out[j] > max_score) max_score = prob_out[j];
  }
  double sum_exp = 0;
  for (int j = 0; j < K; j++) { prob_out[j] = std::exp(prob_out[j] - max_score); sum_exp += prob_out[j]; }
  for (int j = 0; j < K; j++) prob_out[j] /= sum_exp;
}

// [[Rcpp::export(name = ".boot_tvtp_ms_garch")]]
NumericMatrix boot_tvtp_ms_garch(
    NumericMatrix returns,
    int base_idx,
    int eur_idx,
    int n_regimes,
    NumericVector mu_vec,
    NumericVector omega_vec,
    NumericVector alpha_vec,
    NumericVector beta_vec,
    NumericVector gamma_vec,
    NumericVector phi_vec,
    NumericVector lambda_vec,
    NumericMatrix base_trans_mat,
    NumericMatrix delta_mat,
    NumericVector unc_var_vec,
    List std_resid_list,
    NumericVector stationary_prob,
    double fx_mu,
    double fx_omega,
    double fx_alpha,
    double fx_beta,
    NumericVector fx_std_resid
) {
  int n = returns.nrow();
  int K = n_regimes;
  int n_fx_resid = fx_std_resid.size();
  NumericMatrix out(n, returns.ncol());

  for (int i = 0; i < K; i++) {
    double rs = 0; for (int j = 0; j < K; j++) rs += base_trans_mat(i,j);
    if (std::abs(rs - 1.0) > 1e-6) Rcpp::stop("Trans row %d != 1", i+1);
    if (unc_var_vec[i] <= 0) Rcpp::stop("unc_var[%d] <= 0", i+1);
  }

  bool has_ar = false, has_gm = false, has_tvtp = false;
  for (int r = 0; r < K; r++) {
    if (std::abs(phi_vec[r]) > 1e-10) has_ar = true;
    if (std::abs(lambda_vec[r]) > 1e-10) has_gm = true;
  }
  for (int i = 0; i < K; i++) for (int j = 0; j < K; j++)
    if (std::abs(delta_mat(i,j)) > 1e-10) has_tvtp = true;

  double u = R::runif(0,1); int regime = 0; double cum = 0;
  for (int r = 0; r < K; r++) { cum += stationary_prob[r]; if (u <= cum) { regime = r; break; } }

  double pers = alpha_vec[regime]+beta_vec[regime]+gamma_vec[regime]/2.0;
  double sigma2 = (pers < 0.9999) ? omega_vec[regime]/(1.0-pers) : 0;
  if (sigma2 <= 0) { double s=0,s2=0; for(int i=0;i<n;i++){double r=returns(i,base_idx)-1;s+=r;s2+=r*r;} sigma2=s2/n-(s/n)*(s/n); }

  double fx_pers = fx_alpha + fx_beta;
  double fx_sigma2 = (fx_pers < 0.9999 && fx_omega > 0) ? fx_omega/(1.0-fx_pers) : 0;
  if (fx_sigma2 <= 0) { double fs=0,fs2=0; for(int i=0;i<n;i++){double r=returns(i,eur_idx)/returns(i,base_idx)-1;fs+=r;fs2+=r*r;} fx_sigma2=fs2/n-(fs/n)*(fs/n); }

  double prev_eps = 0, prev_r = 0, fx_prev_eps = 0;
  std::vector<double> tvtp_probs(K);

  for (int t = 0; t < n; t++) {
    if (t > 0) {
      int old = regime;
      if (has_tvtp) {
        double s2std = sigma2/unc_var_vec[old] - 1.0;
        if (s2std > 10.0) s2std = 10.0; if (s2std < -0.99) s2std = -0.99;
        compute_tvtp_row(base_trans_mat, delta_mat, old, K, s2std, tvtp_probs);
      } else {
        for (int r = 0; r < K; r++) tvtp_probs[r] = base_trans_mat(old, r);
      }
      double ut = R::runif(0,1); double ct = 0;
      for (int r = 0; r < K; r++) { ct += tvtp_probs[r]; if (ut <= ct) { regime = r; break; } }
      if (regime != old) {
        double np = alpha_vec[regime]+beta_vec[regime]+gamma_vec[regime]/2.0;
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

    double mean_t = mu_vec[regime];
    if (has_ar) mean_t += phi_vec[regime] * prev_r;
    if (has_gm) mean_t += lambda_vec[regime] * sigma_t;

    double eps = sigma_t * z;
    double excess_r = mean_t + eps;
    out(t, base_idx) = 1.0 + excess_r;
    prev_eps = eps;
    prev_r = excess_r;

    // FX GARCH(1,1)
    fx_sigma2 = fx_omega + fx_alpha*fx_prev_eps*fx_prev_eps + fx_beta*fx_sigma2;
    if (fx_sigma2 < 1e-12) fx_sigma2 = 1e-12;
    double fx_eps = std::sqrt(fx_sigma2) * fx_std_resid[(int)floor(R::runif(0,n_fx_resid))];
    out(t, eur_idx) = out(t, base_idx) * (1.0 + fx_mu + fx_eps);
    fx_prev_eps = fx_eps;
  }
  return out;
}

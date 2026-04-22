// helper.cpp
// @brief Core helper functions for bootstrap and simulation library
//
// @requires Rcpp
//
// @details
// Provides foundational numerical and statistical utilities used across
// bootstrap, regime-switching, and leverage-adjusted simulation models.
//
// ---------------------------------------------------------------------
// Transformation layer
// ---------------------------------------------------------------------
// .compute_product
//   Computes leveraged ETF returns from base index returns.
//
// .compute_prices
//   Constructs cumulative price paths with differentiated knockout logic
//   for index vs. leveraged products.
//
// ---------------------------------------------------------------------
// Regime & state construction
// ---------------------------------------------------------------------
// .precompute_regime_indices
//   Precomputes index sets for regime-conditioned resampling.
//
// .assign_regimes
//   Assigns regimes based on volatility thresholds or state variables.
//
// .estimate_trans_mat
//   Estimates Markov transition matrix with Laplace (Dirichlet) smoothing.
//
// ---------------------------------------------------------------------
// Volatility estimation
// ---------------------------------------------------------------------
// .rolling_vol
//   Computes Bessel-corrected rolling standard deviation for unbiased
//   variance estimation under finite sample windows.
//
// ---------------------------------------------------------------------
// Statistical properties
// ---------------------------------------------------------------------
// - Separation of transformation, estimation, and regime assignment layers
// - Designed for consistency across IID, block, regime-switching,
//   and GARCH-based bootstrap methods
//
// @references
// - Bessel, F.W. (1818): Fundamenta Astronomiae. Regiomonti.
// - Agresti, A. & Hitchcock, D.B. (2005): Bayesian Inference for
//   Categorical Data Analysis. Statistical Methods & Applications,
//   14(3): 297–330.
// - Avellaneda, M. & Zhang, S. (2010): Path-Dependence of Leveraged
//   ETF Returns. SIAM Journal on Financial Mathematics, 1(1): 586–603.

#include <Rcpp.h>
using namespace Rcpp;

// Leverage ETF Return Computation (Avellaneda & Zhang 2010)
//
// @details
// Computes leveraged ETF returns from a base index return with
// explicit financing and expense effects.
//
// Core relationship:
//
//   r_LETF = 1 + L * (r_base - 1) - fin_cost - exp_cost
//
// where:
// - r_base : gross return of underlying index (r = P_t / P_{t-1})
// - L      : leverage factor
// - fin_cost : financing cost of leverage
// - exp_cost : management / tracking expense drag
//
// Interpretation of leverage regimes:
//
// 1. Long leverage (L > 1):
//    - Investor borrows (L - 1) capital
//    - Returns are amplified proportionally
//
// 2. Unlevered or reduced exposure (0 < L < 1):
//    - No borrowing; partial exposure to index
//
// 3. Inverse / short (L < 0):
//    - Synthetic short exposure via derivatives
//    - Effective exposure is |L| with daily rebalancing
//
// Important:
// - Path dependency implies that r_LETF ≠ L * cumulative r_base
//   due to compounding and daily reset effects.
// - Volatility drag becomes significant for |L| > 1.
//
// @references
// - Avellaneda, M. & Zhang, S. (2010): Path-Dependence of Leveraged ETF Returns.
//   SIAM Journal on Financial Mathematics, 1(1): 586–603.

// [[Rcpp::export(name = ".compute_product")]]
NumericVector compute_product(
    NumericVector base_ret, double leverage, double finance, double expense
) {
  int n = base_ret.size();
  NumericVector product(n);
  
  double daily_fin = finance / 100.0 / 365.25;
  double daily_exp = expense / 100.0 / 365.25;
  
  double fin_mult;
  if (leverage >= 1.0) fin_mult = leverage - 1.0;
  else if (leverage > 0.0) fin_mult = 0.0;
  else fin_mult = std::abs(leverage);
  
  for (int i = 0; i < n; i++) {
    double r = base_ret[i] - 1.0;
    product[i] = 1.0 + leverage * r - fin_mult * daily_fin - daily_exp;
  }
  
  return product;
}


// Cumulative Price Paths with Differentiated Knockout
//
// @details
// Handles cumulative price construction for leveraged products and
// distinguishes between numerical invalidity and economically meaningful
// knockout events.
//
// Cases:
//
// 1. Index path invalidity:
//    If cumulative index level <= 0 due to numerical or bootstrap
//    artifacts, the path is considered invalid and discarded (NULL).
//
// 2. Leveraged ETF (LETF) knockout:
//    If LETF price <= 0, this is treated as a valid economic event
//    (total loss of capital). The price is then floored at 0 and
//    the path remains valid.
//
//    This reflects path-dependent decay and leverage effects:
//    extreme negative index moves can drive leveraged products to
//    total loss (e.g. 3x leverage with -34% single-day move).
//
// Interpretation:
// - Index <= 0 → invalid model artifact (non-physical path)
// - LETF <= 0  → economically valid default / knockout event
//
// The distinction is crucial for simulation stability and realistic
// modeling of leveraged instruments.
//
// @references
// - Avellaneda, M. & Zhang, S. (2010): Path-Dependence of Leveraged ETF Returns.
//   SIAM Journal on Financial Mathematics, 1(1): 586–603.

// [[Rcpp::export(name = ".compute_prices")]]
SEXP compute_prices(NumericMatrix returns, IntegerVector indizes,
                    IntegerVector letf, double start = 100.0) {
  int n = returns.nrow();
  int k = returns.ncol();
  NumericMatrix prices(n + 1, k);
  
  std::vector<bool> knocked_out(k, false);
  
  for (int j = 0; j < k; j++) prices(0, j) = start;
  
  for (int i = 0; i < n; i++) {
    for (int j = 0; j < k; j++) {
      if (knocked_out[j]) { prices(i + 1, j) = 0.0; continue; }
      prices(i + 1, j) = prices(i, j) * returns(i, j);
      if (prices(i + 1, j) <= 0.0) { prices(i + 1, j) = 0.0; knocked_out[j] = true; }
    }
    for (int idx = 0; idx < indizes.size(); idx++) {
      int col = indizes[idx];
      if (col >= 0 && col < k && knocked_out[col]) return R_NilValue;
    }
  }
  
  if (returns.hasAttribute("dimnames")) prices.attr("dimnames") = returns.attr("dimnames");
  return prices;
}

// Regime Index Precomputation
//
// @details
// Groups observation indices by regime label for efficient
// regime-conditional bootstrap sampling.
//
// Given a regime assignment vector regimes ∈ {1, ..., n_reg},
// this function constructs index sets:
//
//   I_r = { i : regimes[i] == r }
//
// for each regime r.
//
// Implementation:
// - First pass: counts observations per regime (for memory reservation)
// - Second pass: fills index lists
// - Returns 1-based indices (R convention)
//
// Properties:
// - Linear time complexity O(n)
// - Memory-efficient due to preallocation
// - Enables fast regime-conditioned resampling in bootstrap methods
//
// Important:
// - Input regimes are assumed to be 1-based (R indexing)
// - Invalid regime labels are silently ignored
//
// Statistical role:
// This function is a preprocessing step for:
// - Markov-switching bootstrap methods
// - Volatility-threshold regime models
// - Empirical tail / bulk stratification
//
// It does not modify data, only constructs conditioning structure.
//
// @complexity
// Time:  O(n)
// Space: O(n)

// [[Rcpp::export(name = ".precompute_regime_indices")]]
List precompute_regime_indices(IntegerVector regimes, int n_reg) {
  int n = regimes.size();
  std::vector<int> counts(n_reg, 0);
  for (int i = 0; i < n; i++) {
    int r = regimes[i] - 1;
    if (r >= 0 && r < n_reg) counts[r]++;
  }
  std::vector<std::vector<int>> reg_idx(n_reg);
  for (int r = 0; r < n_reg; r++) reg_idx[r].reserve(counts[r]);
  for (int i = 0; i < n; i++) {
    int r = regimes[i] - 1;
    if (r >= 0 && r < n_reg) reg_idx[r].push_back(i + 1);
  }
  List result(n_reg);
  for (int r = 0; r < n_reg; r++) result[r] = wrap(reg_idx[r]);
  return result;
}


// Rolling Volatility (Bessel-corrected)
//
// Uses the unbiased sample variance estimator:
//
//   S^2 = (1 / (n - 1)) * Σ (x_i - x̄)^2
//
// The Bessel correction compensates for the downward bias of the
// naive estimator (1/n) Σ (x_i - x̄)^2 when the true mean is unknown
// and replaced by the sample mean.
//
// Effect:
// - Ensures unbiased estimation of variance under IID assumptions.
// - Particularly important for small rolling windows, where the bias
//   of the uncorrected estimator can be substantial.
//
// Note:
// For very small window sizes, the estimator variance itself becomes
// large, so bias correction does not imply higher accuracy, only
// correct expectation.
//
// @references
// - Bessel, F.W. (1818): The Correction Factor for Variance Estimation
//   (historical origin of the correction).
// - Rao, C.R. (1973): Linear Statistical Inference and Its Applications.
//   Wiley.

// [[Rcpp::export(name = ".rolling_vol")]]
NumericVector rolling_vol(NumericVector x, int window) {
  int n = x.size();
  if (window <= 0) Rcpp::stop("window must be positive");
  if (window > n) { Rcpp::warning("window > n, using n"); window = n; }
  
  NumericVector vol(n);
  double sum = 0.0, sum_sq = 0.0;
  
  for (int i = 0; i < n; i++) {
    double v = x[i] - 1.0;
    sum += v; sum_sq += v * v;
    int cnt;
    if (i < window - 1) cnt = i + 1;
    else {
      if (i >= window) { double old = x[i-window]-1.0; sum -= old; sum_sq -= old*old; }
      cnt = window;
    }
    if (cnt <= 1) vol[i] = 0.0;
    else {
      double mean = sum / cnt;
      double var = (sum_sq - cnt * mean * mean) / (cnt - 1);
      vol[i] = std::sqrt(std::max(0.0, var));
    }
  }
  return vol;
}

// Volatility-Based Regime Assignment
//
// @details
// Maps a continuous volatility measure into discrete regimes
// using threshold binning.
//
// Given volatility series vol_t and ordered thresholds:
//
//   thresh = {τ_0, τ_1, ..., τ_K}
//
// regimes are defined as:
//
//   S_t = r  if τ_{r-1} ≤ vol_t < τ_r
//
// resulting in a discrete state space S_t ∈ {1, ..., K}.
//
// Implementation:
// - Sequential binning over ordered thresholds
// - First matching interval determines regime
// - Default assignment to highest regime if no match occurs
//
// Properties:
// - Converts continuous volatility process into Markov-style state space
// - Enables regime-switching bootstrap methods (MS-GARCH, TVTP-MS)
// - Deterministic and pathwise consistent mapping
//
// Important:
// - Threshold vector must be strictly increasing
// - Boundary convention: left-closed, right-open intervals
//   [τ_r, τ_{r+1})
//
// Statistical role:
// This function is used to construct latent regime labels for:
// - Markov-switching models (MS-GARCH, TVTP-MS-GARCH)
// - Volatility stratified bootstrap methods
// - Empirical risk regime segmentation
//
// Limitations:
// - Hard thresholding (no probabilistic smoothing)
// - Sensitive to threshold specification
// - Does not enforce Markov consistency (purely pointwise mapping)

// [[Rcpp::export(name = ".assign_regimes")]]
IntegerVector assign_regimes(NumericVector vol, NumericVector thresh) {
  int n = vol.size();
  int n_reg = thresh.size() - 1;
  IntegerVector reg(n);
  for (int i = 0; i < n; i++) {
    reg[i] = n_reg;
    for (int r = 0; r < n_reg; r++) {
      if (vol[i] >= thresh[r] && vol[i] < thresh[r + 1]) { reg[i] = r + 1; break; }
    }
  }
  return reg;
}


// Transition Matrix (Laplace-smoothed)
//
// Applies additive smoothing to the estimated transition matrix:
//
//   P_{ij} ∝ N_{ij} + α
//
// followed by row-wise normalization.
//
// This is equivalent to a symmetric Dirichlet(α) prior on each row
// of the transition matrix.
//
// Purpose:
// - Ensures strictly positive transition probabilities
// - Prevents degenerate Markov chains with absorbing states
// - Guarantees irreducibility and improves numerical stability
//   in stationary distribution computation (power iteration)
//
// With α = 0.1 (default), the prior is weak and primarily acts as a
// regularization term rather than a strong structural constraint.
//
// Interpretation:
// Laplace smoothing avoids zero-probability transitions, ensuring that
// every regime remains reachable from every other regime in finite time.
//
// @references
// - Agresti, A. & Hitchcock, D.B. (2005): Bayesian Inference for
//   Categorical Data Analysis. Statistical Methods in Medical Research.
// - Bishop, C.M. (2006): Pattern Recognition and Machine Learning.
//   Springer (Dirichlet priors and smoothing interpretation).

// [[Rcpp::export(name = ".estimate_trans_mat")]]
NumericMatrix estimate_trans_mat(IntegerVector regimes, int n_reg, double alpha = 0.1) {
  NumericMatrix trans(n_reg, n_reg);
  int n = regimes.size();
  if (alpha < 0) { Rcpp::warning("alpha < 0, using 0.1"); alpha = 0.1; }
  
  for (int t = 1; t < n; t++) {
    int from = regimes[t-1] - 1, to = regimes[t] - 1;
    if (from >= 0 && from < n_reg && to >= 0 && to < n_reg) trans(from, to) += 1.0;
  }
  for (int r = 0; r < n_reg; r++) {
    double row_sum = 0.0;
    for (int c = 0; c < n_reg; c++) { trans(r, c) += alpha; row_sum += trans(r, c); }
    for (int c = 0; c < n_reg; c++) trans(r, c) /= row_sum;
  }
  return trans;
}

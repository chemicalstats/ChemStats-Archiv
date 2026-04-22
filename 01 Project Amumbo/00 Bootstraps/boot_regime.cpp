// boot_regime.cpp
// @brief Regime-Switching Bootstrap (Hamilton 1989)
//
// @details
// Generates a bootstrap sample using a finite-state Markov chain
// to model regime dynamics.
//
// Algorithm:
// 1. Compute the stationary distribution pi of the transition
//    matrix P via power iteration:
//       pi_{k+1} = pi_k * P
//    (equivalently: left eigenvector of P for eigenvalue 1).
//
// 2. Draw the initial regime from pi (not from empirical frequencies).
//
// 3. For each time step t:
//    a. Sample an observation uniformly from the current regime.
//    b. Draw the next regime according to the corresponding row of P.
//
// Properties:
// - Preserves regime persistence via the Markov transition structure.
// - Preserves cross-sectional dependence within each sampled observation.
// - Allows for non-linear dynamics induced by regime changes.
//
// Initialization:
// Sampling the initial state from the stationary distribution ensures
// that the Markov chain starts in equilibrium. This avoids transient
// effects and initialization bias, which can be substantial in short
// samples with highly persistent regimes.
//
// Limitations:
// - Assumes time-homogeneous transition probabilities.
// - Ignores within-regime temporal dependence (sampling is IID
//   conditional on the regime).
//
// @references
// - Hamilton, J.D. (1989): A New Approach to the Economic Analysis of
//   Nonstationary Time Series and the Business Cycle. Econometrica,
//   57(2): 357–384.
// - Ang, A. & Bekaert, G. (2002): Regime Switches in Interest Rates.
//   Journal of Business & Economic Statistics, 20(2): 163–182.
// - Guidolin, M. & Timmermann, A. (2007): Asset Allocation under
//   Multivariate Regime Switching. Journal of Economic Dynamics
//   and Control, 31(11): 3503–3544.
// - Norris, J.R. (1997): Markov Chains. Cambridge University Press.

#include <Rcpp.h>
#include <vector>
#include <cmath>
using namespace Rcpp;

static std::vector<double> stationary_distribution(NumericMatrix trans, int n_reg,
                                                    const std::vector<std::vector<int>>& reg_idx,
                                                    int n_obs) {
  std::vector<double> pi(n_reg, 1.0 / n_reg);
  std::vector<double> pi_new(n_reg);
  
  const int max_iter = 1000;
  const double tol = 1e-10;
  
  for (int iter = 0; iter < max_iter; iter++) {
    for (int j = 0; j < n_reg; j++) {
      pi_new[j] = 0.0;
      for (int i = 0; i < n_reg; i++) {
        pi_new[j] += pi[i] * trans(i, j);
      }
    }
    
    double sum = 0.0;
    for (int j = 0; j < n_reg; j++) sum += pi_new[j];
    if (sum > 0) {
      for (int j = 0; j < n_reg; j++) pi_new[j] /= sum;
    }
    
    double diff = 0.0;
    for (int j = 0; j < n_reg; j++) {
      diff += std::abs(pi_new[j] - pi[j]);
    }
    pi = pi_new;
    if (diff < tol) break;
  }
  
  double sum = 0.0;
  for (int j = 0; j < n_reg; j++) {
    if (pi[j] < 0) pi[j] = 0;
    sum += pi[j];
  }
  
  if (sum <= 0 || std::isnan(sum)) {
    for (int j = 0; j < n_reg; j++) {
      pi[j] = (double)reg_idx[j].size() / n_obs;
    }
  } else {
    for (int j = 0; j < n_reg; j++) pi[j] /= sum;
  }
  
  return pi;
}


// [[Rcpp::export(name = ".boot_regime")]]
NumericMatrix boot_regime(NumericMatrix returns, IntegerVector regimes, NumericMatrix trans) {
  int n = returns.nrow();
  int k = returns.ncol();
  int n_reg = trans.nrow();
  NumericMatrix out(n, k);
  
  std::vector<std::vector<int>> reg_idx(n_reg);
  for (int i = 0; i < n; i++) {
    int r = regimes[i] - 1;
    if (r >= 0 && r < n_reg) reg_idx[r].push_back(i);
  }
  
  std::vector<double> start_p = stationary_distribution(trans, n_reg, reg_idx, n);
  
  double u = R::runif(0, 1);
  double cum = 0;
  int cur = 0;
  for (int r = 0; r < n_reg; r++) {
    cum += start_p[r];
    if (u <= cum) { cur = r; break; }
  }
  
  // Generate path
  for (int t = 0; t < n; t++) {
    const std::vector<int>* idx_ptr = &reg_idx[cur];
    
    if (idx_ptr->empty()) {
      for (int r = 0; r < n_reg; r++) {
        if (!reg_idx[r].empty()) { idx_ptr = &reg_idx[r]; break; }
      }
    }
    
    int i = (*idx_ptr)[(int)floor(R::runif(0, idx_ptr->size()))];
    for (int j = 0; j < k; j++) out(t, j) = returns(i, j);
    
    u = R::runif(0, 1);
    cum = 0;
    for (int r = 0; r < n_reg; r++) {
      cum += trans(cur, r);
      if (u <= cum) { cur = r; break; }
    }
  }
  
  return out;
}

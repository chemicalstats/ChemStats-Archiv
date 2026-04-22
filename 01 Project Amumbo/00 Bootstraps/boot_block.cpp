// boot_block.cpp
// @brief Moving Block Bootstrap (Künsch 1989; Liu & Singh 1992)
//
// @details
// Resamples contiguous blocks of fixed length L to preserve local
// temporal dependence within each block.
//
// Blocks start at uniformly sampled positions in {0, ..., n - L},
// following the non-circular scheme of Künsch (1989).
//
// Edge effects:
// Observations near the boundaries are slightly underrepresented.
// The last observation can only appear in blocks starting at n - L.
// This bias is negligible when n >> L (Lahiri 2003).
//
// Limitations:
// Does not generate a stationary bootstrap distribution
// (Politis & Romano 1994). This affects variance estimation,
// but typically not distribution estimation.
//
// @references
// - Künsch, H.R. (1989): The Jackknife and the Bootstrap for General
//   Stationary Observations. Annals of Statistics, 17(3): 1217–1241.
// - Liu, R.Y. & Singh, K. (1992): Moving Blocks Jackknife and Bootstrap
//   Capture Weak Dependence. Exploring the Limits of Bootstrap. Wiley.
// - Lahiri, S.N. (2003): Resampling Methods for Dependent Data. Springer.

#include <Rcpp.h>
#include <vector>
using namespace Rcpp;

// [[Rcpp::export(name = ".boot_block")]]
NumericMatrix boot_block(NumericMatrix returns, int block_length) {
  int n = returns.nrow();
  int k = returns.ncol();
  NumericMatrix out(n, k);
  
  if (block_length <= 0) Rcpp::stop("block_length must be positive");
  if (block_length > n) {
    Rcpp::warning("block_length (%d) > n (%d), using n", block_length, n);
    block_length = n;
  }
  
  int max_start = n - block_length;
  int i = 0;
  
  while (i < n) {
    int start = (int) floor(R::runif(0.0, max_start + 1));
    int len = std::min(block_length, n - i);
    
    for (int t = 0; t < len; t++) {
      for (int j = 0; j < k; j++) {
        out(i + t, j) = returns(start + t, j);
      }
    }
    i += len;
  }
  
  return out;
}

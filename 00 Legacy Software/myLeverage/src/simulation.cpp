#include <Rcpp.h>
#include <vector>
#include <string>
#include <algorithm>
#include <cmath>

using namespace Rcpp;

bool leap_year(int year) {
  return (year % 4 == 0 && (year % 100 != 0 || year % 400 == 0));
}

void parse_date(const std::string& date, int& year, int& month, int& day) {
  year = std::stoi(date.substr(0, 4));
  month = std::stoi(date.substr(5, 2));
  day = std::stoi(date.substr(8, 2));
}

std::string format_date(int year, int month, int day) {
  char buffer[11];
  snprintf(buffer, sizeof(buffer), "%04d-%02d-%02d", year, month, day);
  return std::string(buffer);
}

// [[Rcpp::export]]
List create_sequences(const std::vector<std::string>& dates, int span, Nullable<int> signal_a = R_NilValue, Nullable<int> signal_b = R_NilValue) {
  int max_sma = 1; 
  if (signal_a.isNotNull() || signal_b.isNotNull()) {
    int signal_a_val = signal_a.isNotNull() ? as<int>(signal_a) : 0;
    int signal_b_val = signal_b.isNotNull() ? as<int>(signal_b) : 0;
    max_sma = std::max(signal_a_val, signal_b_val);
  }
  
  std::vector<std::string> start_dates;
  std::vector<std::string> stop_dates;
  
  for (size_t x = max_sma - 1; x < dates.size(); ++x) {
    std::string start_date_str = dates[x];
    int start_year, start_month, start_day;
    parse_date(start_date_str, start_year, start_month, start_day);
    
    int stop_year = start_year + span;
    int stop_month = start_month;
    int stop_day = start_day - 1;
    
    if (start_month == 2 && start_day == 29 && !leap_year(stop_year)) {
      stop_day = 28;
    }
    
    if (stop_day < 1) {
      stop_month -= 1;
      if (stop_month < 1) {
        stop_year -= 1;
        stop_month = 12;
      }
      if (stop_month == 2) {
        stop_day = leap_year(stop_year) ? 29 : 28;
      } else if (stop_month == 4 || stop_month == 6 || stop_month == 9 || stop_month == 11) {
        stop_day = 30;
      } else {
        stop_day = 31;
      }
    }
    
    std::string stop_date_str = format_date(stop_year, stop_month, stop_day);
    
    if (stop_date_str <= dates.back()) {
      start_dates.push_back(start_date_str);
      stop_dates.push_back(stop_date_str);
    } else {
      break;
    }
  }
  
  return DataFrame::create(
    Named("start_date") = start_dates,
    Named("stop_date") = stop_dates
  );
}

// [[Rcpp::export]]
void dca_flows_allocation(List input, String name, double flows, int index) {
  List status = input[1];
  List report = input[4];
  
  List status_name = as<List>(status[name]);
  List report_name = as<List>(report[name]);
  
  NumericVector report_flows = as<NumericVector>(report_name[2]);
  report_flows[index - 1] = flows;
  report_name[2] = report_flows;
  
  double money = as<double>(status_name[3]);
  money += flows;
  status_name[3] = money;
  
  NumericVector report_money = as<NumericVector>(report_name[1]);
  report_money[index - 1] = money;
  report_name[1] = report_money;
  
  double worth = as<double>(status_name[2]);
  double total = money + worth;
  status_name[4] = total;
  
  NumericVector report_total = as<NumericVector>(report_name[3]);
  report_total[index - 1] = total;
  report_name[3] = report_total;
  
  report[name] = report_name;
  status[name] = status_name;
  input[4] = report;
  input[1] = status;
}

// [[Rcpp::export]]
void calculate_buy_report(List input, String name, int index, double trade_count, double trade_price, double market_price) {
  List status = input[1];
  List report = input[4];
  
  List status_name = status[name];
  List report_name = report[name];
  
  double count = status_name["count"];
  double money = status_name["money"];
  
  count += trade_count;
  status_name["count"] = count;
  
  status_name["price"] = market_price;
  
  double worth = count * market_price;
  status_name["worth"] = worth;
  
  money -= (trade_count * trade_price);
  status_name["money"] = money;
  
  double total = worth + money;
  status_name["total"] = total;
  
  status[name] = status_name;
  input[1] = status;
  
  NumericVector worth_vec = report_name["worth"];
  
  worth_vec[index - 1] = worth;
  report_name["worth"] = worth_vec;
  
  NumericVector money_vec = report_name["money"];
  
  money_vec[index - 1] = money;
  report_name["money"] = money_vec;
  
  NumericVector total_vec = report_name["total"];
  
  total_vec[index - 1] = total;
  report_name["total"] = total_vec;
  
  report[name] = report_name;
  input[4] = report;
}

// [[Rcpp::export]]
void calculate_sell_report(List input, String name, int index, double trade_count, double trade_price, double market_price, double capital_gains_tax) {
  List status = input[1];
  List report = input[4];
  
  List status_name = status[name];
  List report_name = report[name];
  
  double count = status_name["count"];
  double money = status_name["money"];
  
  count -= trade_count;
  status_name["count"] = count;
  
  status_name["price"] = market_price;
  
  double worth = count * market_price;
  status_name["worth"] = worth;
  
  money += (trade_count * trade_price) - capital_gains_tax;
  status_name["money"] = money;
  
  double total = worth + money;
  status_name["total"] = total;
  
  status[name] = status_name;
  input[1] = status;
  
  NumericVector worth_vec = report_name["worth"];
  
  worth_vec[index - 1] = worth;
  report_name["worth"] = worth_vec;
  
  NumericVector money_vec = report_name["money"];
  
  money_vec[index - 1] = money;
  report_name["money"] = money_vec;
  
  NumericVector total_vec = report_name["total"];
  
  total_vec[index - 1] = total;
  report_name["total"] = total_vec;
  
  report[name] = report_name;
  input[4] = report;
}

// [[Rcpp::export]]
void calculate_total_report(List input, CharacterVector assets, int index) {
  for (String name : assets) {
    List status = input[1];
    List market = input[2];
    List report = input[4];
    
    List status_name = as<List>(status[name]);
    List market_name = as<List>(market[name]);
    List report_name = as<List>(report[name]);
    
    NumericVector asset_price = as<NumericVector>(market_name[2]);
    double price = asset_price[index - 1];
    status_name[1] = price;
    
    double count = as<double>(status_name[0]);
    double worth = price * count;
    status_name[2] = worth;
    NumericVector report_worth = as<NumericVector>(report_name[0]);
    report_worth[index - 1] = worth;
    
    double money = as<double>(status_name[3]);
    NumericVector report_money = as<NumericVector>(report_name[1]);
    report_money[index - 1] = money;
    
    double total = money + worth;
    status_name[4] = total;
    NumericVector report_total = as<NumericVector>(report_name[3]);
    report_total[index - 1] = total;
  }
  
  double total_worth = 0.0;
  List status = input[1];
  
  for (String name : assets) {
    List status_name = as<List>(status[name]);
    total_worth += as<double>(status_name[4]);
  }
  
  List report = input[4];
  
  for (String name : assets) {
    List status_name = as<List>(status[name]);
    List report_name = as<List>(report[name]);
    
    double total = as<double>(status_name[4]);
    double actual = total / total_worth;
    status_name[7] = actual;
    
    NumericVector report_share = as<NumericVector>(report_name[4]);
    report_share[index - 1] = actual;
    
    double target = as<double>(status_name[6]);
    status_name[8] = actual - target;
  }
}
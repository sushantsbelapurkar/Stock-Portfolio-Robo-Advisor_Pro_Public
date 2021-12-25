drop table mysql_portfolio.rate_of_return_info;
create table mysql_portfolio.rate_of_return_info as
WITH _rate_or_return as
(
 SELECT symbol,year(date) as year, date,close,-- LAST_VALUE(close) over(partition by symbol,year(date) order by date),
-- FIRST_VALUE(close) over(partition by symbol,year(date) order by date),
 (LAST_VALUE(close) over(partition by symbol,year(date) order by date)- FIRST_VALUE(close) over(partition by symbol,year(date) order by date))
 /(FIRST_VALUE(close) over(partition by symbol,year(date) order by date))*100 as ror,
 row_number() over (partition by symbol,year(date)) as row_numb,curdate() as created_at
  FROM mysql_portfolio.historical_prices order by 1,3 desc
 -- WHERE symbol IN ('AAPL','MSFT') order by 1,3 desc
 ),
 _rate_or_return1 as
 (
 SELECT symbol,year,date as latest_date,round(ror,2) as rate_of_return,row_numb, rank() over(partition by symbol, year order by row_numb desc) as rank_
 FROM _rate_or_return order by symbol,year desc
 )SELECT symbol,year,latest_date,rate_of_return FROM _rate_or_return1 WHERE rank_ = 1
;

SELECT * FROM mysql_portfolio.rate_of_return_info;

DROP TABLE mysql_portfolio.avg_std_dev;
CREATE TABLE mysql_portfolio.avg_std_dev AS
 WITH avg_stdev AS
 (
 SELECT *,
 round(avg(rate_of_return) over(partition by symbol),2) as avg_return,
 round(stddev(rate_of_return) over(partition by symbol),2) as std_dev FROM mysql_portfolio.rate_of_return_info order by symbol,year desc
 ),
 yr_count as
 (
 SELECT distinct symbol,count(year) as count_of_years_considered  FROM avg_stdev group by 1
 )
 SELECT DISTINCT avg_stdev.symbol,MAX(avg_stdev.latest_date) over(partition by symbol)as latest_price_date,avg_stdev.avg_return,
 avg_stdev.std_dev as volatility,
 yr_count.count_of_years_considered
 FROM avg_stdev
 LEFT JOIN yr_count
 ON yr_count.symbol = avg_stdev.symbol ;

 SELECT * FROM mysql_portfolio.avg_std_dev;


 drop table mysql_portfolio.expected_rate_of_return;
 TRUNCATE mysql_portfolio.expected_rate_of_return;
 CREATE table mysql_portfolio.expected_rate_of_return
(
  -- id int not null auto_increment,
  symbol varchar(250) null,
  year int,
  possible_return_true float(5,2),
  probability_true decimal(4,2),
  possible_return_positive float(5,2),
  probability_positive decimal(4,2),
  possible_return_negative float(5,2),
  probability_negative decimal(4,2),
  expected_rate_of_return float(5,2)
  -- float(n,n) specifies approximate whereas decimal(n,n) specifies exact decimal places
);

 INSERT INTO mysql_portfolio.expected_rate_of_return
 (
 symbol,year,possible_return_true,probability_true,
 possible_return_positive,probability_positive,
 possible_return_negative,probability_negative,expected_rate_of_return
 )
 SELECT symbol,year(latest_price_date),
 round(avg_return,2) , 0.5,
 round(avg_return+avg_return*0.05,2),0.2,
 round(avg_return-avg_return*0.15,2),0.3,
 round((0.5*round(avg_return,2))
 +(0.2*round(avg_return+avg_return*0.05,2))+(0.3*round(avg_return-avg_return*0.15,2)),2)

 FROM mysql_portfolio.avg_std_dev
--  WHERE year = (SELECT MAX(year(latest_price_date)) FROM mysql_portfolio.avg_std_dev)
 ;

 SELECT * FROM mysql_portfolio.expected_rate_of_return;

 -- TAKE 10YRS RISK FREE RATE
 drop table mysql_portfolio.risk_free_rate;
 TRUNCATE TABLE mysql_portfolio.risk_free_rate;
 CREATE TABLE mysql_portfolio.risk_free_rate
 (
  latest_date date,
  t_bill_rate float(4,2)
  );
 SELECT * FROM mysql_portfolio.risk_free_rate;
 LOAD XML LOCAL INFILE '/Users/sushantbelapurkar/downloads/SUSHANT/XmlView.xml'
INTO TABLE mysql_portfolio.risk_free_rate(latest_date, t_bill_rate);
SHOW GLOBAL VARIABLES LIKE 'local_infile';
SET GLOBAL local_infile = true;

 INSERT INTO mysql_portfolio.risk_free_rate (latest_date, t_bill_rate)values ('2021-12-25',1.5);
 SELECT * FROM mysql_portfolio.risk_free_rate;

 SELECT DISTINCT rate.symbol,rate.expected_rate_of_return,rate.risk_free_rate,
 (rate.expected_rate_of_return-rate.risk_free_rate) as equity_risk_premium,stock_screener.beta,
 round((rate.risk_free_rate + (rate.expected_rate_of_return-rate.risk_free_rate)*stock_screener.beta),2) as cost_of_equity
 FROM(
 SELECT symbol,expected_rate_of_return,
 (SELECT t_bill_rate FROM mysql_portfolio.risk_free_rate WHERE latest_date = (SELECT MAX(latest_date) FROM mysql_portfolio.risk_free_rate))
 as risk_free_rate FROM mysql_portfolio.expected_rate_of_return
 )rate
 LEFT JOIN mysql_portfolio.stock_screener ON
 rate.symbol = stock_screener.symbol;

 -- ABOVE SAME QUERY CAN BE WRITTEN/SIMPLIFIED AS

 DROP TABLE mysql_portfolio.cost_of_equity;
 CREATE TABLE mysql_portfolio.cost_of_equity AS
 (
 WITH rate as
 (
 SELECT symbol,expected_rate_of_return,
 (SELECT t_bill_rate FROM mysql_portfolio.risk_free_rate WHERE latest_date = (SELECT MAX(latest_date) FROM mysql_portfolio.risk_free_rate))
 as risk_free_rate FROM mysql_portfolio.expected_rate_of_return
 )
 SELECT DISTINCT rate.symbol,rate.expected_rate_of_return,rate.risk_free_rate,
 (rate.expected_rate_of_return-rate.risk_free_rate) as equity_risk_premium,stock_screener.beta,
 round((rate.risk_free_rate + (rate.expected_rate_of_return-rate.risk_free_rate)*stock_screener.beta),2) as cost_of_equity
 FROM rate
 LEFT JOIN mysql_portfolio.stock_screener ON
 rate.symbol = stock_screener.symbol
 );
SELECT * FROM mysql_portfolio.cost_of_equity;

DROP TABLE mysql_portfolio.cost_of_debt;
CREATE TABLE mysql_portfolio.cost_of_debt AS
WITH balance_sheet_row_num AS
(
 SELECT *,row_number() over (partition by symbol order by calendarYear) as row_numb FROM mysql_portfolio.balance_sheet
 ),
balance_sheet_max as
  (
  SELECT symbol, max(row_numb) as max_row_numb FROM balance_sheet_row_num group by 1
  ),
balance_sheet_maxyr AS
(
 SELECT balance_sheet_row_num.symbol,balance_sheet_row_num.netDebt
 FROM balance_sheet_max LEFT JOIN balance_sheet_row_num
 ON balance_sheet_max.symbol = balance_sheet_row_num.symbol
 AND balance_sheet_row_num.row_numb = balance_sheet_max.max_row_numb
 ),
 income_statement_row_num AS
(
 SELECT *,row_number() over (partition by symbol order by calendarYear) as row_numb FROM mysql_portfolio.income_statement
 ),
income_statement_max as
  (
  SELECT symbol, max(row_numb) as max_row_numb FROM income_statement_row_num group by 1
  ),
income_statement_maxyr AS
(
 SELECT income_statement_row_num.symbol,income_statement_row_num.date,income_statement_row_num.interestExpense,
 income_statement_row_num.ebitda,income_statement_row_num.depreciationAndAmortization,income_statement_row_num.incomeTaxExpense
 FROM income_statement_max LEFT JOIN income_statement_row_num
 ON income_statement_max.symbol = income_statement_row_num.symbol
 AND income_statement_row_num.row_numb = income_statement_max.max_row_numb
 ),
 cost_of_debt_temp AS
(
 SELECT income_statement.symbol,income_statement.date,
 (income_statement.interestExpense/balance_sheet.netDebt) as cost_of_debt,
(income_statement.ebitda - income_statement.depreciationAndAmortization) as ebit,
(income_statement.incomeTaxExpense/(income_statement.ebitda - income_statement.depreciationAndAmortization)) as effective_tax_rate
FROM income_statement_maxyr income_statement
LEFT JOIN balance_sheet_maxyr balance_sheet
ON income_statement.symbol = balance_sheet.symbol
)
SELECT symbol,date, ebit,effective_tax_rate,round((cost_of_debt * (1- effective_tax_rate))*100,2) as after_tax_cost_of_debt
FROM cost_of_debt_temp;

SELECT * FROM mysql_portfolio.cost_of_debt;


DROP TABLE mysql_portfolio.debt_to_equity_ratio;
CREATE TABLE mysql_portfolio.debt_to_equity_ratio AS
WITH balance_sheet_row_num AS
(
 SELECT *,row_number() over (partition by symbol order by calendarYear) as row_numb FROM mysql_portfolio.balance_sheet
 ),
balance_sheet_max as
  (
  SELECT symbol, max(row_numb) as max_row_numb FROM balance_sheet_row_num group by 1
  ),
balance_sheet_maxyr AS
(
 SELECT balance_sheet_row_num.symbol,balance_sheet_row_num.date,balance_sheet_row_num.shortTermDebt,balance_sheet_row_num.longTermDebt,
 balance_sheet_row_num.totalStockholdersEquity,balance_sheet_row_num.totalAssets,balance_sheet_row_num.totalLiabilities
 FROM balance_sheet_max LEFT JOIN balance_sheet_row_num
 ON balance_sheet_max.symbol = balance_sheet_row_num.symbol
 AND balance_sheet_row_num.row_numb = balance_sheet_max.max_row_numb
 ),
debt_to_equity AS
(
SELECT symbol,date,((shortTermDebt+longTermDebt)/(shortTermDebt+longTermDebt+totalStockholdersEquity)) as debt_to_capitalization,
((totalAssets - totalLiabilities)/(longTermDebt + totalStockholdersEquity)) as equity_to_capitalization
FROM balance_sheet_maxyr
)
SELECT symbol,date,debt_to_capitalization,equity_to_capitalization,
round((debt_to_capitalization/equity_to_capitalization),2) as debt_to_equity_ratio FROM debt_to_equity;

SELECT * FROM mysql_portfolio.debt_to_equity_ratio;

DROP TABLE mysql_portfolio.wacc_data;
CREATE TABLE mysql_portfolio.wacc_data AS
SELECT debt_to_equity_ratio.symbol,debt_to_equity_ratio.date,debt_to_equity_ratio.debt_to_capitalization, debt_to_equity_ratio.equity_to_capitalization,
cost_of_equity.cost_of_equity,cost_of_debt.after_tax_cost_of_debt,
round((cost_of_equity.cost_of_equity*debt_to_equity_ratio.equity_to_capitalization) +
(cost_of_debt.after_tax_cost_of_debt*debt_to_equity_ratio.debt_to_capitalization),2)
as wacc
FROM mysql_portfolio.debt_to_equity_ratio
LEFT JOIN mysql_portfolio.cost_of_equity
ON cost_of_equity.symbol = debt_to_equity_ratio.symbol
LEFT JOIN mysql_portfolio.cost_of_debt
ON cost_of_debt.symbol = debt_to_equity_ratio.symbol
;

SELECT * FROM mysql_portfolio.wacc_data;

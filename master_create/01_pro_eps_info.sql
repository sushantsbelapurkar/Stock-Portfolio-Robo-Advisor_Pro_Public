-- ---------- eps calculation for last 5 years--------------------
DROP PROCEDURE IF EXISTS mysql_portfolio.eps_info;
DELIMITER //
CREATE PROCEDURE mysql_portfolio.eps_info (
IN exchangeName varchar(255)
) 
BEGIN
 DROP TABLE IF EXISTS mysql_portfolio.eps_info;
 create table mysql_portfolio.eps_info as   
 WITH eps_growth AS
 (
 SELECT inc.symbol,inc.calendarYear,inc.eps, lag(inc.eps) over (partition by inc.symbol order by inc.calendarYear) as prev_eps, 
CASE WHEN inc.eps > lag(inc.eps) over (partition by inc.symbol order by inc.calendarYear) THEN 1 ELSE 0 END AS eps_growth,
round(avg(inc.eps) over(partition by inc.symbol order by inc.calendarYear rows between unbounded preceding and unbounded following),2) as avg_eps,
row_number() over (partition by inc.symbol order by inc.calendarYear) as row_numb, curdate() as created_at 
  FROM mysql_portfolio.income_statement inc
  INNER JOIN mysql_portfolio.symbol_list
  on symbol_list.symbol = inc.symbol
 and symbol_list.exchangeShortName = exchangeName
 WHERE inc.calendarYear >= YEAR(DATE_SUB(CURDATE(), INTERVAL 4 YEAR)) -- in redshift we use dateadd() function to do the same; mysql also have date_add() for future dates
 -- order by 1,2 desc
 ),
 eps_details as
 (
 SELECT *, 
 CASE WHEN sum(eps_growth) over(partition by symbol order by calendarYear rows between unbounded preceding and unbounded following) >=3
THEN 1 ELSE 0 END AS positive_eps_growth_3yrs FROM eps_growth
 ),
 max_row as
 ( 
  SELECT symbol, max(row_numb) as max_row_numb FROM eps_details GROUP BY 1
 )
 SELECT eps_details.symbol, eps_details.calendarYear, eps_details.eps as ttm_eps, 
 eps_details.eps_growth as recent_eps_growth,eps_details.positive_eps_growth_3yrs, eps_details.avg_eps as _5yr_avg_eps,
 CURDATE() as created_at
--  max_row.max_row_numb
 FROM eps_details 
 LEFT JOIN max_row
 ON max_row.symbol = eps_details.symbol
 WHERE eps_details.row_numb = max_row.max_row_numb order by 1,2
 ;
 SELECT count(*) from mysql_portfolio.eps_info;
 END //
 DELIMITER ; 

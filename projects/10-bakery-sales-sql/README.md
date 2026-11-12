# Bakery Sales Analysis in SQL

From *Database Fundamentals*, Master of Business Analytics, Schulich School of Business (Summer 2026). The assignment was set for teams: each member wrote a full solution, and the team compared them before submitting. This is my own version.

## Problem

A bakery records every item sold at the till. The owner wants to know what sells, when the shop is busiest, and whether the data can be trusted.

## Data

A point-of-sale table with one row per item sold: date, time, ticket number, item name, quantity and unit price. The course database is not public, so only the queries are included.

## Questions and techniques

[`bakery_sales_analysis.sql`](bakery_sales_analysis.sql) answers five questions in PostgreSQL.

| # | Question | Technique |
|---|---|---|
| 1 | Which three items sell most in each month? | Aggregate in a CTE, then `ROW_NUMBER() OVER (PARTITION BY year, month)` |
| 2 | Which December 2021 tickets held five or more different items? | `COUNT(DISTINCT ...)` with `HAVING` |
| 3 | At what hour are most traditional baguettes sold in July? | `DATE_PART`, ordering with a tie-break |
| 4 | Which two-hour window is the busiest of the day? | `LEAD()` to add each hour to the next, then rank |
| 5 | Is the data clean? | Checks for missing values, duplicate rows, negative amounts, placeholder item names and outliers |

## Design choices

- **Aggregate before ranking.** Question 1 first reduces the table to one row per item and month, so the ranking runs on a small result instead of every sale.
- **Half-open date ranges.** December is selected with `>= '2021-12-01' AND < '2022-01-01'`, which stays correct whether the column holds dates or timestamps.
- **Deterministic answers.** Where two hours could tie, the earlier one wins, so the query always returns the same row.
- **Quality checks come with the analysis.** Negative quantities and a placeholder item name (`.`) would distort totals, so they are surfaced, not silently dropped.

# Coffee Shop Sales Analysis — Access database + Excel decision models

Team project (three people) for *Introduction to Data Analysis and Programming* (NCCU, Spring 2024).

## Problem

Maven Roasters is a fictional coffee chain with three New York locations. Given its transaction log, how should it manage orders day to day, and where is the profit?

## Data

The public *Coffee Shop Sales* dataset from Kaggle (Maven Analytics): transaction date and time, store, product category, type, quantity and unit price. We recoded store IDs, standardised date formats, removed duplicates and outliers, and added a total-sales column.

## What we built

**Access database**
- Four related tables: products, staff, stores, transactions.
- A data-entry form for new orders with navigation, add and delete buttons.
- Queries: top five orders by value; orders and responsible staff for a date range (parameter query); sales per employee over a period.
- A report of each employee's orders by store, date, quantity and amount.

**Excel models**
- Pivot tables across sheets for product sales, staff performance and sales by time of day per store.
- Data table: how many monthly orders each store needs to protect profit as ingredient cost rises.
- Scenario analysis: best combination of bean cost, quantity and coffee price.
- Solver: the profit-maximising Christmas bundle.

## Findings

- Queens is the largest market; Brooklyn has the most room to grow.
- The optimised Christmas bundle earns about $67 profit per bundle sold.

## Files

The database and workbooks are large binary files and the report lists teammates' student IDs, so they are not in this repository. Available on request.

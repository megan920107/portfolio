# Customer360: A Weekly Customer History in SQL

Team project from *Database Fundamentals*, Master of Business Analytics, Schulich School of Business (Summer 2026).

## Problem

Marketing and finance teams ask the same questions about every customer: when did they convert, what did they buy first, how much have they spent since, and are they still active? The answers sit in separate fact and dimension tables. A Customer360 table puts them in one place.

## What the query builds

One row per customer, per conversion, per week, from the conversion week onward:

| Column group | Contents |
|---|---|
| Customer and conversion | Name, conversion number, type, channel, date and week |
| First order | Week and amount of the first order after the conversion |
| Weekly activity | Orders placed, value before discounts, discounts, amount paid (zero when there was no order) |
| Running totals | Revenue since this conversion, and revenue over the customer's lifetime |

Source tables: `fact_tables.conversions`, `fact_tables.orders`, and the customer, product and date dimensions of a star schema.

## How it works

[`customer360.sql`](customer360.sql) is a single PostgreSQL query made of eight common table expressions.

1. **Number the conversions.** `ROW_NUMBER()` orders each customer's conversions, and `LEAD()` finds the next one, which marks where the current conversion period ends.
2. **Roll up orders** from line items to one row per order.
3. **Find the last observed week**, so the timeline stops where the data stops.
4. **Assign each order to a conversion**: the one that was active on the order date.
5. **Pick the first order** per conversion with `ROW_NUMBER()`.
6. **Aggregate orders to conversion-week level.**
7. **Generate the weekly timeline** by joining each conversion to the date dimension.
8. **Join and accumulate** with `SUM() OVER (...)` for both running totals.

## Decisions we had to make

- **Where the timeline ends.** Extending it to the last week in the date dimension produced long runs of empty weeks. We stopped at the last week with any order, which keeps the table focused on observed history.
- **Avoiding double-counted revenue.** Joining orders straight onto the weekly timeline repeats order rows. Orders are aggregated to one row per conversion and week first (step 6), then joined.
- **Keeping incomplete records.** One conversion has no matching customer in the customer dimension. It stays in the output with empty customer fields, because dropping it would hide a data-quality problem.
- **Weeks without orders** are filled with zeros using `COALESCE()` so the running totals stay continuous.

## Data

The course database is not public, so only the query is included here.

-- Bakery sales analysis
--
-- Five business questions answered on a point-of-sale table with one row per
-- item sold: sale_date, sale_time, ticket_number, article, quantity, unit_price.
--
-- Written for PostgreSQL.

-- ---------------------------------------------------------------------------
-- 1. Top three best-selling items in every month
--    Aggregate to item-month first, then rank inside each month.
-- ---------------------------------------------------------------------------

WITH item_month AS (
    SELECT
        DATE_PART('year', sale_date) AS sale_year,
        DATE_PART('month', sale_date) AS sale_month,
        article,
        SUM(quantity) AS total_quantity_sold,
        SUM(quantity * unit_price) AS total_revenue,
        COUNT(DISTINCT ticket_number) AS unique_tickets
    FROM assignment01.bakery_sales
    GROUP BY
        DATE_PART('year', sale_date),
        DATE_PART('month', sale_date),
        article
),

ranked_items AS (
    SELECT
        sale_year,
        sale_month,
        article,
        total_quantity_sold,
        total_revenue,
        unique_tickets,
        ROW_NUMBER() OVER (
            PARTITION BY sale_year, sale_month
            ORDER BY total_quantity_sold DESC
        ) AS item_rank
    FROM item_month
)

SELECT
    sale_year,
    sale_month,
    article,
    total_quantity_sold,
    total_revenue,
    unique_tickets
FROM ranked_items
WHERE item_rank <= 3
ORDER BY sale_year, sale_month, item_rank;

-- ---------------------------------------------------------------------------
-- 2. Large baskets: December 2021 tickets with five or more different items
-- ---------------------------------------------------------------------------

SELECT
    ticket_number AS ticket_id,
    COUNT(DISTINCT article) AS number_of_unique_articles
FROM assignment01.bakery_sales
WHERE sale_date >= '2021-12-01'
  AND sale_date < '2022-01-01'
GROUP BY ticket_number
HAVING COUNT(DISTINCT article) >= 5
ORDER BY number_of_unique_articles DESC, ticket_id;

-- ---------------------------------------------------------------------------
-- 3. The hour of day when most traditional baguettes are sold in July
--    Ties are broken in favour of the earlier hour.
-- ---------------------------------------------------------------------------

SELECT
    DATE_PART('hour', sale_time) AS sale_hour,
    SUM(quantity) AS total_quantity_sold
FROM assignment01.bakery_sales
WHERE article = 'TRADITIONAL BAGUETTE'
  AND DATE_PART('month', sale_date) = 7
GROUP BY DATE_PART('hour', sale_time)
ORDER BY
    SUM(quantity) DESC,
    DATE_PART('hour', sale_time) ASC
LIMIT 1;

-- ---------------------------------------------------------------------------
-- 4. Busiest two-hour window of the day
--    LEAD() adds each hour to the hour after it. This assumes every opening
--    hour has at least one sale, so consecutive rows are consecutive hours.
-- ---------------------------------------------------------------------------

WITH hourly_sales AS (
    SELECT
        DATE_PART('hour', sale_time) AS sale_hour,
        SUM(quantity) AS hourly_quantity,
        SUM(quantity * unit_price) AS hourly_revenue
    FROM assignment01.bakery_sales
    GROUP BY DATE_PART('hour', sale_time)
),

two_hour_sales AS (
    SELECT
        sale_hour AS start_hour,
        sale_hour + 2 AS end_hour,
        hourly_quantity + LEAD(hourly_quantity) OVER (ORDER BY sale_hour) AS two_hour_quantity,
        hourly_revenue + LEAD(hourly_revenue) OVER (ORDER BY sale_hour) AS two_hour_revenue
    FROM hourly_sales
),

ranked_sales AS (
    SELECT
        start_hour,
        end_hour,
        two_hour_quantity,
        two_hour_revenue,
        ROW_NUMBER() OVER (
            ORDER BY two_hour_quantity DESC
        ) AS rank_number
    FROM two_hour_sales
    WHERE two_hour_quantity IS NOT NULL
)

SELECT
    start_hour,
    end_hour,
    two_hour_quantity,
    two_hour_revenue
FROM ranked_sales
WHERE rank_number = 1;

-- ---------------------------------------------------------------------------
-- 5. Data quality checks
-- ---------------------------------------------------------------------------

-- 5a. Missing values in the columns every query depends on

SELECT
    SUM(CASE WHEN sale_date IS NULL THEN 1 ELSE 0 END) AS missing_sale_date,
    SUM(CASE WHEN sale_time IS NULL THEN 1 ELSE 0 END) AS missing_sale_time,
    SUM(CASE WHEN ticket_number IS NULL THEN 1 ELSE 0 END) AS missing_ticket_number,
    SUM(CASE WHEN article IS NULL THEN 1 ELSE 0 END) AS missing_article,
    SUM(CASE WHEN quantity IS NULL THEN 1 ELSE 0 END) AS missing_quantity,
    SUM(CASE WHEN unit_price IS NULL THEN 1 ELSE 0 END) AS missing_unit_price
FROM assignment01.bakery_sales;

-- 5b. Exact duplicate rows

SELECT
    sale_date,
    sale_time,
    ticket_number,
    article,
    quantity,
    unit_price,
    COUNT(*) AS duplicate_count
FROM assignment01.bakery_sales
GROUP BY
    sale_date,
    sale_time,
    ticket_number,
    article,
    quantity,
    unit_price
HAVING COUNT(*) > 1;

-- 5c. Negative quantities or prices (refunds and data-entry errors)

SELECT
    *
FROM assignment01.bakery_sales
WHERE quantity < 0
   OR unit_price < 0;

-- 5d. Placeholder or missing item names

SELECT
    article,
    COUNT(*) AS record_count
FROM assignment01.bakery_sales
WHERE article IS NULL
   OR article = '.'
GROUP BY article;

-- 5e. Ten largest quantities, to review by eye

WITH quantity_rank AS (
    SELECT
        sale_date,
        sale_time,
        ticket_number,
        article,
        quantity,
        unit_price,
        ROW_NUMBER() OVER (
            ORDER BY quantity DESC
        ) AS rank_number
    FROM assignment01.bakery_sales
)

SELECT
    sale_date,
    sale_time,
    ticket_number,
    article,
    quantity,
    unit_price
FROM quantity_rank
WHERE rank_number <= 10;

-- 5f. Ten highest unit prices, to review by eye

WITH price_rank AS (
    SELECT
        sale_date,
        sale_time,
        ticket_number,
        article,
        quantity,
        unit_price,
        ROW_NUMBER() OVER (
            ORDER BY unit_price DESC
        ) AS rank_number
    FROM assignment01.bakery_sales
)

SELECT
    sale_date,
    sale_time,
    ticket_number,
    article,
    quantity,
    unit_price
FROM price_rank
WHERE rank_number <= 10;

-- Customer360: one row per customer, per conversion, per week
--
-- Builds a weekly history for every customer conversion (a sign-up or
-- re-activation) from a star schema: conversions and orders fact tables plus
-- customer, product and date dimensions.
--
-- Output columns include the first order after each conversion, weekly order
-- activity (zero-filled for weeks with no orders) and two running totals:
-- revenue since this conversion and revenue over the customer's lifetime.
--
-- Dialect: PostgreSQL.

-- 1. Every conversion with its sequence number per customer and the date of
--    the customer's next conversion, which marks where this one ends.
WITH conversion_base AS (

    SELECT
        c.conversion_id,
        c.fk_customer,
        cd.customer_id,
        cd.first_name,
        cd.last_name,
        c.conversion_date,
        d.year_week AS conversion_week,
        d.running_week AS conversion_running_week,

        ROW_NUMBER() OVER (
            PARTITION BY c.fk_customer
            ORDER BY c.conversion_date, c.conversion_id
        ) AS conversion_number,

        c.conversion_type,
        c.conversion_channel,

        LEAD(c.conversion_date) OVER (
            PARTITION BY c.fk_customer
            ORDER BY c.conversion_date, c.conversion_id
        ) AS next_conversion_date,

        LEAD(d.year_week) OVER (
            PARTITION BY c.fk_customer
            ORDER BY c.conversion_date, c.conversion_id
        ) AS next_conversion_week,

        LEAD(d.running_week) OVER (
            PARTITION BY c.fk_customer
            ORDER BY c.conversion_date, c.conversion_id
        ) AS next_conversion_running_week

    FROM fact_tables.conversions AS c

    LEFT JOIN dimensions.customer_dimension AS cd
        ON c.fk_customer = cd.sk_customer

    LEFT JOIN dimensions.date_dimension AS d
        ON c.fk_conversion_date = d.sk_date
),


-- 2. Orders rolled up from line items to one row per order.
orders_base AS (

    SELECT
        o.order_id,
        o.order_number,
        o.fk_customer,
        o.order_date,

        d.year_week AS order_week,
        d.running_week AS order_running_week,

        SUM(o.unit_price) AS order_total_before_discounts,
        SUM(o.discount_value) AS order_total_discounts,
        SUM(o.price_paid) AS order_total_paid

    FROM fact_tables.orders AS o

    LEFT JOIN dimensions.date_dimension AS d
        ON o.fk_order_date = d.sk_date

    LEFT JOIN dimensions.product_dimension AS p
        ON o.fk_product = p.sk_product

    GROUP BY
        o.order_id,
        o.order_number,
        o.fk_customer,
        o.order_date,
        d.year_week,
        d.running_week
),


-- 3. The last week that has any order: the weekly timeline stops here.
data_limits AS (

    SELECT
        MAX(order_running_week) AS max_running_week
    FROM orders_base
),


-- 4. Attach each order to the conversion that was active when it was placed.
conversion_orders AS (

    SELECT
        cb.conversion_id,
        cb.fk_customer,
        cb.customer_id,
        cb.conversion_number,

        cb.conversion_date,
        cb.conversion_week,
        cb.conversion_running_week,
        cb.next_conversion_date,
        cb.next_conversion_week,
        cb.next_conversion_running_week,

        ob.order_id,
        ob.order_number,
        ob.order_date,
        ob.order_week,
        ob.order_running_week,

        ob.order_total_before_discounts,
        ob.order_total_discounts,
        ob.order_total_paid

    FROM conversion_base AS cb

    INNER JOIN orders_base AS ob
        ON cb.fk_customer = ob.fk_customer

    WHERE ob.order_date >= cb.conversion_date
      AND (
            cb.next_conversion_date IS NULL
            OR ob.order_date < cb.next_conversion_date
          )
),


-- 5. The first order after each conversion.
first_order AS (

    SELECT
        conversion_id,
        first_order_week,
        first_order_total_paid

    FROM (
        SELECT
            conversion_id,
            order_week AS first_order_week,
            order_total_paid AS first_order_total_paid,

            ROW_NUMBER() OVER (
                PARTITION BY conversion_id
                ORDER BY order_date, order_id
            ) AS rn

        FROM conversion_orders
    ) AS t

    WHERE rn = 1
),


-- 6. Orders aggregated to conversion-week level BEFORE joining to the weekly
--    timeline, so revenue is never double-counted.
weekly_order_summary AS (

    SELECT
        conversion_id,
        fk_customer,
        order_week,
        order_running_week,

        1 AS orders_placed,

        SUM(order_total_before_discounts) AS total_before_discounts,
        SUM(order_total_discounts) AS total_discounts,
        SUM(order_total_paid) AS total_paid_in_week

    FROM conversion_orders

    GROUP BY
        conversion_id,
        fk_customer,
        order_week,
        order_running_week
),


-- 7. One row per week from the conversion week until the week before the next
--    conversion (or the last observed order week).
conversion_weeks AS (

    SELECT DISTINCT
        cb.conversion_id,
        cb.fk_customer,
        cb.customer_id,
        cb.first_name,
        cb.last_name,

        cb.conversion_number,
        cb.conversion_type,
        cb.conversion_date,
        cb.conversion_week,
        cb.conversion_running_week,

        cb.next_conversion_week,
        cb.next_conversion_running_week,
        cb.conversion_channel,

        d.year_week AS order_week,
        d.running_week AS order_running_week

    FROM conversion_base AS cb

    CROSS JOIN data_limits AS dl

    INNER JOIN dimensions.date_dimension AS d
        ON d.running_week >= cb.conversion_running_week
       AND d.running_week <= dl.max_running_week
       AND (
            cb.next_conversion_running_week IS NULL
            OR d.running_week < cb.next_conversion_running_week
       )
),


-- 8. Combine the timeline with weekly orders and add the running totals.
final_customer360 AS (

    SELECT
        cw.customer_id,
        cw.first_name,
        cw.last_name,

        cw.conversion_id,
        cw.conversion_number,
        cw.conversion_type,
        cw.conversion_date,
        cw.conversion_week,
        cw.next_conversion_week,
        cw.conversion_channel,

        fo.first_order_week,
        COALESCE(fo.first_order_total_paid, 0) AS first_order_total_paid,

        ROW_NUMBER() OVER (
            PARTITION BY cw.conversion_id
            ORDER BY cw.order_running_week
        ) AS week_counter,

        cw.order_week,

        COALESCE(wos.orders_placed, 0) AS orders_placed,
        COALESCE(wos.total_before_discounts, 0) AS total_before_discounts,
        COALESCE(wos.total_discounts, 0) AS total_discounts,
        COALESCE(wos.total_paid_in_week, 0) AS total_paid_in_week,

        SUM(COALESCE(wos.total_paid_in_week, 0)) OVER (
            PARTITION BY cw.conversion_id
            ORDER BY cw.order_running_week
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS conversion_cumulative_revenue,

        SUM(COALESCE(wos.total_paid_in_week, 0)) OVER (
            PARTITION BY cw.customer_id
            ORDER BY cw.order_running_week, cw.conversion_number
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS lifetime_cumulative_revenue

    FROM conversion_weeks AS cw

    LEFT JOIN weekly_order_summary AS wos
        ON cw.conversion_id = wos.conversion_id
       AND cw.order_running_week = wos.order_running_week

    LEFT JOIN first_order AS fo
        ON cw.conversion_id = fo.conversion_id
)


SELECT *
FROM final_customer360
ORDER BY customer_id, conversion_number, week_counter;

/*
===============================================================================
AVIATION PROCUREMENT KPI DASHBOARD
Portfolio SQL 03 - Repair Order Creation Trend
===============================================================================

Purpose
-------
Demonstrates the SQL model behind the Power BI Repair Order creation trend.

This sanitized version preserves the architecture of the production model:
- Created RO counts use the Repair Order header as the source of truth
- Cancelled ROs are excluded from operational created counts
- A RO is closed when either the RO or at least one ROL is Received/Vouchered
- One detail table feeds yearly and monthly Power BI summaries
===============================================================================
*/


/* ---------------------------------------------------------------------------
   1. AGGREGATE REPAIR-ORDER-LINE STATUS TO REPAIR ORDER
--------------------------------------------------------------------------- */

DROP TABLE IF EXISTS analytics.rol_status_by_ro;

CREATE TABLE analytics.rol_status_by_ro AS
SELECT
    rol.repair_order_id,

    COUNT(DISTINCT rol.repair_order_line_id)
        AS rol_count,

    MAX(
        CASE
            WHEN UPPER(TRIM(COALESCE(rol.status, '')))
                 IN ('RECEIVED', 'VOUCHERED')
            THEN 1 ELSE 0
        END
    ) AS has_closed_rol_status

FROM source.repair_order_line rol

WHERE rol.is_deleted = 0
  AND rol.repair_order_id IS NOT NULL

GROUP BY
    rol.repair_order_id;

ALTER TABLE analytics.rol_status_by_ro
    ADD INDEX idx_rol_status_ro (repair_order_id);


/* ---------------------------------------------------------------------------
   2. CREATE ONE SOURCE ROW PER REPAIR ORDER

   Important modelling decision:
   created-order counts come directly from Repair Order headers rather than
   from the KPI fact table. This prevents the KPI grain from distorting the
   historical creation count.
--------------------------------------------------------------------------- */

DROP TABLE IF EXISTS analytics.ro_created_detail;

CREATE TABLE analytics.ro_created_detail AS
SELECT
    ro.repair_order_id,
    ro.repair_order_number,
    ro.status,
    ro.vendor_name,

    DATE(ro.created_at) AS ro_created_date,
    YEAR(ro.created_at) AS ro_created_year,
    MONTH(ro.created_at) AS ro_created_month_number,
    DATE_FORMAT(ro.created_at, '%Y-%m') AS ro_created_year_month,
    DATE(DATE_FORMAT(ro.created_at, '%Y-%m-01')) AS ro_created_month_date,

    CASE
        WHEN UPPER(TRIM(COALESCE(ro.status, ''))) LIKE '%CANCEL%'
        THEN 1 ELSE 0
    END AS is_cancelled_ro,

    CASE
        WHEN UPPER(TRIM(COALESCE(ro.status, '')))
             IN ('RECEIVED', 'VOUCHERED')
          OR COALESCE(rol.has_closed_rol_status, 0) = 1
        THEN 1 ELSE 0
    END AS is_closed_ro,

    CASE
        WHEN UPPER(TRIM(COALESCE(ro.status, ''))) LIKE '%CANCEL%'
        THEN 0 ELSE 1
    END AS include_in_created_ro_count,

    COALESCE(rol.rol_count, 0) AS rol_count

FROM source.repair_order ro

LEFT JOIN analytics.rol_status_by_ro rol
    ON rol.repair_order_id = ro.repair_order_id

WHERE ro.is_deleted = 0
  AND ro.repair_order_number IS NOT NULL
  AND ro.created_at IS NOT NULL;

ALTER TABLE analytics.ro_created_detail
    ADD INDEX idx_ro_created_date      (ro_created_date),
    ADD INDEX idx_ro_created_year      (ro_created_year),
    ADD INDEX idx_ro_created_yearmonth (ro_created_year_month),
    ADD INDEX idx_ro_created_cancelled (is_cancelled_ro),
    ADD INDEX idx_ro_created_closed    (is_closed_ro);


/* ---------------------------------------------------------------------------
   3. YEARLY SUMMARY
--------------------------------------------------------------------------- */

DROP TABLE IF EXISTS analytics.ro_created_yearly;

CREATE TABLE analytics.ro_created_yearly AS
SELECT
    ro_created_year AS year,

    COUNT(DISTINCT CASE
        WHEN include_in_created_ro_count = 1
        THEN repair_order_number
    END) AS created_ro_count,

    COUNT(DISTINCT CASE
        WHEN include_in_created_ro_count = 1
         AND is_closed_ro = 1
        THEN repair_order_number
    END) AS created_closed_ro_count,

    COUNT(DISTINCT CASE
        WHEN include_in_created_ro_count = 1
         AND is_closed_ro = 0
        THEN repair_order_number
    END) AS created_open_ro_count,

    COUNT(DISTINCT CASE
        WHEN is_cancelled_ro = 1
        THEN repair_order_number
    END) AS cancelled_ro_count,

    ROUND(
        COUNT(DISTINCT CASE
            WHEN include_in_created_ro_count = 1
             AND is_closed_ro = 1
            THEN repair_order_number
        END)
        /
        NULLIF(
            COUNT(DISTINCT CASE
                WHEN include_in_created_ro_count = 1
                THEN repair_order_number
            END),
            0
        ),
        4
    ) AS currently_closed_pct

FROM analytics.ro_created_detail

WHERE ro_created_year IS NOT NULL

GROUP BY
    ro_created_year

ORDER BY
    ro_created_year;


/* ---------------------------------------------------------------------------
   4. MONTHLY SUMMARY
--------------------------------------------------------------------------- */

DROP TABLE IF EXISTS analytics.ro_created_monthly;

CREATE TABLE analytics.ro_created_monthly AS
SELECT
    ro_created_year_month AS year_month,
    MIN(ro_created_month_date) AS month_date,
    MIN(ro_created_year) AS year,
    MIN(ro_created_month_number) AS month_number,

    COUNT(DISTINCT CASE
        WHEN include_in_created_ro_count = 1
        THEN repair_order_number
    END) AS created_ro_count,

    COUNT(DISTINCT CASE
        WHEN include_in_created_ro_count = 1
         AND is_closed_ro = 1
        THEN repair_order_number
    END) AS created_closed_ro_count,

    COUNT(DISTINCT CASE
        WHEN include_in_created_ro_count = 1
         AND is_closed_ro = 0
        THEN repair_order_number
    END) AS created_open_ro_count,

    COUNT(DISTINCT CASE
        WHEN is_cancelled_ro = 1
        THEN repair_order_number
    END) AS cancelled_ro_count

FROM analytics.ro_created_detail

WHERE ro_created_year_month IS NOT NULL

GROUP BY
    ro_created_year_month

ORDER BY
    month_date;

ALTER TABLE analytics.ro_created_monthly
    ADD INDEX idx_ro_monthly_date (month_date),
    ADD INDEX idx_ro_monthly_year (year),
    ADD INDEX idx_ro_monthly_ym   (year_month);

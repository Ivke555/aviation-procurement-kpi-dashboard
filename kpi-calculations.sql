/*
===============================================================================
AVIATION PROCUREMENT KPI DASHBOARD
Portfolio SQL 02 - KPI Calculations
===============================================================================

Purpose
-------
Demonstrates the KPI semantic layer used for Power BI reporting.

Sanitized portfolio version. Object names and identifiers are generalized.

Key business logic represented
------------------------------
- Closed RO = RO or ROL status is Received / Vouchered
- KPI TAT = final operational milestone - applicable start milestone
- Target = TAT < 73 days
- Outlier = TAT > 150 days
- Open ageing is calculated as of today
- Operational process steps are aggregated to one row per Repair Order
===============================================================================
*/


/* ---------------------------------------------------------------------------
   1. FLATTEN DETAIL TO ONE ROW PER REPAIR ORDER
--------------------------------------------------------------------------- */

DROP TABLE IF EXISTS analytics.procurement_kpi_flat;

CREATE TABLE analytics.procurement_kpi_flat AS
SELECT
    d.repair_order_id,
    d.repair_order_number,

    MAX(d.ro_status) AS ro_status,
    MAX(d.vendor_name) AS vendor_name,
    MAX(d.repair_type) AS repair_type,

    CASE
        WHEN MAX(d.is_closed_ro) = 1
        THEN 1 ELSE 0
    END AS is_closed_ro,

    CASE
        WHEN MAX(d.is_closed_ro) = 1
        THEN 'Closed KPI'
        ELSE 'Open KPI'
    END AS kpi_status,

    CASE
        WHEN MAX(d.is_closed_ro) = 0
        THEN 1 ELSE 0
    END AS is_open_ro,

    /* Representative start-date selection.
       Some process types intentionally begin from Vendor Selection. */
    MIN(
        CASE
            WHEN d.repair_type IN (
                'Asset Management',
                'Managed Repair',
                'Shelf Life Expiry',
                'Special Repair Program'
            )
            THEN COALESCE(
                d.vendor_selection_date,
                d.ro_creation_date,
                d.ro_created_date
            )
            ELSE COALESCE(
                d.vendor_selection_date,
                d.ro_creation_date,
                d.ro_created_date
            )
        END
    ) AS kpi_start_date,

    MAX(
        COALESCE(
            d.receipt_created_at,
            d.docking_date,
            d.return_date
        )
    ) AS kpi_final_date,

    CASE
        WHEN MAX(d.is_closed_ro) = 0
         AND MIN(
                COALESCE(
                    d.vendor_selection_date,
                    d.ro_creation_date,
                    d.ro_created_date
                )
             ) IS NOT NULL
        THEN DATEDIFF(
                CURDATE(),
                MIN(
                    COALESCE(
                        d.vendor_selection_date,
                        d.ro_creation_date,
                        d.ro_created_date
                    )
                )
             )
        ELSE NULL
    END AS open_tat_as_of_today,

    DATEDIFF(
        MAX(
            COALESCE(
                d.receipt_created_at,
                d.docking_date,
                d.return_date
            )
        ),
        MIN(
            COALESCE(
                d.vendor_selection_date,
                d.ro_creation_date,
                d.ro_created_date
            )
        )
    ) AS kpi_tat,

    CASE
        WHEN DATEDIFF(
            MAX(COALESCE(
                d.receipt_created_at,
                d.docking_date,
                d.return_date
            )),
            MIN(COALESCE(
                d.vendor_selection_date,
                d.ro_creation_date,
                d.ro_created_date
            ))
        ) < 73
        THEN 1 ELSE 0
    END AS is_under_73_days,

    CASE
        WHEN DATEDIFF(
            MAX(COALESCE(
                d.receipt_created_at,
                d.docking_date,
                d.return_date
            )),
            MIN(COALESCE(
                d.vendor_selection_date,
                d.ro_creation_date,
                d.ro_created_date
            ))
        ) > 150
        THEN 1 ELSE 0
    END AS is_tat_outlier,

    CAST(AVG(d.vendor_selection_time)       AS DECIMAL(18,4))
        AS vendor_selection_time,
    CAST(AVG(d.ro_creation_time)            AS DECIMAL(18,4))
        AS ro_creation_time,
    CAST(AVG(d.release_processing_time)     AS DECIMAL(18,4))
        AS release_processing_time,
    CAST(AVG(d.pre_shipment_processing)     AS DECIMAL(18,4))
        AS pre_shipment_processing,
    CAST(AVG(d.transit_time_to_vendor)      AS DECIMAL(18,4))
        AS transit_time_to_vendor,
    CAST(AVG(d.vendor_quotation_lead_time)  AS DECIMAL(18,4))
        AS vendor_quotation_lead_time,
    CAST(AVG(d.quote_approval_time)         AS DECIMAL(18,4))
        AS quote_approval_time,
    CAST(AVG(d.vendor_repair_time)           AS DECIMAL(18,4))
        AS vendor_repair_time,
    CAST(AVG(d.transit_time_from_vendor)    AS DECIMAL(18,4))
        AS transit_time_from_vendor,
    CAST(AVG(d.goods_receipt_processing)    AS DECIMAL(18,4))
        AS goods_receipt_processing,

    YEAR(
        MAX(
            COALESCE(
                d.receipt_created_at,
                d.docking_date,
                d.return_date
            )
        )
    ) AS kpi_year,

    DATE_FORMAT(
        MAX(
            COALESCE(
                d.receipt_created_at,
                d.docking_date,
                d.return_date
            )
        ),
        '%Y-%m'
    ) AS kpi_year_month

FROM analytics.procurement_kpi_detail d
GROUP BY
    d.repair_order_id,
    d.repair_order_number;


ALTER TABLE analytics.procurement_kpi_flat
    ADD INDEX idx_kpi_flat_ro         (repair_order_id),
    ADD INDEX idx_kpi_flat_status     (kpi_status),
    ADD INDEX idx_kpi_flat_final_date (kpi_final_date),
    ADD INDEX idx_kpi_flat_year       (kpi_year);


/* ---------------------------------------------------------------------------
   2. EXECUTIVE KPI SUMMARY
--------------------------------------------------------------------------- */

SET @KPI_YEAR := YEAR(CURDATE());

DROP TABLE IF EXISTS analytics.procurement_kpi_summary;

CREATE TABLE analytics.procurement_kpi_summary AS
SELECT
    @KPI_YEAR AS kpi_year,

    CAST(AVG(kpi_tat) AS DECIMAL(18,2))
        AS average_closed_ro_tat,

    COUNT(DISTINCT repair_order_number)
        AS closed_ro_count,

    COUNT(DISTINCT CASE
        WHEN kpi_tat < 73
        THEN repair_order_number
    END) AS ro_under_73_days,

    ROUND(
        COUNT(DISTINCT CASE
            WHEN kpi_tat < 73
            THEN repair_order_number
        END)
        /
        NULLIF(COUNT(DISTINCT repair_order_number), 0)
        * 100,
        2
    ) AS percent_under_73_days,

    COUNT(DISTINCT CASE
        WHEN kpi_tat > 150
        THEN repair_order_number
    END) AS outlier_ro_count,

    ROUND(
        COUNT(DISTINCT CASE
            WHEN kpi_tat > 150
            THEN repair_order_number
        END)
        /
        NULLIF(COUNT(DISTINCT repair_order_number), 0)
        * 100,
        2
    ) AS outlier_percent,

    CAST(AVG(vendor_selection_time)      AS DECIMAL(18,2))
        AS avg_vendor_selection_time,
    CAST(AVG(vendor_quotation_lead_time) AS DECIMAL(18,2))
        AS avg_vendor_quotation_lead_time,
    CAST(AVG(quote_approval_time)        AS DECIMAL(18,2))
        AS avg_quote_approval_time,
    CAST(AVG(vendor_repair_time)         AS DECIMAL(18,2))
        AS avg_vendor_repair_time

FROM analytics.procurement_kpi_flat

WHERE kpi_year = @KPI_YEAR
  AND is_closed_ro = 1
  AND kpi_final_date IS NOT NULL;


/* ---------------------------------------------------------------------------
   3. MULTI-YEAR KPI TREND
--------------------------------------------------------------------------- */

DROP TABLE IF EXISTS analytics.procurement_kpi_by_year;

CREATE TABLE analytics.procurement_kpi_by_year AS
SELECT
    kpi_year,

    CAST(AVG(kpi_tat) AS DECIMAL(18,2))
        AS average_tat,

    COUNT(DISTINCT repair_order_number)
        AS closed_ro_count,

    ROUND(
        COUNT(DISTINCT CASE
            WHEN kpi_tat < 73
            THEN repair_order_number
        END)
        /
        NULLIF(COUNT(DISTINCT repair_order_number), 0)
        * 100,
        2
    ) AS percent_under_73_days,

    COUNT(DISTINCT CASE
        WHEN kpi_tat > 150
        THEN repair_order_number
    END) AS outlier_ro_count

FROM analytics.procurement_kpi_flat

WHERE is_closed_ro = 1
  AND kpi_final_date IS NOT NULL

GROUP BY
    kpi_year

ORDER BY
    kpi_year;

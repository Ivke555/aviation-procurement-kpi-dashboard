/*
===============================================================================
AVIATION PROCUREMENT KPI DASHBOARD
Portfolio SQL 01 - Reporting Model
===============================================================================

Purpose
-------
Demonstrates how operational repair-order data can be transformed into a
reporting layer for Power BI.

This is a sanitized portfolio version of a production implementation.
Schema names, object names, identifiers and some field names have been
generalized. The business logic and modelling approach are representative.

Key techniques demonstrated
---------------------------
- Staging / helper tables
- Indexed reporting stages
- Priority-based record matching
- Deterministic selection of one best match
- Operational milestone integration
- SQL transformation layer for BI
===============================================================================
*/


/* ---------------------------------------------------------------------------
   1. RECEIPT AGGREGATION

   One receipt record is selected per repair-order line so downstream joins do
   not multiply the reporting grain.
--------------------------------------------------------------------------- */

DROP TABLE IF EXISTS analytics.receipt_agg;

CREATE TABLE analytics.receipt_agg AS
SELECT
    r.repair_order_line_id,
    MAX(r.receipt_id)          AS receipt_id,
    MAX(r.receipt_created_at)  AS receipt_created_at,
    MAX(r.inventory_id)        AS received_inventory_id
FROM source.receipt r
WHERE r.repair_order_line_id IS NOT NULL
GROUP BY
    r.repair_order_line_id;

ALTER TABLE analytics.receipt_agg
    ADD INDEX idx_receipt_rol (repair_order_line_id);


/* ---------------------------------------------------------------------------
   2. DOCKING MATCH BASE

   A docking event can be linked by several pieces of operational evidence.
   The model ranks evidence in this order:

       Priority 1 = direct Repair Order Line match
       Priority 2 = Repair Order match
       Priority 3 = Return AWB match

   The final selected row uses the strongest available evidence and then the
   earliest valid docking timestamp.
--------------------------------------------------------------------------- */

DROP TABLE IF EXISTS analytics.docking_rol_base;

CREATE TABLE analytics.docking_rol_base AS
SELECT
    rol.repair_order_line_id,
    rol.repair_order_id,
    rol.return_awb
FROM source.repair_order_line rol
WHERE rol.is_deleted = 0
  AND rol.repair_order_line_id IS NOT NULL;

ALTER TABLE analytics.docking_rol_base
    ADD INDEX idx_drb_rol (repair_order_line_id),
    ADD INDEX idx_drb_ro  (repair_order_id),
    ADD INDEX idx_drb_awb (return_awb);


DROP TABLE IF EXISTS analytics.docking_candidates;

CREATE TABLE analytics.docking_candidates (
    repair_order_line_id VARCHAR(255),
    repair_order_id      VARCHAR(255),
    docking_id           VARCHAR(255),
    match_type           VARCHAR(20),
    match_priority       INT,
    docking_date         DATETIME,

    INDEX idx_dc_rol      (repair_order_line_id),
    INDEX idx_dc_ro       (repair_order_id),
    INDEX idx_dc_priority (match_priority),
    INDEX idx_dc_date     (docking_date)
);


/* Priority 1: direct Repair Order Line evidence */
INSERT INTO analytics.docking_candidates
SELECT
    b.repair_order_line_id,
    b.repair_order_id,
    d.docking_id,
    'ROL' AS match_type,
    1     AS match_priority,
    d.docking_date
FROM analytics.docking_rol_base b
INNER JOIN source.docking d
    ON d.repair_order_line_id = b.repair_order_line_id
WHERE d.repair_order_line_id IS NOT NULL
  AND d.docking_date IS NOT NULL;


/* Priority 2: Repair Order evidence */
INSERT INTO analytics.docking_candidates
SELECT
    b.repair_order_line_id,
    b.repair_order_id,
    d.docking_id,
    'RO' AS match_type,
    2    AS match_priority,
    d.docking_date
FROM analytics.docking_rol_base b
INNER JOIN source.docking d
    ON d.repair_order_id = b.repair_order_id
WHERE d.repair_order_id IS NOT NULL
  AND d.docking_date IS NOT NULL;


/* Priority 3: Return AWB evidence */
INSERT INTO analytics.docking_candidates
SELECT
    b.repair_order_line_id,
    b.repair_order_id,
    d.docking_id,
    'AWB' AS match_type,
    3     AS match_priority,
    d.docking_date
FROM analytics.docking_rol_base b
INNER JOIN source.docking d
    ON d.awb = b.return_awb
WHERE d.awb IS NOT NULL
  AND TRIM(d.awb) <> ''
  AND b.return_awb IS NOT NULL
  AND TRIM(b.return_awb) <> ''
  AND d.docking_date IS NOT NULL;


/* ---------------------------------------------------------------------------
   3. SELECT ONE BEST DOCKING RECORD PER REPAIR-ORDER LINE

   Deterministic anti-join:
   - better priority wins
   - for equal priority, earlier date wins
   - final tie-breaker uses the identifier
--------------------------------------------------------------------------- */

DROP TABLE IF EXISTS analytics.docking_selected;

CREATE TABLE analytics.docking_selected AS
SELECT
    c.repair_order_line_id,
    c.repair_order_id,
    c.docking_id,
    c.match_type,
    c.match_priority,
    c.docking_date
FROM analytics.docking_candidates c
LEFT JOIN analytics.docking_candidates better
    ON better.repair_order_line_id = c.repair_order_line_id
   AND (
        better.match_priority < c.match_priority
        OR (
            better.match_priority = c.match_priority
            AND better.docking_date < c.docking_date
        )
        OR (
            better.match_priority = c.match_priority
            AND better.docking_date = c.docking_date
            AND better.docking_id < c.docking_id
        )
   )
WHERE better.repair_order_line_id IS NULL;

ALTER TABLE analytics.docking_selected
    ADD INDEX idx_ds_rol      (repair_order_line_id),
    ADD INDEX idx_ds_ro       (repair_order_id),
    ADD INDEX idx_ds_date     (docking_date),
    ADD INDEX idx_ds_priority (match_priority);


/* ---------------------------------------------------------------------------
   4. INVENTORY MILESTONES

   Location history is used to reconstruct sourcing / operational milestones.
--------------------------------------------------------------------------- */

DROP TABLE IF EXISTS analytics.inventory_milestones;

CREATE TABLE analytics.inventory_milestones AS
SELECT
    h.inventory_id,
    MAX(CASE WHEN h.new_location = 'Vendor Selection'
             THEN h.changed_at END) AS vendor_selection_date,
    MAX(CASE WHEN h.new_location = 'RO Creation'
             THEN h.changed_at END) AS ro_creation_date
FROM source.inventory_history h
WHERE h.new_location IN ('Vendor Selection', 'RO Creation')
GROUP BY
    h.inventory_id;

ALTER TABLE analytics.inventory_milestones
    ADD INDEX idx_im_inventory (inventory_id);


/* ---------------------------------------------------------------------------
   5. RELEASE AGGREGATION
--------------------------------------------------------------------------- */

DROP TABLE IF EXISTS analytics.release_agg;

CREATE TABLE analytics.release_agg AS
SELECT
    rl.repair_order_line_id,
    MIN(COALESCE(r.release_date, r.created_at, rl.created_at))
        AS release_created_at
FROM source.release_line rl
LEFT JOIN source.release_header r
    ON r.release_id = rl.release_id
WHERE rl.repair_order_line_id IS NOT NULL
GROUP BY
    rl.repair_order_line_id;

ALTER TABLE analytics.release_agg
    ADD INDEX idx_release_rol (repair_order_line_id);


/* ---------------------------------------------------------------------------
   6. REPORTING MODEL

   Produces the detailed operational layer used by the KPI model.
--------------------------------------------------------------------------- */

DROP TABLE IF EXISTS analytics.procurement_kpi_detail;

CREATE TABLE analytics.procurement_kpi_detail AS
SELECT
    rol.repair_order_line_id,
    ro.repair_order_id,
    ro.repair_order_number,

    ro.status  AS ro_status,
    rol.status AS rol_status,

    CASE
        WHEN ro.status IN ('Received', 'Vouchered')
          OR rol.status IN ('Received', 'Vouchered')
        THEN 1 ELSE 0
    END AS is_closed_ro,

    ro.vendor_name,
    rol.repair_type,
    rol.part_number,
    rol.serial_number,

    im.vendor_selection_date,
    im.ro_creation_date,
    ro.created_at AS ro_created_date,
    rel.release_created_at,

    rol.ship_date,
    rol.vendor_pod_date,
    rol.quote_received_date,
    rol.quote_approved_date,
    rol.return_date,

    dock.docking_date,
    rec.receipt_created_at,

    /* Example process-step calculations */

    GREATEST(
        COALESCE(DATEDIFF(im.ro_creation_date, im.vendor_selection_date), 0),
        0
    ) AS vendor_selection_time,

    GREATEST(
        COALESCE(DATEDIFF(ro.created_at, im.ro_creation_date), 0),
        0
    ) AS ro_creation_time,

    GREATEST(
        COALESCE(DATEDIFF(rel.release_created_at, ro.created_at), 0),
        0
    ) AS release_processing_time,

    GREATEST(
        COALESCE(DATEDIFF(rol.ship_date, rel.release_created_at), 0),
        0
    ) AS pre_shipment_processing,

    GREATEST(
        COALESCE(DATEDIFF(rol.vendor_pod_date, rol.ship_date), 0),
        0
    ) AS transit_time_to_vendor,

    GREATEST(
        COALESCE(
            DATEDIFF(rol.quote_received_date, rol.vendor_pod_date),
            0
        ),
        0
    ) AS vendor_quotation_lead_time,

    GREATEST(
        COALESCE(
            DATEDIFF(rol.quote_approved_date, rol.quote_received_date),
            0
        ),
        0
    ) AS quote_approval_time,

    GREATEST(
        COALESCE(
            DATEDIFF(rol.return_date, rol.quote_approved_date),
            0
        ),
        0
    ) AS vendor_repair_time,

    GREATEST(
        COALESCE(
            DATEDIFF(
                COALESCE(dock.docking_date, rec.receipt_created_at),
                rol.return_date
            ),
            0
        ),
        0
    ) AS transit_time_from_vendor,

    CASE
        WHEN dock.docking_date IS NOT NULL
        THEN GREATEST(
            COALESCE(
                DATEDIFF(rec.receipt_created_at, dock.docking_date),
                0
            ),
            0
        )
        ELSE 0
    END AS goods_receipt_processing

FROM source.repair_order_line rol

LEFT JOIN source.repair_order ro
    ON ro.repair_order_id = rol.repair_order_id

LEFT JOIN analytics.inventory_milestones im
    ON im.inventory_id = rol.original_inventory_id

LEFT JOIN analytics.receipt_agg rec
    ON rec.repair_order_line_id = rol.repair_order_line_id

LEFT JOIN analytics.release_agg rel
    ON rel.repair_order_line_id = rol.repair_order_line_id

LEFT JOIN analytics.docking_selected dock
    ON dock.repair_order_line_id = rol.repair_order_line_id

WHERE ro.is_deleted = 0
  AND rol.is_deleted = 0
  AND COALESCE(ro.status, '') <> 'Cancelled'
  AND COALESCE(rol.status, '') <> 'Cancelled';


ALTER TABLE analytics.procurement_kpi_detail
    ADD INDEX idx_pkd_ro     (repair_order_id),
    ADD INDEX idx_pkd_rol    (repair_order_line_id),
    ADD INDEX idx_pkd_closed (is_closed_ro);

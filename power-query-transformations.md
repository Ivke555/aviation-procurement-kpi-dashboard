# Power Query Transformations

This file contains **sanitized portfolio examples** representing the Power Query layer used by the Aviation Procurement KPI Dashboard.

The production solution performs the heavy operational relationship logic and KPI preparation in SQL. Power Query is then used as a controlled semantic-preparation layer before the data enters the Power BI model.

Production server names, schemas, object names and identifiers have been generalized.

---

## Power Query Role in the Architecture

```text
Operational Systems
        ↓
SQL Staging & Business Logic
        ↓
KPI-Ready Reporting Tables
        ↓
Power Query
   • select required fields
   • enforce data types
   • apply report-level cleanup
   • create presentation attributes
        ↓
Power BI Semantic Model
        ↓
DAX Measures & Visuals
```

Keeping complex operational logic in SQL reduces duplicated business rules inside Power BI and makes the reporting layer reusable across dashboards and other reporting tools.

---

# 1. KPI Fact Table

The main Power BI KPI dataset is loaded from the SQL reporting layer at one reporting row per repair order.

```powerquery
let
    Source =
        MySQL.Database(
            "analytics-server.example.com",
            "analytics",
            [ReturnSingleDatabase = true]
        ),

    KPI =
        Source{
            [
                Schema = "analytics",
                Item = "procurement_kpi_flat"
            ]
        }[Data],

    SelectedColumns =
        Table.SelectColumns(
            KPI,
            {
                "repair_order_id",
                "repair_order_number",
                "ro_status",
                "vendor_name",
                "repair_type",
                "is_closed_ro",
                "is_open_ro",
                "kpi_status",
                "kpi_start_date",
                "kpi_final_date",
                "open_tat_as_of_today",
                "kpi_tat",
                "is_under_73_days",
                "is_tat_outlier",
                "vendor_selection_time",
                "ro_creation_time",
                "release_processing_time",
                "pre_shipment_processing",
                "transit_time_to_vendor",
                "vendor_quotation_lead_time",
                "quote_approval_time",
                "vendor_repair_time",
                "transit_time_from_vendor",
                "goods_receipt_processing",
                "kpi_year",
                "kpi_year_month"
            },
            MissingField.Ignore
        ),

    ChangedTypes =
        Table.TransformColumnTypes(
            SelectedColumns,
            {
                {"repair_order_id", type text},
                {"repair_order_number", type text},
                {"ro_status", type text},
                {"vendor_name", type text},
                {"repair_type", type text},

                {"is_closed_ro", Int64.Type},
                {"is_open_ro", Int64.Type},

                {"kpi_status", type text},

                {"kpi_start_date", type date},
                {"kpi_final_date", type date},

                {"open_tat_as_of_today", Int64.Type},
                {"kpi_tat", Int64.Type},

                {"is_under_73_days", Int64.Type},
                {"is_tat_outlier", Int64.Type},

                {"vendor_selection_time", type number},
                {"ro_creation_time", type number},
                {"release_processing_time", type number},
                {"pre_shipment_processing", type number},
                {"transit_time_to_vendor", type number},
                {"vendor_quotation_lead_time", type number},
                {"quote_approval_time", type number},
                {"vendor_repair_time", type number},
                {"transit_time_from_vendor", type number},
                {"goods_receipt_processing", type number},

                {"kpi_year", Int64.Type},
                {"kpi_year_month", type text}
            }
        ),

    ValidRepairOrders =
        Table.SelectRows(
            ChangedTypes,
            each
                [repair_order_number] <> null
                and Text.Trim([repair_order_number]) <> ""
        ),

    RenamedForModel =
        Table.RenameColumns(
            ValidRepairOrders,
            {
                {"repair_order_number", "RO Number"},
                {"ro_status", "RO Status"},
                {"vendor_name", "Vendor"},
                {"repair_type", "Repair Type"},
                {"is_closed_ro", "Is Closed RO"},
                {"is_open_ro", "Is Open RO"},
                {"kpi_status", "KPI Status"},
                {"kpi_start_date", "KPI Start Date"},
                {"kpi_final_date", "KPI Final Date"},
                {"open_tat_as_of_today", "Open TAT As Of Today"},
                {"kpi_tat", "KPI TAT"},
                {"is_under_73_days", "Is Under 73 Days"},
                {"is_tat_outlier", "Is TAT Outlier"},
                {"kpi_year", "KPI Year"},
                {"kpi_year_month", "KPI Year Month"}
            },
            MissingField.Ignore
        )
in
    RenamedForModel
```

### Why this query is intentionally light

The Power Query layer does **not** recalculate the repair-order relationship logic or KPI classification.

Those rules are already handled in SQL, including:

- repair-order reporting grain
- open / closed classification
- milestone selection
- turnaround-time calculation
- target classification
- outlier classification
- operational process-step durations

Power Query mainly controls the model-facing schema and data types.

---

# 2. Repair Order Creation Trend

Repair-order creation analysis uses a separate source grain from the KPI table.

This is important because historical RO creation volume should come from the repair-order creation dataset rather than from a KPI fact table whose grain and scope are designed for TAT reporting.

```powerquery
let
    Source =
        MySQL.Database(
            "analytics-server.example.com",
            "analytics",
            [ReturnSingleDatabase = true]
        ),

    ROCreated =
        Source{
            [
                Schema = "analytics",
                Item = "ro_created_detail"
            ]
        }[Data],

    SelectedColumns =
        Table.SelectColumns(
            ROCreated,
            {
                "repair_order_id",
                "repair_order_number",
                "status",
                "vendor_name",
                "ro_created_date",
                "ro_created_year",
                "ro_created_month_number",
                "ro_created_year_month",
                "ro_created_month_date",
                "is_cancelled_ro",
                "is_closed_ro",
                "include_in_created_ro_count"
            },
            MissingField.Ignore
        ),

    ChangedTypes =
        Table.TransformColumnTypes(
            SelectedColumns,
            {
                {"repair_order_id", type text},
                {"repair_order_number", type text},
                {"status", type text},
                {"vendor_name", type text},

                {"ro_created_date", type date},
                {"ro_created_year", Int64.Type},
                {"ro_created_month_number", Int64.Type},
                {"ro_created_year_month", type text},
                {"ro_created_month_date", type date},

                {"is_cancelled_ro", Int64.Type},
                {"is_closed_ro", Int64.Type},
                {"include_in_created_ro_count", Int64.Type}
            }
        ),

    HistoricalScope =
        Table.SelectRows(
            ChangedTypes,
            each
                [ro_created_date] <> null
                and [ro_created_date] >= #date(2022, 1, 1)
        ),

    AddedMonthName =
        Table.AddColumn(
            HistoricalScope,
            "RO Created Month Name",
            each Date.ToText(
                #date(
                    2000,
                    [ro_created_month_number],
                    1
                ),
                "MMM"
            ),
            type text
        ),

    AddedStatusGroup =
        Table.AddColumn(
            AddedMonthName,
            "RO Reporting Status",
            each
                if [is_cancelled_ro] = 1 then
                    "Cancelled"
                else if [is_closed_ro] = 1 then
                    "Closed"
                else
                    "Open",
            type text
        ),

    RenamedForModel =
        Table.RenameColumns(
            AddedStatusGroup,
            {
                {"repair_order_number", "RO Number"},
                {"status", "RO Status"},
                {"vendor_name", "Vendor"},
                {"ro_created_date", "RO Created Date"},
                {"ro_created_year", "RO Created Year"},
                {"ro_created_month_number", "RO Created Month Number"},
                {"ro_created_year_month", "RO Created Year Month"},
                {"ro_created_month_date", "RO Created Month Date"},
                {"is_cancelled_ro", "Is Cancelled RO"},
                {"is_closed_ro", "Is Closed RO"},
                {"include_in_created_ro_count", "Include In Created RO Count"}
            },
            MissingField.Ignore
        )
in
    RenamedForModel
```

This table supports Power BI measures such as:

```text
Created RO Count
Created RO Count Previous Year Same Month
Created RO Difference vs Previous Year Same Month
Created RO Difference vs Previous Year Same Month %
```

---

# 3. Reusable Report-Level Classification Pattern

Power Query is also useful for lightweight presentation classifications when the rule is not part of the core business logic.

For example, an open-ageing band can be created without changing the upstream KPI calculation.

```powerquery
let
    Source = #"KPI Fact Table",

    AddedOpenAgeBand =
        Table.AddColumn(
            Source,
            "Open Age Band",
            each
                if [Open TAT As Of Today] = null then
                    null
                else if [Open TAT As Of Today] <= 30 then
                    "<=30"
                else if [Open TAT As Of Today] <= 60 then
                    "31-60"
                else if [Open TAT As Of Today] <= 90 then
                    "61-90"
                else if [Open TAT As Of Today] <= 180 then
                    "91-180"
                else
                    "180+",
            type text
        ),

    AddedOpenAgeSort =
        Table.AddColumn(
            AddedOpenAgeBand,
            "Open Age Sort",
            each
                if [Open TAT As Of Today] = null then
                    null
                else if [Open TAT As Of Today] <= 30 then
                    1
                else if [Open TAT As Of Today] <= 60 then
                    2
                else if [Open TAT As Of Today] <= 90 then
                    3
                else if [Open TAT As Of Today] <= 180 then
                    4
                else
                    5,
            Int64.Type
        )
in
    AddedOpenAgeSort
```

The numeric sort column allows the reporting category to display in operational order rather than alphabetical order.

---

# 4. Example Join Pattern

When supplementary dimensions are needed, Power Query can use a controlled left join without changing the grain of the KPI fact table.

```powerquery
let
    KPI = #"KPI Fact Table",
    VendorDimension = #"Vendor Dimension",

    MergedVendor =
        Table.NestedJoin(
            KPI,
            {"Vendor"},
            VendorDimension,
            {"Vendor"},
            "Vendor Dimension",
            JoinKind.LeftOuter
        ),

    ExpandedVendor =
        Table.ExpandTableColumn(
            MergedVendor,
            "Vendor Dimension",
            {
                "Vendor Group",
                "Vendor Region"
            },
            {
                "Vendor Group",
                "Vendor Region"
            }
        )
in
    ExpandedVendor
```

The fact table remains the left-hand table so unmatched dimension records do not remove operational KPI records.

---

# Power Query Design Principles Demonstrated

## Push heavy logic upstream

Complex operational rules belong in the SQL reporting layer where they can be tested, indexed and reused.

## Select only required columns

`Table.SelectColumns` prevents unnecessary source fields from entering the semantic model.

## Enforce explicit types

`Table.TransformColumnTypes` avoids relying on automatic type inference for dates, identifiers and KPI values.

## Preserve reporting grain

Power Query merges should enrich the existing fact grain rather than accidentally multiplying operational records.

## Separate business logic from presentation logic

Core KPI definitions are calculated upstream. Lightweight reporting labels and sort attributes can remain in Power Query.

## Keep names readable in the semantic model

Source-system field names are converted into business-friendly names before DAX measures and visuals consume them.

---

# SQL vs Power Query vs DAX

| Layer | Primary responsibility |
|---|---|
| SQL | Relationships, operational milestones, reporting grain, row-level KPI logic |
| Power Query | Model-facing cleanup, typing, enrichment and presentation attributes |
| DAX | Filter-context aggregation, percentages, time intelligence and interactive analysis |

This separation of responsibilities makes the reporting solution easier to maintain, audit and extend.

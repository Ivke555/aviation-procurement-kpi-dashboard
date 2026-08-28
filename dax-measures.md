# DAX Measures

This file contains a **sanitized portfolio implementation** of the DAX layer used by the Aviation Procurement KPI Dashboard.

The measure names and analytical purposes are based on the current Power BI model and report visuals.  
Production table names and implementation details have been generalized for public use.

## Assumed Portfolio Model

The examples below use these generalized tables:

- `KPI` — one row per repair order for KPI reporting
- `RO Created` — repair-order creation history
- `Dim Date` — shared date dimension
- `TAT Steps` — disconnected table used to display process-step timing

Representative KPI columns include:

- `KPI[RO Number]`
- `KPI[KPI TAT]`
- `KPI[Is Closed RO]`
- `KPI[Is Open RO]`
- `KPI[Open TAT As Of Today]`
- `KPI[Is Under 73 Days]`
- `KPI[Is TAT Outlier]`
- `KPI[Procurement Controlled Time]`
- `KPI[KPI Final Date]`
- `KPI[KPI Year Month]`

---

# Executive KPI Measures

## Closed ROs

```DAX
Closed ROs =
CALCULATE (
    DISTINCTCOUNT ( KPI[RO Number] ),
    KPI[Is Closed RO] = 1
)
```

Counts distinct repair orders classified as closed in the reporting layer.

---

## Avg Closed RO TAT

```DAX
Avg Closed RO TAT =
CALCULATE (
    AVERAGE ( KPI[KPI TAT] ),
    KPI[Is Closed RO] = 1,
    NOT ISBLANK ( KPI[KPI Final Date] )
)
```

Returns the average turnaround time for completed repair orders.

---

## ROs Under 73 Days

```DAX
ROs Under 73 Days =
CALCULATE (
    DISTINCTCOUNT ( KPI[RO Number] ),
    KPI[Is Closed RO] = 1,
    KPI[Is Under 73 Days] = 1
)
```

---

## % Under 73 Days

```DAX
% Under 73 Days =
DIVIDE (
    [ROs Under 73 Days],
    [Closed ROs]
)
```

Measures the share of completed repair orders meeting the 73-day KPI threshold.

---

## Target % Under 73 Days

```DAX
Target % Under 73 Days =
0.80
```

Used as the management KPI target line in trend visuals.

---

## Outlier ROs

```DAX
Outlier ROs =
CALCULATE (
    DISTINCTCOUNT ( KPI[RO Number] ),
    KPI[Is Closed RO] = 1,
    KPI[Is TAT Outlier] = 1
)
```

---

## Outlier %

```DAX
Outlier % =
DIVIDE (
    [Outlier ROs],
    [Closed ROs]
)
```

Shows the proportion of completed repair orders with TAT above the defined outlier threshold.

---

# Open Repair Order Measures

## Open ROs

```DAX
Open ROs =
CALCULATE (
    DISTINCTCOUNT ( KPI[RO Number] ),
    KPI[Is Open RO] = 1
)
```

---

## Avg Open RO TAT

```DAX
Avg Open RO TAT =
CALCULATE (
    AVERAGE ( KPI[Open TAT As Of Today] ),
    KPI[Is Open RO] = 1
)
```

Open cases use current ageing rather than a completed TAT.

---

## Open ROs Under 73 Days

```DAX
Open ROs Under 73 Days =
CALCULATE (
    DISTINCTCOUNT ( KPI[RO Number] ),
    KPI[Is Open RO] = 1,
    KPI[Open TAT As Of Today] < 73
)
```

---

## Open RO % Under 73

```DAX
Open RO % Under 73 =
DIVIDE (
    [Open ROs Under 73 Days],
    [Open ROs]
)
```

Provides an early-warning view of the open workload against the same KPI threshold.

---

# Procurement Controlled Time

## Avg Procurement Controlled Time

```DAX
Avg Procurement Controlled Time =
CALCULATE (
    AVERAGE ( KPI[Procurement Controlled Time] ),
    KPI[Is Closed RO] = 1
)
```

Separates the portion of total turnaround time attributed to procurement-controlled process stages.

---

# Monthly KPI Measures

## Monthly RO Count

```DAX
Monthly RO Count =
CALCULATE (
    DISTINCTCOUNT ( KPI[RO Number] ),
    KPI[Is Closed RO] = 1
)
```

The date context from `Dim Date` determines the reporting month.

---

## Monthly Avg TAT

```DAX
Monthly Avg TAT =
CALCULATE (
    AVERAGE ( KPI[KPI TAT] ),
    KPI[Is Closed RO] = 1
)
```

---

# RO Creation Trend Measures

The RO-created page intentionally uses the repair-order creation dataset rather than the KPI fact table so historical creation volumes are not distorted by KPI grain.

## Created RO Count

```DAX
Created RO Count =
CALCULATE (
    DISTINCTCOUNT ( 'RO Created'[RO Number] ),
    'RO Created'[Include In Created RO Count] = 1
)
```

---

## Created RO Count Previous Year Same Month

```DAX
Created RO Count Previous Year Same Month =
CALCULATE (
    [Created RO Count],
    DATEADD (
        'Dim Date'[Date],
        -1,
        YEAR
    )
)
```

Compares the selected month with the same month in the previous year.

---

## Created RO Difference vs Previous Year Same Month

```DAX
Created RO Difference vs Previous Year Same Month =
[Created RO Count]
    - [Created RO Count Previous Year Same Month]
```

---

## Created RO Difference vs Previous Year Same Month %

```DAX
Created RO Difference vs Previous Year Same Month % =
DIVIDE (
    [Created RO Difference vs Previous Year Same Month],
    [Created RO Count Previous Year Same Month]
)
```

This percentage pattern is retained from the dashboard's archived RO-created trend logic.

---

# TAT Process-Step Measure

A disconnected `TAT Steps` table can be used to display process-step timing in a single Power BI table or chart.

Example values in `TAT Steps[Step]`:

- Vendor Selection
- RO Creation
- Release Processing
- Pre-Shipment Processing
- Transit to Vendor
- Vendor Quotation
- Quote Approval
- Vendor Repair
- Transit from Vendor
- Goods Receipt Processing
- Final Processing
- Other / Data Gap

## TAT Step Days

```DAX
TAT Step Days =
SWITCH (
    SELECTEDVALUE ( 'TAT Steps'[Step] ),

    "Vendor Selection",
        AVERAGE ( KPI[Vendor Selection Time] ),

    "RO Creation",
        AVERAGE ( KPI[RO Creation Time] ),

    "Release Processing",
        AVERAGE ( KPI[Release Processing Time] ),

    "Pre-Shipment Processing",
        AVERAGE ( KPI[Pre-Shipment Processing] ),

    "Transit to Vendor",
        AVERAGE ( KPI[Transit Time to Vendor] ),

    "Vendor Quotation",
        AVERAGE ( KPI[Vendor Quotation Lead Time] ),

    "Quote Approval",
        AVERAGE ( KPI[Quote Approval Time] ),

    "Vendor Repair",
        AVERAGE ( KPI[Vendor Repair Time] ),

    "Transit from Vendor",
        AVERAGE ( KPI[Transit Time from Vendor] ),

    "Goods Receipt Processing",
        AVERAGE ( KPI[Goods Receipt Processing] ),

    "Final Processing",
        AVERAGE ( KPI[Final Processing Time] ),

    "Other / Data Gap",
        AVERAGE ( KPI[Other Data Gap] ),

    BLANK ()
)
```

This pattern allows multiple operational process measures to be displayed through one common visual axis.

---

# Year-to-Date and Previous-Year Comparison

## Closed ROs YTD

```DAX
Closed ROs YTD =
CALCULATE (
    [Closed ROs],
    DATESYTD ( 'Dim Date'[Date] )
)
```

---

## Closed ROs Previous Year YTD

```DAX
Closed ROs Previous Year YTD =
CALCULATE (
    [Closed ROs YTD],
    DATEADD (
        'Dim Date'[Date],
        -1,
        YEAR
    )
)
```

---

## Avg TAT YTD

```DAX
Avg TAT YTD =
CALCULATE (
    [Avg Closed RO TAT],
    DATESYTD ( 'Dim Date'[Date] )
)
```

---

## Avg TAT Previous Year YTD

```DAX
Avg TAT Previous Year YTD =
CALCULATE (
    [Avg TAT YTD],
    DATEADD (
        'Dim Date'[Date],
        -1,
        YEAR
    )
)
```

---

# Why Keep This Logic in DAX?

The project deliberately separates responsibilities between SQL and Power BI:

**SQL**
- resolves operational relationships
- applies process-specific milestone logic
- prepares KPI-ready records
- calculates row-level process durations
- establishes reporting grain

**DAX**
- responds to report filter context
- aggregates KPI-ready data
- calculates percentages
- performs time-intelligence comparisons
- drives interactive dashboard visuals

This separation keeps complex operational transformation logic out of individual Power BI measures while retaining the flexibility of DAX for interactive analysis.

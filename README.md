# Aviation Procurement KPI Dashboard

End-to-end aviation procurement analytics solution built with **Power BI, SQL, Power Query and DAX** to transform operational procurement data into management KPIs, exception reporting and actionable performance insights.

> **Portfolio version:** This repository contains a sanitized representation of a real-world analytics solution. Company-confidential data, credentials, customer/vendor identities and proprietary production information are excluded.

---

## Project Overview

Procurement performance data is often distributed across multiple operational processes including sourcing, repair orders, receipts, exchanges, logistics and invoicing.

The objective of this project was to create a consolidated analytics solution capable of:

- Measuring procurement turnaround time
- Monitoring operational KPIs
- Identifying long-running and exceptional cases
- Tracking open and completed procurement activity
- Detecting missing or inconsistent operational data
- Providing management-level reporting
- Supporting drill-down from KPIs to individual transactions
- Reducing manual reporting effort

---

## Technology Stack

| Technology | Purpose |
|---|---|
| Power BI | Dashboarding and interactive analytics |
| DAX | KPI measures and analytical calculations |
| SQL | Reporting layer, transformations and validation |
| Power Query | Data preparation and integration |
| Excel | Operational reporting and supporting analysis |
| Python | Automated refresh workflows |
| Power Automate | Scheduled reporting and notifications |
| Salesforce / AvSight | Operational source data |

---

## Solution Architecture

```mermaid
flowchart LR
    A[Operational Systems] --> B[SQL Reporting Layer]
    B --> C[Power Query]
    C --> D[Power BI Data Model]
    D --> E[Executive KPI Dashboard]
    D --> F[Operational Analysis]
    D --> G[Exception Reporting]

    B --> H[Data Quality Checks]
    H --> I[Automated Notifications]

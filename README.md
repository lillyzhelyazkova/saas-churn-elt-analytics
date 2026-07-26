# B2B SaaS Customer Churn & Engagement Analytics

## Project Overview
This project builds an end-to-end ELT (Extract, Load, Transform) data pipeline and an interactive Power BI dashboard to analyze customer retention, product engagement, and support ticket friction for a B2B SaaS company. The primary business goal is to identify early warning signs of customer churn.

## Tech Stack
*   **Data Warehouse/Engine:** DB Browser for SQLite (SQL)
*   **Pipeline Architecture:** ELT (Raw Staging ➔ Modeled Production Schema)
*   **Data Modeling:** Galaxy / Snowflake Schema Hybrid
*   **Data Visualization:** Power BI

## The Dataset
The project analyzes data across 2023 and 2024 spanning 5 core relational tables:
1.  **dim_calendar:** A custom-generated continuous date dimensions matrix.
2.  **dim_accounts:** Core B2B customer firmographic profiles and status flags.
3.  **dim_subscriptions:** Historical log of account plan upgrades, downgrades, and renewals.
4.  **fact_churn_events:** Granular cancellation data mapping churn reasons and financial impacts.
5.  **fact_feature_usage:** Daily product application logs tracking feature-level engagement.
6.  **fact_support_tickets:** Customer success logs tracking ticket volume and resolution statuses.

## Core Business Questions Addressed
*   Analyzing monthly customer retention trends and financial impacts.
*   Investigating the relationship between application feature usage and customer churn.
*   Evaluating customer support ticket resolution rates and their impact on account satisfaction.



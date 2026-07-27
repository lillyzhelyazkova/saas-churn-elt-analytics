/* ====================================================================
   B2B SaaS ELT Pipeline Script
   Author:  Lilyana Zhelyazkova
   Purpose: End-to-end data transformation pipeline. This script 
            extracts raw staging data, applies cleaning constraints, 
            loads it into an optimized Galaxy Schema, and applies 
            performance indexes for optimized Power BI querying.
   ==================================================================== */

-- Turn off foreign key checks so we can safely drop/rebuild tables without errors
PRAGMA foreign_keys = OFF;

-- ====================================================================
-- PHASE 1: CORE DIMENSIONS
-- ====================================================================

-- Drop old tables to ensure the script is completely repeatable
DROP TABLE IF EXISTS dim_calendar;
DROP TABLE IF EXISTS dim_accounts;

-- Create calendar table to enforce a continuous, unbroken timeline for Power BI
CREATE TABLE dim_calendar (
    date_id TEXT PRIMARY KEY NOT NULL,
	calendar_date TEXT NOT NULL UNIQUE,
	year INTEGER NOT NULL,
	month INTEGER NOT NULL,
	month_name TEXT NOT NULL,
	quarter INTEGER NOT NULL,
	day_of_week TEXT NOT NULL,
	is_weekend INTEGER NOT NULL CHECK (is_weekend IN (0,1))
);

-- Populate the table with date values from 2023 and 2024
WITH RECURSIVE dates(date_value) AS (
    SELECT '2023-01-01'
	UNION ALL
	SELECT date(date_value, '+1 day')
	FROM dates
	WHERE date_value < '2024-12-31'
)
INSERT INTO dim_calendar (
    date_id,
	calendar_date,
	year,
	month,
	month_name,
	quarter,
	day_of_week,
	is_weekend
)
SELECT date_value AS date_id,
       date_value AS calendar_date,
	   CAST(strftime('%Y', date_value) AS INTEGER) AS year,
	   CAST(strftime('%m', date_value) AS INTEGER) AS month,
	   CASE strftime('%m', date_value)
	       WHEN '01' THEN 'January' WHEN '02' THEN 'February' WHEN '03' THEN 'March'
		   WHEN '04' THEN 'April'   WHEN '05' THEN 'May'      WHEN '06' THEN 'June'
		   WHEN '07' THEN 'July'    WHEN '08' THEN 'August'   WHEN '09' THEN 'September'
		   WHEN '10' THEN 'October' WHEN '11' THEN 'November' WHEN '12' THEN 'December'
	   END AS month_name,
	   CASE
	       WHEN strftime('%m', date_value) IN ('01','02','03') THEN 1
		   WHEN strftime('%m', date_value) IN ('04','05','06') THEN 2
		   WHEN strftime('%m', date_value) IN ('06','07','08') THEN 3
		   ELSE 4
	   END AS quarter,
	   CASE strftime('%w', date_value)
	       WHEN '0' THEN 'Sunday' WHEN '1' THEN 'Monday' WHEN '2' THEN 'Tuesday'
		   WHEN '3' THEN 'Wednesday' WHEN '4' THEN 'Thursday' WHEN '5' THEN 'Friday'
		   WHEN '6' THEN 'Saturday'
	   END AS day_of_week,
	   CASE WHEN strftime('%w', date_value) IN ('0','6') THEN 1 ELSE 0 END AS is_weekend
FROM dates;

-- Create master customer accounts dimension
CREATE TABLE dim_accounts (
    account_id TEXT PRIMARY KEY NOT NULL,
	account_name TEXT DEFAULT 'Unknown',
	industry TEXT DEFAULT 'Unknown',
	country TEXT DEFAULT 'Unknown',
	signup_date TEXT NOT NULL,
	referral_source TEXT DEFAULT 'Unknown',
	plan_tier TEXT DEFAULT 'Unknown',
	seats INTEGER DEFAULT 1 CHECK (seats >=0),
	is_trial INTEGER NOT NULL DEFAULT 1 CHECK (is_trial IN (0,1)),
	churn_flag INTEGER DEFAULT 0 CHECK (churn_flag IN (0,1))
);

-- Extract from staging and load into production
INSERT INTO dim_accounts (
    account_id,
	account_name,
	industry,
	country,
	signup_date,
	referral_source,
	plan_tier,
	seats,
	is_trial,
	churn_flag
)
SELECT TRIM(account_id), -- Trimmed to prevent invisible spacing breaking Power BI relationships
       account_name,
	   industry,
	   country,
	   signup_date,
	   referral_source,
	   plan_tier,
	   seats,
	    -- Convert text 'true'/'false' strings to 1/0 integers for faster DAX calculations
	   CASE LOWER(TRIM(is_trial)) WHEN 'true' THEN 1 ELSE 0 END,
	   CASE LOWER(TRIM(churn_flag)) WHEN 'true' THEN 1 ELSE 0 END
FROM stg_accounts;


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

-- Drop old tables to ensure the script is completely repeatable
DROP TABLE IF EXISTS fact_support_tickets;
DROP TABLE IF EXISTS fact_feature_usage;
DROP TABLE IF EXISTS fact_subscriptions;
DROP TABLE IF EXISTS fact_churn_events;
DROP TABLE IF EXISTS dim_accounts;
DROP TABLE IF EXISTS dim_calendar;

-- ====================================================================
-- PHASE 1: CORE DIMENSIONS
-- ====================================================================

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

-- ====================================================================
-- PHASE 2: FACT TABLES
-- ====================================================================

--Create churn events fact table
CREATE TABLE fact_churn_events (
    churn_event_id TEXT PRIMARY KEY NOT NULL,
	account_id TEXT NOT NULL,
	churn_date TEXT NOT NULL,
	reason_code TEXT DEFAULT 'Unknown',
	refund_amount_usd REAL DEFAULT 0.0 CHECK (refund_amount_usd >= 0),
	preceding_upgrade_flag INTEGER NOT NULL DEFAULT 0 CHECK (preceding_upgrade_flag IN (0,1)),
	preceding_downgrade_flag INTEGER NOT NULL DEFAULT 0 CHECK (preceding_downgrade_flag IN (0,1)),
	is_reactivation INTEGER NOT NULL DEFAULT 0 CHECK (is_reactivation IN (0,1)),
	feedback_text TEXT,
	FOREIGN KEY (account_id) REFERENCES dim_accounts(account_id),
	FOREIGN KEY (churn_date) REFERENCES dim_calendar(date_id)
);

-- Extract from staging and load into production
INSERT INTO fact_churn_events (
    churn_event_id,
	account_id,
	churn_date,
	reason_code,
	refund_amount_usd,
	preceding_upgrade_flag,
	preceding_downgrade_flag,
	is_reactivation,
	feedback_text
)
SELECT TRIM(churn_event_id),
       TRIM(account_id),
	   churn_date,
	   reason_code,
	   refund_amount_usd,
	   CASE LOWER(TRIM(preceding_upgrade_flag)) WHEN 'true' THEN 1 ELSE 0 END,
	   CASE LOWER(TRIM(preceding_downgrade_flag)) WHEN 'true' then 1 ELSE 0 END,
	   CASE LOWER(TRIM(is_reactivation)) WHEN 'true' THEN 1 ELSE 0 END,
	   feedback_text
FROM stg_churn_events;

--Create subscriptions fact table
CREATE TABLE fact_subscriptions (
    subscription_id TEXT PRIMARY KEY NOT NULL,
	account_id TEXT NOT NULL,
	start_date TEXT NOT NULL,
	end_date TEXT,
	plan_tier TEXT DEFAULT 'Unknown',
	seats INTEGER DEFAULT 1 CHECK (seats >= 0),
	mrr_amount INTEGER DEFAULT 0 CHECK (mrr_amount >= 0),
	arr_amount INTEGER DEFAULT 0 CHECK (arr_amount >= 0),
	is_trial INTEGER NOT NULL DEFAULT 1 CHECK (is_trial IN (0,1)),
	upgrade_flag INTEGER NOT NULL DEFAULT 0 CHECK (upgrade_flag IN (0,1)),
	downgrade_flag INTEGER NOT NULL DEFAULT 0 CHECK (downgrade_flag IN (0,1)),
	churn_flag INTEGER NOT NULL DEFAULT 0 CHECK (churn_flag IN (0,1)),
	billing_frequency TEXT DEFAULT 'Unknown',
	auto_renew_flag INTEGER NOT NULL DEFAULT 0 CHECK (auto_renew_flag IN (0,1)),
	FOREIGN KEY (account_id) REFERENCES dim_accounts(account_id),
	FOREIGN KEY (start_date) REFERENCES dim_calendar(date_id)
);

-- Extract from staging and load into production
INSERT INTO fact_subscriptions (
    subscription_id,
	account_id,
	start_date,
	end_date,
	plan_tier,
	seats,
	mrr_amount,
	arr_amount,
	is_trial,
	upgrade_flag,
	downgrade_flag,
	churn_flag,
	billing_frequency,
	auto_renew_flag
)
SELECT TRIM(subscription_id),
       TRIM(account_id),
	   start_date,
	   end_date,
	   plan_tier,
	   seats,
	   mrr_amount,
	   arr_amount,
	   CASE LOWER(TRIM(is_trial)) WHEN 'true' THEN 1 ELSE 0 END is_trial,
	   CASE LOWER(TRIM(upgrade_flag)) WHEN 'true' THEN 1 ELSE 0 END,
	   CASE LOWER(TRIM(downgrade_flag)) WHEN 'true' THEN 1 ELSE 0 END,
	   CASE LOWER(TRIM(churn_flag)) WHEN 'true' THEN 1 ELSE 0 END,
	   billing_frequency,
	   CASE LOWER(TRIM(auto_renew_flag)) WHEN 'true' THEN 1 ELSE 0 END
FROM stg_subscriptions;

-- Create feature usage fact table with a surrogate autoincrementing primary key
-- after a data audit identifying duplicate usage_id strings containing unique
-- records in the rest of the columns, in order to preserve the data intact
CREATE TABLE fact_feature_usage (
    row_id INTEGER PRIMARY KEY AUTOINCREMENT, -- Created a surrogate autoincrementing primary key
	usage_id TEXT NOT NULL, -- Preserved raw source tracking ID
	subscription_id TEXT NOT NULL,
	usage_date TEXT NOT NULL,
	feature_name TEXT NOT NULL,
	usage_count INTEGER DEFAULT 0 CHECK (usage_count >= 0),
	usage_duration_secs INTEGER DEFAULT 0 CHECK (usage_duration_secs >= 0),
	error_count INTEGER DEFAULT 0 CHECK (error_count >= 0),
	is_beta_feature INTEGER DEFAULT 0 CHECK (is_beta_feature IN (0,1)),
	FOREIGN KEY (subscription_id) REFERENCES fact_subscriptions(subscription_id),
	FOREIGN KEY (usage_date) REFERENCES dim_calendar(date_id)
);

-- Extract from staging and load into production
INSERT INTO fact_feature_usage (
    usage_id,
	subscription_id,
	usage_date,
	feature_name,
	usage_count,
	usage_duration_secs,
	error_count,
	is_beta_feature
)
SELECT TRIM(usage_id),
       TRIM(subscription_id),
	   usage_date,
	   feature_name,
	   usage_count,
	   usage_duration_secs,
	   error_count,
	   CASE LOWER(TRIM(is_beta_feature)) WHEN 'true' THEN 1 ELSE 0 END
FROM stg_feature_usage;

-- Create a support tickets fact table
CREATE TABLE fact_support_tickets (
    ticket_id TEXT PRIMARY KEY NOT NULL,
	account_id TEXT NOT NULL,
	submitted_at TEXT NOT NULL,
	closed_at TEXT NOT NULL,
	resolution_time_hours REAL CHECK (resolution_time_hours >= 0.0),
	priority TEXT DEFAULT 'Unknown',
	first_response_time_minutes INTEGER CHECK (first_response_time_minutes >= 1),
	satisfaction_score REAL,
	escalation_flag INTEGER NOT NULL CHECK (escalation_flag IN (0,1)),
	FOREIGN KEY (account_id) REFERENCES dim_accounts(account_id),
	FOREIGN KEY (submitted_at) REFERENCES dim_calendar(date_id)
);

-- Extract from staging and load into production
INSERT INTO fact_support_tickets (
    ticket_id,
	account_id,
	submitted_at,
	closed_at,
	resolution_time_hours,
	priority,
	first_response_time_minutes,
	satisfaction_score,
	escalation_flag
)
SELECT TRIM(ticket_id),
	   TRIM(account_id),
	   submitted_at,
	   closed_at,
	   resolution_time_hours,
	   priority,
	   first_response_time_minutes,
	   satisfaction_score,
	   CASE LOWER(TRIM(escalation_flag)) WHEN 'true' THEN 1 ELSE 0 END
FROM stg_support_tickets;
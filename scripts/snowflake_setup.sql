-- One-time Snowflake bootstrap for hindsight-warehouse. Paste this into a
-- Snowsight worksheet and run it; takes <30 seconds on a fresh trial
-- account. All defaults match .env.example so you can edit one place if you
-- want different names. Safe to re-run: every object uses IF NOT EXISTS.

-- 1. A small compute warehouse that auto-suspends fast to control cost.
CREATE WAREHOUSE IF NOT EXISTS COMPUTE_WH
    WAREHOUSE_SIZE = 'XSMALL'
    AUTO_SUSPEND = 60
    AUTO_RESUME = TRUE
    INITIALLY_SUSPENDED = TRUE
    COMMENT = 'Compute for hindsight-warehouse dbt builds';

-- 2. A dedicated database for the project.
CREATE DATABASE IF NOT EXISTS HINDSIGHT
    COMMENT = 'Product-safety warehouse built from hindsight raw feeds';

USE DATABASE HINDSIGHT;

-- 3. Schemas the loader and dbt land into. The loader writes RAW, dbt writes
-- into the three dev schemas plus a seed schema. If you prefer a different
-- analyst-facing schema name, set SNOWFLAKE_SCHEMA in .env and dbt will
-- honour it.
CREATE SCHEMA IF NOT EXISTS RAW
    COMMENT = 'Landing tables written by scripts/load_raw.py';
CREATE SCHEMA IF NOT EXISTS STAGING
    COMMENT = 'dbt staging layer (views)';
CREATE SCHEMA IF NOT EXISTS INTERMEDIATE
    COMMENT = 'dbt intermediate layer (views)';
CREATE SCHEMA IF NOT EXISTS ANALYTICS
    COMMENT = 'dbt marts layer (tables) -- analyst-facing contract';
CREATE SCHEMA IF NOT EXISTS SEED
    COMMENT = 'dbt seeds (CSV reference data)';

-- 4. Sanity check: show what you just created.
SHOW SCHEMAS IN DATABASE HINDSIGHT;
SHOW WAREHOUSES LIKE 'COMPUTE_WH';

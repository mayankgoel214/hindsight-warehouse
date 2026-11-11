{{ config(materialized='table') }}

-- Per-source data-quality scorecard. Each row answers:
--   1. How many records did we actually load?
--   2. What share have a non-null event date, URL, brand, categories?
--   3. What share have a passing extraction (quote found in text)?
--   4. How does our count compare to what Hindsight's own version.json
--      reported for that day?
--
-- The singular test `assert_counts_within_tolerance` reads this table.

with source_counts as (
    select 'cpsc_recall'              as source_key,
           COUNT(*)                   as row_count,
           SUM(CASE WHEN url is not null and url <> '' THEN 1 ELSE 0 END)                as rows_with_url,
           SUM(CASE WHEN recall_date is not null THEN 1 ELSE 0 END)                      as rows_with_date,
           SUM(CASE WHEN categories_csv is not null and categories_csv <> '' THEN 1 ELSE 0 END) as rows_with_category,
           0                                                                              as rows_with_brand
    from {{ ref('stg_cpsc_recalls') }}
    union all
    select 'saferproducts_incident',
           COUNT(*),
           SUM(CASE WHEN product_description is not null THEN 1 ELSE 0 END),
           SUM(CASE WHEN incident_date is not null THEN 1 ELSE 0 END),
           SUM(CASE WHEN categories_csv is not null and categories_csv <> '' THEN 1 ELSE 0 END),
           SUM(CASE WHEN brand is not null and brand <> '' THEN 1 ELSE 0 END)
    from {{ ref('stg_saferproducts_incidents') }}
    union all
    select 'healthcanada_recall',
           COUNT(*),
           SUM(CASE WHEN url is not null and url <> '' THEN 1 ELSE 0 END),
           SUM(CASE WHEN recall_date is not null THEN 1 ELSE 0 END),
           SUM(CASE WHEN categories_csv is not null and categories_csv <> '' THEN 1 ELSE 0 END),
           SUM(CASE WHEN brand is not null and brand <> '' THEN 1 ELSE 0 END)
    from {{ ref('stg_healthcanada_recalls') }}
    union all
    select 'eu_safetygate',
           COUNT(*),
           SUM(CASE WHEN url is not null and url <> '' THEN 1 ELSE 0 END),
           SUM(CASE WHEN report_date is not null THEN 1 ELSE 0 END),
           SUM(CASE WHEN categories_csv is not null and categories_csv <> '' THEN 1 ELSE 0 END),
           SUM(CASE WHEN brand is not null and brand <> '' THEN 1 ELSE 0 END)
    from {{ ref('stg_eu_safetygate_alerts') }}
),

extraction_quality as (
    select
        source,
        COUNT(*) as extractions_total,
        SUM(CASE WHEN quote_status IN ('exact', 'near') THEN 1 ELSE 0 END) as extractions_with_supported_quote,
        SUM(CASE WHEN failure_mode is not null THEN 1 ELSE 0 END)           as extractions_with_failure_mode
    from {{ ref('stg_extractions') }}
    where in_scope = true and duplicate = false
    group by source
),

hindsight_counts as (
    select pipeline_record_count, pipeline_quote_support_rate from {{ ref('stg_hindsight_version') }}
),

-- Rows that made it into the fact table, per source.
fact_per_source as (
    select source, COUNT(*) as fact_row_count
    from {{ ref('fct_failure_reports') }}
    group by 1
)

select
    sc.source_key,
    sc.row_count,
    sc.rows_with_url,
    sc.rows_with_date,
    sc.rows_with_category,
    sc.rows_with_brand,
    ROUND(sc.rows_with_date::DOUBLE  / NULLIF(sc.row_count, 0), 4) as pct_date_populated,
    ROUND(sc.rows_with_url::DOUBLE   / NULLIF(sc.row_count, 0), 4) as pct_url_populated,
    ROUND(sc.rows_with_category::DOUBLE / NULLIF(sc.row_count, 0), 4) as pct_category_populated,
    COALESCE(fps.fact_row_count, 0) as fact_row_count,
    COALESCE(eq.extractions_total, 0) as extractions_total,
    COALESCE(eq.extractions_with_supported_quote, 0) as extractions_with_supported_quote,
    COALESCE(
        ROUND(eq.extractions_with_supported_quote::DOUBLE / NULLIF(eq.extractions_total, 0), 4),
        0
    ) as quote_support_rate,
    hc.pipeline_record_count as hindsight_pipeline_total,
    hc.pipeline_quote_support_rate as hindsight_quote_support_rate
from source_counts sc
left join extraction_quality eq on eq.source = sc.source_key
left join fact_per_source     fps on fps.source = sc.source_key
cross join hindsight_counts   hc

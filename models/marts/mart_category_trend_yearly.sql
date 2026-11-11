{{ config(materialized='table') }}

-- Per-category yearly trend with LAG() to compute YoY change in total reports
-- and in injury reports. Useful for spotting categories where the signal is
-- trending the wrong way.

with per_year as (
    select
        category_key,
        event_year,
        COUNT(*)                                                            as total_reports,
        SUM(CASE WHEN is_verified AND kind = 'recall' THEN 1 ELSE 0 END)    as verified_recalls,
        SUM(CASE WHEN NOT is_verified THEN 1 ELSE 0 END)                    as unverified_reports,
        SUM(CASE WHEN injury_level IN ('medical','serious') THEN 1 ELSE 0 END) as injury_reports,
        SUM(CASE WHEN injury_level = 'serious' THEN 1 ELSE 0 END)           as serious_reports,
        COUNT(DISTINCT record_id)                                           as unique_records
    from {{ ref('int_reports_with_extractions') }}
    where event_year is not null
      and event_year >= 2010 and event_year <= 2027
    group by 1, 2
),

lagged as (
    select
        category_key,
        event_year,
        total_reports,
        verified_recalls,
        unverified_reports,
        injury_reports,
        serious_reports,
        unique_records,
        LAG(total_reports)  OVER (PARTITION BY category_key ORDER BY event_year) as prev_year_total,
        LAG(injury_reports) OVER (PARTITION BY category_key ORDER BY event_year) as prev_year_injuries,
        -- Rolling 3-year total for smoothing.
        SUM(total_reports) OVER (
            PARTITION BY category_key
            ORDER BY event_year
            ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
        ) as rolling_3yr_total
    from per_year
)

select
    category_key,
    event_year,
    total_reports,
    verified_recalls,
    unverified_reports,
    injury_reports,
    serious_reports,
    unique_records,
    prev_year_total,
    prev_year_injuries,
    rolling_3yr_total,
    case
        when prev_year_total is null or prev_year_total = 0 then null
        else (total_reports - prev_year_total) * 1.0 / prev_year_total
    end as yoy_total_change,
    case
        when prev_year_injuries is null or prev_year_injuries = 0 then null
        else (injury_reports - prev_year_injuries) * 1.0 / prev_year_injuries
    end as yoy_injuries_change
from lagged

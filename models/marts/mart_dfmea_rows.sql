{{ config(materialized='table') }}

-- DFMEA-ready rows: one row per (record, failure_mode) with the fields a
-- mechanical engineer drops into their Design FMEA worksheet. Every row has
-- a verbatim quote from the source text proving the failure mode, and a URL
-- back to the source so an engineer can verify the claim.

with with_ext as (
    select *
    from {{ ref('int_reports_with_extractions') }}
    where is_v1_scope is true
      and failure_mode is not null
      and TRIM(failure_mode) <> ''
),

-- Severity hint: a simple ladder on the injury_level buckets. S=1 (negligible)
-- to S=10 (safety/catastrophic). This is a starting hint for an engineer, not
-- a final severity -- it says "evidence supports at least this severity".
severity_mapped as (
    select
        record_id,
        source,
        kind,
        is_verified,
        event_date,
        category_key,
        component,
        failure_mode,
        failure_mode_label,
        cause,
        effect,
        hazard_type,
        injury_level,
        quote,
        quote_status,
        quote_score,
        url,
        title,
        case injury_level
            when 'serious' then 9
            when 'medical' then 7
            when 'minor'   then 4
            when 'none'    then 2
            else null
        end as severity_hint
    from with_ext
)

select
    record_id,
    source,
    kind,
    is_verified,
    event_date,
    category_key,
    component,
    -- Prefer the free-text label (used when failure_mode = "other"), fall back
    -- to the taxonomy key. Treat empty strings as null so we don't surface a
    -- blank failure mode to an engineer.
    COALESCE(NULLIF(TRIM(failure_mode_label), ''), NULLIF(TRIM(failure_mode), '')) as failure_mode,
    cause,
    effect,
    hazard_type,
    injury_level,
    severity_hint,
    quote,
    quote_status,
    quote_score,
    url,
    title
from severity_mapped
order by category_key, failure_mode, event_date desc

{{ config(
    materialized='incremental',
    unique_key='record_id',
    on_schema_change='sync_all_columns'
) }}

-- ONE row per source record (not per category). The grain intentionally drops
-- back to the record level — a given CPSC recall is a single event even if it
-- lands in two of our twelve categories. Downstream marts that need the
-- (record, category) split use `int_reports_with_extractions` instead.
--
-- Incremental on `event_date` because new recalls and incidents arrive over
-- time; a daily `dbt build` only reprocesses rows whose event_date is newer
-- than the max in the table. The full-refresh fallback rebuilds everything.

with reports as (
    select * from {{ ref('int_reports_unioned') }}
    {% if is_incremental() %}
      where event_date >= (select coalesce(max(event_date), DATE '1900-01-01') from {{ this }})
    {% endif %}
),

brands as (
    select record_id, brand_display, manufacturer, canonical_brand, is_canonical
    from {{ ref('int_brand_canonicalized') }}
),

-- The extractor runs once per record, so we pull the first (primary)
-- extraction per record even though the exploded view has one per category.
extraction_per_record as (
    select
        record_id,
        MAX(component)          as component,
        MAX(failure_mode)       as failure_mode,
        MAX(failure_mode_label) as failure_mode_label,
        MAX(cause)              as cause,
        MAX(effect)             as effect,
        MAX(hazard_type)        as hazard_type,
        MAX(injury_level)       as injury_level,
        MAX(quote)              as quote,
        MAX(quote_status)       as quote_status,
        MAX(quote_score)        as quote_score
    from {{ ref('stg_extractions') }}
    where in_scope is true and duplicate is false
    group by record_id
),

primary_category as (
    -- Pick a deterministic primary category per record when the categorizer
    -- tagged it with more than one. v1-scope categories win over non-v1
    -- categories, then alphabetical.
    select
        record_id,
        category_key as primary_category_key,
        ROW_NUMBER() OVER (
            PARTITION BY record_id
            ORDER BY is_v1_scope DESC, category_key
        ) as rn
    from {{ ref('int_reports_with_extractions') }}
),

primary_cat_one as (
    select record_id, primary_category_key
    from primary_category
    where rn = 1
)

select
    r.record_id,
    r.source,
    r.kind,
    r.is_verified,
    r.event_date,
    r.event_year,
    r.title,
    r.text,
    r.brand_raw,
    b.brand_display,
    b.canonical_brand,
    b.manufacturer,
    b.is_canonical as brand_is_canonical,
    r.categories_csv,
    pc.primary_category_key,
    r.is_sharkninja,
    e.component,
    e.failure_mode,
    e.failure_mode_label,
    e.cause,
    e.effect,
    e.hazard_type,
    COALESCE(e.injury_level, r.injury_level_raw) as injury_level,
    e.quote,
    e.quote_status,
    e.quote_score,
    r.hazard_types_raw,
    r.url,
    CURRENT_TIMESTAMP as loaded_at
from reports r
left join brands b              on b.record_id = r.record_id
left join extraction_per_record e on e.record_id = r.record_id
left join primary_cat_one pc    on pc.record_id = r.record_id

{{ config(materialized='view') }}

-- Attaches the LLM extraction fields (failure_mode, cause, effect, hazard
-- type, quote) to each exploded (record, category) row. Extractions join on
-- `record_id`; only records that actually went through the extractor and
-- survived quote verification end up with a non-null failure_mode. The
-- extractor runs per record, not per category, so the same extraction is
-- replicated across a record's categories — that is intentional for the
-- per-category marts.

with reports as (
    select * from {{ ref('int_reports_categorized') }}
),

extractions as (
    select * from {{ ref('stg_extractions') }}
    where in_scope is true
      and duplicate is false
),

v1 as (
    select category_key from (values
        ('pressure_multi_cooker'),
        ('air_fryer'),
        ('blender_food_processor'),
        ('ice_cream_frozen_drink'),
        ('coffee_maker'),
        ('kettle'),
        ('oven_toaster'),
        ('grill')
    ) as v(category_key)
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
    r.is_sharkninja,
    r.injury_level_raw,
    r.hazard_types_raw,
    r.url,
    r.category_key,
    -- True iff this category is in the Ninja v1 scope the LLM extractor used.
    (v1.category_key is not null) as is_v1_scope,
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
    e.record_hash
from reports r
left join extractions e on r.record_id = e.record_id
left join v1 on r.category_key = v1.category_key

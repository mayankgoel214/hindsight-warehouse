{{ config(materialized='view') }}

-- Explodes the comma-separated `categories_csv` into one row per
-- (record, category) pair. Hindsight tags a record with every category that
-- matches; a blender/food-processor combo lands in both `blender_food_processor`
-- and potentially `oven_toaster`. Marts work best when each (category,
-- failure_mode) is its own bucket, so we flatten here.

{% if target.type == 'snowflake' %}
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
    TRIM(cat_flat.value::VARCHAR) as category_key
from {{ ref('int_reports_unioned') }} r,
     LATERAL FLATTEN(input => SPLIT(r.categories_csv, ',')) cat_flat
where TRIM(cat_flat.value::VARCHAR) <> ''
{% else %}
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
    TRIM(cat.category_value) as category_key
from {{ ref('int_reports_unioned') }} r,
     UNNEST(string_split(r.categories_csv, ',')) as cat(category_value)
where TRIM(cat.category_value) <> ''
{% endif %}

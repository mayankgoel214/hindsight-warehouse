{{ config(materialized='view') }}

-- Unifies the four source-specific staging models into one shape. Downstream
-- marts never have to know which source a row came from unless they want to.
-- Each source contributes a (record_id, source, kind, is_verified, event_date,
-- text, brand_raw, categories_csv, is_sharkninja, injury_level, url) tuple.

with cpsc as (
    select
        record_id,
        source,
        kind,
        is_verified,
        recall_date as event_date,
        title,
        text,
        null::VARCHAR as brand_raw,  -- CPSC brands live inside Manufacturers/Importers; the extraction join brings canonical brand
        categories_csv,
        is_sharkninja,
        null::VARCHAR as injury_level_raw,
        hazard_types_raw,
        url
    from {{ ref('stg_cpsc_recalls') }}
),

saferproducts as (
    select
        record_id,
        source,
        kind,
        is_verified,
        incident_date as event_date,
        product_description as title,
        text,
        brand as brand_raw,
        categories_csv,
        is_sharkninja,
        injury_level as injury_level_raw,
        null::VARCHAR as hazard_types_raw,
        url
    from {{ ref('stg_saferproducts_incidents') }}
),

healthcanada as (
    select
        record_id,
        source,
        kind,
        is_verified,
        recall_date as event_date,
        title,
        text,
        brand as brand_raw,
        categories_csv,
        is_sharkninja,
        null::VARCHAR as injury_level_raw,
        hazard_short as hazard_types_raw,
        url
    from {{ ref('stg_healthcanada_recalls') }}
),

eu as (
    select
        record_id,
        source,
        kind,
        is_verified,
        report_date as event_date,
        product_name as title,
        text,
        brand as brand_raw,
        categories_csv,
        is_sharkninja,
        null::VARCHAR as injury_level_raw,
        risk_type as hazard_types_raw,
        url
    from {{ ref('stg_eu_safetygate_alerts') }}
),

unioned as (
    select * from cpsc
    union all
    select * from saferproducts
    union all
    select * from healthcanada
    union all
    select * from eu
)

select
    record_id,
    source,
    kind,
    is_verified,
    event_date,
    EXTRACT(year FROM event_date)::INTEGER as event_year,
    title,
    text,
    brand_raw,
    categories_csv,
    is_sharkninja,
    injury_level_raw,
    hazard_types_raw,
    url
from unioned
where event_date is not null

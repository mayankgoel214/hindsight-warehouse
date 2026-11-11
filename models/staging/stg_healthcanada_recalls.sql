{{ config(materialized='view') }}

-- Health Canada recall staging. Verified regulator actions. Many of these
-- duplicate CPSC recalls (joint US/Canada actions); the intermediate layer
-- carries the dedup key that resolves the overlap.

with raw as (
    select
        source_record_id,
        payload,
        _loaded_at
    from {{ source('raw', 'healthcanada_recalls') }}
),

typed as (
    select
        'healthcanada-' || source_record_id                     as record_id,
        source_record_id                                        as hc_nid,
        {{ json_text('payload', 'title') }}                     as title,
        {{ json_text('payload', 'url') }}                       as url,
        {{ json_text('payload', 'product') }}                   as product,
        {{ json_text('payload', 'issue') }}                     as hazard_short,
        {{ json_text('payload', 'category') }}                  as category_raw,
        {{ parse_date_iso(json_text('payload', 'lastUpdated')) }} as last_updated,
        {{ parse_date_iso(json_text('payload', 'recallDate')) }}  as recall_date,
        {{ json_text('payload', 'whatToDo') }}                  as what_to_do,
        {{ json_text('payload', 'hazard') }}                    as hazard_detail,
        {{ json_text('payload', 'background') }}                as background,
        {{ json_text('payload', 'brand') }}                     as brand,
        {{ json_text('payload', 'body') }}                      as body_text,
        {{ json_array_to_string('payload', 'categories', ',') }} as categories_csv,
        {{ json_bool('payload', 'sharkninja') }}                as is_sharkninja,
        payload                                                 as payload,
        _loaded_at                                              as loaded_at
    from raw
)

select
    record_id,
    'healthcanada_recall'::VARCHAR                              as source,
    'recall'::VARCHAR                                           as kind,
    true                                                        as is_verified,
    hc_nid,
    title,
    url,
    product,
    hazard_short,
    hazard_detail,
    category_raw,
    -- The Health Canada feed gives lastUpdated but not always recallDate.
    -- Use the earlier of the two as the effective recall date.
    COALESCE(recall_date, last_updated)                         as recall_date,
    what_to_do,
    background,
    brand,
    body_text,
    categories_csv,
    is_sharkninja,
    NULLIF(
        TRIM(
            COALESCE(title, '') || ' '
            || COALESCE(hazard_short, '') || ' '
            || COALESCE(hazard_detail, '') || ' '
            || COALESCE(product, '')
        ),
        ''
    )                                                           as text,
    payload,
    loaded_at
from typed
where categories_csv is not null
  and categories_csv <> ''

{{ config(materialized='view') }}

-- CPSC recall staging. One row per recall, typed fields pulled out of the
-- raw JSON payload. Every CPSC recall is a VERIFIED regulator action.

with raw as (
    select
        source_record_id,
        payload,
        _loaded_at
    from {{ source('raw', 'cpsc_recalls') }}
),

typed as (
    select
        -- Stable id for the downstream unioned fact table.
        'cpsc-' || source_record_id                             as record_id,
        source_record_id                                        as cpsc_recall_id,
        {{ json_text('payload', 'RecallNumber') }}              as recall_number,
        {{ json_text('payload', 'Title') }}                     as title,
        {{ json_text('payload', 'URL') }}                       as url,
        {{ parse_date_iso(json_text('payload', 'RecallDate')) }} as recall_date,
        {{ json_text('payload', 'Description') }}               as description,
        {{ json_array_to_string('payload', 'Hazards', ' ') }}   as hazards_text,
        {{ json_array_to_string('payload', 'Remedies', ' ') }}  as remedies_text,
        {{ json_array_to_string('payload', 'Injuries', ' ') }}  as injuries_text,
        {{ json_array_to_string('payload', 'HazardTypes', ', ') }} as hazard_types_raw,
        {{ json_array_to_string('payload', 'categories', ',') }}   as categories_csv,
        {{ json_bool('payload', 'sharkninja') }}                as is_sharkninja,
        payload                                                 as payload,
        _loaded_at                                              as loaded_at
    from raw
),

final as (
    select
        record_id,
        'cpsc_recall'::VARCHAR                                  as source,
        'recall'::VARCHAR                                       as kind,
        true                                                    as is_verified,
        cpsc_recall_id,
        recall_number,
        title,
        url,
        recall_date,
        description,
        hazards_text,
        remedies_text,
        injuries_text,
        hazard_types_raw,
        categories_csv,
        is_sharkninja,
        -- Short display text used by the fact table for grouping and search.
        NULLIF(TRIM(COALESCE(title, '') || ' ' || COALESCE(hazards_text, '') || ' ' || COALESCE(description, '')), '') as text,
        payload,
        loaded_at
    from typed
    where recall_date is not null  -- drop malformed dates (none observed; the filter is defensive)
      and categories_csv is not null
      and categories_csv <> ''      -- drop recalls outside the twelve tracked categories
)

select * from final

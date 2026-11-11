{{ config(materialized='view') }}

-- Single-row control table carrying the counts Hindsight's pipeline reported
-- the day the data was pulled. `mart_data_quality` compares its own numbers
-- back to these as a cross-check.

with raw as (
    select payload, _loaded_at from {{ source('raw', 'hindsight_version') }}
)

select
    {{ parse_date_iso(json_text('payload', 'date')) }}          as snapshot_date,
    {{ json_int('payload', 'records') }}                        as pipeline_record_count,
    TRY_CAST({{ json_text('payload', 'pipeline.quote_support_rate') }} AS DOUBLE) as pipeline_quote_support_rate,
    _loaded_at                                                  as loaded_at
from raw

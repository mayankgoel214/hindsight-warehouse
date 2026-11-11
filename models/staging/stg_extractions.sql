{{ config(materialized='view') }}

-- LLM extraction outputs from the Hindsight pipeline. One row per record that
-- made it through quote verification. Downstream models join on record_id.

with raw as (
    select
        payload,
        _loaded_at
    from {{ source('raw', 'extractions') }}
)

select
    {{ json_text('payload', 'id') }}                            as record_id,
    {{ json_text('payload', 'source') }}                        as source,
    {{ json_bool('payload', 'in_scope') }}                      as in_scope,
    {{ json_text('payload', 'scope_reason') }}                  as scope_reason,
    {{ json_text('payload', 'component') }}                     as component,
    {{ json_text('payload', 'failure_mode') }}                  as failure_mode,
    {{ json_text('payload', 'failure_mode_label') }}            as failure_mode_label,
    {{ json_text('payload', 'cause') }}                         as cause,
    {{ json_text('payload', 'effect') }}                        as effect,
    {{ json_text('payload', 'hazard_type') }}                   as hazard_type,
    {{ json_text('payload', 'injury') }}                        as injury_level,
    {{ json_text('payload', 'quote') }}                         as quote,
    {{ json_text('payload', 'quote_status') }}                  as quote_status,
    TRY_CAST({{ json_text('payload', 'quote_score') }} AS DOUBLE) as quote_score,
    {{ json_text('payload', 'hash') }}                          as record_hash,
    {{ json_bool('payload', 'duplicate') }}                     as duplicate,
    _loaded_at                                                  as loaded_at
from raw

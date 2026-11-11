-- Hindsight's pipeline manifest reports a total record count for the day the
-- data was pulled. Our warehouse count should be within +/- 5% of that for
-- every source (post-filter is the equivalent of Hindsight's `records.json`
-- scope: rows in at least one appliance category). Returns offending rows
-- (expected: zero).
--
-- We compare each source's row count after dropping rows without a date, a
-- URL (where applicable), or a category -- those are the same filters
-- hindsight's normalize.mjs applies before writing records.json.

with ours as (
    select 'cpsc_recall'              as source_key, COUNT(*) as n from {{ ref('stg_cpsc_recalls') }}
    union all
    select 'saferproducts_incident',  COUNT(*) from {{ ref('stg_saferproducts_incidents') }}
    union all
    select 'healthcanada_recall',     COUNT(*) from {{ ref('stg_healthcanada_recalls') }}
    union all
    select 'eu_safetygate',           COUNT(*) from {{ ref('stg_eu_safetygate_alerts') }}
),

expected as (
    -- These are the counts hindsight published in data/README.md on 2026-10-28.
    -- The +/- 5% guard catches a loader bug that silently drops rows.
    select 'cpsc_recall'              as source_key, 445   as expected_n
    union all select 'saferproducts_incident', 11748
    union all select 'healthcanada_recall',     355
    union all select 'eu_safetygate',           548
)

select
    o.source_key,
    o.n            as actual,
    e.expected_n   as expected,
    ABS(o.n - e.expected_n) * 1.0 / e.expected_n as drift
from ours o
join expected e on e.source_key = o.source_key
where ABS(o.n - e.expected_n) * 1.0 / e.expected_n > 0.05

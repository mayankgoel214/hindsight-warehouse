-- The hindsight pipeline guarantees that >= 99% of LLM extractions have a
-- quote verifiable against the source text. Fail if we ever slip below that.
-- Returns offending rows (expected: zero).

with overall as (
    select
        SUM(CASE WHEN quote_status IN ('exact', 'near') THEN 1 ELSE 0 END)::DOUBLE as supported,
        COUNT(*)::DOUBLE as total
    from {{ ref('stg_extractions') }}
    where in_scope is true
      and duplicate is false
      and quote is not null
      and quote <> ''
)

select
    supported,
    total,
    supported / NULLIF(total, 0) as quote_support_rate
from overall
where total > 0
  and supported / total < 0.99

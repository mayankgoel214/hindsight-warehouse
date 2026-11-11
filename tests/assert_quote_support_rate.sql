-- The hindsight pipeline guarantees that >= 99% of LLM extractions have a
-- quote verifiable against the source text. Fail if we ever slip below that.
-- Returns offending rows (expected: zero).

with overall as (
    select
        SUM(CASE WHEN quote_status IN ('exact', 'near') THEN 1 ELSE 0 END)::DOUBLE as n_supported,
        COUNT(*)::DOUBLE as n_total
    from {{ ref('stg_extractions') }}
    where in_scope = true
      and duplicate = false
      and quote is not null
      and quote <> ''
)

select
    n_supported,
    n_total,
    n_supported / NULLIF(n_total, 0) as quote_support_rate
from overall
where n_total > 0
  and n_supported / n_total < 0.99

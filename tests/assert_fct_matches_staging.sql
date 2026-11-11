-- The record count in fct_failure_reports should equal the row count in
-- int_reports_unioned, because the fact table is 1:1 with distinct records.
-- Drift here means the incremental build or a join blew up fan-out.

with fct as (
    select COUNT(*) as n from {{ ref('fct_failure_reports') }}
),
src as (
    select COUNT(*) as n from {{ ref('int_reports_unioned') }}
)

select fct.n as fct_rows, src.n as unioned_rows, (fct.n - src.n) as diff
from fct, src
where fct.n <> src.n

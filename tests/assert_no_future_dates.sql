-- No event in the warehouse should be dated in the future. Allow a 7-day
-- grace window for records that were published in a different timezone than
-- the one CI runs in. Returns offending rows (expected: zero).

select
    record_id,
    source,
    event_date
from {{ ref('fct_failure_reports') }}
where event_date > CURRENT_DATE + INTERVAL 7 DAY

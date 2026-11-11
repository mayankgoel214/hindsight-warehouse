{{ config(materialized='table') }}

-- Compact date dimension covering the span of events in the warehouse. Years
-- 2005 to 2027 because the EU and CPSC feeds reach back to 2005 and we want a
-- small buffer for near-future recall dates.

with bounds as (
    select
        DATE '2005-01-01' as start_date,
        DATE '2027-12-31' as end_date
)

{% if target.type == 'snowflake' %}
, dates as (
    select DATEADD(day, seq4(), start_date) as date_day
    from TABLE(GENERATOR(ROWCOUNT => 10000)), bounds
    where DATEADD(day, seq4(), start_date) <= end_date
)
{% else %}
, dates as (
    select date_day
    from bounds,
         UNNEST(generate_series(start_date, end_date, INTERVAL 1 DAY)) as g(date_day)
)
{% endif %}

select
    date_day,
    EXTRACT(year  FROM date_day)::INTEGER as year,
    EXTRACT(month FROM date_day)::INTEGER as month,
    EXTRACT(day   FROM date_day)::INTEGER as day_of_month,
    EXTRACT(quarter FROM date_day)::INTEGER as quarter,
    EXTRACT(dow   FROM date_day)::INTEGER as day_of_week
from dates

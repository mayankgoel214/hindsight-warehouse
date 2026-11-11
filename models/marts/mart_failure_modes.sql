{{ config(materialized='table') }}

-- Category x failure_mode aggregate. The "failure mode" fact table a safety
-- engineer actually wants to read: for each (category, failure_mode), how
-- many verified recalls vs unverified incidents, how many injuries, which
-- years span the evidence, and the top three brands observed.

with with_ext as (
    select *
    from {{ ref('int_reports_with_extractions') }}
    where is_v1_scope = true
      and failure_mode is not null
      and TRIM(failure_mode) <> ''
),

brands as (
    select record_id, brand_display from {{ ref('int_brand_canonicalized') }}
),

joined as (
    select
        w.record_id,
        w.category_key,
        w.failure_mode,
        w.failure_mode_label,
        w.kind,
        w.is_verified,
        w.event_year,
        w.injury_level,
        b.brand_display
    from with_ext w
    left join brands b on b.record_id = w.record_id
),

-- Per (category, failure_mode) counts and year span.
agg as (
    select
        category_key,
        failure_mode,
        MAX(failure_mode_label) as failure_mode_label,
        SUM(CASE WHEN is_verified AND kind = 'recall' THEN 1 ELSE 0 END)  as verified_recalls,
        SUM(CASE WHEN is_verified AND kind = 'alert'  THEN 1 ELSE 0 END)  as verified_alerts,
        SUM(CASE WHEN NOT is_verified THEN 1 ELSE 0 END)                  as unverified_reports,
        SUM(CASE WHEN injury_level IN ('medical', 'serious') THEN 1 ELSE 0 END) as injury_reports,
        SUM(CASE WHEN injury_level = 'serious' THEN 1 ELSE 0 END)               as serious_reports,
        COUNT(DISTINCT record_id)                                         as total_reports,
        MIN(event_year)                                                   as first_year,
        MAX(event_year)                                                   as last_year
    from joined
    group by 1, 2
),

-- Window-ranked top brands per (category, failure_mode) via a conditional
-- aggregation. We take the three brands with the highest record count.
brand_counts as (
    select
        category_key,
        failure_mode,
        brand_display,
        COUNT(*) as n,
        ROW_NUMBER() OVER (
            PARTITION BY category_key, failure_mode
            ORDER BY COUNT(*) DESC, brand_display
        ) as rn
    from joined
    where brand_display is not null
    group by 1, 2, 3
),

top_brands as (
    select
        category_key,
        failure_mode,
        {{ dbt.listagg('brand_display', "', '") }} as top_brands
    from (
        select category_key, failure_mode, brand_display
        from brand_counts
        where rn <= 3
        order by category_key, failure_mode, rn
    ) t
    group by 1, 2
)

select
    a.category_key,
    a.failure_mode,
    a.failure_mode_label,
    a.verified_recalls,
    a.verified_alerts,
    a.unverified_reports,
    a.injury_reports,
    a.serious_reports,
    a.total_reports,
    a.first_year,
    a.last_year,
    tb.top_brands,
    -- Risk score: injuries-weighted sum, verified counts 2x, serious 3x.
    (3 * a.serious_reports + a.injury_reports + 2 * (a.verified_recalls + a.verified_alerts)) as risk_score,
    -- Rank by risk within each category (window function).
    RANK() OVER (
        PARTITION BY a.category_key
        ORDER BY (3 * a.serious_reports + a.injury_reports + 2 * (a.verified_recalls + a.verified_alerts)) DESC
    ) as rank_in_category
from agg a
left join top_brands tb
       on tb.category_key = a.category_key
      and tb.failure_mode = a.failure_mode

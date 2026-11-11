{{ config(materialized='view') }}

-- Maps each report's raw brand string onto a canonical display brand +
-- manufacturer, using the `brand_aliases` seed. The matcher strips legal
-- suffixes and punctuation (see the brand_sig macro), then tries progressively
-- shorter prefixes until it finds an alias. Unmatched brands get Title Case'd
-- so the dim doesn't lose them; a separate `is_canonical` flag lets marts
-- weigh mapped vs. unmapped brands.

with reports as (
    select record_id, source, brand_raw from {{ ref('int_reports_unioned') }}
),

aliases as (
    select LOWER(TRIM(alias)) as alias, display, manufacturer
    from {{ ref('brand_aliases') }}
),

signature as (
    select
        record_id,
        source,
        brand_raw,
        {{ brand_sig('brand_raw') }} as brand_sig_raw
    from reports
),

collapsed as (
    select
        record_id,
        source,
        brand_raw,
        -- Collapse multiple spaces that the suffix strip may leave behind.
        TRIM(REGEXP_REPLACE(brand_sig_raw, '\s+', ' ' {{ re_flag_g() }})) as brand_sig
    from signature
),

tokens as (
    select
        record_id,
        source,
        brand_raw,
        brand_sig,
        SPLIT_PART(brand_sig, ' ', 1)                     as w1,
        SPLIT_PART(brand_sig, ' ', 1) || ' ' || SPLIT_PART(brand_sig, ' ', 2) as w2,
        SPLIT_PART(brand_sig, ' ', 1) || ' ' ||
        SPLIT_PART(brand_sig, ' ', 2) || ' ' ||
        SPLIT_PART(brand_sig, ' ', 3)                     as w3
    from collapsed
)

select
    t.record_id,
    t.source,
    t.brand_raw,
    t.brand_sig,
    COALESCE(a3.display, a2.display, a1.display)          as canonical_brand,
    COALESCE(a3.manufacturer, a2.manufacturer, a1.manufacturer) as manufacturer,
    COALESCE(
        a3.display, a2.display, a1.display,
        -- Unmapped brands keep their cleaned lower-case signature; marts can
        -- still group them, and `is_canonical = false` flags the fallback.
        NULLIF(TRIM(t.brand_sig), '')
    )                                                     as brand_display,
    (COALESCE(a3.display, a2.display, a1.display) is not null) as is_canonical
from tokens t
left join aliases a1 on a1.alias = TRIM(t.w1) and TRIM(t.w1) <> ''
left join aliases a2 on a2.alias = TRIM(t.w2) and TRIM(t.w2) <> ''
left join aliases a3 on a3.alias = TRIM(t.w3) and TRIM(t.w3) <> ''

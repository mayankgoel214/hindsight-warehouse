{{ config(materialized='table') }}

-- One row per canonical (or fallback) brand display name. Counts the records
-- that resolved to this brand across all four sources so analysts can quickly
-- see which brands dominate the warehouse. The three SharkNinja rollups
-- ("Ninja (SharkNinja)", "Shark", "Euro-Pro") collapse into one here.

with brands as (
    select
        brand_display,
        MAX(canonical_brand) as canonical_brand,
        MAX(manufacturer)    as manufacturer,
        {{ dbt.bool_or('is_canonical') }} as is_canonical,
        COUNT(*) as record_count
    from {{ ref('int_brand_canonicalized') }}
    where brand_display is not null
    group by 1
),

ranked as (
    select
        brand_display,
        canonical_brand,
        manufacturer,
        is_canonical,
        record_count,
        ROW_NUMBER() OVER (ORDER BY record_count DESC, brand_display) as rank_overall
    from brands
)

select
    -- A deterministic surrogate key beats using brand_display directly in a
    -- fact table because brand_display is editable in the seed.
    {{ dbt_utils.generate_surrogate_key(['brand_display']) }} as brand_sk,
    brand_display,
    canonical_brand,
    manufacturer,
    is_canonical,
    record_count,
    rank_overall
from ranked

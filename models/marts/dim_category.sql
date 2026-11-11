{{ config(materialized='table') }}

-- One row per category key, lifted directly from the seed. The `is_v1_scope`
-- flag marks the eight Ninja categories the LLM extractor's failure-mode
-- taxonomy covers; other categories still show up in counts, but DFMEA rows
-- are gated to v1.

with v1 as (
    select category_key, true as is_v1_scope from (values
        ('pressure_multi_cooker'),
        ('air_fryer'),
        ('blender_food_processor'),
        ('ice_cream_frozen_drink'),
        ('coffee_maker'),
        ('kettle'),
        ('oven_toaster'),
        ('grill')
    ) as v(category_key)
)

select
    s.key           as category_key,
    s.label         as category_label,
    s.family        as category_family,
    COALESCE(v1.is_v1_scope, false) as is_v1_scope
from {{ ref('category_labels') }} s
left join v1 on v1.category_key = s.key

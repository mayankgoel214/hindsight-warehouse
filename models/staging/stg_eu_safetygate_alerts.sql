{{ config(materialized='view') }}

-- EU Safety Gate alert staging. Verified alerts from the EU/EFTA market
-- surveillance system (formerly RAPEX). The `danger` field is the richest
-- narrative; it frequently names the EN/IEC standard that was breached.

with raw as (
    select
        source_record_id,
        payload,
        _loaded_at
    from {{ source('raw', 'eu_safetygate_alerts') }}
),

typed as (
    select
        'eu-' || source_record_id                               as record_id,
        source_record_id                                        as case_number_clean,
        {{ json_text('payload', 'caseNumber') }}                as case_number,
        {{ json_text('payload', 'report') }}                    as report_slug,
        {{ parse_date_dmy(json_text('payload', 'reportDate')) }} as report_date,
        {{ json_text('payload', 'url') }}                       as url,
        {{ json_text('payload', 'category') }}                  as category_raw,
        {{ json_text('payload', 'product') }}                   as product,
        {{ json_text('payload', 'brand') }}                     as brand,
        {{ json_text('payload', 'name') }}                      as product_name,
        {{ json_text('payload', 'model') }}                     as model,
        {{ json_text('payload', 'riskType') }}                  as risk_type,
        {{ json_text('payload', 'riskLevel') }}                 as risk_level,
        {{ json_text('payload', 'danger') }}                    as danger,
        {{ json_text('payload', 'measures') }}                  as measures,
        {{ json_text('payload', 'description') }}               as description,
        {{ json_text('payload', 'notifyingCountry') }}          as notifying_country,
        {{ json_text('payload', 'countryOfOrigin') }}           as country_of_origin,
        {{ json_text('payload', 'alertType') }}                 as alert_type,
        {{ json_array_to_string('payload', 'categories', ',') }} as categories_csv,
        {{ json_bool('payload', 'sharkninja') }}                as is_sharkninja,
        payload                                                 as payload,
        _loaded_at                                              as loaded_at
    from raw
)

select
    record_id,
    'eu_safetygate'::VARCHAR                                    as source,
    'alert'::VARCHAR                                            as kind,
    true                                                        as is_verified,
    case_number,
    case_number_clean,
    report_slug,
    report_date,
    url,
    category_raw,
    product,
    brand,
    product_name,
    model,
    risk_type,
    risk_level,
    danger,
    measures,
    description,
    notifying_country,
    country_of_origin,
    alert_type,
    categories_csv,
    is_sharkninja,
    NULLIF(
        TRIM(
            COALESCE(product, '') || ' '
            || COALESCE(product_name, '') || ' '
            || COALESCE(danger, '') || ' '
            || COALESCE(description, '')
        ),
        ''
    )                                                           as text,
    payload,
    loaded_at
from typed
where report_date is not null
  and categories_csv is not null
  and categories_csv <> ''

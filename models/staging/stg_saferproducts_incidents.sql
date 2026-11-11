{{ config(materialized='view') }}

-- SaferProducts.gov incident staging. One row per consumer-submitted report.
-- These are UNVERIFIED consumer claims. The `is_verified` flag is set to
-- false for every row so downstream analytics never silently treat these as
-- regulator-confirmed failures.

with raw as (
    select
        source_record_id,
        payload,
        _loaded_at
    from {{ source('raw', 'saferproducts_incidents') }}
),

typed as (
    select
        'saferproducts-' || source_record_id                    as record_id,
        source_record_id                                        as report_no,
        -- SaferProducts stores dates as M/D/YYYY strings. The parse_date_us
        -- macro resolves to STRPTIME on DuckDB and TRY_TO_DATE on Snowflake.
        {{ parse_date_us(json_text('payload', 'reportDate')) }}      as incident_date,
        {{ parse_date_us(json_text('payload', 'publicationDate')) }} as publication_date,
        {{ json_text('payload', 'submitterCategory') }}         as submitter_category,
        {{ json_text('payload', 'productDescription') }}        as product_description,
        {{ json_text('payload', 'productCategory') }}           as product_category,
        {{ json_text('payload', 'productSubCategory') }}        as product_subcategory,
        {{ json_text('payload', 'productType') }}               as product_type,
        {{ json_text('payload', 'productCode') }}               as product_code,
        {{ json_text('payload', 'manufacturer') }}              as manufacturer,
        {{ json_text('payload', 'brand') }}                     as brand,
        {{ json_text('payload', 'model') }}                     as model,
        {{ json_text('payload', 'incidentDescription') }}       as incident_description,
        {{ json_text('payload', 'state') }}                     as state,
        {{ json_text('payload', 'location') }}                  as incident_location,
        {{ json_text('payload', 'victimSeverity') }}            as victim_severity,
        {{ json_text('payload', 'victimSex') }}                 as victim_sex,
        {{ json_int('payload', 'victimAge') }}                  as victim_age,
        {{ json_text('payload', 'submitterHasProduct') }}       as submitter_has_product,
        {{ json_text('payload', 'contactedManufacturer') }}     as contacted_manufacturer,
        {{ json_array_to_string('payload', 'categories', ',') }} as categories_csv,
        {{ json_bool('payload', 'sharkninja') }}                as is_sharkninja,
        payload                                                 as payload,
        _loaded_at                                              as loaded_at
    from raw
),

classified as (
    select
        record_id,
        'saferproducts_incident'::VARCHAR                       as source,
        'incident'::VARCHAR                                     as kind,
        false                                                   as is_verified,
        report_no,
        incident_date,
        publication_date,
        submitter_category,
        product_description,
        product_category,
        product_subcategory,
        product_type,
        product_code,
        manufacturer,
        brand,
        model,
        incident_description,
        state,
        incident_location,
        victim_severity,
        victim_sex,
        victim_age,
        submitter_has_product,
        contacted_manufacturer,
        categories_csv,
        is_sharkninja,
        -- Buckets the text severity into an ordered injury level so marts can
        -- aggregate it. Matches the mapping used in hindsight/normalize.mjs.
        case
            when LOWER(COALESCE(victim_severity, '')) like '%death%' then 'serious'
            when LOWER(COALESCE(victim_severity, '')) like '%hospital%' then 'serious'
            when LOWER(COALESCE(victim_severity, '')) like '%serious%' then 'serious'
            when LOWER(COALESCE(victim_severity, '')) like '%medical%' then 'medical'
            when LOWER(COALESCE(victim_severity, '')) like '%minor%' then 'minor'
            when LOWER(COALESCE(victim_severity, '')) like '%no injury%' then 'none'
            when victim_severity is null or victim_severity = '' then 'unknown'
            else 'unknown'
        end                                                     as injury_level,
        NULLIF(TRIM(COALESCE(product_description, '') || ' ' || COALESCE(incident_description, '')), '') as text,
        -- Public report pages are keyed by report number. Mirrors the URL
        -- hindsight/normalize.mjs builds.
        'https://www.saferproducts.gov/PublicSearch/Detail?reportId=' || report_no as url,
        payload,
        loaded_at
    from typed
    where incident_date is not null
      and categories_csv is not null
      and categories_csv <> ''
)

select * from classified

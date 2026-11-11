{# ---------------------------------------------------------------------
   JSON-access macros that work across DuckDB and Snowflake.

   The raw tables land JSON records in a `payload` column (JSON type in
   DuckDB, VARIANT in Snowflake). Staging models need to pull typed fields
   out of that payload. Both warehouses can do it; the syntax differs:

      DuckDB     json_extract_string(payload, '$.field') / payload->>'field'
      Snowflake  payload:field::VARCHAR

   Rather than sprinkle `{% if target.type == 'snowflake' %}` branches across
   every staging model, the macros below hide the difference. Staging SQL
   reads the same way on both targets.
--------------------------------------------------------------------- #}

{% macro json_text(column, path) %}
    {%- if target.type == 'snowflake' -%}
        {{ column }}:{{ path }}::VARCHAR
    {%- else -%}
        json_extract_string({{ column }}, '$.{{ path }}')
    {%- endif -%}
{% endmacro %}


{% macro json_int(column, path) %}
    {%- if target.type == 'snowflake' -%}
        TRY_TO_NUMBER({{ column }}:{{ path }}::VARCHAR)
    {%- else -%}
        TRY_CAST(json_extract_string({{ column }}, '$.{{ path }}') AS BIGINT)
    {%- endif -%}
{% endmacro %}


{% macro json_bool(column, path) %}
    {%- if target.type == 'snowflake' -%}
        {{ column }}:{{ path }}::BOOLEAN
    {%- else -%}
        CAST(json_extract({{ column }}, '$.{{ path }}') AS BOOLEAN)
    {%- endif -%}
{% endmacro %}


{% macro json_array_elements_text(column, path) %}
    {#- Returns a scalar array of text. Both warehouses expose the raw array
        value; the staging code then flattens it with a UNNEST equivalent. -#}
    {%- if target.type == 'snowflake' -%}
        {{ column }}:{{ path }}
    {%- else -%}
        json_extract({{ column }}, '$.{{ path }}')
    {%- endif -%}
{% endmacro %}


{% macro json_array_to_string(column, path, sep) %}
    {#- Produce a single joined string from a JSON array of strings. Used in
        staging when we want a canonical comma-separated form of brands or
        categories for easy debugging; the authoritative array is still
        exposed separately. -#}
    {%- if target.type == 'snowflake' -%}
        ARRAY_TO_STRING({{ column }}:{{ path }}, '{{ sep }}')
    {%- else -%}
        array_to_string(
            CAST(json_extract({{ column }}, '$.{{ path }}') AS VARCHAR[]),
            '{{ sep }}'
        )
    {%- endif -%}
{% endmacro %}


{% macro parse_date_iso(expr) %}
    {%- if target.type == 'snowflake' -%}
        TRY_TO_DATE({{ expr }})
    {%- else -%}
        TRY_CAST({{ expr }} AS DATE)
    {%- endif -%}
{% endmacro %}


{% macro lower_trim(expr) %}
    LOWER(TRIM({{ expr }}))
{% endmacro %}


{% macro parse_date_us(expr) %}
    {#- Parse a M/D/YYYY string into a DATE. Both DuckDB and Snowflake
        tolerate single- and double-digit month/day via their lenient
        parsers; we null out malformed strings rather than failing. -#}
    {%- if target.type == 'snowflake' -%}
        TRY_TO_DATE({{ expr }}, 'MM/DD/YYYY')
    {%- else -%}
        TRY_CAST(STRPTIME({{ expr }}, '%-m/%-d/%Y') AS DATE)
    {%- endif -%}
{% endmacro %}


{% macro parse_date_dmy(expr) %}
    {#- Day/Month/Year form used by the EU Safety Gate feed. -#}
    {%- if target.type == 'snowflake' -%}
        TRY_TO_DATE({{ expr }}, 'DD/MM/YYYY')
    {%- else -%}
        TRY_CAST(STRPTIME({{ expr }}, '%-d/%-m/%Y') AS DATE)
    {%- endif -%}
{% endmacro %}

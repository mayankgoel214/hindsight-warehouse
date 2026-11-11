{# ---------------------------------------------------------------------
   brand_sig(expr): collapse a raw brand string to a lowercase, punctuation-
   stripped, suffix-stripped "signature" the alias map keys off.

     "SharkNinja Operating LLC"   -> "sharkninja operating"  -> "sharkninja"
     "Char-Broil LLC"             -> "char broil"            -> matches alias
     "Sunbeam Products, Inc. d/b/a Jarden" -> "sunbeam products"

   DuckDB regexp_replace takes a `'g'` flag as the 4th arg; Snowflake applies
   replace-all by default (the position/occurrence/parameters args are
   optional). The regex flag is handled by the re_flag macro below so staging
   code stays readable.
--------------------------------------------------------------------- #}

{% macro re_flag_g() %}
    {%- if target.type == 'snowflake' -%}
        , 1, 0, 'i'
    {%- else -%}
        , 'ig'
    {%- endif -%}
{% endmacro %}

{% macro brand_sig(expr) %}
    LOWER(
        TRIM(
            REGEXP_REPLACE(
                REGEXP_REPLACE(
                    REGEXP_REPLACE(
                        COALESCE({{ expr }}, ''),
                        '\s+d/?b/?a\s+.*$',
                        ''
                        {{ re_flag_g() }}
                    ),
                    '\b(l\.?l\.?c\.?|inc\.?|corp(oration)?|co\.?|ltd\.?|gmbh|operating|holdings?|aktiengesellschaft|dba)\b',
                    ' '
                    {{ re_flag_g() }}
                ),
                '[^a-zA-Z0-9 ]+',
                ' '
                {{ re_flag_g() }}
            )
        )
    )
{% endmacro %}

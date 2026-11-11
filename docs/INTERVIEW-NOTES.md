# Interview notes

Written for Mayank. Plain English. Explains what each piece of this repo is
and why a hiring manager might ask about it.

## The elevator version

> I took four government safety feeds, 13,000 records in all, loaded them
> into a warehouse, wrote 18 SQL transformations that unify the schemas,
> canonicalise brand names, and surface the top failure modes for each
> appliance category, then wrote 92 data-quality tests that have to pass
> before anything ships. Same SQL runs on DuckDB locally or on Snowflake.

## The pieces, in plain English

### dbt

dbt stands for *data build tool*. Think of it as a framework for writing
SQL transformations the way you'd write code: every transformation is a
file, there's version control, a dependency graph, documentation, and
tests. The payoff is that an analytics codebase can be reviewed, tested,
and deployed the same way an application codebase can.

- Each `.sql` file in `models/` is a **model**. dbt wraps it in
  `CREATE VIEW` or `CREATE TABLE AS` and runs it against your warehouse.
- Each `.yml` file alongside the models describes columns and declares
  tests.
- `dbt build` = run every model in topological order, then run every test.
- `dbt run --select staging` = only run the staging models.

If an interviewer says *"walk me through a dbt project you've shipped"*,
start with: *"three layers -- staging renames raw fields and types them,
intermediate joins and reshapes, marts are analyst-facing. Tests on every
layer."*

### Snowflake

Snowflake is a cloud data warehouse. Three vocabulary items:

- **Database** -- the top-level namespace. We use one called `HINDSIGHT`.
- **Warehouse** -- the compute cluster (not storage). Sized XSMALL for
  this project; costs less than a coffee per full build. Auto-suspends
  after 60 seconds.
- **Role** -- the permission bag. You assume a role to run queries.

Snowflake's semi-structured type is `VARIANT`. Our loader stores the
whole JSON record as a `VARIANT` column so staging can pull typed fields
out of it with `payload:fieldName::VARCHAR`. DuckDB has an equivalent
`JSON` type with `payload->>'fieldName'`. The macros in `macros/json_access.sql`
hide the syntax difference.

### DuckDB

An in-process analytical database (like SQLite but column-store,
designed for OLAP). Single file, zero setup. We use it as the default
dbt target so a stranger can clone the repo and run `dbt build` without
touching cloud credentials.

### Staging / intermediate / marts

A convention popularised by dbt Labs:

- **Staging** -- one model per source. Rename fields, cast types, drop
  rows with broken keys. No joins. One staging model points at exactly
  one source table.
- **Intermediate** -- join, union, reshape. Where the complicated
  transformations live. Intermediate models are not meant to be queried
  directly by end users.
- **Marts** -- analyst-facing. Fact and dimension tables, aggregates,
  trends. Marts are the stable contract between data engineering and
  the rest of the company.

### Incremental model

Most models are rebuilt from scratch every run. An **incremental** model
only processes *new* rows since the last build. In this project,
`fct_failure_reports` is incremental on `event_date`: a daily build only
scans rows whose event date is newer than the max currently in the table.

The pattern:

```sql
{{ config(materialized='incremental', unique_key='record_id') }}

select ...
from {{ ref('int_reports_unioned') }}
{% if is_incremental() %}
  where event_date >= (select coalesce(max(event_date), '1900-01-01') from {{ this }})
{% endif %}
```

`--full-refresh` on the CLI forces a rebuild.

### Window functions

Functions that compute a value across a *window* of rows without
collapsing them. The marts use three:

- `ROW_NUMBER() OVER (PARTITION BY record_id ORDER BY is_v1_scope DESC)` -- pick the "primary" category per record.
- `RANK() OVER (PARTITION BY category_key ORDER BY risk_score DESC)` -- rank failure modes within each category.
- `LAG(total_reports) OVER (PARTITION BY category_key ORDER BY event_year)` -- previous year's total, for year-over-year change.
- `SUM(x) OVER (ORDER BY event_year ROWS BETWEEN 2 PRECEDING AND CURRENT ROW)` -- rolling three-year total.

## What each test catches

### Generic (schema.yml tests)

- **unique** -- more than one row with the same `record_id` -> fail. Catches
  a loader bug that duplicates records on retry.
- **not_null** -- `event_date is null` -> fail. Catches a parse bug that
  silently drops dates.
- **accepted_values** -- `injury_level` in `{serious, medical, minor, none,
  unknown}` -> otherwise fail. Catches a new enum value we haven't planned
  for.
- **relationships** -- `primary_category_key` must exist in `dim_category`.
  Catches a typo in a category key.

### Singular (tests/*.sql)

- **assert_quote_support_rate** -- the hindsight pipeline promises that >=
  99% of LLM extractions have a quote verifiable against the source text.
  If an LLM run drifts, we catch it here. (Current: 99.88%.)
- **assert_cpsc_recalls_have_url** -- a DFMEA row without a source URL is
  useless to an engineer. (Current: 100% URL coverage.)
- **assert_counts_within_tolerance** -- compares our row counts to the
  counts hindsight's own `version.json` reports. Drift > 5% means the
  loader is silently dropping rows.
- **assert_no_future_dates** -- an event dated six months in the future is
  a parse bug (wrong date format, year parsed as day, etc).
- **assert_fct_matches_staging** -- row count of `fct_failure_reports` must
  equal `int_reports_unioned`. Drift means the brand or extraction join
  blew up fan-out.

## Ten interview questions and answers

**1. Walk me through how data flows through this project.**
> Four public-feed JSON files land in `data/raw/`. A Python loader writes
> each one to a `raw.<source>` table in DuckDB or Snowflake, with the JSON
> record stored in a single `payload` column. Six **staging** models pull
> typed fields out of `payload` and expose a clean per-source view.
> **Intermediate** unions the four sources, explodes the comma-separated
> categories into one row per (record, category), canonicalises brands
> through a seed CSV, and joins on LLM extractions. **Marts** aggregate
> into a fact table, two dimensions, and four analyst-facing marts:
> failure modes, yearly category trends, DFMEA rows, and a data-quality
> scorecard.

**2. Why staging / intermediate / marts? Why not one layer?**
> Separation of concerns. Staging is 1:1 with sources -- it says "this is
> what the raw data looks like after we fix types and names". Intermediate
> is where messy joins and reshapes live. Marts are the stable contract
> the rest of the business consumes. If a source changes its schema, I
> only touch one staging model; everything downstream keeps working.

**3. Why is one model incremental and the rest aren't?**
> Fact tables grow over time and are expensive to rebuild. Everything else
> is small enough (under 14k rows) that a full rebuild is cheaper than
> managing state. If this scaled to millions of incidents per month, more
> models would go incremental.

**4. How did you handle the schema differences across the four feeds?**
> Each source has its own staging model that takes responsibility for its
> own quirks -- CPSC uses nested `Products[].NumberOfUnits` strings like
> "about 1,846,400", Health Canada uses two different date fields with
> partial coverage, EU dates are DD/MM/YYYY, SaferProducts uses M/D/YYYY.
> Each staging model normalises all of that behaviour into the same
> (record_id, event_date, text, brand, categories, is_verified) shape by
> the time it leaves the staging layer.

**5. How did you handle brand names?**
> There's a `brand_aliases.csv` seed with 54 common brand variants mapping
> to canonical display names. The `int_brand_canonicalized` model
> lower-cases the raw brand, strips legal suffixes like "LLC" and "Inc.",
> and tries the first one, two, or three words against the alias map. If
> nothing matches, the row keeps its cleaned signature and `is_canonical`
> is false. About 2,500 of 13,000 rows get a canonical match -- the rest
> are long-tail singleton brands.

**6. How do you know the pipeline is working?**
> 92 tests run on every build. The five custom ones encode the data
> contract: 99% quote support rate, 100% CPSC URL coverage, row counts
> within 5% of the upstream manifest, no future dates, and no fan-out in
> the fact table. CI runs the whole thing on every push against DuckDB.

**7. What's the difference between a view and a table in dbt?**
> A view is recomputed on every query; a table is materialised once per
> build. Staging and intermediate models are views (cheap, always
> up-to-date given the inputs). Marts are tables so BI tools can scan
> them fast without re-running the joins every time.

**8. How does the same SQL run on both DuckDB and Snowflake?**
> Two macros (`macros/json_access.sql`, `macros/brand_sig.sql`) that
> dispatch on `target.type`. Staging SQL calls `{{ json_text('payload',
> 'field') }}` instead of writing the warehouse-specific syntax. Same
> for date parsing and regex flags. When something isn't macro-able, the
> model body has a minimal `{% if target.type == 'snowflake' %}` branch
> (one in the entire repo, in `int_reports_categorized` for the lateral
> unnest).

**9. What are the DFMEA rows, and why does every one have a quote?**
> DFMEA = Design Failure Mode and Effects Analysis. It's the worksheet a
> mechanical engineer builds during product design: what can fail, what
> the cause is, what the effect is, and the verification test that
> catches it. The LLM extractor was constrained to return a verbatim
> quote from the source text proving each failure mode -- 99.88% of
> extractions pass verification. That's the test that keeps the
> extractor honest: no hallucinated failure modes.

**10. What would you add next?**
> A `dim_manufacturer` table so we can roll up SharkNinja / Sunbeam /
> Newell Brands correctly. A snapshot of `mart_failure_modes` so an
> analyst can see how a category's profile moved month over month.
> Better unification with the EU IEC/EN standard references in the
> `danger` text -- right now those are plain text; parsing them into a
> structured column would let an engineer filter DFMEA rows by standard.
> And adding an NEISS injury-surveillance source for a non-brand
> baseline of overall injury rates.

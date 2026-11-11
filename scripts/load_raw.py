#!/usr/bin/env python3
"""Load hindsight raw JSON files into the warehouse `raw` schema.

Same script covers both targets:
    python scripts/load_raw.py --target duckdb
    python scripts/load_raw.py --target snowflake

For DuckDB we use the built-in JSON reader (fast, zero network). For
Snowflake we upload via the Python connector's `write_pandas` helper
(single COPY under the hood) -- fine for the ~12k rows at play here;
larger loads would warrant a staged COPY FROM.

No credentials are printed or logged. Snowflake config comes only from
environment variables (see .env.example).
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path

# ``extractions`` holds the LLM-joined extraction rows the staging layer joins
# in; the four primary sources are the per-source raw tables.
SOURCE_FILES: dict[str, str] = {
    "cpsc_recalls": "cpsc_recalls.json",
    "saferproducts_incidents": "saferproducts_incidents.json",
    "healthcanada_recalls": "healthcanada_recalls.json",
    "eu_safetygate_alerts": "eu_safetygate_alerts.json",
    "extractions": "extractions.json",
    "hindsight_version": "hindsight_version.json",
}


@dataclass
class Row:
    """Each raw table stores ``payload`` (the full JSON record as text) plus a
    stable ``source_record_id`` and a ``_loaded_at`` timestamp. The staging
    models extract the typed fields they care about from ``payload``. This
    pattern mirrors the Fivetran / Airbyte / Stitch "landing" layer in real
    warehouses: minimal typing at ingest, full typing in staging."""

    source_record_id: str
    payload: str
    loaded_at: str


def row_for(table: str, record: dict, loaded_at: str) -> Row:
    """Pick a stable id depending on the source table."""
    if table == "cpsc_recalls":
        rid = str(record.get("RecallID") or record.get("RecallNumber") or "")
    elif table == "saferproducts_incidents":
        rid = str(record.get("reportNo") or "")
    elif table == "healthcanada_recalls":
        rid = str(record.get("NID") or "")
    elif table == "eu_safetygate_alerts":
        rid = str(record.get("caseNumber") or "")
    elif table == "extractions":
        rid = str(record.get("id") or "")
    else:
        rid = str(record.get("id") or record.get("RecallID") or "")

    if not rid:
        # Fall back to a hash of the record text so uniqueness is preserved.
        import hashlib

        rid = hashlib.sha256(
            json.dumps(record, sort_keys=True).encode("utf-8")
        ).hexdigest()[:16]

    return Row(
        source_record_id=rid,
        payload=json.dumps(record, separators=(",", ":"), ensure_ascii=False),
        loaded_at=loaded_at,
    )


def load_raw_dir(raw_dir: Path) -> dict[str, list[Row]]:
    """Read every source JSON once and turn it into per-table row lists."""
    loaded_at = datetime.now(timezone.utc).isoformat(timespec="seconds")
    out: dict[str, list[Row]] = {}
    for table, filename in SOURCE_FILES.items():
        path = raw_dir / filename
        if not path.exists():
            print(f"WARN: {path} missing, skipping {table}", file=sys.stderr)
            out[table] = []
            continue
        data = json.loads(path.read_text())
        if table == "hindsight_version":
            # Version is a single document, not a list.
            data = [data]
        if not isinstance(data, list):
            raise RuntimeError(f"{path} must be a JSON array, got {type(data)}")
        out[table] = [row_for(table, rec, loaded_at) for rec in data]
        print(f"  {table}: {len(out[table])} rows")
    return out


# ---------- DuckDB target --------------------------------------------------


def load_duckdb(tables: dict[str, list[Row]], db_path: Path) -> None:
    import duckdb

    print(f"Writing to DuckDB at {db_path}")
    con = duckdb.connect(str(db_path))
    con.execute("CREATE SCHEMA IF NOT EXISTS raw")
    for table, rows in tables.items():
        fq = f"raw.{table}"
        con.execute(f"DROP TABLE IF EXISTS {fq}")
        con.execute(
            f"""
            CREATE TABLE {fq} (
                source_record_id VARCHAR,
                payload JSON,
                _loaded_at TIMESTAMP
            )
            """
        )
        if not rows:
            continue
        con.executemany(
            f"INSERT INTO {fq} VALUES (?, ?::JSON, ?)",
            [(r.source_record_id, r.payload, r.loaded_at) for r in rows],
        )
        n = con.execute(f"SELECT count(*) FROM {fq}").fetchone()[0]
        print(f"    {fq}: {n:,} rows")
    con.close()


# ---------- Snowflake target ----------------------------------------------


def load_snowflake(tables: dict[str, list[Row]]) -> None:
    """Load into Snowflake using the vanilla connector + write_pandas."""
    import pandas as pd
    import snowflake.connector
    from snowflake.connector.pandas_tools import write_pandas

    required = ("SNOWFLAKE_ACCOUNT", "SNOWFLAKE_USER", "SNOWFLAKE_PRIVATE_KEY_PATH")
    missing = [k for k in required if not os.environ.get(k)]
    if missing:
        raise SystemExit(
            f"Missing env vars: {', '.join(missing)}. Copy .env.example to "
            ".env and fill it in."
        )

    database = os.environ.get("SNOWFLAKE_DATABASE", "HINDSIGHT")
    schema_raw = "RAW"
    warehouse = os.environ.get("SNOWFLAKE_WAREHOUSE", "COMPUTE_WH")
    role = os.environ.get("SNOWFLAKE_ROLE", "ACCOUNTADMIN")

    print(f"Connecting to Snowflake account={os.environ['SNOWFLAKE_ACCOUNT']!r}")
    con = snowflake.connector.connect(
        account=os.environ["SNOWFLAKE_ACCOUNT"],
        user=os.environ["SNOWFLAKE_USER"],
        private_key_file=os.path.expanduser(os.environ["SNOWFLAKE_PRIVATE_KEY_PATH"]),
        role=role,
        warehouse=warehouse,
    )
    try:
        cur = con.cursor()
        cur.execute(f"CREATE DATABASE IF NOT EXISTS {database}")
        cur.execute(f"USE DATABASE {database}")
        cur.execute(f"CREATE SCHEMA IF NOT EXISTS {schema_raw}")
        cur.execute(f"USE SCHEMA {schema_raw}")
        cur.execute(f"USE WAREHOUSE {warehouse}")

        for table, rows in tables.items():
            fq = f"{database}.{schema_raw}.{table.upper()}"
            cur.execute(f"DROP TABLE IF EXISTS {fq}")
            # VARIANT is Snowflake's semi-structured type -- the dbt models
            # pull typed fields out of it with PARSE_JSON / dot notation.
            cur.execute(
                f"""
                CREATE TABLE {fq} (
                    SOURCE_RECORD_ID VARCHAR,
                    PAYLOAD VARIANT,
                    _LOADED_AT TIMESTAMP_NTZ
                )
                """
            )
            if not rows:
                continue
            df = pd.DataFrame(
                [
                    {
                        "SOURCE_RECORD_ID": r.source_record_id,
                        "PAYLOAD": r.payload,
                        "_LOADED_AT": r.loaded_at,
                    }
                    for r in rows
                ]
            )
            # write_pandas sends the payload as a string column; cast to VARIANT
            # with a staged UPDATE after upload since COPY needs JSON parsing.
            stage_table = f"{table.upper()}_STAGE"
            success, _nchunks, nrows, _ = write_pandas(
                con,
                df,
                table_name=stage_table,
                database=database,
                schema=schema_raw,
                auto_create_table=True,
                overwrite=True,
            )
            if not success:
                raise RuntimeError(f"write_pandas failed for {table}")
            cur.execute(
                f"""
                INSERT INTO {fq} (SOURCE_RECORD_ID, PAYLOAD, _LOADED_AT)
                SELECT SOURCE_RECORD_ID, PARSE_JSON(PAYLOAD), _LOADED_AT
                FROM {database}.{schema_raw}.{stage_table}
                """
            )
            cur.execute(f"DROP TABLE IF EXISTS {database}.{schema_raw}.{stage_table}")
            n = cur.execute(f"SELECT COUNT(*) FROM {fq}").fetchone()[0]
            print(f"    {fq}: {n:,} rows")
    finally:
        con.close()


# ---------- CLI ------------------------------------------------------------


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--target",
        choices=("duckdb", "snowflake"),
        default="duckdb",
        help="Which warehouse to load into",
    )
    parser.add_argument(
        "--raw-dir",
        default="data/raw",
        help="Directory with the source JSON files",
    )
    parser.add_argument(
        "--duckdb-path",
        default=os.environ.get("DBT_DUCKDB_PATH", "hindsight_warehouse.duckdb"),
        help="Path to the DuckDB database file",
    )
    args = parser.parse_args()

    raw_dir = Path(args.raw_dir).resolve()
    if not raw_dir.is_dir():
        raise SystemExit(f"raw dir not found: {raw_dir}")

    print(f"Loading from {raw_dir}")
    tables = load_raw_dir(raw_dir)

    if args.target == "duckdb":
        load_duckdb(tables, Path(args.duckdb_path).resolve())
    else:
        load_snowflake(tables)


if __name__ == "__main__":
    main()

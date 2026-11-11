# Raw data sources

Committed JSON pulled by the [`hindsight`](https://github.com/mayankgoel214/hindsight)
pipeline on **2026-10-28**. Terms of use for each source are listed in
`hindsight/data/README.md`; all four are redistributable under public-domain
or Commission Decision 2011/833/EU terms.

| File                              | Rows   | Shape                                            | Trust                  |
|-----------------------------------|--------|--------------------------------------------------|------------------------|
| `cpsc_recalls.json`               | 445    | One recall per object (RecallID, Products, ...)  | Verified               |
| `saferproducts_incidents.json`    | 11,748 | Consumer reports, incident + product fields      | **Unverified claims**  |
| `healthcanada_recalls.json`       | 355    | NID + title + product + hazard text              | Verified               |
| `eu_safetygate_alerts.json`       | 548    | Weekly Safety Gate alerts (danger, riskType)     | Verified               |
| `extractions.json`                | 5,179  | LLM-extracted failure_mode/cause/effect per record | Pipeline output      |
| `hindsight_version.json`          | 1      | Upstream manifest: record count, quote support   | Ground-truth snapshot  |

Two deliberate trims so the repo stays under 25 MB:

1. `saferproducts_incidents.json` drops seven fields that `scripts/load_raw.py`
   does not use (`companyComments`, `serial`, `upc`, `dateManufactured`,
   `mfrDateCode`, `retailer`, `purchaseDate`, `associatedReports`,
   `damagedBefore`, `modifiedBefore`). Every row and every analytic field used
   in staging is preserved.
2. `extractions.json` carries only the LLM extraction fields plus the join
   key (`id`), not the full record — the staging layer joins it back onto
   the source record by `record_id`.

To refresh this data, run the upstream `hindsight` scripts and copy the
output here; the warehouse is intentionally pinned to one snapshot so build
output is reproducible.

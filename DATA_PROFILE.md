# Data Profiling Report — T1.1

**SD6103 Data Systems** · AY26S1 · Profiled 29 Sep 2026
**Scope:** all 4 raw sources in `data/raw/`, before any schema is written.

> This is task **T1.1** in [PROJECT_PLAN.md](PROJECT_PLAN.md) — *"the highest-leverage task in the project."*
> Three assumptions in the plan turn out to be wrong. They are corrected in [§6](#6-corrections-to-project_planmd).

---

## 1. Inventory

| Path | Rows | Notes |
|---|---:|---|
| `hawker_resale_prices/…1990 - 1999.csv` | 287,196 | approval date |
| `hawker_resale_prices/…2000 - Feb 2012.csv` | 369,651 | approval date |
| `hawker_resale_prices/…Mar 2012 to Dec 2014.csv` | 52,203 | registration date |
| `hawker_resale_prices/…Jan 2015 to Dec 2016.csv` | 37,153 | registration date |
| `hawker_resale_prices/…Jan-2017 onwards.csv` | 241,483 | runs to **2026-09** |
| **Total resale transactions** | **987,686** | |
| `hdb_geo/hdb.csv` | 12,442 | 35 columns; flat coordinates |
| `hawker_geo/hawker_geo.csv` | 129 | hawker coordinates |
| `hawker_centres/ListofGovernmentMarketsHawkerCentres.csv` | 107 | stall counts → **Q5** |

### Resale schema across the 5 files

All five share the same 10 columns:

```
month, town, flat_type, block, street_name, storey_range,
floor_area_sqm, flat_model, lease_commence_date, resale_price
```

The 2015–2016 and 2017+ files add an 11th, `remaining_lease`.

### A note on the size ladder

The file sizes are **not monotonic** in the order Task 3 suggests loading them. File 1 (52k) is larger than the 2015–16 file (37k), and the two oldest files are 5–7× either of them.

**Implication:** the x-axis of the Task 3 plot must be **actual loaded row count** (or `pg_database_size()`), never "file 1…5". A ladder of 52k → 89k → 331k → 618k → 988k rows is a genuine ~19× growth curve, which is good for the experiment — but only if the axis reflects it.

---

## 2. The hawker join — use postal code, not name

This is Risk #1 in the plan, and name matching is as bad as feared.

| Join key | Centres matched (of 107) |
|---|---|
| Normalised name, exact | **17 (16%)** |
| Fuzzy name (`difflib`, cutoff 0.6) | unusable — see below |
| **6-digit postal code from the address** | **104 (97%)** |

### Why names fail

The two files use **inverted naming conventions**:

| `ListofGovernmentMarketsHawkerCentres.csv` | `hawker_geo.csv` |
|---|---|
| `Blk 20 Ghim Moh Road` | `Ghim Moh Road Blk 20` |
| `Blk 448 Clementi Ave 3` | `Clementi Ave 3 Blk 448` |
| `Blk 159 Mei Chin Road` | `Mei Chin Road Blk 159 (Mei Chin Road Market)` |

Fuzzy string matching does not rescue this and is actively dangerous — it silently produces confident wrong pairs:

```
Amoy Street Food Centre        ->  Adam Road Food Centre        ✗
Chinatown Market               ->  Tanglin Halt Market          ✗
Pek Kio Market & Food Centre   ->  Bedok Food Centre            ✗
Blk 85 Bedok North Street 4    ->  Bedok North Street 3 Blk 538 ✗
```

### Why postal code works

Both address fields embed a 6-digit postal code, and it is **unique within each file** (zero duplicates in either):

| File | Field | Format | Coverage |
|---|---|---|---|
| centres | `location_of_centre` | `2, Adam Road, S(289876)` | 107 / 107 |
| geo | `ADDRESS_MYENV` | `31, Commonwealth Crescent, Singapore 149644` | 112 / 129 |

Extract with `re.findall(r'\d{6}', addr)`. One centre lists three postal codes for one site (`S(141001/141002/141003)`), so match on **any** extracted code, not just the last.

### The three unmatched centres

| Centre | `no_of_mkt_produce_stalls` |
|---|---|
| Market Street Food Centre | 0 |
| Blk 4A Woodlands Centre Road | 0 |
| Blks 1A/ 2A/ 3A Commonwealth Drive | 0 |

**All three have zero market-produce stalls.** Therefore:

> **All 81 fresh-market hawker centres geocode successfully (100%). Q5 is fully supported.**

Risk #1 is closed. This belongs in the Task 2 report verbatim.

### The 25 geo rows with no stall data

129 geo rows − 104 matched = **25 hawker centres that have coordinates but no stall counts**. They are the post-2015 new-generation centres:

```
Yew Tee · Kampung Admiralty · Marsiling Mall · Pasir Ris Central
Bukit Panjang · Ci Yuan · Our Tampines Hub · Jurong West · Yishun Park …
```

These are NEA socially-conscious-enterprise centres, absent from a list of *government* markets by definition. 17 of the 25 also have a blank `ADDRESS_MYENV`, so they cannot be postal-joined even in principle.

→ **Decision required.** See [§5](#5-decisions-this-forces).

---

## 3. The flat geocoding join — no normalisation needed

The plan budgets effort for normalising street abbreviations (`ST`/`STREET`, `AVE`/`AVENUE`, `NTH`/`NORTH`). **This is unnecessary.** Both files already use identical abbreviations, and `hdb.csv` is clean:

- 12,442 rows, **unique** on `(blk_no, street)` — zero duplicates
- **zero null** `lat` / `lng`

A plain exact join on `UPPER(TRIM(block)) || '|' || UPPER(TRIM(street_name))`:

| File | Distinct flats | Matched | Rows matched |
|---|---:|---|---|
| Mar 2012 – Dec 2014 | 8,025 | **100.0%** (2 misses) | 100.0% |
| Jan 2017 onwards | 9,753 | **100.0%** (1 miss) | 100.0% |
| 1990 – 1999 | 5,910 | **97.1%** | 96.8% |

### The 1990s gap is a finding, not a bug

`hdb.csv` is a snapshot of *currently standing* HDB blocks. Blocks demolished since the 1990s are absent by construction — e.g. several blocks on Ang Mo Kio Ave 1/3/4 and Hillview Ave.

This is not something to "fix". It is a data-currency mismatch to state in the report, and it forces a decision about transactions that cannot be geocoded ([§5](#5-decisions-this-forces)).

---

## 4. Per-column gotchas

### 4.1 `flat_type` — the hyphen that breaks file 5

| File | Value |
|---|---|
| 1990 – 1999 | `MULTI GENERATION` — **no hyphen** |
| all other files | `MULTI-GENERATION` |

Otherwise all five files agree: `1 ROOM`, `2 ROOM`, `3 ROOM`, `4 ROOM`, `5 ROOM`, `EXECUTIVE`.

> ⚠️ A `CHECK (flat_type IN (...))` written against file 1 will **fail on the last load of the benchmark**, or silently create a spurious 8th flat type. Normalise in the ETL and write the constraint against the union of all five files.

### 4.2 `flat_model` — casing and cardinality drift

| File | Distinct values | Casing |
|---|---:|---|
| 1990 – 1999 | 13 | `IMPROVED`, `MAISONETTE` (UPPER) |
| 2000 – Feb 2012 | 16 | `Improved`, `Adjoined flat` (Title) |
| Mar 2012 – Dec 2014 | 17 | Title |
| Jan 2015 – Dec 2016 | 20 | Title |
| Jan 2017 onwards | 21 | Title, adds `3Gen`, `DBSS` |

Normalise casing in the ETL. New models appear over time — this is real, not dirty data.

### 4.3 `town` — there are 27, not 26

Every individual file contains exactly 26 towns, which makes 26 look like the answer. The **union is 27**:

| Town | Appears in |
|---|---|
| `LIM CHU KANG` | 1990–1999 **only** |
| `PUNGGOL` | every file **except** 1990–1999 |

> The `Town` table must be built from the union of loaded files, or grown incrementally as each file is added. Seeding it from file 1 alone will cause FK violations at load 5.

### 4.4 `remaining_lease` — three representations

| File | Present | Type | Example |
|---|---|---|---|
| 1990–1999 | ✗ | — | — |
| 2000–Feb 2012 | ✗ | — | — |
| Mar 2012–Dec 2014 | ✗ | — | — |
| Jan 2015–Dec 2016 | ✓ | integer years | `70` |
| Jan 2017 onwards | ✓ | text | `61 years 04 months` |

Confirms Risk #2 exactly. Derive uniformly in the ETL as
`remaining_lease = 99 − (txn_year − lease_commence_date)`, and parse the text form where present to validate the derivation.

### 4.5 Other fields

| Field | Observation |
|---|---|
| `month` | `YYYY-MM` in all five files — consistent |
| `storey_range` | `10 TO 12` / `06 TO 10` — **bucket widths differ between files** (3-storey vs 5-storey bands) |
| `hdb.csv` extras | carries a `market_hawker` Y/N flag and `year_completed`, `max_floor_lvl`, planning area / region — free extra attributes for the ER model if wanted |

---

## 5. Decisions this forces

Each needs a team decision **and a line in the report** — the brief rewards deliberate, defended choices.

| # | Decision | Affects | Recommendation |
|---|---|---|---|
| **D1** | Hawker centres with coordinates but no stall data (25 rows) — load with NULL stall counts, or exclude? | Q4 needs no stalls; Q5 needs them | Load with NULL, add `has_fresh_market BOOLEAN`. Excluding them would understate proximity in newer towns (Punggol, Tampines) |
| **D2** | Transactions whose flat does not geocode (~2.9% of the 1990s file) | proximity coverage | Load the transaction, assign no proximity rows. Dropping ~8k real sales to protect a join is worse |
| **D3** | `flat_type` CHECK constraint | load 5 of the benchmark | Write against the union; normalise `MULTI GENERATION` → `MULTI-GENERATION` in the ETL |
| **D4** | `Town` table population | FK integrity | Populate from the union of all 5 files up front (27 rows), not incrementally |
| **D5** | Task 3 x-axis | plot validity | Use loaded row count / `pg_database_size()`, not file ordinal |

Still open from the plan, unchanged by this profiling: the proximity thresholds (NEAR/MEDIUM/FAR), and the Q5 budget threshold — which can only be fixed once all five files are loaded.

---

## 6. Corrections to PROJECT_PLAN.md

| Plan says | Reality | Impact |
|---|---|---|
| Risk #1 — hawker name matching, "fuzzy matching required" | Name matching gives 16%; **postal code gives 97%**, and 100% of fresh-market centres | Risk closed; fuzzy matching should be **avoided**, it produces wrong pairs |
| T2.3 — "Normalise street abbreviations (`ST`/`STREET`, `AVE`/`AVENUE`, `NTH`/`NORTH`)" | Exact join already yields 100% / 100% / 97.1% | Work not needed; spend the time on D1/D2 instead |
| Risk #3 — "The 1990s file has a different column set" | Column set is **identical** to the Mar 2012–14 file | Real breakages are the `MULTI GENERATION` hyphen and `flat_model` casing |
| T2.4 — "~10k flats × 129 hawkers" | 12,442 flats × 129 = ~1.6M pairs | Still trivial brute force; estimate confirmed |
| §3 — "Q1 requires a 3-year range" → start with Mar 2012–14 | Confirmed: that file spans 2012-03 → 2014-12 | Recommendation stands |

---

## 7. Reproducing this

The checks above were run as ad-hoc `pandas` scripts against `data/raw/`. **Not yet committed as a script** — `etl/profile.py` is still to be written so the numbers in this report are reproducible evidence for the Task 1 write-up.

Environment used: Python 3.10.11, pandas 2.3.3.

Housekeeping: `data/.DS_Store` and `data/raw/.DS_Store` should go in `.gitignore`.

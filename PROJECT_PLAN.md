# Data Systems Project — Team Plan

**Course:** SD6103 Data Systems (AY26S1, Prof. Melanie Herschel)
**Team size:** 6
**Submission:** Friday, end of day, Week 13 (≈ 13 Nov 2026 — *confirm on NTULearn*)
**Viva:** Week 14, 15 min, all members must attend, on site

---

## 1. What we are building

A PostgreSQL backend linking **HDB resale transactions** to **nearby hawker centres**, then querying and benchmarking it.

### Grade weights

| Component | Weight |
|---|---|
| Task 1 — Modeling (ER + schema) | 25% |
| Task 2 — DB Population (ETL) | 10% |
| Task 3 — Querying | 25% |
| Task 4 — Indexing | 20% |
| Deliverable quality (formatting, code comments) | 5% |
| Viva | 15% |

### Datasets (4 sources, all must be joined)

| Source | Gives us | Gotcha |
|---|---|---|
| data.gov.sg collection 189 | HDB resale — **5 CSV files** | `remaining_lease` only exists in the 2015+ files |
| data.gov.sg `d_68a42f09f350881996d83f9cd73ab02f` | Hawker centres + **stall counts** | Needed for Q5 "fresh market stalls" |
| `hawker_geo.csv` (local, 129 rows) | Hawker lat/long | 17 rows have a blank `ADDRESS_MYENV` |
| `BlueSkyLT/siteselect_sg` → `hdb.csv` | HDB block lat/long | Join on block + street_name; expect misses |

---

## 2. Deliverables checklist

- [ ] **Report PDF** — Task 1–4 sections + AI-usage declaration + reflection paragraph
- [ ] **ER diagram** — (min,max) notation, keys marked
- [ ] `schema.sql` — CREATE DATABASE / TABLE + all constraints
- [ ] **ETL code** (Python) — produces one CSV per table
- [ ] `queries.sql` — Q1–Q6
- [ ] `indexes.sql` — CREATE INDEX statements
- [ ] **Task 3 measurements file** — exactly **150 rows** (6 queries × 5 runs × 5 DB sizes)
- [ ] **Task 4 measurements file** — with/without index on the largest DB
- [ ] **Plots** — DB size vs runtime (line, per query) + with/without index (bar)
- [ ] **Screenshots** of every query result

---

## 3. Decisions to lock in first

Everything downstream depends on these. Agree as a team, write each one down — the report has to state and justify them.

| Decision | Recommendation | Why |
|---|---|---|
| **Which HDB file first?** | `Mar 2012 – Dec 2014` (~52k rows) | Small, **and spans 3 calendar years** — Q1 requires a 3-year range in the loaded data. The Jan2015–Dec2016 file is smaller but only covers 2 years, which breaks Q1. |
| **Proximity definition** | Haversine distance, 3 classes: **NEAR ≤ 500 m**, **MEDIUM 500 m – 1 km**, **FAR 1 – 2 km** | Brief says the given data "primarily supports a distance-based definition". Walking-path / transit needs external API calls = scope risk. |
| **Flat with no hawker within 2 km?** | Assign no proximity row (not a 4th class) — but decide explicitly and document it | Q4 compares closest vs furthest class; unhandled nulls will silently skew the result |
| **ER relationship style** | Binary only: `HDB_Flat —(near)— Hawker_Centre`, with `distance_m` and `proximity_class` as **relationship attributes** | Week 3 slides: *"A diamond has exactly two connecting lines to boxes."* Ternary relationships are not part of this course's ER syntax. |
| **Q5 budget threshold** | Pick once on the **full** DB, so the result is neither empty nor all towns | Threshold tuned on the small DB will return empty as data grows |

---

## 4. Task graph

Grouped into 5 phases. Within a phase, tasks on the same line run in parallel. Nothing in a later phase starts before its dependency finishes.

### Phase 0 — Setup (everyone, ~2 days)

- [ ] **T0.1** Everyone installs PostgreSQL + pgAdmin locally; agree on one PG version
- [ ] **T0.2** Shared Git repo + folder layout (`/data`, `/etl`, `/sql`, `/results`, `/report`)
- [ ] **T0.3** Download all 4 datasets into `/data/raw`; commit a README with source URLs + download date
- [ ] **T0.4** Confirm team is registered on the NTULearn form (team name, daytime viva availability)

### Phase 1 — Modeling (Task 1, 25%)

```
T1.1 Data profiling ──┬─→ T1.2 Proximity definition ──┐
(all raw files:       │                               ├─→ T1.3 ER diagram ─→ T1.4 FD analysis / 3NF proof ─→ T1.5 schema.sql
 columns, types,      │                               │
 nulls, cardinality) ─┘                               │
```

- [ ] **T1.1** Profile every raw file: column names, dtypes, null counts, distinct `town` / `flat_type` values, date formats. **Highest-leverage task in the project** — prevents ~80% of the Task 2 pain.
- [ ] **T1.2** Write the proximity definition (one paragraph, goes verbatim into the report)
- [ ] **T1.3** ER diagram: `Town`, `HDB_Flat`, `Resale_Transaction`, `Hawker_Centre` + the proximity relationship. Every edge labelled `(min,max)`. Keys underlined.
- [ ] **T1.4** List FDs per relation, run the closure algorithm, state which normal form each table reaches and why. Rubric explicitly rewards *"fully normalized schema"*.
- [ ] **T1.5** `schema.sql` — PKs, FKs, NOT NULL, CHECK constraints (e.g. `floor_area_sqm > 0`, `flat_type IN (...)`, `resale_price > 0`). Rubric top band: *"constraints are consistently well-chosen and correctly defined."*

### Phase 2 — ETL & Population (Task 2, 10%)

```
T1.5 ─┬─→ T2.1 HDB resale ETL ──→ T2.3 HDB geocode join ──┐
      ├─→ T2.2 Hawker ETL ───────────────────────────────┼─→ T2.4 Proximity computation ─→ T2.5 Bulk load + error log ─→ T2.6 Reload script
      └─→ (T1.2 proximity def) ──────────────────────────┘
```

- [ ] **T2.1** Parse HDB resale CSV → `town.csv`, `hdb_flat.csv`, `resale_transaction.csv`. **Derive `remaining_lease` = 99 − (txn_year − lease_commence_date)** so it exists uniformly across all 5 files; also parse the `"61 years 04 months"` string format used in the 2017+ file.
- [ ] **T2.2** Join `hawker_geo.csv` (coords) with the data.gov hawker dataset (stall counts incl. market stalls) **on centre name** — fuzzy matching required, log every unmatched row. Without this, **Q5 is unanswerable**.
- [ ] **T2.3** Join flats to `hdb.csv` on block + street_name for lat/long. Normalise street abbreviations (`ST`/`STREET`, `AVE`/`AVENUE`, `NTH`/`NORTH`). Log the match rate.
- [ ] **T2.4** Compute Haversine distance for every (flat × hawker) pair within 2 km → `proximity.csv`. ~10k flats × 129 hawkers = trivial brute force, no spatial index needed.
- [ ] **T2.5** `\copy` each CSV in FK-safe order. **Keep a running log of every error** — encoding, type mismatch, duplicate keys, FK violations. The report requires a reflection on these; do not try to reconstruct it from memory at the end.
- [ ] **T2.6** Make loading **idempotent and incremental** — Task 3 makes you do this 5 times. Write `truncate_all.sql` + a `load.py --files N` driver **now**, not in Week 12.

### Phase 3 — Queries & Performance (Task 3, 25%)

```
T2.5 ─┬─→ T3.1 Q1,Q2,Q3 ─┬─→ T3.3 Insights (1 per query) ─┐
      └─→ T3.2 Q4,Q5,Q6 ─┘                                │
                         └─→ T3.4 Timing harness ─→ T3.5 Run @ 5 sizes ─→ T3.6 Plots + interpretation
                                   ↑ (needs T2.6)
```

- [ ] **T3.1** **Q1** avg price per m², 4-Room & 5-Room, 3-year range · **Q2** `CASE` lease buckets + median via `PERCENTILE_CONT` + avg price/m² + txn volume, per town · **Q3** `WITH` → top-10 towns by avg 3-Room floor area, then max resale price per year
- [ ] **T3.2** **Q4** near-vs-far price differential, exact output schema `(town, flat_type, avg_price_near_hawker, avg_price_far_hawker, price_diff_percentage)` · **Q5** avg price per proximity class, fresh-market hawkers only, `HAVING` a budget threshold · **Q6** our own query joining **all** tables
- [ ] **T3.3** One written insight per query. "From this result alone we cannot conclude X" is an acceptable insight per the brief.
- [ ] **T3.4** Timing script: `EXPLAIN ANALYZE` or `\timing`, 5 runs each, log `(db_size_label, query_id, run_no, ms)`; also record `pg_database_size()` and row counts per size.
- [ ] **T3.5** Load file 1 → measure → add file 2 → measure → … → file 5. **150 rows total.** Budget a full day; expect ETL bugs when new files arrive (the 1990s file has a different column set).
- [ ] **T3.6** Line chart: DB size vs runtime per query, plus written interpretation — which queries scale linearly, which blow up, and why (joins vs aggregates vs full scans).

### Phase 4 — Indexing (Task 4, 20%)

```
T3.5 ─→ T4.1 EXPLAIN on largest DB ─→ T4.2 Design + justify indexes ─→ T4.3 Re-measure ─→ T4.4 Bar chart + discussion
```

- [ ] **T4.1** Capture the execution plan for all 6 queries on the full DB. **Save the plans** — they are the justification evidence.
- [ ] **T4.2** Create indexes, each with a written reason (e.g. *"Q4 seq-scans `resale_transaction` filtering on `flat_id`; B-tree on `(flat_id, resale_price)` enables an index-only scan"*). Rubric top band is *"clear justification for each index created"* — an unjustified index scores worse than no index.
- [ ] **T4.3** 5 runs × 6 queries with indexes, at the same DB size as the final Task 3 measurement.
- [ ] **T4.4** Bar chart with/without indexes. **Discuss the cases where the index did not help** — that is where the marks are.

### Phase 5 — Report & Viva

- [ ] **T5.1** Report assembly — consistent template, figure numbering, captions
- [ ] **T5.2** Code cleanup + comments (5% of the grade is literally formatting and commenting)
- [ ] **T5.3** AI usage declaration + reflection paragraph (explicitly requested — free marks)
- [ ] **T5.4** **Viva prep:** each member presents the section they did *not* own to the rest of the team. The rubric penalises *"lacks understanding of design choices"*, and anyone can be asked about any part.

---

## 5. Who does what

The brief requires **equal contribution** and that **all 6 understand the whole project** for the viva, so members are paired and rotated across phases rather than siloed.

| | Phase 1 | Phase 2 | Phase 3 | Phase 4–5 |
|---|---|---|---|---|
| **A** (lead / integrator) | T1.3 ER diagram | reviews T2.5 | T3.4 timing harness | T5.1 report assembly |
| **B** | T1.4 FD / normalization | T2.1 HDB resale ETL | T3.1 Q1–Q3 | T4.2 index justification |
| **C** | T1.5 schema.sql | T2.3 geocode join | T3.1 Q1–Q3 | T4.1 EXPLAIN |
| **D** | T1.1 profiling | T2.2 hawker ETL | T3.2 Q4–Q6 | T4.3 re-measure |
| **E** | T1.2 proximity definition | T2.4 proximity computation | T3.2 Q4–Q6 | T4.4 plots + discussion |
| **F** | T1.1 profiling | T2.5 / T2.6 load + reload driver | T3.5 run all 5 sizes | T3.6 plots, T5.2 code cleanup |

> Everyone writes their own report subsection **as they go**. Do not leave the report to one person in Week 13.

---

## 6. Risks to pre-empt

1. **Hawker name matching (T2.2)** — `hawker_geo.csv` and the data.gov hawker dataset use different name spellings. Q5 is unanswerable without this join. Do it in the first week of Phase 2, not last.
2. **`remaining_lease` inconsistency** — three different representations across the 5 files. Normalise in the ETL, not in SQL.
3. **The 1990s file** has a different column set (no `remaining_lease`, different `flat_model` values). It will break an ETL that was only ever tested on one file — smoke-test all 5 headers during T1.1.
4. **Q5's budget threshold** goes empty as the data grows. Pick it on the full DB and note the assumption.
5. **Timing noise** — run all measurements on one machine, warm cache, everything else closed. Document the method in the report.

---

## 7. Timeline

The brief says *"Tasks 1 and 2 can be completed before recess week"* — we are behind that suggestion, so this is the catch-up schedule.

| Milestone | Target |
|---|---|
| Phase 1 done (ER + schema) | end of Week 8 |
| Phase 2 done (data loaded) | end of Week 9 |
| Phase 3 queries written | Week 10 |
| Phase 3 measurements done (150 rows) | Week 11 |
| Phase 4 done (indexes + plots) | Week 12 |
| Report finalised + buffer | Week 13 |
| **Submission** | **Friday, Week 13** |
| Viva | Week 14 |

# Task 4 findings

## Setup

All measurements use the largest database (step 5: 987,686 sales from 1990-01 to 2026-09) and the six queries of Task 3 (`Task 3/queries.sql`, unchanged). Machine: PostgreSQL 18.4 (Postgres.app) on macOS (arm64), 10 CPUs, default settings (`shared_buffers` 128 MB, `work_mem` 4 MB, 2 parallel workers per query, JIT on). Snapshot in `results/task4_environment.json` (`measured_at` 2026-11-01T01:37:07).

Database size depends on when it was measured:

| Snapshot | File | DB size (MB) | Housing tables incl. indexes (MB) |
|---|---|---|---|
| Task 3 step 5 | `Task 3/results/task3_summary.csv` | 104.87 | 95.99 |
| Task 4 environment (before the final drop/create cycle finished) | `task4_environment.json` | 130.71 | — |
| Final runs without the Task 4 index | `task4_measurements.csv` | 124.01 | 115.91 |
| Final runs with the Task 4 index | `task4_measurements.csv` | 130.75 | 122.65 |

The gap between Task 3 and Task 4 sizes is real in the saved files; this report does not force them to one value. The final with/without comparison below uses the Task 4 measurement rows only.

Method (same protocol as Task 3 for the timed runs):

- Runtime is client wall-clock time from sending the query until all rows have arrived (`time.perf_counter` around `execute` + `fetchall`). It is not the `EXPLAIN ANALYZE` Execution Time.
- One untimed warm-up run, then 5 timed runs, per query and condition. Warm-up is discarded.
- Means and standard deviations are over the 5 timed runs. The standard deviation is the sample standard deviation (pandas `.std()`, divide by n−1).
- Percentage change is computed from the means after they are rounded as in `task4_summary.csv`: `(avg_with − avg_without) / avg_without × 100`. Speed-up is `avg_without / avg_with`. We do **not** average per-run percentages.
- Statistics are refreshed with `VACUUM (ANALYZE)` on all seven tables before measuring, and with `ANALYZE` / `VACUUM (ANALYZE)` after index create/drop as in the notebook.
- "Without" and "with" the final index are measured in the same notebook session (Part C). The un-indexed averages are 0.92 to 0.99 times the Task 3 step-5 averages (`this_vs_task3_x` in `task4_summary.csv`).
- Every query returns exactly the same rows with and without an index (MD5 of the result identical in every run of a query).
- A change counts as **noticeable** only if both hold: the `EXPLAIN` plan changed, and the absolute change of the average is greater than 10% of the un-indexed average **and** greater than 2 sample standard deviations of the un-indexed runs. This is a project rule of thumb for the write-up, not a formal statistical significance test. If the plan is identical, the index is not part of the plan, and any runtime difference is treated as run-to-run noise.

Final numbers for the submitted index come from `results/task4_measurements.csv` (60 rows) and `results/task4_summary.csv`. Screening, combinations, insert cost and supporting experiments are separate files and must not be mixed with that 60-row set.

## 1. How the queries read the data

Before any new index, the schema only has the 13 indexes PostgreSQL creates for primary keys, unique constraints and the exclusion constraint. None is on `transaction_month` or on `resale_transaction.flat_id`. `EXPLAIN (ANALYZE, BUFFERS)` shows how each query reads the fact table `resale_transaction` (saved under `results/plans/*_without_index.txt`):

| Query | Scan of `resale_transaction` | Rows kept | Rows thrown away | Single-run Execution Time (ms) |
|---|---|---|---|---|
| Q1 | Parallel Seq Scan, filter on `transaction_month` | 80,306 (8.1%) | 907,380 | 57.092 |
| Q2 | Parallel Seq Scan | 987,686 (100%) | 0 | 458.565 |
| Q3 | Seq Scan | 987,686 (100%) | 0 | 267.642 |
| Q4 | Parallel Seq Scan | 987,686 (100%) | 0 | 88.332 |
| Q5 | Seq Scan | 987,686 (100%) | 0 | 264.497 |
| Q6 | Parallel Seq Scan, filter on `transaction_month` | 80,306 (8.1%) | 907,380 | 41.066 |

Insight: Only Q1 and Q6 filter the fact table (sales of 2022-2024) and throw away 92% of the rows they read. That is the case an index can help. Q2 to Q5 need every sale, so an index has nothing to skip.

The Execution Time column is one `EXPLAIN ANALYZE` run. It is a different metric from the five-run client averages in section 5 and must not be read as the speed-up claim for the index.

## 2. Initial four-index configuration

We first created four indexes from the table structure and the joins of the queries:

| # | Index | Reason for testing |
|---|---|---|
| 1 | `resale_transaction(transaction_month)` | Q1 filters to 2022-2024; locate the date range instead of scanning every sale |
| 2 | `resale_transaction(flat_id)` | join column of every query (transaction to flat) |
| 3 | `hdb_flat(building_id)` | join from flats to buildings |
| 4 | `proximity(building_id, distance_m)` | nearest hawker centre per building (`MIN(distance_m)`) in Q4 and Q5 |

Five Q1 runs compared with the Task 3 step-5 baseline. The baseline column matches `Task 3/results/task3_measurements.csv` (step 5, Q1) exactly. The "four indexes" column is a historical transcription that was attributed to `Task4_Q1_Index_Benchmark_Log.xlsx`; that spreadsheet is **not** in the repository, and these five times are **not** produced by the current Task 4 notebook. Treat them as unreproducible from the saved CSVs.

| Run | Task 3 baseline (ms) | Four indexes (ms, transcribed) |
|---|---|---|
| 1 | 22.308 | 38.135 |
| 2 | 22.013 | 39.678 |
| 3 | 22.363 | 39.433 |
| 4 | 22.141 | 39.992 |
| 5 | 22.560 | 38.692 |
| Average | 22.277 | 39.186 |

On that transcribed pair of means, Q1 was 75.9% slower with the four indexes, which is why the project moved to testing candidates one by one (section 3). Limits of this evidence:

- It measures the four indexes **together**; it does not show which one slowed Q1, or whether any did.
- Only Q1 was timed; the four-index times cannot be regenerated from `Task 4/results/`.
- Later saved experiments did not reproduce a slowdown for the date index alone: in the screening archive, C1 alone has Q1 at 15.21 ms (−35.8% vs the pooled screening baseline). In the combination archive, C1+C4 and C1 plus five further indexes have Q1 at 14.5 to 14.8 ms. Index 3 was not re-tested, so the cause of the transcribed four-index result is **not established**.
- Index 3 was probably redundant anyway: the unique constraint `flat_profile_unique` on `hdb_flat` already starts with `building_id`.

## 3. Candidate screening: nine indexes, one at a time

Protocol for each candidate: create it, refresh statistics, record whether the plan changed and uses the index, run Q1 to Q6 (1 warm-up + 5 timed runs each), drop it. Source: `results/task4_candidate_screening.csv` (330 rows: 9 candidates + two baseline blocks, 6 queries × 5 runs) and `results/task4_candidate_summary.csv`.

Un-indexed baselines in the **saved** screening file (sample mean ± sample standard deviation, ms):

| Block | Q1 | Q2 | Q3 | Q4 | Q5 | Q6 |
|---|---|---|---|---|---|---|
| BASELINE_START (5 runs) | 26.30 ± 0.83 | 407.09 ± 14.16 | 208.66 ± 2.18 | 74.08 ± 1.04 | 209.11 ± 3.53 | 32.89 ± 0.65 |
| BASELINE_END (5 runs) | 21.06 ± 0.29 | 391.92 ± 7.14 | 212.12 ± 1.68 | 72.47 ± 5.71 | 223.61 ± 28.64 | 40.32 ± 8.10 |
| Pooled (10 runs, used for `%` in the table and heat map) | 23.68 ± 2.82 | 399.50 ± 13.25 | 210.39 ± 2.59 | 73.28 ± 3.96 | 216.36 ± 20.70 | 36.61 ± 6.68 |

The two blocks disagree, especially Q1 and Q6. BASELINE_END for Q5 includes 273.719 ms and for Q6 includes 50.324 ms and 47.824 ms; those points inflate the pooled mean and standard deviation. All 330 rows are kept. Percentages below use the pooled baseline, as in `task4_candidate_summary.csv` and `task4_candidate_screening.png`. A negative percentage against that pooled baseline is **not** by itself a reliable claim of speed-up when the end block drifted.

| ID | Index | Why we tried it | Size (MB) | Build (ms) | Q1 | Q6 | Q2–Q5 | Verdict |
|---|---|---|---|---|---|---|---|---|
| C1 | `resale_transaction(transaction_month)` | date filter of Q1, Q6 | 6.73 | 130.1 | **−35.8%** (15.21 ms) | −4.9% (noise; plan uses index) | −5.1% to +1.2% | **kept** |
| C2 | same, `INCLUDE (flat_id, resale_price)` | covering: index-only scan possible | 29.73 | 409.4 | −39.3% (14.36 ms) | −5.7% (noise) | +1.1% to +5.8% | rejected: about 0.85 ms more on Q1 than C1 at 4.4 times the size |
| C3 | `resale_transaction USING brin (transaction_month)` | same filter, tiny | 0.02 | 23.8 | −31.8% (16.15 ms) | −27.7% (not beyond the noise rule: pooled Q6 std is large) | −4.3% to +2.2% | best measured option for Q1+Q6 together; not submitted (section 4) |
| C4 | `resale_transaction(flat_id)` | foreign key, join column | 9.72 | 202.0 | −11.2% (noise; plan unchanged) | **+66.6% (slower)** | −5.5% to +1.9% | rejected |
| C5 | `resale_transaction(flat_id) INCLUDE (transaction_month, resale_price)` | covering version of C4 | 29.73 | 495.0 | −12.2% (noise; plan unchanged) | +21.0% (slower; not beyond noise rule) | −2.9% to +1.9% | rejected |
| C6 | `hdb_flat(flat_type)` | equality filter in Q1, Q3, Q6 | 0.99 | 29.8 | noise | noise | none noticeable | rejected: no effect under the rule |
| C7 | `hdb_building(town_id)` | foreign key | 0.09 | 1.2 | noise | noise | none noticeable | rejected: no effect under the rule |
| C8 | `proximity(hawker_id)` | foreign key; primary key starts with `building_id` | 0.23 | 5.0 | noise | noise | none noticeable | rejected: no effect under the rule |
| C9 | `proximity(building_id, distance_m, hawker_id)` | `MIN` per building (Q4, Q5), `DISTINCT ON` (Q6) | 0.95 | 3.9 | noise | −19.2% (noise under the rule) | −6.1% to +1.6% | rejected: no effect under the rule |

"noise" means the plan did not change, or the change fails the project's 10% / 2-SD rule of thumb. Build times in this table are CREATE only (then `VACUUM (ANALYZE)`); they are not the create+`ANALYZE` figure in section 7.

![Effect of each candidate index on Q1-Q6](results/task4_candidate_screening.png)

Insight: Only candidates on `transaction_month` clearly helped Q1 under the noticeability rule. The heat map percentages match the pooled baseline above (C1 on Q1 −36%*, C4 on Q6 +67%*). For Q6, C1's −5%* against the pooled baseline coexists with a higher runtime than BASELINE_START (34.83 vs 32.89 ms): the negative sign is an artefact of pooling with the slow end block, not evidence that C1 speeds up Q6. The `flat_id` indexes (C4, C5) were used by the planner on Q6 and made it slower. A likely reason is that a join through an index on a randomly ordered column costs more than a hash join over the whole table; we did not prove that from the plans beyond noting the change. The small tables (C7 to C9) stay cheap to read in full.

The decision for the submitted index rests on the final same-session with/without measurement (section 5), not on screening percentages alone.

Combinations (average ms over 5 runs; source `task4_combination_tests.csv`). The baseline row is the same pooled screening baseline as above:

| Set | Q1 | Q2 | Q3 | Q4 | Q5 | Q6 |
|---|---|---|---|---|---|---|
| baseline (pooled screening) | 23.7 | 399.5 | 210.4 | 73.3 | 216.4 | 36.6 |
| C1 | 16.7 | 408.6 | 274.0 | 74.4 | 230.9 | 36.5 |
| C1 + C6 | 14.8 | 416.4 | 207.7 | 68.7 | 206.7 | 34.5 |
| C1 + C4 | 14.5 | 384.8 | 211.1 | 70.6 | 206.2 | 34.7 |
| C1 + C4, C6, C7, C8, C9 | 14.7 | 389.8 | 208.4 | 70.2 | 212.3 | 32.2 |

The C1-only block is noisy (Q3 includes a 409.28 ms run, which pulls the Q3 mean to 274.0 ms). Adding further indexes to C1 does not improve Q1 beyond the 14.5–14.8 ms band and does not help Q2–Q5 in a way that would justify those indexes. The full set brings Q6 near 32.2 ms; that was not investigated further and does not justify five extra indexes.

## 4. Final index

```sql
CREATE INDEX idx_resale_transaction_month
    ON housing.resale_transaction (transaction_month);

ANALYZE housing.resale_transaction;
```

(also in `indexes.sql`)

Why this index: Q1 and Q6 keep only 8.1% of the sales (2022-2024) and the plan reads and discards the other 92%. With the index PostgreSQL can avoid that full filter scan. In the screening archive it is the plain B-tree that helped Q1 under the noticeability rule without the large Q6 regression of the `flat_id` indexes.

Why a plain B-tree and not the alternatives:

- A B-tree does not depend on how the rows are stored. A BRIN index only skips table pages when the dates follow the physical order of the table. Here that order comes from the order of the loaded CSV files and is not guaranteed by the schema.
- The covering B-tree (C2) gave about 0.85 ms more on Q1 than C1 (14.36 against 15.21 ms) at 4.4 times the size.
- **Trade-off we accept:** In the screening archive BRIN was smaller (0.02 MB) and had a large negative percentage on Q6 against the pooled baseline (−27.7%), while the B-tree's Q6 change was inside the noise rule. The B-tree was chosen for robustness, not because screening proved it faster than BRIN on every query. The authoritative with/without numbers for the submitted B-tree are in section 5.

## 5. Results: with and without the index

Average of 5 timed runs ± sample standard deviation, in ms, from executing `indexes.sql` on the same database in Part C. Source: `results/task4_measurements.csv` → `results/task4_summary.csv`.

| Query | Without index | With index | Change | Index used by the plan |
|---|---|---|---|---|
| Q1 | 21.56 ± 0.25 | 14.93 ± 0.32 | **−30.8% (1.44 times faster)** | yes |
| Q2 | 392.17 ± 3.93 | 386.40 ± 5.59 | no effect (plan unchanged) | no |
| Q3 | 212.18 ± 0.48 | 208.10 ± 0.89 | no effect (plan unchanged) | no |
| Q4 | 69.97 ± 0.80 | 70.32 ± 0.49 | no effect (plan unchanged) | no |
| Q5 | 209.47 ± 6.36 | 205.62 ± 2.69 | no effect (plan unchanged) | no |
| Q6 | 32.62 ± 1.64 | 34.61 ± 0.15 | +6.1% slower (~1.99 ms); within the project's noise rule | yes |

Ranges of the five timed runs (ms): Q1 without 21.19–21.87, with 14.55–15.30; Q6 without 31.02–35.09, with 34.41–34.76. The Q6 ranges overlap (one without-index run is 35.093 ms, above every with-index run).

![Query runtime without and with the index](results/task4_runtime_with_vs_without_index.png)

The chart is built from the same summary: bars are the five-run averages (labels rounded to whole milliseconds), dots are the individual timed runs, and the dashed line in each panel is the Task 3 step-5 average (Q1 22.28, Q2 412.19, Q3 217.83, Q4 70.58, Q5 226.61, Q6 33.47 ms). Panel titles follow the noticeability flags in `task4_summary.csv` (Q1: 1.4x faster (−31%); Q6: plan changed, runtime within noise).

Discussion:

- **Q1 (−6.63 ms).** The plan changes from a Parallel Seq Scan that reads and filters 987,686 rows to a Parallel Bitmap Heap Scan fed by a Bitmap Index Scan on `idx_resale_transaction_month` that returns the 80,306 matching rows (`results/plans/q1_*.txt`). A single `EXPLAIN ANALYZE` Execution Time in those files is 57.092 ms without the index and 18.419 ms with it; that is one plan-instrumented run, not the five-run client average above. The client-side gain is limited because the rest of the query (scan of the 4- and 5-room flats, joins to buildings and towns) is unchanged, and because Q1 was already fast under parallel scan.
- **Q6 (+1.99 ms, +6.1%).** The planner uses the index, and the average client runtime rises. The absolute change (1.99 ms) is below both parts of the project's rule of thumb (10% of 32.62 ms ≈ 3.26 ms, and 2 × 1.64 ≈ 3.28 ms), so `beyond_noise` and `noticeable` are false in `task4_summary.csv`. The five with-index runs are not uniformly slower than the five without-index runs. We report the measured +6.1% and leave the cause unisolated.
- **Q2 to Q5.** The plans are identical with and without the index, so the index plays no part, and the differences (−1.9% to +0.5%) are noise under the rule. These queries read every sale (section 1).

Q5 returns 2 rows at step 5 in every measurement, so the budget of SGD 450,000 still gives a non-empty result on the largest database.

## 6. What indexes cannot fix

Task 3 named Q2 and Q3 as the first candidates for indexes. No index helps them under the screening rule (section 3). Two experiments with session settings only (no schema change, `queries.sql` untouched) show where their time goes. Source: `results/task4_supporting_experiments.csv` (5 timed runs each; means ± sample SD):

| Experiment | Before (ms) | After (ms) | Change |
|---|---|---|---|
| Q2 with `work_mem = 256MB` (removes the sort spill; saved Q2 without-index plan shows `Disk: 14824kB`) | 417.0 ± 64.7 | 356.4 ± 5.8 | −14.5% |
| Q3 with its `WITH three_room` subquery declared `NOT MATERIALIZED` (same result) | 210.2 ± 0.4 | 109.9 ± 1.1 | **−47.7%** |

The Q2 default block includes one slow run of 532.036 ms (other four runs 380.6–399.6 ms). That point lifts the before-mean and therefore the −14.5% figure; it should not be read as a stable 14.5% win from raising `work_mem`. Even with the spill removed, most of Q2's time remains. Q3 gets about twice as fast from a rewrite, not from an index. We did not change `queries.sql`, because it is a Task 3 deliverable, but the NOT MATERIALIZED experiment is the largest speed-up in the supporting file.

## 7. Cost of the index

Source: `results/task4_index_cost.csv`. Insert single-run times are not stored in that CSV; they appear in the saved notebook output of the cost cell (`insert runs without: [206, 227, 176] | with: [300, 283, 283]`).

| Item | Value |
|---|---|
| Size of `idx_resale_transaction_month` | 6.73 MB (13.7% of the 49.1 MB table heap) |
| Build time (execute `indexes.sql`, including its `ANALYZE`) | 148.4 ms |
| Inserting 100,000 sales into a scratch copy, without index | 203.0 ms (mean of 3 runs: 206, 227, 176) |
| The same insert with the index | 288.9 ms (mean of 3 runs: 300, 283, 283), **+42.4%** |

Insight: The index makes inserts slower and takes space. Only three insert runs were collected, so the slowdown is reported as this measured mean ratio, not as a tight range. The database is only read after loading, so this cost is acceptable here.

## 8. Limitations

- One database size (the largest), one machine, 5 timed runs per condition after one warm-up. The benefit of an index depends on the hardware: Q1 was already about 22 ms here because the sales table is scanned in parallel, which leaves limited room to save.
- The data mostly fits in memory (with the final index, housing tables are 122.65 MB in the measurement file; `shared_buffers` is 128 MB; the OS also caches files). Cold-cache runs were not measured.
- The workload is read-only analysis. The insert cost matters little here, but would in a system that keeps receiving sales.
- The initial four-index measurement is Q1 only, uses a historical transcription whose spreadsheet is missing from the repo, and cannot be attributed to a single index (section 2).
- The screening archive has drifted start/end baselines; pooled percentages for Q6 in particular must be read with that caveat (section 3).
- The noise rule is a write-up threshold (10% and 2 sample SDs), not a formal hypothesis test. Q6's +6.1% fails that threshold on the saved final runs.

## 9. Discrepancies and how we handled them

- **Stale statistics right after loading.** Q4 and Q5 ran much slower until `VACUUM (ANALYZE)` on all seven tables. All measurements here are taken after refreshing the statistics.
- **PostgreSQL 18 prints fractional row counts** in `EXPLAIN ANALYZE` (for example `rows=26768.67`). The notebook's plan parser expected whole numbers and failed, so it was changed to accept decimals.
- **Screening baseline drift.** In the saved screening CSV, BASELINE_START and BASELINE_END disagree (Q1 26.30 vs 21.06 ms; Q6 32.89 vs 40.32 ms with two slow end runs). The archive was not edited. Percentages use the pooled 10 runs and are interpreted with that limit; the submitted index is judged from the final Part C measurement instead.
- **Q6 under the project's noise rule.** Final runs: +6.1%, overlapping ranges, `noticeable = false`. We report the measured change and the plan change, without claiming a clean five-vs-five separation.
- **The transcribed four-index slowdown is not in the CSVs** and was not reproduced by C1 alone or by the saved combinations (section 2).
- **Insert test:** three runs per condition; means 203.0 vs 288.9 ms (+42.4%). Single runs only in the notebook output (section 7).
- **Older draft numbers** in a previous version of this report (for example Q1 20.9 → 14.6 ms, Q6 +9.6%, build 124 ms, insert +83%) do not match the saved CSVs. The notebook still contains a saved check output that flagged those older `indexes.sql` comments as MISMATCH against `task4_summary.csv`; the comments and this report now follow the CSV.

## Supplementary files

| File | Content |
|---|---|
| `indexes.sql` | The final `CREATE INDEX` statement, with the reasoning |
| `Task 4 Index Experiments.ipynb` | The notebook that produced every number in this report |
| `results/task4_measurements.csv` | Raw final measurements: 60 rows (6 queries × 5 runs × with/without index) |
| `results/task4_summary.csv` | Average, sample standard deviation, min and max per query, with and without the index |
| `results/task4_runtime_with_vs_without_index.png` | The bar chart of section 5 |
| `results/task4_candidate_screening.csv` | Raw screening: 330 rows (9 candidates and two baselines, 6 queries × 5 runs) |
| `results/task4_candidate_summary.csv`, `results/task4_candidate_screening.png` | Summary and heat map of the screening (pooled baseline) |
| `results/task4_combination_tests.csv` | Candidates in combination |
| `results/task4_index_cost.csv` | Size, build time and insert slowdown |
| `results/task4_supporting_experiments.csv` | Q2 `work_mem` and Q3 `NOT MATERIALIZED` runs |
| `results/task4_environment.json` | PostgreSQL version, CPU count and settings of the measuring machine |
| `results/plans/` | `EXPLAIN ANALYZE` of every query without and with the index |

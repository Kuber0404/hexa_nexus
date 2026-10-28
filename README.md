# HDB resale prices and hawker centres: Data Systems project

Team project for SD6103 Data Systems (AY26S1). We build a PostgreSQL database that links HDB resale transactions to nearby hawker centres, load it from the data.gov.sg datasets, query it, and measure how query runtime grows with database size. The brief is `Data Systems Project.pdf`.

| Task | Content | Status |
|---|---|---|
| 1 | ER model, relational schema, SQL to create it | Done: `Task 1/revised/` |
| 2 | Python ETL that turns the raw files into one CSV per table | Done: `Task 2/` |
| 3 | SQL queries Q1–Q6, insights, runtime at 5 database sizes | Done: `Task 3/` |
| 4 | Indexes and their effect on runtime | Not started |

## Repository layout

```
.
├── Data Systems Project.pdf        course brief (tasks, required queries, rubric)
├── README.md                       this file
├── Task 1/
│   ├── Task 1 — Dataset-Verified Design_old.pdf   first design, kept for reference
│   └── revised/                    current design (see below)
├── Task 2/
│   ├── notebook/
│   │   ├── Data Systems Task 2 (revised).ipynb   current ETL
│   │   └── Data Systems Task 2.ipynb             first ETL, kept for reference
│   ├── task2_report.md
│   └── Resale Flat Prices ... Jan 2015 to Dec 2016.csv   old copy, see "Housekeeping"
├── Task 3/
│   ├── Task 3 Queries and Measurements.ipynb
│   ├── queries.sql
│   ├── task3_report.md
│   └── results/
└── data/
    ├── raw/                        source datasets, unchanged
    ├── cache/                      OneMap answers already fetched
    ├── processed/                  output of the first ETL (2015–2016 only)
    └── processed_steps/step_1..5/  output of the current ETL, one folder per database size
```

`.venv/` holds the Python environment and is ignored by git.

## Task 1: design (`Task 1/revised/`)

| File | What it does |
|---|---|
| `task1_report.md` | Task 1 report: proximity definition, ER diagram, mapping to tables, normal form, constraints, full schema SQL |
| `er_diagram.png` | Chen-notation ER diagram with (min,max) cardinalities |
| `er_diagram.py` | Draws the diagram as SVG; render it to PNG with a browser to update `er_diagram.png` |
| `schema.sql` | Creates the `housing` schema and its 7 tables with all keys and constraints, in one transaction |
| `load_data.sql` | Bulk-loads the 7 CSVs of one step with `COPY` (full file paths; see "Running everything") |

The 7 tables are `town`, `hdb_building`, `hdb_flat`, `resale_transaction`, `hawker_centre`, `proximity_level` and `proximity`.

## Task 2: ETL (`Task 2/`)

| File | What it does |
|---|---|
| `notebook/Data Systems Task 2 (revised).ipynb` | The ETL. Reads the raw files, cleans and splits them into the 7 tables, finds coordinates, computes building–hawker distances, validates everything against the schema, and writes the CSVs plus `data_quality_report.txt` |
| `notebook/Data Systems Task 2.ipynb` | The first ETL, which used only the 2015–2016 file and writes to `data/processed/`. Kept to show what had to change |
| `task2_report.md` | Task 2 report: transformations, what we had to redo, errors during loading |

The revised notebook has a `STEP` setting (1–5, or the environment variable `RESALE_STEP`). Step k combines the first k resale files and writes to `data/processed_steps/step_k/`.

## Task 3: queries and runtime (`Task 3/`)

| File | What it does |
|---|---|
| `queries.sql` | Q1–Q6. Each query starts with a `-- @Qn` marker, which the notebook uses to read it |
| `Task 3 Queries and Measurements.ipynb` | Part A runs each query once and shows the result. Part B runs each query 5 times and appends the runtimes to the measurements file. Part C draws the runtime chart |
| `task3_report.md` | Task 3 report: SQL, result images, insights, runtime table, chart and discussion |
| `results/task3_measurements.csv` | Raw measurements: 150 rows (6 queries × 5 runs × 5 sizes) with database size and row counts |
| `results/task3_summary.csv` | Average, standard deviation, min and max per query and size |
| `results/task3_runtime_vs_size.png` | One panel per query: runtime against database size |
| `results/screenshots/` | Step-1 result of each query, first 20 rows |
| `results/query_results_step1/` | Full step-1 result of each query as CSV |

The notebook's settings are `DB_NAME` (the database holding the `housing` schema), `STEP` (or the environment variable `TASK3_STEP`) and `RUNS`.

## Data (`data/`)

| Path | Content |
|---|---|
| `raw/flat_resale_prices/` | The 5 HDB resale files from data.gov.sg collection 189 (1990–1999, 2000–Feb 2012, Mar 2012–2014, 2015–2016, 2017 onwards) |
| `raw/hawker_centres/ListofGovernmentMarketsHawkerCentres.csv` | NEA list of 107 markets and hawker centres with stall counts |
| `raw/hawker_geo/hawker_geo.csv` | Hawker centre coordinates (from NTULearn) |
| `raw/hdb_geo/hdb.csv` | HDB block coordinates from BlueSkyLT/siteselect_sg |
| `cache/onemap_search_cache.json` | OneMap search answers, so no address is looked up twice |
| `processed/` | First ETL output (2015–2016 file, old proximity columns) |
| `processed_steps/step_1` … `step_5` | Current ETL output, one folder per database size (below) |

The steps add older files in reverse date order, and each step keeps everything from the step before:

| Step | File added | Period | Sales | Size (MB) |
|---|---|---|---|---|
| 1 | Jan 2017 onwards | 2017–2026 | 241,483 | 44.2 |
| 2 | Jan 2015 – Dec 2016 | 2015–2026 | 278,636 | 47.5 |
| 3 | Mar 2012 – Dec 2014 | 2012–2026 | 330,839 | 53.7 |
| 4 | 2000 – Feb 2012 | 2000–2026 | 700,490 | 83.0 |
| 5 | 1990 – 1999 | 1990–2026 | 987,686 | 104.9 |

## Running everything

You need Python 3.10+, PostgreSQL (we used 18) and the packages `pandas numpy requests psycopg[binary] matplotlib jupyter`.

```bash
python3 -m venv .venv
.venv/bin/pip install pandas numpy requests "psycopg[binary]" matplotlib jupyter
```

1. Build the CSVs: open the revised Task 2 notebook, set `STEP`, and run all cells. Repeat for each step you need. OneMap is only called for buildings missing from `hdb.csv` and not yet in the cache.
2. Create the schema: in any SQL tool connected to your database, run `DROP SCHEMA IF EXISTS housing CASCADE;` and then all of `Task 1/revised/schema.sql`.
3. Load the data: in `Task 1/revised/load_data.sql`, change the 7 paths to your repository folder and to the step you want (`data/processed_steps/step_k/`), then run it. Each `COPY` prints the rows loaded. Use `COPY`, not `\copy`; `\copy` only works inside psql.
4. Measure: in the Task 3 notebook set `DB_NAME` and `STEP`, then run all cells. Rerunning a step replaces that step's rows in the measurements file.

The ETL renumbers the surrogate keys on every run, so each step is a full reload of all 7 tables, not an append.

## Design decisions

These were agreed after comparing the first Task 1 design with the first ETL:

- Proximity is the Haversine distance × 1.5 as an estimated walking distance. Three levels: walking distance (under 800 m), nearby (800–1,600 m) and accessible (1,600–2,400 m). Pairs at 2,400 m or more are not stored, so buildings with no centre in range have no proximity class.
- The level is not stored in `proximity`, since distance determines it. Queries join `proximity_level` on the distance range.
- Only `distance_m` is stored; the straight-line distance (`distance_m / 1.5`) was dropped to keep 3NF. The source-hash columns of the first design were dropped as unused.
- `hdb_flat` is a flat profile, because the data has no unit number. The lease start year stays on the flat: across all files, 3 buildings have two lease years.
- `remaining_lease` exists only from 2015. Older rows store NULL, and Q2 derives remaining lease as 99 − (sale year − lease start year), which is within ±1 year of the reported value.
- The 1990s file spells `MULTI GENERATION`; the ETL maps it to `MULTI-GENERATION` to pass the schema check.
- Step 1 uses the 2017 onwards file, because Q1 needs a 3-year range and the 2015–2016 file covers only two years.
- Q5's budget is SGD 450,000. The first value, 600,000, returned no rows at steps 4 and 5.
- Query insights use step 1. Later steps mix prices from 1990 to 2026 without inflation adjustment.

## Known data issues

- 140 old blocks could not be located in `hdb.csv` or OneMap; their coordinates are NULL and they have no proximity class. Another 10 matched OneMap on block number only.
- One hawker centre (Blk 4A Woodlands Centre Road) has no coordinates.
- Files up to Feb 2012 use the approval date and later files the registration date. Because of this, 51 older sales get a derived remaining lease of 100 or 101 years.
- Q2 and Q3 sort more data than PostgreSQL's default 4 MB `work_mem` and spill to disk at the larger steps.

## Housekeeping

- `Task 2/Resale Flat Prices ... Jan 2015 to Dec 2016.csv` is an old committed copy of the file in `data/raw/flat_resale_prices/` and can be removed.
- `data/processed/onemap_search_cache.json` is the first notebook's copy of the cache. Both notebooks now use `data/cache/`.
- `load_data.sql` and the Task 3 notebook's `DB_NAME` contain values for one team member's machine; change them before running.

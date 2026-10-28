# Task 2: Data acquisition and population

## Transformations and computations

The program is `notebook/Data Systems Task 2 (revised).ipynb`. It reads the resale file(s), the NEA hawker list, `hawker_geo.csv` and `hdb.csv`, and writes one CSV per table to `data/processed_steps/step_<k>/`, ready for `COPY`. No row is dropped for a missing value; a gap is filled from another source or left NULL.

| Input | Transformation | Reason |
|---|---|---|
| Resale | Trim and upper-case town, block, street, flat type and model | One spelling per value |
| Resale | `month` to a DATE; `storey_range` "10 TO 12" to two integers | Matches column types; atomic values |
| Resale | `remaining_lease` to months ("61 years 04 months" gives 736); NULL if the file has no such column | One unit, no invented values |
| Resale | `MULTI GENERATION` to `MULTI-GENERATION` | The 1990s file uses a different spelling |
| Resale | Split into town, building, flat profile and transaction with surrogate keys | Removes repeated data (BCNF) |
| Buildings | Coordinates from `hdb.csv` by block and street, then OneMap, else NULL | Offline first, cached API second |
| Hawkers | Join the two hawker files on postal code, not name | Names match for 17 of 107 centres, postal codes for 104 |
| Proximity | Haversine × 1.5, pairs under 2,400 m kept | Walking estimate (Task 1) |

A validation step checks keys, foreign keys and every Task 1 constraint before loading.

## What we had to redo

Task 3 showed problems that sent us back to Task 1. We first loaded the 2015–2016 file, but it covers two years and Q1 needs three, so we switched to the 2017 onwards file. Task 3 then adds the older files, and those have no `remaining_lease` column, so the ETL stopped. We made the column nullable and derive remaining lease in Q2 from the lease start year instead. We also removed `straight_line_m`, because walking distance is computed from it and storing both broke 3NF. The notebook now takes a `STEP` setting and builds the five cumulative datasets in one run.

Because we start from the newest file, the steps add the older files in reverse date order. Each step keeps everything from the step before and adds one earlier period:

| Step | File added | Period covered | Sales |
|---|---|---|---|
| 1 | Jan 2017 onwards | 2017–2026 | 241,483 |
| 2 | Jan 2015 – Dec 2016 | 2015–2026 | 278,636 |
| 3 | Mar 2012 – Dec 2014 | 2012–2026 | 330,839 |
| 4 | 2000 – Feb 2012 | 2000–2026 | 700,490 |
| 5 | 1990 – 1999 | 1990–2026 | 987,686 |

## Errors during loading

`\copy` failed in our SQL tool with `syntax error at or near "\"`, since it only works in psql. We switched to server-side `COPY` with full paths. Rerunning the schema gave `schema "housing" already exists`, which aborted the rest of the transaction, so a reload now starts with `DROP SCHEMA housing CASCADE`. One load left `proximity` empty and Q4–Q6 returned no rows until we loaded it. The ETL renumbers keys on every run, so each step reloads all seven tables rather than appending. OneMap could not place 140 old blocks, which keep NULL coordinates. Two problems were caught before loading. The 279 `MULTI GENERATION` rows from the 1990s would have broken the `flat_type` check, and the first notebook looked for its inputs in its own folder, which failed once the raw files moved to `data/raw/`.

## Supplementary material

The executable code is `notebook/Data Systems Task 2 (revised).ipynb`; set `STEP` from 1 to 5 to rebuild each dataset. The first version, `Data Systems Task 2.ipynb`, and its 2015–2016 output in `data/processed/` are kept to show what changed.

-- =============================================================================
-- Task 1 (revised): HDB resale x hawker centre database, PostgreSQL schema
--
-- Matches the CSVs produced by the Task 2 ETL (data/processed/*.csv).
-- Run once, from a shell:
--     createdb hdb_hawker
--     psql -d hdb_hawker -v ON_ERROR_STOP=1 -f "Task 1/revised/schema.sql"
--
-- Surrogate keys are plain integers because the ETL assigns them; no sequences
-- are needed. No performance indexes are created here (that is Task 4); only the
-- indexes PostgreSQL creates automatically for PRIMARY KEY / UNIQUE / EXCLUDE.
-- =============================================================================

BEGIN;

-- Fails if the schema already exists, so existing data is never overwritten.
CREATE SCHEMA housing;

-- -----------------------------------------------------------------------------
-- Town: one row per HDB town.
-- -----------------------------------------------------------------------------
CREATE TABLE housing.town (
    town_id    integer PRIMARY KEY,
    town_name  text    NOT NULL UNIQUE,
    CONSTRAINT town_name_canonical CHECK (town_name <> '' AND town_name = upper(btrim(town_name)))
);

-- -----------------------------------------------------------------------------
-- HDB building: one row per (block, street_name) address; belongs to one town.
-- Coordinates come from hdb.csv, else OneMap, else stay NULL.
-- -----------------------------------------------------------------------------
CREATE TABLE housing.hdb_building (
    building_id        integer PRIMARY KEY,
    town_id            integer NOT NULL REFERENCES housing.town (town_id) ON DELETE RESTRICT,
    block              text    NOT NULL,
    street_name        text    NOT NULL,
    latitude           double precision,
    longitude          double precision,
    coordinate_source  text    NOT NULL,
    CONSTRAINT building_address_unique UNIQUE (block, street_name),
    CONSTRAINT block_canonical  CHECK (block <> '' AND block = upper(btrim(block))),
    CONSTRAINT street_canonical CHECK (street_name <> '' AND street_name = upper(btrim(street_name))),
    CONSTRAINT building_coordinate_pair CHECK ((latitude IS NULL) = (longitude IS NULL)),
    -- bounding box around Singapore, the same one the ETL uses
    CONSTRAINT building_in_singapore CHECK (latitude BETWEEN 1.15 AND 1.48 AND longitude BETWEEN 103.6 AND 104.1),
    CONSTRAINT building_coordinate_source CHECK (
        coordinate_source IN ('hdb_dataset', 'onemap_exact', 'onemap_block_only', 'none')),
    -- 'none' exactly when no source could locate the building
    CONSTRAINT building_source_matches_coords CHECK ((coordinate_source = 'none') = (latitude IS NULL))
);

-- -----------------------------------------------------------------------------
-- HDB flat: an observable flat profile within a building. The source data has
-- no unit number, so several physical units can share one profile.
-- lease_commence_year stays here (not on the building): across all five resale
-- files, 3 buildings have two different lease years.
-- -----------------------------------------------------------------------------
CREATE TABLE housing.hdb_flat (
    flat_id              integer      PRIMARY KEY,
    building_id          integer      NOT NULL REFERENCES housing.hdb_building (building_id) ON DELETE RESTRICT,
    flat_type            text         NOT NULL,
    flat_model           text         NOT NULL,
    floor_area_sqm       numeric(6,1) NOT NULL,
    storey_lower         smallint     NOT NULL,
    storey_upper         smallint     NOT NULL,
    lease_commence_year  smallint     NOT NULL,
    CONSTRAINT flat_profile_unique UNIQUE (building_id, flat_type, flat_model, floor_area_sqm,
                                           storey_lower, storey_upper, lease_commence_year),
    CONSTRAINT flat_type_valid CHECK (flat_type IN ('1 ROOM', '2 ROOM', '3 ROOM', '4 ROOM', '5 ROOM',
                                                    'EXECUTIVE', 'MULTI-GENERATION')),
    CONSTRAINT flat_model_canonical CHECK (flat_model <> '' AND flat_model = upper(btrim(flat_model))),
    CONSTRAINT flat_area_positive   CHECK (floor_area_sqm > 0),
    CONSTRAINT flat_storey_range    CHECK (storey_lower >= 1 AND storey_upper >= storey_lower),
    -- HDB was founded in 1960; the upper bound only guards against typos
    CONSTRAINT flat_lease_year      CHECK (lease_commence_year BETWEEN 1960 AND 2100)
);

-- -----------------------------------------------------------------------------
-- Resale transaction: one row per sale of a flat profile.
-- reported_remaining_lease_months is NULL where the source file has no
-- remaining_lease column (all files before 2015). Q2 derives remaining lease
-- from lease_commence_year instead; no estimate is stored.
-- -----------------------------------------------------------------------------
CREATE TABLE housing.resale_transaction (
    transaction_id                   integer       PRIMARY KEY,
    flat_id                          integer       NOT NULL REFERENCES housing.hdb_flat (flat_id) ON DELETE RESTRICT,
    transaction_month                date          NOT NULL,
    resale_price                     numeric(12,2) NOT NULL,
    reported_remaining_lease_months  smallint,
    CONSTRAINT transaction_month_first_day CHECK (EXTRACT(DAY FROM transaction_month) = 1),
    CONSTRAINT transaction_month_range     CHECK (transaction_month >= DATE '1990-01-01'),
    CONSTRAINT transaction_price_positive  CHECK (resale_price > 0),
    -- an HDB lease is 99 years = 1188 months
    CONSTRAINT transaction_lease_range     CHECK (reported_remaining_lease_months BETWEEN 0 AND 1188)
);

-- -----------------------------------------------------------------------------
-- Hawker centre: merged from the NEA government list (type, stall counts) and
-- hawker_geo.csv (coordinates). Attributes a source does not have stay NULL.
-- -----------------------------------------------------------------------------
CREATE TABLE housing.hawker_centre (
    hawker_id              integer PRIMARY KEY,
    centre_name            text    NOT NULL UNIQUE,
    address                text,
    centre_type            text,
    latitude               double precision,
    longitude              double precision,
    total_stalls           integer,
    cooked_food_stalls     integer,
    market_produce_stalls  integer,
    data_source            text    NOT NULL,
    CONSTRAINT hawker_name_nonempty    CHECK (btrim(centre_name) <> ''),
    CONSTRAINT hawker_address_nonempty CHECK (btrim(address) <> ''),
    -- HC = hawker centre, MHC = market & hawker centre, MK = market
    CONSTRAINT hawker_centre_type      CHECK (centre_type IN ('HC', 'MHC', 'MK')),
    CONSTRAINT hawker_coordinate_pair  CHECK ((latitude IS NULL) = (longitude IS NULL)),
    CONSTRAINT hawker_in_singapore     CHECK (latitude BETWEEN 1.15 AND 1.48 AND longitude BETWEEN 103.6 AND 104.1),
    CONSTRAINT hawker_stalls_nonnegative CHECK (total_stalls >= 0 AND cooked_food_stalls >= 0
                                                AND market_produce_stalls >= 0),
    CONSTRAINT hawker_cooked_within_total CHECK (cooked_food_stalls <= total_stalls),
    CONSTRAINT hawker_market_within_total CHECK (market_produce_stalls <= total_stalls),
    -- gov = NEA list; geo = hawker_geo.csv; hdb / onemap / manual = where missing coordinates came from
    CONSTRAINT hawker_data_source CHECK (
        data_source IN ('gov+geo', 'geo_only', 'gov_only', 'gov+hdb', 'gov+onemap', 'gov+manual'))
);

-- -----------------------------------------------------------------------------
-- Proximity level: the three proximity classes, as half-open intervals
-- [min_dist_m, max_dist_m) of estimated walking distance.
-- -----------------------------------------------------------------------------
CREATE TABLE housing.proximity_level (
    level_id    smallint     PRIMARY KEY,
    label       text         NOT NULL UNIQUE,
    min_dist_m  numeric(7,1) NOT NULL,
    max_dist_m  numeric(7,1) NOT NULL,
    CONSTRAINT level_label_nonempty CHECK (btrim(label) <> ''),
    CONSTRAINT level_interval_valid CHECK (min_dist_m >= 0 AND max_dist_m > min_dist_m),
    -- no two levels may overlap, so every distance maps to at most one level
    CONSTRAINT level_no_overlap EXCLUDE USING gist (numrange(min_dist_m, max_dist_m, '[)') WITH &&)
);

-- -----------------------------------------------------------------------------
-- Proximity: the M:N relationship between buildings and hawker centres.
-- distance_m = estimated walking distance = 1.5 x Haversine straight-line
-- distance. Only pairs inside the outermost level (< 2,400 m) are stored.
-- The level is not stored: it follows from distance_m, so queries join
-- proximity_level on min_dist_m <= distance_m < max_dist_m.
-- -----------------------------------------------------------------------------
CREATE TABLE housing.proximity (
    building_id  integer      NOT NULL REFERENCES housing.hdb_building (building_id) ON DELETE RESTRICT,
    hawker_id    integer      NOT NULL REFERENCES housing.hawker_centre (hawker_id) ON DELETE RESTRICT,
    distance_m   numeric(7,1) NOT NULL,
    PRIMARY KEY (building_id, hawker_id),
    CONSTRAINT proximity_distance_nonnegative CHECK (distance_m >= 0)
);

COMMIT;

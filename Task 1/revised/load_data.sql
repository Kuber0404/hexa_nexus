-- =============================================================================
-- Bulk-load the Task 2 CSVs into the schema created by schema.sql.
--
-- How to run: in any SQL tool (VS Code, pgAdmin, psql), connected to the
-- database that holds the housing schema, run the statements below IN ORDER.
-- Parents are loaded before children so every foreign key resolves.
--
-- Uses server-side COPY (plain SQL), so it works in every tool. \copy would
-- only work inside psql. COPY needs the FULL path of each file: if the
-- repository is in a different folder on your machine, replace
--     /Users/kuberbellad04/Documents/MSDS/Sem 1/Data Systems/hexa_nexus
-- with your own repository path (find-and-replace, 7 places).
--
-- Column lists are explicit so the load never depends on CSV column order.
-- Each statement prints COPY <rows>; expected counts (Jan 2017 onwards file):
--   town 26, hdb_building 9753, hdb_flat 98205, resale_transaction 241483,
--   hawker_centre 131, proximity_level 3, proximity 30084
-- To start over: DROP SCHEMA housing CASCADE; then run schema.sql again.
-- =============================================================================

COPY housing.town (town_id, town_name)
FROM '/Users/kuberbellad04/Documents/MSDS/Sem 1/Data Systems/hexa_nexus/data/processed_steps/step_4/town.csv'
WITH (FORMAT csv, HEADER true);

COPY housing.hdb_building (building_id, town_id, block, street_name, latitude, longitude, coordinate_source)
FROM '/Users/kuberbellad04/Documents/MSDS/Sem 1/Data Systems/hexa_nexus/data/processed_steps/step_4/hdb_building.csv'
WITH (FORMAT csv, HEADER true);

COPY housing.hdb_flat (flat_id, building_id, flat_type, flat_model, floor_area_sqm, storey_lower, storey_upper, lease_commence_year)
FROM '/Users/kuberbellad04/Documents/MSDS/Sem 1/Data Systems/hexa_nexus/data/processed_steps/step_4/hdb_flat.csv'
WITH (FORMAT csv, HEADER true);

COPY housing.resale_transaction (transaction_id, flat_id, transaction_month, resale_price, reported_remaining_lease_months)
FROM '/Users/kuberbellad04/Documents/MSDS/Sem 1/Data Systems/hexa_nexus/data/processed_steps/step_4/resale_transaction.csv'
WITH (FORMAT csv, HEADER true);

COPY housing.hawker_centre (hawker_id, centre_name, address, centre_type, latitude, longitude, total_stalls, cooked_food_stalls, market_produce_stalls, data_source)
FROM '/Users/kuberbellad04/Documents/MSDS/Sem 1/Data Systems/hexa_nexus/data/processed_steps/step_4/hawker_centre.csv'
WITH (FORMAT csv, HEADER true);

COPY housing.proximity_level (level_id, label, min_dist_m, max_dist_m)
FROM '/Users/kuberbellad04/Documents/MSDS/Sem 1/Data Systems/hexa_nexus/data/processed_steps/step_4/proximity_level.csv'
WITH (FORMAT csv, HEADER true);

COPY housing.proximity (building_id, hawker_id, distance_m)
FROM '/Users/kuberbellad04/Documents/MSDS/Sem 1/Data Systems/hexa_nexus/data/processed_steps/step_4/proximity.csv'
WITH (FORMAT csv, HEADER true);

-- refresh planner statistics after the bulk load
ANALYZE;

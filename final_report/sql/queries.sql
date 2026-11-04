-- =============================================================================
-- Task 3: SQL queries Q1-Q6 on the housing schema (Task 1/revised/schema.sql)
--
-- Each query starts with a line "-- @Qn"; the Task 3 notebook uses these
-- markers to read the queries from this file.
--
-- Shared definitions
--   price per square metre  = resale_price / floor_area_sqm  (per sale)
--   remaining lease (years) = 99 - (sale year - lease_commence_year)
--       Derived for every sale, because files before 2015 do not report it.
--       Within +-1 year of the reported value where one is reported.
--   proximity class of a building = level of its NEAREST hawker centre
--       (Q5: of its nearest centre with market produce stalls). Buildings with
--       no centre within 2,400 m have no class and are left out of Q4-Q6.
-- =============================================================================


-- @Q1
-- Price per square metre across towns: average price per m2 of 4-room and
-- 5-room flats sold in the 3-year range 2022-2024, per town and flat type.
SELECT t.town_name,
       f.flat_type,
       ROUND(AVG(rt.resale_price / f.floor_area_sqm), 2) AS avg_price_per_sqm,
       COUNT(*)                                          AS transactions
FROM housing.resale_transaction rt
JOIN housing.hdb_flat     f ON f.flat_id     = rt.flat_id
JOIN housing.hdb_building b ON b.building_id = f.building_id
JOIN housing.town         t ON t.town_id     = b.town_id
WHERE f.flat_type IN ('4 ROOM', '5 ROOM')
  AND rt.transaction_month >= DATE '2022-01-01'
  AND rt.transaction_month <  DATE '2025-01-01'
GROUP BY t.town_name, f.flat_type
ORDER BY t.town_name, f.flat_type;


-- @Q2
-- Remaining lease vs transaction price: per town and remaining-lease bucket,
-- the median resale price, average price per m2 and number of sales.
WITH sale AS (
    SELECT t.town_name,
           rt.resale_price,
           rt.resale_price / f.floor_area_sqm AS price_per_sqm,
           99 - (EXTRACT(YEAR FROM rt.transaction_month)::int - f.lease_commence_year) AS remaining_lease_years
    FROM housing.resale_transaction rt
    JOIN housing.hdb_flat     f ON f.flat_id     = rt.flat_id
    JOIN housing.hdb_building b ON b.building_id = f.building_id
    JOIN housing.town         t ON t.town_id     = b.town_id
),
bucketed AS (
    SELECT town_name, resale_price, price_per_sqm,
           CASE
               WHEN remaining_lease_years < 50 THEN '1: < 50 years'
               WHEN remaining_lease_years < 70 THEN '2: 50-69 years'
               WHEN remaining_lease_years < 90 THEN '3: 70-89 years'
               ELSE                                 '4: 90+ years'
           END AS lease_bucket
    FROM sale
)
SELECT town_name,
       lease_bucket,
       percentile_cont(0.5) WITHIN GROUP (ORDER BY resale_price) AS median_resale_price,
       ROUND(AVG(price_per_sqm), 2)                              AS avg_price_per_sqm,
       COUNT(*)                                                  AS transaction_volume
FROM bucketed
GROUP BY town_name, lease_bucket
ORDER BY town_name, lease_bucket;


-- @Q3
-- Resale price for towns with large flats: the 10 towns with the highest
-- average floor area of 3-room flats sold, and for each of them the highest
-- 3-room resale price in every year.
WITH three_room AS (
    SELECT t.town_name,
           EXTRACT(YEAR FROM rt.transaction_month)::int AS sale_year,
           f.floor_area_sqm,
           rt.resale_price
    FROM housing.resale_transaction rt
    JOIN housing.hdb_flat     f ON f.flat_id     = rt.flat_id
    JOIN housing.hdb_building b ON b.building_id = f.building_id
    JOIN housing.town         t ON t.town_id     = b.town_id
    WHERE f.flat_type = '3 ROOM'
),
top_towns AS (
    SELECT town_name, ROUND(AVG(floor_area_sqm), 2) AS avg_floor_area_sqm
    FROM three_room
    GROUP BY town_name
    ORDER BY avg_floor_area_sqm DESC, town_name
    LIMIT 10
)
SELECT tt.town_name,
       tt.avg_floor_area_sqm,
       r.sale_year,
       MAX(r.resale_price) AS max_resale_price
FROM top_towns tt
JOIN three_room r ON r.town_name = tt.town_name
GROUP BY tt.town_name, tt.avg_floor_area_sqm, r.sale_year
ORDER BY tt.avg_floor_area_sqm DESC, tt.town_name, r.sale_year;


-- @Q4
-- Hawker centre proximity effect: average resale price of flats whose nearest
-- hawker centre is in the closest class (level 1, < 800 m walking) vs the
-- furthest class (level 3, 1,600-2,400 m), per town and flat type.
-- Only (town, flat type) groups with sales in both classes are returned.
WITH nearest AS (
    SELECT building_id, MIN(distance_m) AS nearest_m
    FROM housing.proximity
    GROUP BY building_id
),
sale AS (
    SELECT t.town_name, f.flat_type, l.level_id, rt.resale_price
    FROM housing.resale_transaction rt
    JOIN housing.hdb_flat        f ON f.flat_id     = rt.flat_id
    JOIN housing.hdb_building    b ON b.building_id = f.building_id
    JOIN housing.town            t ON t.town_id     = b.town_id
    JOIN nearest                 n ON n.building_id = b.building_id
    JOIN housing.proximity_level l ON n.nearest_m >= l.min_dist_m AND n.nearest_m < l.max_dist_m
),
by_class AS (
    SELECT town_name, flat_type,
           AVG(resale_price) FILTER (WHERE level_id = 1) AS avg_near,
           AVG(resale_price) FILTER (WHERE level_id = 3) AS avg_far
    FROM sale
    GROUP BY town_name, flat_type
)
SELECT town_name                                    AS town,
       flat_type,
       ROUND(avg_near, 2)                           AS avg_price_near_hawker,
       ROUND(avg_far, 2)                            AS avg_price_far_hawker,
       ROUND((avg_near - avg_far) * 100 / avg_far, 2) AS price_diff_percentage
FROM by_class
WHERE avg_near IS NOT NULL
  AND avg_far  IS NOT NULL
ORDER BY town, flat_type;


-- @Q5
-- Town-level price near fresh-market hawkers: for flats near a hawker centre
-- with market produce stalls, the average resale price per proximity class of
-- the nearest such centre. Only towns whose overall average price for these
-- flats exceeds the budget of SGD 450,000 are returned. The budget was chosen
-- so the result is neither empty nor all towns at every database size (1-5).
WITH nearest_market AS (
    SELECT p.building_id, MIN(p.distance_m) AS nearest_m
    FROM housing.proximity p
    JOIN housing.hawker_centre h ON h.hawker_id = p.hawker_id
    WHERE h.market_produce_stalls > 0
    GROUP BY p.building_id
),
sale AS (
    SELECT t.town_name, l.level_id, l.label AS proximity_class, rt.resale_price
    FROM nearest_market nm
    JOIN housing.proximity_level    l  ON nm.nearest_m >= l.min_dist_m AND nm.nearest_m < l.max_dist_m
    JOIN housing.hdb_building       b  ON b.building_id = nm.building_id
    JOIN housing.town               t  ON t.town_id     = b.town_id
    JOIN housing.hdb_flat           f  ON f.building_id = b.building_id
    JOIN housing.resale_transaction rt ON rt.flat_id    = f.flat_id
),
towns_over_budget AS (
    SELECT town_name
    FROM sale
    GROUP BY town_name
    HAVING AVG(resale_price) > 450000
)
SELECT s.town_name                  AS town,
       s.proximity_class,
       ROUND(AVG(s.resale_price), 2) AS avg_resale_price,
       COUNT(*)                     AS transactions
FROM sale s
JOIN towns_over_budget o ON o.town_name = s.town_name
GROUP BY s.town_name, s.level_id, s.proximity_class
ORDER BY town, s.level_id;


-- @Q6
-- Own query, joins all 7 tables: does the TYPE of the nearest hawker centre
-- matter? For 4-room flats sold 2022-2024, the average price per m2 by the
-- proximity class and type of the nearest centre (HC = hawker centre,
-- MHC = market & hawker centre, MK = market; UNKNOWN = not in the NEA list).
WITH nearest AS (
    SELECT DISTINCT ON (building_id) building_id, hawker_id, distance_m
    FROM housing.proximity
    ORDER BY building_id, distance_m, hawker_id
)
SELECT l.label                                           AS proximity_class,
       COALESCE(h.centre_type, 'UNKNOWN')                AS nearest_centre_type,
       COUNT(DISTINCT t.town_id)                         AS towns,
       COUNT(*)                                          AS transactions,
       ROUND(AVG(rt.resale_price / f.floor_area_sqm), 2) AS avg_price_per_sqm
FROM housing.resale_transaction rt
JOIN housing.hdb_flat        f ON f.flat_id     = rt.flat_id
JOIN housing.hdb_building    b ON b.building_id = f.building_id
JOIN housing.town            t ON t.town_id     = b.town_id
JOIN nearest                 n ON n.building_id = b.building_id
JOIN housing.hawker_centre   h ON h.hawker_id   = n.hawker_id
JOIN housing.proximity_level l ON n.distance_m >= l.min_dist_m AND n.distance_m < l.max_dist_m
WHERE f.flat_type = '4 ROOM'
  AND rt.transaction_month >= DATE '2022-01-01'
  AND rt.transaction_month <  DATE '2025-01-01'
GROUP BY l.level_id, l.label, COALESCE(h.centre_type, 'UNKNOWN')
ORDER BY l.level_id, nearest_centre_type;

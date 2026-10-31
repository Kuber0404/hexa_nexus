-- =============================================================================
-- Task 4: indexes for the housing schema (final set)
--
-- Run AFTER the schema is created and the data is loaded (step 5, all five
-- resale files), in any SQL tool connected to the database:
--     psql -d <your_db> -f "Task 4/indexes.sql"
--
-- Nine candidate indexes were evaluated one at a time on the largest database
-- (see the report). Only one is kept; the other eight are not created.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Index 1: resale_transaction(transaction_month)
--
-- Why: Q1 and Q6 keep only the sales of 2022-2024 (about 8% of the 987,686 rows).
-- Without an index PostgreSQL reads every row and discards 92% of them.
--
-- Measured effect (5 runs each, same database, final protocol):
--   Q1  20.9 ms -> 14.6 ms   (-30%, plan changed to a bitmap index scan)
--   Q6  31.8 ms -> 34.9 ms   (+10%, index used, slightly slower)
--   Q2-Q5: plan unchanged (they read most or all sales), no effect.
--
-- Why a plain B-tree:
--   * It does not depend on how the rows are stored. A BRIN index only skips
--     table pages when the dates follow the physical order of the table, which here comes
--     from the order the CSV files were loaded and is not guaranteed by the
--     schema. A B-tree keeps its benefit if the table is reloaded, updated or
--     reordered, and it also supports exact-date lookups and ORDER BY.
--   * On the query it was built for it performed similarly to the alternatives:
--     Q1 improved by about 30% with the B-tree, and by a similar amount with
--     BRIN and with the covering B-tree.
--   * The covering variant gave only a marginal extra gain (about 1 ms on Q1) at four times the size
--     (29.7 MB vs 6.7 MB).
--   * Trade-off accepted: BRIN was smaller (0.02 MB) and also improved Q6 in
--     the screening, while the B-tree makes Q6 about 3 ms slower. The B-tree
--     was chosen for robustness, not for being the fastest option measured.
-- 
-- 
-- 
-- Not created (tested, rejected): indexes on resale_transaction(flat_id) made
-- Q6 much slower; indexes on hdb_flat(flat_type), hdb_building(town_id),
-- proximity(hawker_id) and proximity(building_id, distance_m, hawker_id) had no
-- measurable effect and would only cost space and slow inserts.
-- -----------------------------------------------------------------------------
CREATE INDEX idx_resale_transaction_month
    ON housing.resale_transaction (transaction_month);

-- Refresh planner statistics so the new index is costed correctly.
ANALYZE housing.resale_transaction;


-- -----------------------------------------------------------------------------
-- To go back to the "no index" state (used by the Task 4 notebook between runs):
--     DROP INDEX IF EXISTS housing.idx_resale_transaction_month;
-- -----------------------------------------------------------------------------
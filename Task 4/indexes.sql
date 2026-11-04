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
-- Measured effect (5 timed runs each after 1 warm-up, same database, Part C of
-- the Task 4 notebook; source: results/task4_summary.csv):
--   Q1  21.56 ms -> 14.93 ms   (-30.8%, 1.44x; plan changed to a bitmap index scan)
--   Q6  32.62 ms -> 34.61 ms   (+6.1%, index used; within the project's noise rule)
--   Q2-Q5: plan unchanged (they read most or all sales), no effect under that rule.
--
-- Why a plain B-tree:
--   * It does not depend on how the rows are stored. A BRIN index only skips
--     table pages when the dates follow the physical order of the table, which here comes
--     from the order the CSV files were loaded and is not guaranteed by the
--     schema. A B-tree keeps its benefit if the table is reloaded, updated or
--     reordered, and it also supports exact-date lookups and ORDER BY.
--   * On the query it was built for it performed similarly to the alternatives
--     in the screening archive: Q1 improved under the noticeability rule with
--     the B-tree, BRIN and the covering B-tree.
--   * The covering variant gave only a marginal extra gain (about 0.85 ms on Q1)
--     at four times the size (29.7 MB vs 6.7 MB).
--   * Trade-off accepted: BRIN was smaller (0.02 MB) and looked strong on Q6 in
--     the screening archive against a drifted pooled baseline, while the B-tree's
--     final Q6 change is +6.1% (within the noise rule). The B-tree was chosen for
--     robustness, not for being the fastest option measured in every experiment.
--
-- Not created (tested, rejected): indexes on resale_transaction(flat_id) made
-- Q6 much slower; indexes on hdb_flat(flat_type), hdb_building(town_id),
-- proximity(hawker_id) and proximity(building_id, distance_m, hawker_id) had no
-- noticeable effect under the project's rule and would only cost space and slow inserts.
-- -----------------------------------------------------------------------------
CREATE INDEX idx_resale_transaction_month
    ON housing.resale_transaction (transaction_month);

-- Refresh planner statistics so the new index is costed correctly.
ANALYZE housing.resale_transaction;


-- -----------------------------------------------------------------------------
-- To go back to the "no index" state (used by the Task 4 notebook between runs):
--     DROP INDEX IF EXISTS housing.idx_resale_transaction_month;
-- -----------------------------------------------------------------------------

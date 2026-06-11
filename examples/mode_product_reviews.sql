/*
  Mode: unimodal, bimodal, and no-mode distributions
  Function: STATS_MODE returns JSON {"values": [...], "min": x, "max": y}

  STATS_MODE accumulates frequency counts and returns all values that share
  the highest frequency (i.e. all modes, not just one):
    values — sorted array of every mode value
    min    — smallest mode (first element of values)
    max    — largest mode  (last element of values)

  Returns NULL when no value appears more than once (all values are unique).

  Context: customer star ratings (1–5) for three products on an e-commerce platform.

    Product A — Unimodal: well-liked product, most customers rate it 4 stars.
      Ratings: 2,3,3,4,4,4,4,4,5,5  →  mode = {4}  (appears 5 times)

    Product B — Bimodal: divisive product, customers either love it or hate it.
      Ratings: 1,1,1,2,3,4,5,5,5,3  →  modes = {1, 5}  (each appears 3 times)

    Product C — No mode (NULL): mixed reviews, each rating appears exactly once.
      Ratings: 1,2,3,4,5            →  NULL (no value repeated)
*/

INSTALL EXTENSION vsql_statistics;

DROP TABLE IF EXISTS product_reviews;

CREATE TABLE product_reviews (
    product CHAR(1) NOT NULL,   -- 'A', 'B', or 'C'
    rating  DOUBLE  NOT NULL    -- star rating 1–5
);

-- Product A: popular — rating 4 dominates
INSERT INTO product_reviews VALUES
    ('A', 2), ('A', 3), ('A', 3), ('A', 4), ('A', 4),
    ('A', 4), ('A', 4), ('A', 4), ('A', 5), ('A', 5);

-- Product B: polarising — 1-star and 5-star equally frequent
INSERT INTO product_reviews VALUES
    ('B', 1), ('B', 1), ('B', 1), ('B', 2), ('B', 3),
    ('B', 3), ('B', 4), ('B', 5), ('B', 5), ('B', 5);

-- Product C: no repeated rating — STATS_MODE returns NULL
INSERT INTO product_reviews VALUES
    ('C', 1), ('C', 2), ('C', 3), ('C', 4), ('C', 5);

-- ============================================================================
-- Mode results per product
-- ============================================================================

WITH mode_data AS (
    SELECT
        product,
        COUNT(*)                                   AS n,
        ROUND(AVG(rating), 2)                      AS mean_rating,
        CAST(STATS_MODE(rating) AS CHAR(200))      AS json
    FROM product_reviews
    GROUP BY product
)
SELECT
    product,
    n,
    mean_rating,
    JSON_EXTRACT(json, '$.values')                 AS mode_values,
    JSON_EXTRACT(json, '$.min')                    AS mode_min,
    JSON_EXTRACT(json, '$.max')                    AS mode_max,
    JSON_LENGTH(JSON_EXTRACT(json, '$.values'))    AS mode_count,
    CASE
        WHEN json IS NULL                                        THEN 'No mode — all ratings equally rare'
        WHEN JSON_LENGTH(JSON_EXTRACT(json, '$.values')) = 1    THEN 'Unimodal — one dominant rating'
        WHEN JSON_LENGTH(JSON_EXTRACT(json, '$.values')) = 2    THEN 'Bimodal  — two equally frequent ratings'
        ELSE                                                          'Multimodal — multiple dominant ratings'
    END                                            AS distribution_shape
FROM mode_data
ORDER BY product;

DROP TABLE product_reviews;

UNINSTALL EXTENSION vsql_statistics;

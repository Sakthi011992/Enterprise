-- Table positions are cells on the floor setup grid (12 columns x 8 rows). The demo seed stored
-- pixels (bar seats 60 px apart, tables 140 px apart), which put most tables off the grid.
-- Convert any position outside the grid to cells (60 px per cell keeps the seeded tables apart).
UPDATE "dining_tables"
SET "posX" = LEAST(11, GREATEST(0, ROUND("posX" / 60.0)::int)),
    "posY" = LEAST(7, GREATEST(0, ROUND("posY" / 60.0)::int))
WHERE "posX" > 11 OR "posY" > 7 OR "posX" < 0 OR "posY" < 0;

-- Theme token contract v2: a header background and its text colour.
-- Existing themes keep the look they had: the header uses the card colour and the main text colour.
UPDATE "themes"
SET "tokens" = jsonb_set(
      jsonb_set(
        jsonb_set(
          jsonb_set(
            "tokens"::jsonb,
            '{modes,light,color,background,header}', "tokens"::jsonb #> '{modes,light,color,background,surface}'),
          '{modes,light,color,content,onHeader}', "tokens"::jsonb #> '{modes,light,color,content,primary}'),
        '{modes,dark,color,background,header}', "tokens"::jsonb #> '{modes,dark,color,background,surface}'),
      '{modes,dark,color,content,onHeader}', "tokens"::jsonb #> '{modes,dark,color,content,primary}'
    ) || '{"schemaVersion":2}'::jsonb,
    "schemaVersion" = 2
WHERE "schemaVersion" = 1;

ALTER TABLE "themes" ALTER COLUMN "schemaVersion" SET DEFAULT 2;

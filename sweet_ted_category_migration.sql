-- Sweet Ted Cafe — Coffee/Pastry category migration
-- Adds a `category` column to `batches` and a `category_type` column to `ingredients`
-- so items can be organized into Coffee vs Pastry across all admin pages and the POS.
--
-- Run this once in your Supabase SQL Editor.

-- 1) Batches: which product family does this batch belong to?
ALTER TABLE batches
  ADD COLUMN IF NOT EXISTS category text DEFAULT 'pastry';

-- Backfill existing batches based on their template name.
UPDATE batches
SET category = CASE
  WHEN name ILIKE '%espresso%'   THEN 'coffee'
  WHEN name ILIKE '%latte%'      THEN 'coffee'
  WHEN name ILIKE '%americano%'  THEN 'coffee'
  WHEN name ILIKE '%cappuccino%' THEN 'coffee'
  WHEN name ILIKE '%mocha%'      THEN 'coffee'
  WHEN name ILIKE '%coffee%'     THEN 'coffee'
  ELSE 'pastry'
END
WHERE category IS NULL OR category = 'pastry';

-- Optional: enforce only valid values
ALTER TABLE batches
  DROP CONSTRAINT IF EXISTS batches_category_check;
ALTER TABLE batches
  ADD CONSTRAINT batches_category_check CHECK (category IN ('coffee','pastry'));

-- 2) Ingredients: tag each ingredient as Coffee or Pastry stock
ALTER TABLE ingredients
  ADD COLUMN IF NOT EXISTS category_type text DEFAULT 'pastry';

UPDATE ingredients
SET category_type = CASE
  WHEN name ILIKE '%coffee%'  THEN 'coffee'
  WHEN name ILIKE '%bean%'    THEN 'coffee'
  WHEN name ILIKE '%espresso%' THEN 'coffee'
  WHEN name ILIKE '%milk%'    THEN 'coffee'
  WHEN name ILIKE '%syrup%'   THEN 'coffee'
  WHEN name ILIKE '%cream%'   THEN 'coffee'
  ELSE 'pastry'
END
WHERE category_type IS NULL OR category_type = 'pastry';

ALTER TABLE ingredients
  DROP CONSTRAINT IF EXISTS ingredients_category_type_check;
ALTER TABLE ingredients
  ADD CONSTRAINT ingredients_category_type_check CHECK (category_type IN ('coffee','pastry'));

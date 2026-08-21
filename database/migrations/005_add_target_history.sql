ALTER TABLE user_profiles
  ADD COLUMN IF NOT EXISTS nutrition_target_effective_from DATE NOT NULL DEFAULT DATE '1970-01-01';

CREATE TABLE IF NOT EXISTS nutrition_target_history (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  effective_from DATE NOT NULL,
  calories_kcal NUMERIC(8,2) NOT NULL,
  carbohydrates_g NUMERIC(8,2) NOT NULL,
  protein_g NUMERIC(8,2) NOT NULL,
  fat_g NUMERIC(8,2) NOT NULL,
  keep_custom_nutrition_targets BOOLEAN NOT NULL DEFAULT FALSE,
  UNIQUE (user_id, effective_from)
);
CREATE INDEX IF NOT EXISTS nutrition_target_history_lookup
  ON nutrition_target_history (user_id, effective_from DESC);
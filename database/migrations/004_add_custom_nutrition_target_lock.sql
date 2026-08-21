ALTER TABLE user_profiles
  ADD COLUMN IF NOT EXISTS keep_custom_nutrition_targets BOOLEAN NOT NULL DEFAULT FALSE;

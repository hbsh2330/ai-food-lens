-- Food Lens PostgreSQL schema
-- Login providers will populate users.provider / users.provider_subject later.
CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE IF NOT EXISTS users (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  provider VARCHAR(20),
  provider_subject VARCHAR(255),
  display_name VARCHAR(80),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (provider, provider_subject)
);

-- Until Google/Kakao login is added, the app can use one local/guest user row.
CREATE TABLE IF NOT EXISTS user_profiles (
  user_id UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  height_cm NUMERIC(6,2),
  weight_kg NUMERIC(6,2),
  target_weight_kg NUMERIC(6,2),
  age SMALLINT CHECK (age BETWEEN 19 AND 80),
  biological_sex VARCHAR(10) CHECK (biological_sex IN ('male', 'female')) ,
  activity_level VARCHAR(20) CHECK (activity_level IN ('low', 'light', 'moderate', 'high', 'very_high')) ,
  goal_type VARCHAR(10) CHECK (goal_type IN ('loss', 'gain', 'maintain')),
  keep_custom_nutrition_targets BOOLEAN NOT NULL DEFAULT FALSE,
  nutrition_target_effective_from DATE NOT NULL DEFAULT DATE '1970-01-01',
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS nutrition_targets (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  target_date DATE,
  calories_kcal NUMERIC(8,2) NOT NULL,
  carbohydrates_g NUMERIC(8,2) NOT NULL,
  protein_g NUMERIC(8,2) NOT NULL,
  fat_g NUMERIC(8,2) NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE NULLS NOT DISTINCT (user_id, target_date)
);

-- Previous global nutrition targets are kept so historical dates remain unchanged.
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
-- Catalog foods are imported from the verified nutrition Excel file.
-- User foods will later be shared after Google/Kakao login; use_count supports popularity sorting.
CREATE TABLE IF NOT EXISTS foods (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_user_id UUID REFERENCES users(id) ON DELETE SET NULL,
  source VARCHAR(20) NOT NULL CHECK (source IN ('catalog', 'user')),
  food_code VARCHAR(30),
  name VARCHAR(160) NOT NULL,
  serving_grams NUMERIC(9,2) NOT NULL,
  calories_kcal NUMERIC(9,2) NOT NULL,
  carbohydrate_g NUMERIC(9,2) NOT NULL DEFAULT 0,
  protein_g NUMERIC(9,2) NOT NULL,
  fat_g NUMERIC(9,2) NOT NULL,
  sodium_mg NUMERIC(9,2) NOT NULL,
  image_url TEXT,
  use_count INTEGER NOT NULL DEFAULT 0 CHECK (use_count >= 0),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE UNIQUE INDEX IF NOT EXISTS foods_catalog_name_serving_unique ON foods (name, serving_grams) WHERE source = 'catalog';
CREATE INDEX IF NOT EXISTS foods_search_order ON foods (name, source, use_count DESC);

CREATE TABLE IF NOT EXISTS meals (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  meal_date DATE NOT NULL,
  meal_type VARCHAR(12) NOT NULL CHECK (meal_type IN ('breakfast', 'lunch', 'dinner')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS meals_user_date ON meals (user_id, meal_date);

-- Snapshot fields preserve nutrition values even if the original food entry changes later.
CREATE TABLE IF NOT EXISTS meal_foods (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  meal_id UUID NOT NULL REFERENCES meals(id) ON DELETE CASCADE,
  food_id UUID REFERENCES foods(id) ON DELETE SET NULL,
  food_code VARCHAR(30),
  food_name VARCHAR(160) NOT NULL,
  source VARCHAR(20) NOT NULL CHECK (source IN ('ai', 'catalog', 'user')),
  image_url TEXT,
  ai_confidence NUMERIC(6,5),
  serving_grams NUMERIC(9,2),
  serving_unit VARCHAR(12) NOT NULL DEFAULT 'grams',
  serving_count NUMERIC(6,2),
  calories_kcal NUMERIC(9,2) NOT NULL,
  carbohydrate_g NUMERIC(9,2) NOT NULL DEFAULT 0,
  protein_g NUMERIC(9,2) NOT NULL,
  fat_g NUMERIC(9,2) NOT NULL,
  sodium_mg NUMERIC(9,2) NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS meal_foods_meal_id ON meal_foods (meal_id);

CREATE TABLE IF NOT EXISTS weight_records (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  recorded_month DATE NOT NULL,
  weight_kg NUMERIC(6,2) NOT NULL CHECK (weight_kg > 0),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (user_id, recorded_month)
);
CREATE INDEX IF NOT EXISTS weight_records_user_month ON weight_records (user_id, recorded_month DESC);

CREATE OR REPLACE FUNCTION set_updated_at() RETURNS TRIGGER AS $$
BEGIN NEW.updated_at = NOW(); RETURN NEW; END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS users_updated_at ON users;
CREATE TRIGGER users_updated_at BEFORE UPDATE ON users FOR EACH ROW EXECUTE FUNCTION set_updated_at();
DROP TRIGGER IF EXISTS profiles_updated_at ON user_profiles;
CREATE TRIGGER profiles_updated_at BEFORE UPDATE ON user_profiles FOR EACH ROW EXECUTE FUNCTION set_updated_at();
DROP TRIGGER IF EXISTS targets_updated_at ON nutrition_targets;
CREATE TRIGGER targets_updated_at BEFORE UPDATE ON nutrition_targets FOR EACH ROW EXECUTE FUNCTION set_updated_at();
DROP TRIGGER IF EXISTS foods_updated_at ON foods;
CREATE TRIGGER foods_updated_at BEFORE UPDATE ON foods FOR EACH ROW EXECUTE FUNCTION set_updated_at();
DROP TRIGGER IF EXISTS meals_updated_at ON meals;
CREATE TRIGGER meals_updated_at BEFORE UPDATE ON meals FOR EACH ROW EXECUTE FUNCTION set_updated_at();


-- Existing local databases need these columns as well as new installations.
ALTER TABLE user_profiles ADD COLUMN IF NOT EXISTS age SMALLINT;
ALTER TABLE user_profiles ADD COLUMN IF NOT EXISTS biological_sex VARCHAR(10);
ALTER TABLE user_profiles ADD COLUMN IF NOT EXISTS activity_level VARCHAR(20);
ALTER TABLE user_profiles ADD COLUMN IF NOT EXISTS goal_type VARCHAR(10);
-- Target-lock and effective-date fields were added after initial DB creation.
-- IF NOT EXISTS keeps this upgrade safe for both old and new local databases.
ALTER TABLE user_profiles ADD COLUMN IF NOT EXISTS keep_custom_nutrition_targets BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE user_profiles ADD COLUMN IF NOT EXISTS nutrition_target_effective_from DATE NOT NULL DEFAULT DATE '1970-01-01';

-- Carbohydrates were added after the first local database version; keep upgrades safe.
ALTER TABLE foods ADD COLUMN IF NOT EXISTS carbohydrate_g NUMERIC(9,2) NOT NULL DEFAULT 0;
ALTER TABLE meal_foods ADD COLUMN IF NOT EXISTS carbohydrate_g NUMERIC(9,2) NOT NULL DEFAULT 0;
ALTER TABLE meal_foods ADD COLUMN IF NOT EXISTS serving_unit VARCHAR(12) NOT NULL DEFAULT 'grams';
ALTER TABLE meal_foods ADD COLUMN IF NOT EXISTS serving_count NUMERIC(6,2);

ALTER TABLE foods ADD COLUMN IF NOT EXISTS image_url TEXT;

ALTER TABLE user_profiles DROP CONSTRAINT IF EXISTS user_profiles_goal_type_check;
ALTER TABLE user_profiles ADD CONSTRAINT user_profiles_goal_type_check CHECK (goal_type IS NULL OR goal_type IN ('loss', 'gain', 'maintain'));

-- Images that the AI could not identify are retained separately for model improvement.
CREATE TABLE IF NOT EXISTS ai_recognition_feedback (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  image_url TEXT NOT NULL,
  original_filename TEXT,
  failure_reason VARCHAR(30) NOT NULL
    CHECK (failure_reason IN ('no_detection', 'invalid_food_code', 'incorrect_prediction')),
  predicted_food_code VARCHAR(30),
  predicted_food_name VARCHAR(160),
  predicted_confidence NUMERIC(6,5),
  candidates JSONB NOT NULL DEFAULT '[]'::jsonb,
  model_version VARCHAR(100) NOT NULL,
  feedback_type VARCHAR(20) NOT NULL DEFAULT 'unrecognized'
    CHECK (feedback_type IN ('unrecognized', 'incorrect')),
  corrected_food_id UUID REFERENCES foods(id) ON DELETE SET NULL,
  corrected_food_name VARCHAR(160),
  corrected_food_code VARCHAR(30),
  review_status VARCHAR(20) NOT NULL DEFAULT 'pending'
    CHECK (review_status IN ('pending', 'approved', 'rejected')),
  annotation_status VARCHAR(20) NOT NULL DEFAULT 'none'
    CHECK (annotation_status IN ('none', 'needed', 'completed')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  reviewed_at TIMESTAMPTZ
);
CREATE INDEX IF NOT EXISTS ai_recognition_feedback_user_created
  ON ai_recognition_feedback (user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS ai_recognition_feedback_review_status
  ON ai_recognition_feedback (review_status, created_at DESC);
-- AI feedback columns were added after the first feedback-table version.
ALTER TABLE ai_recognition_feedback DROP CONSTRAINT IF EXISTS ai_recognition_feedback_failure_reason_check;
ALTER TABLE ai_recognition_feedback ADD CONSTRAINT ai_recognition_feedback_failure_reason_check
  CHECK (failure_reason IN ('no_detection', 'invalid_food_code', 'incorrect_prediction'));
ALTER TABLE ai_recognition_feedback ADD COLUMN IF NOT EXISTS feedback_type VARCHAR(20) NOT NULL DEFAULT 'unrecognized';
ALTER TABLE ai_recognition_feedback DROP CONSTRAINT IF EXISTS ai_recognition_feedback_feedback_type_check;
ALTER TABLE ai_recognition_feedback ADD CONSTRAINT ai_recognition_feedback_feedback_type_check
  CHECK (feedback_type IN ('unrecognized', 'incorrect'));
ALTER TABLE ai_recognition_feedback ADD COLUMN IF NOT EXISTS corrected_food_id UUID REFERENCES foods(id) ON DELETE SET NULL;
ALTER TABLE ai_recognition_feedback ADD COLUMN IF NOT EXISTS corrected_food_name VARCHAR(160);
ALTER TABLE ai_recognition_feedback ADD COLUMN IF NOT EXISTS corrected_food_code VARCHAR(30);
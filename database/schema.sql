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
  protein_g NUMERIC(9,2) NOT NULL,
  fat_g NUMERIC(9,2) NOT NULL,
  sodium_mg NUMERIC(9,2) NOT NULL,
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
  calories_kcal NUMERIC(9,2) NOT NULL,
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

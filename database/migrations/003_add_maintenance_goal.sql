ALTER TABLE user_profiles DROP CONSTRAINT IF EXISTS user_profiles_goal_type_check;
ALTER TABLE user_profiles ADD CONSTRAINT user_profiles_goal_type_check CHECK (goal_type IS NULL OR goal_type IN ('loss', 'gain', 'maintain'));

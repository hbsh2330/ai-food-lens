import os
from pathlib import Path
import psycopg
from dotenv import load_dotenv
load_dotenv(Path('.env'))
with psycopg.connect(os.environ['DATABASE_URL']) as conn:
    with conn.cursor() as cur:
        for table in ('users', 'foods', 'user_profiles', 'nutrition_targets', 'meals', 'meal_foods', 'weight_records'):
            cur.execute(f'SELECT count(*) FROM {table}')
            print(f'{table}: {cur.fetchone()[0]}')

"""Create Food Lens tables and import the verified Excel food catalog into PostgreSQL."""
from __future__ import annotations

import os
from pathlib import Path

import openpyxl
import psycopg
from dotenv import load_dotenv

ROOT = Path(__file__).resolve().parents[1]
load_dotenv(ROOT / '.env')
DATABASE_URL = os.getenv('DATABASE_URL')
if not DATABASE_URL:
    raise SystemExit('DATABASE_URL is missing. Copy .env.example to .env and set the connection string.')

schema = (ROOT / 'database' / 'schema.sql').read_text(encoding='utf-8-sig')
excel_path = ROOT / 'food_images_and_nutrition_text' / 'calorie_dataset' / 'food_nutrition_db.xlsx'


def number(value: object) -> float:
    return float(value) if isinstance(value, (int, float)) else 0.0

with psycopg.connect(DATABASE_URL) as connection:
    with connection.cursor() as cursor:
        cursor.execute(schema)
        cursor.execute("INSERT INTO users (provider, provider_subject, display_name) VALUES ('guest', 'local-default', '임시 사용자') ON CONFLICT (provider, provider_subject) DO NOTHING")
        workbook = openpyxl.load_workbook(excel_path, read_only=True, data_only=True)
        worksheet = workbook.active
        count = 0
        for row in worksheet.iter_rows(min_row=2, values_only=True):
            name = str(row[0]).strip() if row[0] is not None else ''
            if not name:
                continue
            cursor.execute(
                '''INSERT INTO foods (source, name, serving_grams, calories_kcal, carbohydrate_g, protein_g, fat_g, sodium_mg)
                   VALUES ('catalog', %s, %s, %s, %s, %s, %s, %s)
                   ON CONFLICT (name, serving_grams) WHERE source = 'catalog' DO UPDATE
                   SET calories_kcal = EXCLUDED.calories_kcal, carbohydrate_g = EXCLUDED.carbohydrate_g, protein_g = EXCLUDED.protein_g,
                       fat_g = EXCLUDED.fat_g, sodium_mg = EXCLUDED.sodium_mg''',
                (name, number(row[1]), number(row[2]), number(row[3]), number(row[6]), number(row[5]), number(row[9])),
            )
            count += 1
    connection.commit()
print(f'Created schema and imported {count} catalog foods.')


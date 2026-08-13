"""Database CRUD routes for the temporary guest user."""
from __future__ import annotations
from datetime import date
from typing import Literal
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field
from .database import connect, guest_user_id

router = APIRouter(prefix='/data', tags=['app-data'])

class ProfileIn(BaseModel): height_cm: float | None = None; weight_kg: float | None = None; target_weight_kg: float | None = None
class TargetsIn(BaseModel): calories_kcal: float; carbohydrates_g: float; protein_g: float; fat_g: float; target_date: date | None = None
class FoodIn(BaseModel): name: str = Field(min_length=1); serving_grams: float; calories_kcal: float; protein_g: float; fat_g: float; sodium_mg: float
class MealFoodIn(BaseModel): food_id: str | None = None; food_code: str | None = None; food_name: str; source: Literal['ai','catalog','user']; image_url: str | None = None; ai_confidence: float | None = None; serving_grams: float | None = None; calories_kcal: float; protein_g: float; fat_g: float; sodium_mg: float
class MealIn(BaseModel): meal_date: date; meal_type: Literal['breakfast','lunch','dinner']; food: MealFoodIn
class WeightIn(BaseModel): recorded_month: date; weight_kg: float

def rows(query: str, params=()):
    with connect() as connection:
        user_id = guest_user_id(connection)
        with connection.cursor() as cursor:
            cursor.execute(query, (user_id, *params))
            result = cursor.fetchall()
        connection.commit()
    return result

@router.get('/profile')
def get_profile():
    result = rows('SELECT height_cm, weight_kg, target_weight_kg FROM user_profiles WHERE user_id = %s')
    return result[0] if result else {}

@router.put('/profile')
def put_profile(body: ProfileIn):
    with connect() as connection:
        user_id = guest_user_id(connection)
        with connection.cursor() as cursor:
            cursor.execute('''INSERT INTO user_profiles (user_id,height_cm,weight_kg,target_weight_kg) VALUES (%s,%s,%s,%s)
            ON CONFLICT (user_id) DO UPDATE SET height_cm=EXCLUDED.height_cm, weight_kg=EXCLUDED.weight_kg, target_weight_kg=EXCLUDED.target_weight_kg RETURNING *''', (user_id, body.height_cm, body.weight_kg, body.target_weight_kg))
            result=cursor.fetchone()
        connection.commit()
    return result

@router.get('/targets')
def get_targets(target_date: date | None = None):
    with connect() as connection:
        user_id = guest_user_id(connection)
        with connection.cursor() as cursor:
            cursor.execute('''SELECT calories_kcal,carbohydrates_g,protein_g,fat_g,target_date FROM nutrition_targets
            WHERE user_id=%s AND target_date IS NOT DISTINCT FROM %s''',(user_id,target_date))
            result=cursor.fetchone()
    return result or {}

@router.put('/targets')
def put_targets(body: TargetsIn):
    with connect() as connection:
        user_id=guest_user_id(connection)
        with connection.cursor() as cursor:
            cursor.execute('''INSERT INTO nutrition_targets (user_id,target_date,calories_kcal,carbohydrates_g,protein_g,fat_g)
            VALUES (%s,%s,%s,%s,%s,%s) ON CONFLICT (user_id,target_date) DO UPDATE SET calories_kcal=EXCLUDED.calories_kcal,carbohydrates_g=EXCLUDED.carbohydrates_g,protein_g=EXCLUDED.protein_g,fat_g=EXCLUDED.fat_g RETURNING *''',(user_id,body.target_date,body.calories_kcal,body.carbohydrates_g,body.protein_g,body.fat_g)); result=cursor.fetchone()
        connection.commit()
    return result
# 초성 한 글자(ㄱ, ㄴ 등)를 해당 한글 음절 범위로 변환합니다.
# 유니코드 한글 정렬은 가 → 갸 → 거 → 겨 → 고 순서를 유지합니다.
_HANGUL_INITIALS = 'ㄱㄲㄴㄷㄸㄹㅁㅂㅃㅅㅆㅇㅈㅉㅊㅋㅌㅍㅎ'
def _initial_range(query: str):
    if len(query) != 1 or query not in _HANGUL_INITIALS:
        return None
    offset = _HANGUL_INITIALS.index(query) * 588
    return chr(0xAC00 + offset), chr(0xAC00 + offset + 588)
@router.get('/foods')
def search_foods(q: str = '', mine_only: bool = False):
    with connect() as connection:
        user_id = guest_user_id(connection)
        with connection.cursor() as cursor:
            if not q.strip():
                # 처음 화면은 카탈로그가 아니라 사용자가 최근 식사에 넣은 음식만 보여줍니다.
                cursor.execute('''SELECT id,name,serving_grams,calories_kcal,protein_g,fat_g,sodium_mg,source,use_count,is_mine
                FROM (
                    SELECT DISTINCT ON (mf.food_name) mf.food_id AS id,mf.food_name AS name,mf.serving_grams,mf.calories_kcal,mf.protein_g,mf.fat_g,mf.sodium_mg,mf.source,0 AS use_count,false AS is_mine,mf.created_at AS last_used_at
                    FROM meal_foods mf JOIN meals m ON m.id=mf.meal_id WHERE m.user_id=%s
                    ORDER BY mf.food_name,mf.created_at DESC
                ) recent_foods ORDER BY last_used_at DESC LIMIT 20''',(user_id,))
            else:
                initial_range = _initial_range(q.strip())
                if initial_range:
                    cursor.execute('''SELECT id,name,serving_grams,calories_kcal,protein_g,fat_g,sodium_mg,source,use_count,
                    CASE WHEN owner_user_id=%s THEN true ELSE false END AS is_mine FROM foods
                    WHERE name >= %s AND name < %s AND (%s=false OR owner_user_id=%s)
                    ORDER BY CASE WHEN owner_user_id=%s THEN 0 ELSE 1 END, use_count DESC, name LIMIT 400''',
                    (user_id, initial_range[0], initial_range[1], mine_only, user_id, user_id))
                else:
                    cursor.execute('''SELECT id,name,serving_grams,calories_kcal,protein_g,fat_g,sodium_mg,source,use_count,
                    CASE WHEN owner_user_id=%s THEN true ELSE false END AS is_mine FROM foods
                    WHERE name ILIKE %s AND (%s=false OR owner_user_id=%s)
                    ORDER BY CASE WHEN lower(name)=lower(%s) THEN 0 ELSE 1 END, CASE WHEN owner_user_id=%s THEN 0 ELSE 1 END, use_count DESC, name LIMIT 400''', (user_id, f'%{q}%', mine_only, user_id, q, user_id))
            result=cursor.fetchall()
    return result
@router.post('/foods')
def create_food(body: FoodIn):
    with connect() as connection:
        user_id = guest_user_id(connection)
        with connection.cursor() as cursor:
            cursor.execute('''INSERT INTO foods (owner_user_id,source,name,serving_grams,calories_kcal,protein_g,fat_g,sodium_mg)
            VALUES (%s,'user',%s,%s,%s,%s,%s,%s) RETURNING *''', (user_id,body.name,body.serving_grams,body.calories_kcal,body.protein_g,body.fat_g,body.sodium_mg))
            result=cursor.fetchone()
        connection.commit()
    return result

@router.get('/meals')
def get_meals(from_date: date, to_date: date):
    return rows('''SELECT m.id AS meal_id,m.meal_date,m.meal_type,mf.* FROM meals m JOIN meal_foods mf ON mf.meal_id=m.id
                   WHERE m.user_id=%s AND m.meal_date BETWEEN %s AND %s ORDER BY m.meal_date,m.created_at,mf.created_at''', (from_date,to_date))

@router.post('/meals')
def add_meal_food(body: MealIn):
    with connect() as connection:
        user_id=guest_user_id(connection)
        with connection.cursor() as cursor:
            cursor.execute('INSERT INTO meals (user_id,meal_date,meal_type) VALUES (%s,%s,%s) RETURNING id', (user_id,body.meal_date,body.meal_type))
            meal_id=cursor.fetchone()['id']; food=body.food
            cursor.execute('''INSERT INTO meal_foods (meal_id,food_id,food_code,food_name,source,image_url,ai_confidence,serving_grams,calories_kcal,protein_g,fat_g,sodium_mg)
            VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s) RETURNING *''', (meal_id,food.food_id,food.food_code,food.food_name,food.source,food.image_url,food.ai_confidence,food.serving_grams,food.calories_kcal,food.protein_g,food.fat_g,food.sodium_mg))
            result=cursor.fetchone()
            if food.food_id: cursor.execute('UPDATE foods SET use_count=use_count+1 WHERE id=%s',(food.food_id,))
        connection.commit()
    return result

@router.delete('/meal-foods/{record_id}')
def delete_meal_food(record_id: str):
    with connect() as connection:
        user_id=guest_user_id(connection)
        with connection.cursor() as cursor:
            cursor.execute('''DELETE FROM meal_foods mf USING meals m WHERE mf.id=%s AND mf.meal_id=m.id AND m.user_id=%s RETURNING mf.id''',(record_id,user_id))
            result=cursor.fetchone()
        connection.commit()
    if not result: raise HTTPException(404,'식사 기록을 찾지 못했습니다.')
    return {'deleted': True}

@router.get('/weights')
def get_weights(): return rows('SELECT recorded_month,weight_kg FROM weight_records WHERE user_id=%s ORDER BY recorded_month DESC')

@router.put('/weights')
def put_weight(body: WeightIn):
    with connect() as connection:
        user_id=guest_user_id(connection)
        with connection.cursor() as cursor:
            cursor.execute('''INSERT INTO weight_records (user_id,recorded_month,weight_kg) VALUES (%s,%s,%s)
            ON CONFLICT (user_id,recorded_month) DO UPDATE SET weight_kg=EXCLUDED.weight_kg RETURNING *''',(user_id,body.recorded_month,body.weight_kg)); result=cursor.fetchone()
        connection.commit()
    return result





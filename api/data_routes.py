"""PostgreSQL CRUD routes scoped to the authenticated Food Lens user."""
from __future__ import annotations

import json

from datetime import date, timedelta
from pathlib import Path
from uuid import uuid4
from typing import Literal

from fastapi import APIRouter, Depends, File, Form, HTTPException, UploadFile
from pydantic import BaseModel, Field
from PIL import Image, UnidentifiedImageError
from io import BytesIO

from .auth import require_user_id
from .database import connect

router = APIRouter(prefix="/data", tags=["app-data"])

ROOT = Path(__file__).resolve().parents[1]
FOOD_IMAGE_DIR = ROOT / 'uploads' / 'food-images'
AI_FEEDBACK_DIR = ROOT / 'uploads' / 'ai-feedback'


class ProfileIn(BaseModel):
    height_cm: float | None = None
    weight_kg: float | None = None
    target_weight_kg: float | None = None
    age: int | None = Field(default=None, ge=19, le=80)
    biological_sex: Literal["male", "female"] | None = None
    activity_level: Literal["low", "light", "moderate", "high", "very_high"] | None = None
    goal_type: Literal["loss", "gain", "maintain"] | None = None


class ProfileSetupIn(BaseModel):
    height_cm: float = Field(gt=100, le=250)
    weight_kg: float = Field(gt=25, le=350)
    target_weight_kg: float = Field(gt=25, le=350)
    age: int = Field(ge=19, le=80)
    biological_sex: Literal["male", "female"]
    activity_level: Literal["low", "light", "moderate", "high", "very_high"]
    goal_type: Literal["loss", "gain", "maintain"]


class TargetsIn(BaseModel):
    calories_kcal: float
    carbohydrates_g: float
    protein_g: float
    fat_g: float
    target_date: date | None = None
    # Whole-range changes can begin at the date currently selected in the app.
    effective_from: date | None = None
    keep_custom_nutrition_targets: bool | None = None

class FoodIn(BaseModel):
    name: str = Field(min_length=1)
    serving_grams: float
    calories_kcal: float
    carbohydrate_g: float
    protein_g: float
    fat_g: float
    sodium_mg: float
    image_url: str | None = None


class MealFoodIn(BaseModel):
    food_id: str | None = None
    food_code: str | None = None
    food_name: str
    source: Literal["ai", "catalog", "user"]
    image_url: str | None = None
    ai_confidence: float | None = None
    serving_grams: float | None = None
    serving_unit: Literal["grams", "servings"] = "grams"
    serving_count: float | None = None
    calories_kcal: float
    carbohydrate_g: float
    protein_g: float
    fat_g: float
    sodium_mg: float


class MealFoodUpdateIn(BaseModel):
    food_name: str
    image_url: str | None = None
    serving_grams: float | None = None
    serving_unit: Literal["grams", "servings"] = "grams"
    serving_count: float | None = None
    calories_kcal: float
    carbohydrate_g: float
    protein_g: float
    fat_g: float
    sodium_mg: float

class AiFeedbackCorrectionIn(BaseModel):
    corrected_food_id: str | None = None
    corrected_food_name: str = Field(min_length=1)
    corrected_food_code: str | None = None


class MealIn(BaseModel):
    meal_date: date
    meal_type: Literal["breakfast", "lunch", "dinner"]
    food: MealFoodIn


class WeightIn(BaseModel):
    recorded_month: date
    weight_kg: float


def rows(user_id: str, query: str, params=()):
    with connect() as connection:
        with connection.cursor() as cursor:
            cursor.execute(query, (user_id, *params))
            result = cursor.fetchall()
    return result


def _snapshot_global_target(cursor, user_id: str, effective_from: date) -> None:
    """Keep the previous global target for dates before the next change."""
    today = date.today()
    if effective_from >= today:
        return
    cursor.execute("""SELECT t.calories_kcal, t.carbohydrates_g, t.protein_g, t.fat_g,
                             COALESCE(p.keep_custom_nutrition_targets, FALSE) AS keep_custom_nutrition_targets
                      FROM nutrition_targets t
                      LEFT JOIN user_profiles p ON p.user_id=t.user_id
                      WHERE t.user_id=%s AND t.target_date IS NULL""", (user_id,))
    current = cursor.fetchone()
    if current is None:
        return
    cursor.execute("""INSERT INTO nutrition_target_history
                      (user_id,effective_from,calories_kcal,carbohydrates_g,protein_g,fat_g,keep_custom_nutrition_targets)
                      VALUES (%s,%s,%s,%s,%s,%s,%s)
                      ON CONFLICT (user_id,effective_from) DO UPDATE SET
                        calories_kcal=EXCLUDED.calories_kcal,
                        carbohydrates_g=EXCLUDED.carbohydrates_g,
                        protein_g=EXCLUDED.protein_g,
                        fat_g=EXCLUDED.fat_g,
                        keep_custom_nutrition_targets=EXCLUDED.keep_custom_nutrition_targets""",
                   (user_id, effective_from, current["calories_kcal"], current["carbohydrates_g"],
                    current["protein_g"], current["fat_g"], current["keep_custom_nutrition_targets"]))


@router.get("/profile")
def get_profile(user_id: str = Depends(require_user_id)):
    result = rows(user_id, """SELECT height_cm, weight_kg, target_weight_kg, age,
                  biological_sex, activity_level, goal_type,
                  keep_custom_nutrition_targets, nutrition_target_effective_from
           FROM user_profiles WHERE user_id = %s""")
    return result[0] if result else {}


@router.put("/profile")
def put_profile(body: ProfileIn, user_id: str = Depends(require_user_id)):
    """Save body data and update unlocked targets from today onward."""
    with connect() as connection:
        with connection.cursor() as cursor:
            cursor.execute("""SELECT height_cm,weight_kg,target_weight_kg,age,
                              biological_sex,activity_level,goal_type,
                              keep_custom_nutrition_targets,nutrition_target_effective_from
                           FROM user_profiles WHERE user_id=%s""", (user_id,))
            existing = cursor.fetchone() or {}
            values = {
                "height_cm": body.height_cm if body.height_cm is not None else existing.get("height_cm"),
                "weight_kg": body.weight_kg if body.weight_kg is not None else existing.get("weight_kg"),
                "target_weight_kg": body.target_weight_kg if body.target_weight_kg is not None else existing.get("target_weight_kg"),
                "age": body.age if body.age is not None else existing.get("age"),
                "biological_sex": body.biological_sex if body.biological_sex is not None else existing.get("biological_sex"),
                "activity_level": body.activity_level if body.activity_level is not None else existing.get("activity_level"),
                "goal_type": body.goal_type if body.goal_type is not None else existing.get("goal_type"),
            }
            setup = ProfileSetupIn(**values)
            validate_goal(setup)
            calculated = recommended_targets(setup)
            fields = ("height_cm", "weight_kg", "target_weight_kg", "age", "biological_sex", "activity_level", "goal_type")
            profile_changed = any(values[name] != existing.get(name) for name in fields)
            locked = bool(existing.get("keep_custom_nutrition_targets"))
            cursor.execute("""INSERT INTO user_profiles
                     (user_id,height_cm,weight_kg,target_weight_kg,age,biological_sex,activity_level,goal_type)
                   VALUES (%s,%s,%s,%s,%s,%s,%s,%s)
                   ON CONFLICT (user_id) DO UPDATE SET
                     height_cm=EXCLUDED.height_cm, weight_kg=EXCLUDED.weight_kg,
                     target_weight_kg=EXCLUDED.target_weight_kg, age=EXCLUDED.age,
                     biological_sex=EXCLUDED.biological_sex, activity_level=EXCLUDED.activity_level,
                     goal_type=EXCLUDED.goal_type
                   RETURNING *""",
                (user_id, values["height_cm"], values["weight_kg"], values["target_weight_kg"],
                 values["age"], values["biological_sex"], values["activity_level"], values["goal_type"]))
            profile = cursor.fetchone()
            if profile_changed and not locked:
                _snapshot_global_target(cursor, user_id, existing.get("nutrition_target_effective_from", date(1970, 1, 1)))
                cursor.execute("UPDATE user_profiles SET nutrition_target_effective_from=%s WHERE user_id=%s",
                               (date.today(), user_id))
                cursor.execute("""INSERT INTO nutrition_targets
                         (user_id,target_date,calories_kcal,carbohydrates_g,protein_g,fat_g)
                       VALUES (%s,NULL,%s,%s,%s,%s)
                       ON CONFLICT (user_id,target_date) DO UPDATE SET
                         calories_kcal=EXCLUDED.calories_kcal,
                         carbohydrates_g=EXCLUDED.carbohydrates_g,
                         protein_g=EXCLUDED.protein_g,
                         fat_g=EXCLUDED.fat_g
                       RETURNING *""",
                    (user_id, calculated["calories_kcal"], calculated["carbohydrates_g"], calculated["protein_g"], calculated["fat_g"]))
                target_result = cursor.fetchone()
                # Profile edits are always effective from the real current date.
                _snapshot_global_target(cursor, user_id, date.today())
            else:
                cursor.execute("""SELECT calories_kcal, carbohydrates_g, protein_g, fat_g, target_date
                                  FROM nutrition_targets WHERE user_id=%s AND target_date IS NULL""", (user_id,))
                target_result = cursor.fetchone()
        connection.commit()
    return {"profile": profile, "targets": target_result}

def recommended_targets(body: ProfileSetupIn) -> dict[str, float]:
    """Return a conservative adult estimate; users can always edit it later."""
    sex_offset = 5 if body.biological_sex == "male" else -161
    # The target weight makes calorie, protein, fat, and carbohydrate goals move together.
    bmr = 10 * body.target_weight_kg + 6.25 * body.height_cm - 5 * body.age + sex_offset
    # Conservative activity adjustment: prevents large calorie jumps from a self-reported activity level.
    activity_factors = {"low": 1.20, "light": 1.30, "moderate": 1.40, "high": 1.50, "very_high": 1.60}
    maintenance = bmr * activity_factors[body.activity_level]
    adjustment = {"loss": -500, "gain": 300, "maintain": 0}[body.goal_type]
    calorie_floor = 1500 if body.biological_sex == "male" else 1200
    calories = max(maintenance + adjustment, calorie_floor)
    protein = body.target_weight_kg * 1.6
    fat = calories * 0.25 / 9
    carbs = max(50.0, (calories - protein * 4 - fat * 9) / 4)
    return {
        "calories_kcal": round(calories / 10) * 10,
        "protein_g": round(protein),
        "fat_g": round(fat),
        "carbohydrates_g": round(carbs),
    }


def validate_goal(body: ProfileSetupIn) -> None:
    """Block contradictory gain/loss goals; maintenance is always allowed."""
    if body.goal_type == "loss" and body.target_weight_kg >= body.weight_kg:
        raise HTTPException(status_code=422, detail="감량 목표는 현재 몸무게보다 낮아야 합니다. 유지 목표를 선택하면 현재·목표 체중과 관계없이 저장할 수 있습니다.")
    if body.goal_type == "gain" and body.target_weight_kg <= body.weight_kg:
        raise HTTPException(status_code=422, detail="증량 목표는 현재 몸무게보다 높아야 합니다. 유지 목표를 선택하면 현재·목표 체중과 관계없이 저장할 수 있습니다.")

@router.put("/profile/setup")
def setup_profile(body: ProfileSetupIn, user_id: str = Depends(require_user_id)):
    validate_goal(body)
    targets = recommended_targets(body)
    with connect() as connection:
        with connection.cursor() as cursor:
            cursor.execute("""INSERT INTO user_profiles
                     (user_id,height_cm,weight_kg,target_weight_kg,age,biological_sex,activity_level,goal_type,nutrition_target_effective_from)
                   VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s)
                   ON CONFLICT (user_id) DO UPDATE SET
                     height_cm=EXCLUDED.height_cm, weight_kg=EXCLUDED.weight_kg,
                     target_weight_kg=EXCLUDED.target_weight_kg, age=EXCLUDED.age,
                     biological_sex=EXCLUDED.biological_sex, activity_level=EXCLUDED.activity_level,
                     goal_type=EXCLUDED.goal_type
                   RETURNING *""",
                (user_id, body.height_cm, body.weight_kg, body.target_weight_kg,
                 body.age, body.biological_sex, body.activity_level, body.goal_type, date.today()))
            profile = cursor.fetchone()
            cursor.execute("""INSERT INTO nutrition_targets
                     (user_id,target_date,calories_kcal,carbohydrates_g,protein_g,fat_g)
                   VALUES (%s,NULL,%s,%s,%s,%s)
                   ON CONFLICT (user_id,target_date) DO UPDATE SET
                     calories_kcal=EXCLUDED.calories_kcal,
                     carbohydrates_g=EXCLUDED.carbohydrates_g,
                     protein_g=EXCLUDED.protein_g,
                     fat_g=EXCLUDED.fat_g
                   RETURNING *""",
                (user_id, targets["calories_kcal"], targets["carbohydrates_g"], targets["protein_g"], targets["fat_g"]))
            target_result = cursor.fetchone()
        connection.commit()
    return {"profile": profile, "targets": target_result}


@router.get("/targets")
def get_targets(target_date: date | None = None, user_id: str = Depends(require_user_id)):
    with connect() as connection:
        with connection.cursor() as cursor:
            if target_date is not None:
                cursor.execute("""SELECT calories_kcal, carbohydrates_g, protein_g, fat_g, target_date,
                                         FALSE AS keep_custom_nutrition_targets
                                  FROM nutrition_targets
                                  WHERE user_id=%s AND target_date=%s""", (user_id, target_date))
                day_target = cursor.fetchone()
                if day_target is not None:
                    return day_target
                if target_date < date.today():
                    cursor.execute("""SELECT calories_kcal, carbohydrates_g, protein_g, fat_g,
                                             NULL::date AS target_date, keep_custom_nutrition_targets
                                      FROM nutrition_target_history
                                      WHERE user_id=%s AND effective_from <= %s
                                      ORDER BY effective_from DESC LIMIT 1""", (user_id, target_date))
                    historical = cursor.fetchone()
                    if historical is not None:
                        return historical
            cursor.execute("""SELECT t.calories_kcal, t.carbohydrates_g, t.protein_g, t.fat_g, t.target_date,
                                     COALESCE(p.keep_custom_nutrition_targets, FALSE) AS keep_custom_nutrition_targets
                              FROM nutrition_targets t
                              LEFT JOIN user_profiles p ON p.user_id=t.user_id
                              WHERE t.user_id=%s AND t.target_date IS NULL""", (user_id,))
            current = cursor.fetchone()
        connection.commit()
    return current or {}

@router.put("/targets")
def put_targets(body: TargetsIn, user_id: str = Depends(require_user_id)):
    """Save a one-day override or a global target effective from a chosen date."""
    with connect() as connection:
        with connection.cursor() as cursor:
            is_global = body.target_date is None
            if is_global:
                # A whole-range edit starts on the calendar date chosen by the user.
                effective_from = body.effective_from or date.today()
                cursor.execute("""SELECT nutrition_target_effective_from, keep_custom_nutrition_targets
                                  FROM user_profiles WHERE user_id=%s""", (user_id,))
                profile_state = cursor.fetchone() or {}
                cursor.execute("""SELECT calories_kcal, carbohydrates_g, protein_g, fat_g,
                                         COALESCE(p.keep_custom_nutrition_targets, FALSE) AS keep_custom_nutrition_targets
                                  FROM nutrition_targets t
                                  LEFT JOIN user_profiles p ON p.user_id=t.user_id
                                  WHERE t.user_id=%s AND t.target_date IS NULL""", (user_id,))
                old = cursor.fetchone()
                values_changed = old is None or any(old[key] != value for key, value in {
                    "calories_kcal": body.calories_kcal,
                    "carbohydrates_g": body.carbohydrates_g,
                    "protein_g": body.protein_g,
                    "fat_g": body.fat_g,
                }.items()) or (body.keep_custom_nutrition_targets is not None and
                                bool(old["keep_custom_nutrition_targets"]) != body.keep_custom_nutrition_targets)
                if values_changed:
                    old_effective_from = profile_state.get(
                        "nutrition_target_effective_from", date(1970, 1, 1))
                    # Preserve the old goal only before the newly selected start date.
                    if old is not None and old_effective_from < effective_from:
                        _snapshot_global_target(cursor, user_id, old_effective_from)
                    # Editing 8/13, for example, intentionally replaces later target history too.
                    cursor.execute("DELETE FROM nutrition_target_history WHERE user_id=%s AND effective_from >= %s",
                                   (user_id, effective_from))
            cursor.execute("""INSERT INTO nutrition_targets
                (user_id,target_date,calories_kcal,carbohydrates_g,protein_g,fat_g)
                VALUES (%s,%s,%s,%s,%s,%s)
                ON CONFLICT (user_id,target_date) DO UPDATE SET
                  calories_kcal=EXCLUDED.calories_kcal,
                  carbohydrates_g=EXCLUDED.carbohydrates_g,
                  protein_g=EXCLUDED.protein_g,
                  fat_g=EXCLUDED.fat_g
                RETURNING *""", (user_id, body.target_date, body.calories_kcal,
                                   body.carbohydrates_g, body.protein_g, body.fat_g))
            result = cursor.fetchone()
            if is_global:
                if body.keep_custom_nutrition_targets is not None:
                    cursor.execute("UPDATE user_profiles SET keep_custom_nutrition_targets=%s WHERE user_id=%s",
                                   (body.keep_custom_nutrition_targets, user_id))
                if values_changed:
                    cursor.execute("UPDATE user_profiles SET nutrition_target_effective_from=%s WHERE user_id=%s",
                                   (effective_from, user_id))
                    # Store the newly saved goal at its selected effective date.
                    _snapshot_global_target(cursor, user_id, effective_from)
        connection.commit()
    return result
_HANGUL_INITIALS = "ㄱㄲㄴㄷㄸㄹㅁㅂㅃㅅㅆㅇㅈㅉㅊㅋㅌㅍㅎ"
def _initial_range(query: str):
    if len(query) != 1 or query not in _HANGUL_INITIALS:
        return None
    offset = _HANGUL_INITIALS.index(query) * 588
    return chr(0xAC00 + offset), chr(0xAC00 + offset + 588)


@router.get("/foods")
def search_foods(q: str = "", mine_only: bool = False, user_id: str = Depends(require_user_id)):
    with connect() as connection:
        with connection.cursor() as cursor:
            if not q.strip():
                return []
            initial_range = _initial_range(q.strip())
            if initial_range:
                cursor.execute("""SELECT id,name,serving_grams,calories_kcal,carbohydrate_g,protein_g,fat_g,sodium_mg,image_url,source,use_count,
                CASE WHEN owner_user_id=%s THEN true ELSE false END AS is_mine FROM foods
                WHERE name >= %s AND name < %s AND (%s=false OR owner_user_id=%s)
                ORDER BY CASE WHEN owner_user_id=%s THEN 0 ELSE 1 END, use_count DESC, name LIMIT 400""",
                (user_id, initial_range[0], initial_range[1], mine_only, user_id, user_id))
            else:
                cursor.execute("""SELECT id,name,serving_grams,calories_kcal,carbohydrate_g,protein_g,fat_g,sodium_mg,image_url,source,use_count,
                CASE WHEN owner_user_id=%s THEN true ELSE false END AS is_mine FROM foods
                WHERE name ILIKE %s AND (%s=false OR owner_user_id=%s)
                ORDER BY CASE WHEN lower(name)=lower(%s) THEN 0 ELSE 1 END, CASE WHEN owner_user_id=%s THEN 0 ELSE 1 END, use_count DESC, name LIMIT 400""",
                (user_id, f"%{q}%", mine_only, user_id, q, user_id))
            return cursor.fetchall()


@router.post("/food-images")
async def upload_food_image(file: UploadFile = File(...), user_id: str = Depends(require_user_id)):
    """Store a user-registered food image and return its app URL."""
    image_bytes = await file.read()
    if not image_bytes or len(image_bytes) > 5 * 1024 * 1024:
        raise HTTPException(400, "이미지는 5MB 이하로 등록해 주세요.")
    try:
        with Image.open(BytesIO(image_bytes)) as image:
            image.verify()
    except (UnidentifiedImageError, OSError):
        raise HTTPException(400, "이미지 파일만 등록할 수 있습니다.")
    suffix = Path(file.filename or "food.jpg").suffix.lower()
    if suffix not in {".jpg", ".jpeg", ".png", ".webp"}:
        suffix = ".jpg"
    FOOD_IMAGE_DIR.mkdir(parents=True, exist_ok=True)
    file_name = f"{user_id}_{uuid4().hex}{suffix}"
    (FOOD_IMAGE_DIR / file_name).write_bytes(image_bytes)
    return {"image_url": f"/uploads/food-images/{file_name}"}

@router.post("/ai-feedback")
async def create_incorrect_ai_feedback(
    file: UploadFile = File(...),
    predicted_food_code: str | None = Form(None),
    predicted_food_name: str | None = Form(None),
    predicted_confidence: float | None = Form(None),
    failure_reason: str = Form("incorrect_prediction"),
    feedback_type: str = Form("incorrect"),
    candidates_json: str = Form("[]"),
    user_id: str = Depends(require_user_id),
):
    """Save the original image when a user rejects an otherwise valid AI prediction."""
    if failure_reason not in {"no_detection", "invalid_food_code", "incorrect_prediction"}:
        raise HTTPException(400, "Invalid AI feedback failure reason.")
    if feedback_type not in {"unrecognized", "incorrect"}:
        raise HTTPException(400, "Invalid AI feedback type.")

    try:
        candidates = json.loads(candidates_json)
        if not isinstance(candidates, list):
            raise ValueError
    except (TypeError, ValueError, json.JSONDecodeError):
        raise HTTPException(400, "Candidates must be a JSON array.")
    image_bytes = await file.read()
    if not image_bytes or len(image_bytes) > 5 * 1024 * 1024:
        raise HTTPException(400, "Image must be between 1 byte and 5 MB.")
    try:
        with Image.open(BytesIO(image_bytes)) as image:
            image.verify()
    except (UnidentifiedImageError, OSError):
        raise HTTPException(400, "Only valid image files can be saved.")

    suffix = Path(file.filename or "feedback.jpg").suffix.lower()
    if suffix not in {".jpg", ".jpeg", ".png", ".webp"}:
        suffix = ".jpg"
    AI_FEEDBACK_DIR.mkdir(parents=True, exist_ok=True)
    file_name = f"{user_id}_{uuid4().hex}{suffix}"
    target = AI_FEEDBACK_DIR / file_name
    target.write_bytes(image_bytes)
    image_url = f"/uploads/ai-feedback/{file_name}"
    try:
        with connect() as connection:
            with connection.cursor() as cursor:
                cursor.execute(
                    """INSERT INTO ai_recognition_feedback
                       (user_id,image_url,original_filename,failure_reason,
                        predicted_food_code,predicted_food_name,predicted_confidence,
                        candidates,model_version,feedback_type)
                       VALUES (%s,%s,%s,%s,%s,%s,%s,%s::jsonb,
                               'yolov3-spp-403cls-best_403food_e200b150v2',%s)
                       RETURNING id""",
                    (user_id, image_url, file.filename, failure_reason, predicted_food_code,
                     predicted_food_name, predicted_confidence, json.dumps(candidates, ensure_ascii=False), feedback_type),
                )
                feedback_id = str(cursor.fetchone()["id"])
            connection.commit()
    except Exception:
        target.unlink(missing_ok=True)
        raise
    return {"id": feedback_id, "image_url": image_url}


@router.put("/ai-feedback/{feedback_id}/correction")
def complete_ai_feedback(
    feedback_id: str,
    body: AiFeedbackCorrectionIn,
    user_id: str = Depends(require_user_id),
):
    """Attach the food selected by the user as the correct answer for a failed AI image."""
    with connect() as connection:
        with connection.cursor() as cursor:
            cursor.execute(
                """UPDATE ai_recognition_feedback
                   SET corrected_food_id=%s, corrected_food_name=%s,
                       corrected_food_code=%s, annotation_status='needed'
                   WHERE id=%s AND user_id=%s
                   RETURNING id""",
                (body.corrected_food_id, body.corrected_food_name,
                 body.corrected_food_code, feedback_id, user_id),
            )
            result = cursor.fetchone()
        connection.commit()
    if result is None:
        raise HTTPException(404, "AI feedback record not found.")
    return {"id": str(result["id"]), "saved": True}


@router.post("/foods")
def create_food(body: FoodIn, user_id: str = Depends(require_user_id)):
    with connect() as connection:
        with connection.cursor() as cursor:
            cursor.execute("""INSERT INTO foods (owner_user_id,source,name,serving_grams,calories_kcal,carbohydrate_g,protein_g,fat_g,sodium_mg,image_url)
            VALUES (%s,'user',%s,%s,%s,%s,%s,%s,%s,%s) RETURNING *""", (user_id,body.name,body.serving_grams,body.calories_kcal,body.carbohydrate_g,body.protein_g,body.fat_g,body.sodium_mg,body.image_url))
            result=cursor.fetchone()
        connection.commit()
    return result


@router.get("/my-foods")
def get_my_foods(user_id: str = Depends(require_user_id)):
    """Return only foods directly registered by the signed-in user."""
    return rows(user_id, """SELECT id,name,serving_grams,calories_kcal,carbohydrate_g,
        protein_g,fat_g,sodium_mg,image_url,source,use_count,created_at
        FROM foods
        WHERE owner_user_id=%s AND source='user'
        ORDER BY created_at DESC""")


@router.put("/foods/{food_id}")
def update_my_food(food_id: str, body: FoodIn, user_id: str = Depends(require_user_id)):
    """Update an owned user food. Catalog foods and other users' foods are immutable."""
    with connect() as connection:
        with connection.cursor() as cursor:
            cursor.execute("""UPDATE foods SET name=%s, serving_grams=%s,
                calories_kcal=%s, carbohydrate_g=%s, protein_g=%s, fat_g=%s,
                sodium_mg=%s, image_url=%s, updated_at=NOW()
                WHERE id=%s AND owner_user_id=%s AND source='user'
                RETURNING *""", (
                body.name, body.serving_grams, body.calories_kcal,
                body.carbohydrate_g, body.protein_g, body.fat_g,
                body.sodium_mg, body.image_url, food_id, user_id))
            result = cursor.fetchone()
        connection.commit()
    if result is None:
        raise HTTPException(404, "Food not found or not owned by this user")
    return result


@router.delete("/foods/{food_id}")
def delete_my_food(food_id: str, user_id: str = Depends(require_user_id)):
    """Delete an owned food definition while retaining past meal records."""
    with connect() as connection:
        with connection.cursor() as cursor:
            cursor.execute("""DELETE FROM foods
                WHERE id=%s AND owner_user_id=%s AND source='user'
                RETURNING id""", (food_id, user_id))
            result = cursor.fetchone()
        connection.commit()
    if result is None:
        raise HTTPException(404, "Food not found or not owned by this user")
    return {"deleted": True}


@router.get("/meals")
def get_meals(from_date: date, to_date: date, user_id: str = Depends(require_user_id)):
    return rows(user_id, """SELECT m.id AS meal_id,m.meal_date,m.meal_type,mf.* FROM meals m JOIN meal_foods mf ON mf.meal_id=m.id
                   WHERE m.user_id=%s AND m.meal_date BETWEEN %s AND %s ORDER BY m.meal_date,m.created_at,mf.created_at""", (from_date,to_date))


@router.post("/meals")
def add_meal_food(body: MealIn, user_id: str = Depends(require_user_id)):
    """Create a meal record and increment the linked food's global registration count."""
    with connect() as connection:
        with connection.cursor() as cursor:
            food = body.food
            resolved_food_id = food.food_id

            # AI detections do not start with a foods.id. Reuse a catalog item by
            # model code/name, or create one so future AI registrations share its count.
            if resolved_food_id is None and food.source == "ai":
                if food.food_code:
                    cursor.execute(
                        "SELECT id FROM foods WHERE source='catalog' AND food_code=%s LIMIT 1",
                        (food.food_code,),
                    )
                    found = cursor.fetchone()
                    resolved_food_id = str(found["id"]) if found else None
                if resolved_food_id is None:
                    cursor.execute(
                        """SELECT id FROM foods
                           WHERE source='catalog' AND lower(name)=lower(%s)
                           ORDER BY use_count DESC LIMIT 1""",
                        (food.food_name,),
                    )
                    found = cursor.fetchone()
                    resolved_food_id = str(found["id"]) if found else None
                if resolved_food_id is None:
                    cursor.execute(
                        """INSERT INTO foods
                           (owner_user_id, source, food_code, name, serving_grams,
                            calories_kcal, carbohydrate_g, protein_g, fat_g, sodium_mg, image_url)
                           VALUES (NULL, 'catalog', %s, %s, %s, %s, %s, %s, %s, %s, %s)
                           RETURNING id""",
                        (
                            food.food_code,
                            food.food_name,
                            food.serving_grams or 100,
                            food.calories_kcal,
                            food.carbohydrate_g,
                            food.protein_g,
                            food.fat_g,
                            food.sodium_mg,
                            food.image_url,
                        ),
                    )
                    resolved_food_id = str(cursor.fetchone()["id"])

            cursor.execute(
                """INSERT INTO meals (user_id, meal_date, meal_type)
                   VALUES (%s, %s, %s) RETURNING id""",
                (user_id, body.meal_date, body.meal_type),
            )
            meal_id = cursor.fetchone()["id"]
            cursor.execute(
                """INSERT INTO meal_foods
                   (meal_id, food_id, food_code, food_name, source, image_url,
                    ai_confidence, serving_grams, serving_unit, serving_count,
                    calories_kcal, carbohydrate_g, protein_g, fat_g, sodium_mg)
                   VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
                   RETURNING *""",
                (
                    meal_id, resolved_food_id, food.food_code, food.food_name,
                    food.source, food.image_url, food.ai_confidence,
                    food.serving_grams, food.serving_unit, food.serving_count,
                    food.calories_kcal, food.carbohydrate_g, food.protein_g,
                    food.fat_g, food.sodium_mg,
                ),
            )
            result = cursor.fetchone()
            if resolved_food_id:
                cursor.execute(
                    "UPDATE foods SET use_count=use_count+1 WHERE id=%s",
                    (resolved_food_id,),
                )
        connection.commit()
    return result

@router.put("/meal-foods/{record_id}")
def update_meal_food(record_id: str, body: MealFoodUpdateIn, user_id: str = Depends(require_user_id)):
    """Update only the serving amount and nutrition values of the user's existing meal record."""
    with connect() as connection:
        with connection.cursor() as cursor:
            cursor.execute("""UPDATE meal_foods mf
                              SET food_name=%s, image_url=%s, serving_grams=%s, serving_unit=%s, serving_count=%s,
                                  calories_kcal=%s, carbohydrate_g=%s, protein_g=%s,
                                  fat_g=%s, sodium_mg=%s
                              FROM meals m
                              WHERE mf.id=%s AND mf.meal_id=m.id AND m.user_id=%s
                              RETURNING mf.*""",
                           (body.food_name, body.image_url, body.serving_grams, body.serving_unit, body.serving_count,
                             body.calories_kcal, body.carbohydrate_g, body.protein_g,
                            body.fat_g, body.sodium_mg, record_id, user_id))
            result = cursor.fetchone()
        connection.commit()
    if not result:
        raise HTTPException(404, "Meal record was not found.")
    return result

@router.delete("/meal-foods/{record_id}")
def delete_meal_food(record_id: str, user_id: str = Depends(require_user_id)):
    """Delete one meal food and reverse its registration-count increment."""
    with connect() as connection:
        with connection.cursor() as cursor:
            cursor.execute(
                """DELETE FROM meal_foods mf
                   USING meals m
                   WHERE mf.id=%s AND mf.meal_id=m.id AND m.user_id=%s
                   RETURNING mf.id, mf.food_id""",
                (record_id, user_id),
            )
            result = cursor.fetchone()
            if result and result["food_id"]:
                # Old records may have no food_id. Never let the aggregate counter go below zero.
                cursor.execute(
                    """UPDATE foods
                       SET use_count = GREATEST(use_count - 1, 0)
                       WHERE id=%s""",
                    (result["food_id"],),
                )
        connection.commit()
    if not result:
        raise HTTPException(404, "식사 기록을 찾지 못했습니다.")
    return {"deleted": True}

@router.get("/weights")
def get_weights(user_id: str = Depends(require_user_id)):
    """Return one latest record for each calendar month."""
    return rows(user_id, """SELECT DISTINCT ON (date_trunc('month', recorded_month))
                                date_trunc('month', recorded_month)::date AS recorded_month,
                                weight_kg
                           FROM weight_records
                          WHERE user_id=%s
                          ORDER BY date_trunc('month', recorded_month) DESC,
                                   recorded_month DESC""")


@router.put("/weights")
def put_weight(body: WeightIn, user_id: str = Depends(require_user_id)):
    """Save exactly one weight for a calendar month; later saves update it."""
    month_start = body.recorded_month.replace(day=1)
    next_month = (month_start.replace(day=28) + timedelta(days=4)).replace(day=1)
    with connect() as connection:
        with connection.cursor() as cursor:
            # Clear legacy day-based rows in this month, then store the canonical month record.
            cursor.execute(
                """DELETE FROM weight_records
                   WHERE user_id=%s AND recorded_month >= %s AND recorded_month < %s""",
                (user_id, month_start, next_month),
            )
            cursor.execute(
                """INSERT INTO weight_records (user_id, recorded_month, weight_kg)
                   VALUES (%s, %s, %s)
                   ON CONFLICT (user_id, recorded_month)
                   DO UPDATE SET weight_kg=EXCLUDED.weight_kg
                   RETURNING *""",
                (user_id, month_start, body.weight_kg),
            )
            result = cursor.fetchone()
        connection.commit()
    return result
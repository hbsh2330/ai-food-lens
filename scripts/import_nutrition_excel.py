"""Import serving-based nutrition data from the supplied calorie Excel DB."""

from __future__ import annotations

import json
from pathlib import Path

import openpyxl


ROOT = Path(__file__).resolve().parents[1]
CATALOG_PATH = ROOT / "data" / "food_catalog.json"
EXCEL_PATH = ROOT / "음식 이미지 및 영양정보 텍스트" / "칼로리데이터셋" / "음식분류 AI 데이터 영양DB.xlsx"
SHEET_NAME = "400외식메뉴"

# Names which describe the same menu differently in the YOLO label and DB.
NAME_ALIASES = {
    "잡곡밥": "기타잡곡밥",
}


def number_or_none(value: object) -> float | None:
    return float(value) if isinstance(value, (int, float)) else None


def main() -> None:
    catalog = json.loads(CATALOG_PATH.read_text(encoding="utf-8"))
    workbook = openpyxl.load_workbook(EXCEL_PATH, read_only=True, data_only=True)
    worksheet = workbook[SHEET_NAME]
    db_rows = {
        str(row[0]).strip(): row
        for row in worksheet.iter_rows(min_row=2, values_only=True)
        if row[0]
    }

    imported, unmatched = 0, []
    for code, food in catalog["foods"].items():
        name = food["name_ko"]
        if not name:
            unmatched.append(code)
            continue
        db_name = NAME_ALIASES.get(name.strip(), name.strip())
        row = db_rows.get(db_name)
        if row is None:
            unmatched.append(f"{code} ({name})")
            continue

        food["serving_grams"] = number_or_none(row[1])
        food["nutrition_per_serving"] = {
            "energy_kcal": number_or_none(row[2]),
            "carbohydrate_g": number_or_none(row[3]),
            "sugars_g": number_or_none(row[4]),
            "fat_g": number_or_none(row[5]),
            "protein_g": number_or_none(row[6]),
            "calcium_mg": number_or_none(row[7]),
            "phosphorus_mg": number_or_none(row[8]),
            "sodium_mg": number_or_none(row[9]),
            "potassium_mg": number_or_none(row[10]),
            "magnesium_mg": number_or_none(row[11]),
            "iron_mg": number_or_none(row[12]),
            "zinc_mg": number_or_none(row[13]),
            "cholesterol_mg": number_or_none(row[14]),
            "trans_fat_g": number_or_none(row[15]),
        }
        food["nutrition_source"] = {
            "file": EXCEL_PATH.name,
            "sheet": SHEET_NAME,
            "basis": "1 serving",
        }
        imported += 1

    CATALOG_PATH.write_text(json.dumps(catalog, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Imported nutrition for {imported} foods.")
    print(f"Unmatched: {unmatched}")


if __name__ == "__main__":
    main()

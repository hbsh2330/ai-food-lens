"""Create the food-code catalog used by the inference API and Flutter app.

The source project already has an authoritative food-code-to-Korean-name table
in server/app/food.py.  Nutrition values are deliberately left null until they
are imported from a verified nutrition-data source.
"""

from __future__ import annotations

import json
import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CLASS_CODES_PATH = ROOT / "data" / "403food.names"
FOOD_NAME_SOURCE_PATH = ROOT / "server" / "app" / "food.py"
OUTPUT_PATH = ROOT / "data" / "food_catalog.json"


def load_food_names() -> dict[str, str]:
    source = FOOD_NAME_SOURCE_PATH.read_text(encoding="utf-8")
    return dict(re.findall(r"'([0-9]{8})'\s*:\s*'([^']+)'", source))


def main() -> None:
    class_labels = CLASS_CODES_PATH.read_text(encoding="utf-8").splitlines()
    food_names = load_food_names()
    food_codes = sorted({label for label in class_labels if re.fullmatch(r"[0-9]{8}", label)})
    foods = {
        code: {
            "name_ko": food_names.get(code),
            "nutrition_per_serving": {
                "energy_kcal": None,
                "carbohydrate_g": None,
                "sugars_g": None,
                "protein_g": None,
                "fat_g": None,
                "sodium_mg": None,
            },
            "serving_grams": None,
            "nutrition_source": None,
        }
        for code in food_codes
    }
    classes = [
        {
            "class_index": index,
            "detector_label": label,
            "food_code": label if re.fullmatch(r"[0-9]{8}", label) else None,
            "name_ko": food_names.get(label, "숟가락" if label == "spoon" else None),
            "is_food": label != "spoon",
        }
        for index, label in enumerate(class_labels)
    ]
    catalog = {
        "schema_version": 1,
        "description": "YOLO food-code catalog. Nutrition values must be imported from a verified source.",
        "classes": classes,
        "foods": foods,
    }
    OUTPUT_PATH.write_text(
        json.dumps(catalog, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    unnamed_foods = [code for code, food in foods.items() if food["name_ko"] is None]
    print(f"Created {OUTPUT_PATH} with {len(classes)} classes and {len(foods)} food codes.")
    print(f"Food codes without a Korean name: {unnamed_foods}")


if __name__ == "__main__":
    main()

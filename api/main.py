"""HTTP API that returns detected food and nutrition information."""

from __future__ import annotations

import contextlib
import json
import logging
import tempfile
import threading
from uuid import uuid4
from pathlib import Path

import torch
from fastapi import Depends, FastAPI, File, HTTPException, UploadFile
from fastapi.staticfiles import StaticFiles
from api.data_routes import router as data_router
from api.auth import require_user_id, router as auth_router
from api.database import connect
from PIL import Image, UnidentifiedImageError

from models import Darknet
from utils import torch_utils
from utils.datasets import LoadImages
from utils.utils import load_classes, non_max_suppression, scale_coords


ROOT = Path(__file__).resolve().parents[1]
logger = logging.getLogger(__name__)
CFG_PATH = ROOT / "cfg" / "yolov3-spp-403cls.cfg"
NAMES_PATH = ROOT / "data" / "403food.names"
WEIGHTS_PATH = ROOT / "weights" / "best_403food_e200b150v2.pt"
CATALOG_PATH = ROOT / "data" / "food_catalog.json"


class FoodDetector:
    def __init__(self) -> None:
        self.lock = threading.Lock()
        self.device = torch_utils.select_device("cpu")
        self.names = load_classes(str(NAMES_PATH))
        self.catalog = json.loads(CATALOG_PATH.read_text(encoding="utf-8"))
        self.model = Darknet(str(CFG_PATH), 512)
        # The legacy checkpoint contains metadata objects and profiling keys.
        checkpoint = torch.load(WEIGHTS_PATH, map_location=self.device, weights_only=False)
        self.model.load_state_dict(checkpoint["model"], strict=False)
        self.model.to(self.device).eval()
    def _near_candidates(self, predictions: torch.Tensor) -> list[dict]:
        """Return low-confidence candidates for failure analysis and console diagnostics."""
        low_detections = non_max_suppression(
            predictions.clone(), conf_thres=0.01, iou_thres=0.6
        )[0]
        if low_detections is None or not len(low_detections):
            print("[FoodDetector] No food candidate found, even at 1% confidence.")
            return []

        labels: list[str] = []
        candidates: list[dict] = []
        seen_class_ids: set[int] = set()
        for *_, confidence, class_id in low_detections:
            class_index = int(class_id)
            if class_index in seen_class_ids:
                continue
            seen_class_ids.add(class_index)
            food_code = self.names[class_index]
            food_name = self.catalog["foods"].get(food_code, {}).get("name_ko")
            confidence_value = round(float(confidence), 4)
            candidates.append({
                "food_code": food_code,
                "food_name": food_name,
                "confidence": confidence_value,
            })
            labels.append(f"{food_code} ({food_name or 'unknown'}, {confidence_value:.1%})")
            if len(candidates) == 5:
                break
        print("[FoodDetector] Top candidates (includes low confidence): " + "; ".join(labels))
        return candidates
    def predict(self, image_path: Path, confidence_threshold: float = 0.15) -> tuple[list[dict], list[dict]]:
        results: list[dict] = []
        candidates: list[dict] = []
        with self.lock, torch.no_grad():
            dataset = LoadImages(str(image_path), img_size=512)
            for _, image, original, _ in dataset:
                tensor = torch.from_numpy(image).to(self.device).float() / 255.0
                if tensor.ndimension() == 3:
                    tensor = tensor.unsqueeze(0)

                predictions = self.model(tensor)[0]
                candidates = self._near_candidates(predictions)
                detections = non_max_suppression(predictions, confidence_threshold, 0.6)[0]
                if detections is None or not len(detections):
                    continue

                detections[:, :4] = scale_coords(tensor.shape[2:], detections[:, :4], original.shape).round()
                for *xyxy, confidence, class_id in detections:
                    food_code = self.names[int(class_id)]
                    food = self.catalog["foods"].get(food_code, {})
                    results.append(
                        {
                            "food_code": food_code,
                            "food_name": food.get("name_ko"),
                            "confidence": round(float(confidence), 4),
                            "box_xyxy": [int(value) for value in xyxy],
                            "serving_grams": food.get("serving_grams"),
                            "nutrition_per_serving": food.get("nutrition_per_serving"),
                        }
                    )
        return results, candidates

    


app = FastAPI(
    title="Food Nutrition AI API",
    version="1.0.0",
    description="Detect Korean food from an uploaded image and return nutrition information.",
)
detector: FoodDetector | None = None
UPLOADS_DIR = ROOT / "uploads"
UPLOADS_DIR.mkdir(parents=True, exist_ok=True)
app.mount("/uploads", StaticFiles(directory=UPLOADS_DIR), name="uploads")
app.include_router(auth_router)
app.include_router(data_router)


@app.on_event("startup")
def load_model() -> None:
    global detector
    # Keep model summary messages out of the API response/log stream.
    with contextlib.redirect_stdout(__import__("sys").stderr):
        detector = FoodDetector()


@app.get("/health")
def health() -> dict:
    return {"status": "ok", "model_loaded": detector is not None}


AI_FEEDBACK_DIR = UPLOADS_DIR / "ai-feedback"
MODEL_VERSION = "yolov3-spp-403cls-best_403food_e200b150v2"


def _save_unrecognized_feedback(
    *,
    user_id: str,
    image_bytes: bytes,
    original_filename: str | None,
    suffix: str,
    failure_reason: str,
    detections: list[dict],
    candidates: list[dict],
) -> str | None:
    """Persist one failed recognition image and its diagnostic candidates for later labeling."""
    safe_suffix = suffix.lower() if suffix.lower() in {".jpg", ".jpeg", ".png", ".webp"} else ".jpg"
    AI_FEEDBACK_DIR.mkdir(parents=True, exist_ok=True)
    file_name = f"{user_id}_{uuid4().hex}{safe_suffix}"
    target = AI_FEEDBACK_DIR / file_name
    target.write_bytes(image_bytes)
    image_url = f"/uploads/ai-feedback/{file_name}"
    first = detections[0] if detections else {}
    try:
        with connect() as connection:
            with connection.cursor() as cursor:
                cursor.execute(
                    """INSERT INTO ai_recognition_feedback
                       (user_id,image_url,original_filename,failure_reason,
                        predicted_food_code,predicted_food_name,predicted_confidence,
                        candidates,model_version)
                       VALUES (%s,%s,%s,%s,%s,%s,%s,%s::jsonb,%s)
                       RETURNING id""",
                    (
                        user_id,
                        image_url,
                        original_filename,
                        failure_reason,
                        first.get("food_code"),
                        first.get("food_name"),
                        first.get("confidence"),
                        json.dumps(candidates, ensure_ascii=False),
                        MODEL_VERSION,
                    ),
                )
                feedback_id = str(cursor.fetchone()["id"])
            connection.commit()
        return feedback_id
    except Exception:
        # Failure logging must never hide the normal 'not recognized' result from the app.
        target.unlink(missing_ok=True)
        logger.exception("Could not save failed AI recognition feedback")
        return None


@app.post("/predict")
async def predict(
    file: UploadFile = File(...),
    user_id: str = Depends(require_user_id),
) -> dict:
    if detector is None:
        raise HTTPException(status_code=503, detail="Model is still loading.")
    if file.content_type and (
        not file.content_type.startswith("image/")
        and file.content_type != "application/octet-stream"
    ):
        raise HTTPException(status_code=415, detail="Only image files can be uploaded.")

    image_bytes = await file.read()
    if not image_bytes:
        raise HTTPException(status_code=400, detail="The uploaded image is empty.")
    try:
        with Image.open(__import__("io").BytesIO(image_bytes)) as image:
            image.verify()
    except (UnidentifiedImageError, OSError):
        raise HTTPException(status_code=400, detail="The uploaded file is not a valid image.")

    suffix = Path(file.filename or "image.jpg").suffix or ".jpg"
    with tempfile.NamedTemporaryFile(suffix=suffix, delete=False) as temporary:
        temporary.write(image_bytes)
        temporary_path = Path(temporary.name)
    try:
        detections, candidates = detector.predict(temporary_path)
    finally:
        temporary_path.unlink(missing_ok=True)

    # The Flutter app uses the first detection as the AI answer. Therefore
    # feedback must use that exact same primary result: if it is the special
    # ``00000000`` unknown class, save the image even when lower-ranked
    # candidates happen to contain a valid food.
    primary_detection = detections[0] if detections else None
    failure_reason: str | None = None
    if primary_detection is None:
        failure_reason = "no_detection"
    elif (
        primary_detection.get("food_code") == "00000000"
        or not primary_detection.get("food_name")
    ):
        failure_reason = "invalid_food_code"

    # Do not store the photo yet. It becomes training feedback only when the
    # user chooses manual registration and successfully saves a meal.
    feedback_id = None

    return {
        "filename": file.filename,
        "detection_count": len(detections),
        "detections": detections,
        "candidates": candidates[:3],
        "feedback_id": feedback_id,
    }
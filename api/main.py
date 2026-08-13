"""HTTP API that returns detected food and nutrition information."""

from __future__ import annotations

import contextlib
import json
import tempfile
import threading
from pathlib import Path

import torch
from fastapi import FastAPI, File, HTTPException, UploadFile
from api.data_routes import router as data_router
from PIL import Image, UnidentifiedImageError

from models import Darknet
from utils import torch_utils
from utils.datasets import LoadImages
from utils.utils import load_classes, non_max_suppression, scale_coords


ROOT = Path(__file__).resolve().parents[1]
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
    def _log_near_candidates(self, predictions: torch.Tensor) -> None:
        """Print low-confidence candidates when nothing passes the API threshold."""
        low_detections = non_max_suppression(
            predictions.clone(), conf_thres=0.01, iou_thres=0.6
        )[0]
        if low_detections is None or not len(low_detections):
            print("[FoodDetector] 신뢰도 1%인 음식도 못찾았습니다..")
            return

        candidates: list[str] = []
        seen_class_ids: set[int] = set()
        for *_, confidence, class_id in low_detections:
            class_index = int(class_id)
            if class_index in seen_class_ids:
                continue
            seen_class_ids.add(class_index)
            food_code = self.names[class_index]
            food_name = self.catalog["foods"].get(food_code, {}).get("name_ko", "unknown")
            candidates.append(f"{food_code} ({food_name}, {float(confidence):.1%})")
            if len(candidates) == 5:
                break

        print("[FoodDetector] Top 3 candidates (includes low confidence): " + "; ".join(candidates))

    def predict(self, image_path: Path, confidence_threshold: float = 0.15) -> list[dict]:
        results: list[dict] = []
        with self.lock, torch.no_grad():
            dataset = LoadImages(str(image_path), img_size=512)
            for _, image, original, _ in dataset:
                tensor = torch.from_numpy(image).to(self.device).float() / 255.0
                if tensor.ndimension() == 3:
                    tensor = tensor.unsqueeze(0)

                predictions = self.model(tensor)[0]
                self._log_near_candidates(predictions)
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
        return results

    


app = FastAPI(
    title="Food Nutrition AI API",
    version="1.0.0",
    description="Detect Korean food from an uploaded image and return nutrition information.",
)
detector: FoodDetector | None = None
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


@app.post("/predict")
async def predict(file: UploadFile = File(...)) -> dict:
    if detector is None:
        raise HTTPException(status_code=503, detail="Model is still loading.")
    if file.content_type and (
        not file.content_type.startswith("image/")
        and file.content_type != "application/octet-stream"
    ):
        raise HTTPException(status_code=415, detail="이미지 파일만 업로드할 수 있습니다.")

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
        detections = detector.predict(temporary_path)
    finally:
        temporary_path.unlink(missing_ok=True)

    return {
        "filename": file.filename,
        "detection_count": len(detections),
        "detections": detections,
    }



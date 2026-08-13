"""Run food detection for one image and write an app-ready JSON response."""

from __future__ import annotations

import argparse
import contextlib
import json
import sys
from pathlib import Path

import torch

from models import Darknet
from utils.datasets import LoadImages
from utils.utils import check_file, load_classes, non_max_suppression, scale_coords
from utils import torch_utils


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Detect food and return nutrition JSON.")
    parser.add_argument("--source", required=True, help="One input image path")
    parser.add_argument("--cfg", default="cfg/yolov3-spp-403cls.cfg")
    parser.add_argument("--names", default="data/403food.names")
    parser.add_argument("--weights", default="weights/best_403food_e200b150v2.pt")
    parser.add_argument("--catalog", default="data/food_catalog.json")
    parser.add_argument("--img-size", type=int, default=512)
    parser.add_argument("--conf-thres", type=float, default=0.25)
    parser.add_argument("--iou-thres", type=float, default=0.6)
    parser.add_argument("--device", default="cpu")
    parser.add_argument("--json-output", help="Optional path to save the JSON response")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    if not Path(args.source).is_file():
        raise FileNotFoundError(f"Input image not found: {args.source}")

    cfg_path = check_file(args.cfg)
    names_path = check_file(args.names)
    catalog = json.loads(Path(args.catalog).read_text(encoding="utf-8"))
    names = load_classes(names_path)

    # Keep framework progress messages on stderr so stdout is valid JSON.
    with contextlib.redirect_stdout(sys.stderr):
        device = torch_utils.select_device(args.device)
        model = Darknet(cfg_path, args.img_size)
        checkpoint = torch.load(args.weights, map_location=device, weights_only=False)
        model.load_state_dict(checkpoint["model"], strict=False)
        model.to(device).eval()

    images = []
    with contextlib.redirect_stdout(sys.stderr):
        dataset = LoadImages(args.source, img_size=args.img_size)
        with torch.no_grad():
            for path, image, original, _ in dataset:
                tensor = torch.from_numpy(image).to(device).float() / 255.0
                if tensor.ndimension() == 3:
                    tensor = tensor.unsqueeze(0)

                predictions = model(tensor)[0]
                detections = non_max_suppression(predictions, args.conf_thres, args.iou_thres)[0]
                response_detections = []
                if detections is not None and len(detections):
                    detections[:, :4] = scale_coords(tensor.shape[2:], detections[:, :4], original.shape).round()
                    for *xyxy, confidence, class_id in reversed(detections):
                        code = names[int(class_id)]
                        food = catalog["foods"].get(code, {})
                        response_detections.append(
                            {
                                "food_code": code,
                                "food_name": food.get("name_ko"),
                                "confidence": round(float(confidence), 4),
                                "box_xyxy": [int(value) for value in xyxy],
                                "serving_grams": food.get("serving_grams"),
                                "nutrition_per_serving": food.get("nutrition_per_serving"),
                            }
                        )
                images.append({"image": str(path), "detections": response_detections})

    response = {"images": images}
    response_text = json.dumps(response, ensure_ascii=False, indent=2)
    if args.json_output:
        output_path = Path(args.json_output)
        output_path.parent.mkdir(parents=True, exist_ok=True)
        output_path.write_text(response_text + "\n", encoding="utf-8")
    print(response_text)


if __name__ == "__main__":
    main()

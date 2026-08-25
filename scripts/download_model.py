"""Prepare the YOLO checkpoint for a Cloud Run container startup.

Local development keeps using weights/best_403food_e200b150v2.pt. In Cloud Run,
set MODEL_GCS_URI to a private gs:// URI and grant the service account Storage
Object Viewer on that bucket. Application Default Credentials are supplied by
Cloud Run, so no JSON key file is stored in this project.
"""

from __future__ import annotations

import hashlib
import os
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_MODEL_PATH = ROOT / "weights" / "best_403food_e200b150v2.pt"


def _parse_gcs_uri(uri: str) -> tuple[str, str]:
    """Split a gs:// URI into its bucket and object name."""
    if not uri.startswith("gs://"):
        raise ValueError("MODEL_GCS_URI must start with gs://")
    remainder = uri[5:]
    bucket, separator, blob_name = remainder.partition("/")
    if not bucket or not separator or not blob_name:
        raise ValueError("MODEL_GCS_URI must include both a bucket and object path")
    return bucket, blob_name


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as model_file:
        for chunk in iter(lambda: model_file.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def main() -> int:
    model_uri = os.getenv("MODEL_GCS_URI", "").strip()
    model_path = Path(os.getenv("MODEL_LOCAL_PATH", str(DEFAULT_MODEL_PATH)))
    expected_hash = os.getenv("MODEL_SHA256", "").strip().lower()

    # A mounted/local model takes precedence, which keeps local Docker and
    # existing Windows development commands working without cloud credentials.
    if model_path.is_file():
        print(f"[model] Using local checkpoint: {model_path}")
    elif not model_uri:
        print(
            "[model] Checkpoint is missing. Add the weights file locally or set "
            "MODEL_GCS_URI for Cloud Run.",
            file=sys.stderr,
        )
        return 1
    else:
        try:
            from google.cloud import storage

            bucket_name, blob_name = _parse_gcs_uri(model_uri)
            model_path.parent.mkdir(parents=True, exist_ok=True)
            temporary_path = model_path.with_suffix(model_path.suffix + ".download")
            print(f"[model] Downloading {model_uri} to {model_path}")
            storage.Client().bucket(bucket_name).blob(blob_name).download_to_filename(
                str(temporary_path)
            )
            temporary_path.replace(model_path)
        except Exception as error:
            print(f"[model] Download failed: {error}", file=sys.stderr)
            return 1

    if expected_hash and _sha256(model_path) != expected_hash:
        print("[model] SHA-256 verification failed.", file=sys.stderr)
        return 1

    print(f"[model] Checkpoint ready ({model_path.stat().st_size} bytes).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
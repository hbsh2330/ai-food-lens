"""Storage adapter for local development and private Cloud Storage deployments."""

from __future__ import annotations

import mimetypes
import os
from functools import lru_cache
from pathlib import Path, PurePosixPath


ROOT = Path(__file__).resolve().parents[1]
LOCAL_UPLOADS_DIR = ROOT / "uploads"
UPLOADS_GCS_BUCKET = os.getenv("UPLOADS_GCS_BUCKET", "").strip()


def uses_cloud_storage() -> bool:
    """Return True only when production configured an uploads bucket."""
    return bool(UPLOADS_GCS_BUCKET)


def _safe_object_name(object_name: str) -> str:
    """Reject traversal paths before reading or writing an uploaded object."""
    path = PurePosixPath(object_name.strip("/"))
    if not object_name or path.is_absolute() or ".." in path.parts:
        raise ValueError("Invalid upload object path")
    return path.as_posix()


@lru_cache(maxsize=1)
def _storage_client():
    """Create the Cloud Storage client lazily so local development needs no credentials."""
    from google.cloud import storage

    return storage.Client()


def upload_url(object_name: str) -> str:
    """Keep database URLs stable while the backend chooses local or cloud storage."""
    return f"/uploads/{_safe_object_name(object_name)}"


def save_upload(object_name: str, content: bytes, content_type: str | None = None) -> str:
    """Save bytes to local uploads or the configured private Cloud Storage bucket."""
    object_name = _safe_object_name(object_name)
    if uses_cloud_storage():
        blob = _storage_client().bucket(UPLOADS_GCS_BUCKET).blob(object_name)
        blob.upload_from_string(content, content_type=content_type or "application/octet-stream")
    else:
        destination = LOCAL_UPLOADS_DIR / object_name
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_bytes(content)
    return upload_url(object_name)


def read_upload(object_name: str) -> tuple[bytes, str]:
    """Read a stored image for the existing /uploads application route."""
    object_name = _safe_object_name(object_name)
    if uses_cloud_storage():
        blob = _storage_client().bucket(UPLOADS_GCS_BUCKET).blob(object_name)
        if not blob.exists():
            raise FileNotFoundError(object_name)
        return blob.download_as_bytes(), blob.content_type or "application/octet-stream"

    source = LOCAL_UPLOADS_DIR / object_name
    if not source.is_file():
        raise FileNotFoundError(object_name)
    return source.read_bytes(), mimetypes.guess_type(source.name)[0] or "application/octet-stream"


def delete_upload(object_name: str) -> None:
    """Best-effort cleanup when the related database transaction fails."""
    object_name = _safe_object_name(object_name)
    if uses_cloud_storage():
        _storage_client().bucket(UPLOADS_GCS_BUCKET).blob(object_name).delete()
    else:
        (LOCAL_UPLOADS_DIR / object_name).unlink(missing_ok=True)
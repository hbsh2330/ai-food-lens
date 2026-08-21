"""Google sign-in verification and short-lived app session tokens."""
from __future__ import annotations

import logging
import os
from pathlib import Path
from datetime import datetime, timedelta, timezone

import jwt
import requests
from fastapi import APIRouter, Depends, HTTPException
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from google.auth.transport import requests as google_requests
from google.oauth2 import id_token
from pydantic import BaseModel

from .database import connect

router = APIRouter(prefix="/auth", tags=["authentication"])
_bearer = HTTPBearer(auto_error=False)
_logger = logging.getLogger(__name__)


def _google_client_id() -> str:
    value = os.getenv("GOOGLE_WEB_CLIENT_ID")
    if not value:
        raise RuntimeError("GOOGLE_WEB_CLIENT_ID is missing.")
    return value


def _jwt_secret() -> str:
    value = os.getenv("APP_JWT_SECRET")
    if not value:
        raise RuntimeError("APP_JWT_SECRET is missing.")
    return value


def create_access_token(user_id: str) -> str:
    payload = {
        "sub": user_id,
        "iat": datetime.now(timezone.utc),
        "exp": datetime.now(timezone.utc) + timedelta(days=14),
    }
    return jwt.encode(payload, _jwt_secret(), algorithm="HS256")


def require_user_id(
    credentials: HTTPAuthorizationCredentials | None = Depends(_bearer),
) -> str:
    if credentials is None or credentials.scheme.lower() != "bearer":
        raise HTTPException(status_code=401, detail="로그인이 필요합니다.")
    try:
        payload = jwt.decode(credentials.credentials, _jwt_secret(), algorithms=["HS256"])
        user_id = payload.get("sub")
        if not user_id:
            raise ValueError("Missing subject")
        return str(user_id)
    except (jwt.InvalidTokenError, ValueError) as error:
        raise HTTPException(status_code=401, detail="로그인 정보가 만료되었거나 올바르지 않습니다.") from error


class GoogleTokenIn(BaseModel):
    id_token: str


class KakaoTokenIn(BaseModel):
    access_token: str

def _profile_complete(profile: dict | None) -> bool:
    if not profile:
        return False
    required = (
        "height_cm",
        "weight_kg",
        "target_weight_kg",
        "age",
        "biological_sex",
        "activity_level",
        "goal_type",
    )
    return all(profile.get(field) is not None for field in required)


def _user_payload(connection, user_id: str) -> dict:
    with connection.cursor() as cursor:
        cursor.execute("SELECT id, provider, display_name FROM users WHERE id = %s", (user_id,))
        user = cursor.fetchone()
        cursor.execute(
            """SELECT height_cm, weight_kg, target_weight_kg, age,
                      biological_sex, activity_level, goal_type
               FROM user_profiles WHERE user_id = %s""",
            (user_id,),
        )
        profile = cursor.fetchone()
    if user is None:
        raise HTTPException(status_code=401, detail="사용자 정보를 찾지 못했습니다.")
    return {
        "id": str(user["id"]),
        "provider": user["provider"],
        "display_name": user["display_name"] or "Food Lens 사용자",
        "onboarding_completed": _profile_complete(profile),
    }


@router.post("/google")
def google_sign_in(body: GoogleTokenIn):
    try:
        payload = id_token.verify_oauth2_token(
            body.id_token,
            google_requests.Request(),
            _google_client_id(),
        )
        subject = str(payload["sub"])
    except Exception as error:
        # Do not log the ID token. The error text identifies audience, expiry, or verification issues.
        _logger.warning("Google ID token verification failed: %s", error)
        raise HTTPException(status_code=401, detail="Google 로그인 정보를 확인하지 못했습니다.") from error

    display_name = str(payload.get("name") or payload.get("email") or "Food Lens 사용자")
    with connect() as connection:
        with connection.cursor() as cursor:
            cursor.execute(
                """INSERT INTO users (provider, provider_subject, display_name)
                   VALUES ('google', %s, %s)
                   ON CONFLICT (provider, provider_subject)
                   DO UPDATE SET display_name = EXCLUDED.display_name
                   RETURNING id""",
                (subject, display_name),
            )
            user_id = str(cursor.fetchone()["id"])
        user = _user_payload(connection, user_id)
        connection.commit()
    return {"access_token": create_access_token(user_id), "token_type": "bearer", "user": user}


@router.post("/kakao")
def kakao_sign_in(body: KakaoTokenIn):
    """Verify the Kakao SDK access token server-side and issue a Food Lens JWT."""
    try:
        response = requests.get(
            "https://kapi.kakao.com/v2/user/me",
            headers={"Authorization": f"Bearer {body.access_token}"},
            timeout=10,
        )
        if response.status_code != 200:
            raise ValueError(f"Kakao user API returned {response.status_code}")
        payload = response.json()
        subject = str(payload["id"])
    except Exception as error:
        raise HTTPException(
            status_code=401,
            detail="Could not verify the Kakao login token.",
        ) from error

    account = payload.get("kakao_account") or {}
    profile = account.get("profile") or {}
    display_name = str(profile.get("nickname") or account.get("email") or "Food Lens 사용자")
    with connect() as connection:
        with connection.cursor() as cursor:
            cursor.execute(
                """INSERT INTO users (provider, provider_subject, display_name)
                   VALUES ('kakao', %s, %s)
                   ON CONFLICT (provider, provider_subject)
                   DO UPDATE SET display_name = EXCLUDED.display_name,
                                 updated_at = NOW()
                   RETURNING id""",
                (subject, display_name),
            )
            user_id = str(cursor.fetchone()["id"])
        user = _user_payload(connection, user_id)
        connection.commit()
    return {"access_token": create_access_token(user_id), "token_type": "bearer", "user": user}

@router.delete("/account")
def delete_account(user_id: str = Depends(require_user_id)):
    """Permanently remove the signed-in Food Lens account and its app data."""
    food_image_dir = Path(__file__).resolve().parents[1] / "uploads" / "food-images"
    image_paths: list[str] = []
    with connect() as connection:
        with connection.cursor() as cursor:
            cursor.execute(
                "SELECT image_url FROM foods WHERE owner_user_id=%s AND image_url IS NOT NULL",
                (user_id,),
            )
            image_paths = [row["image_url"] for row in cursor.fetchall()]
            # User foods may appear in another user's history. Their snapshot remains,
            # while food_id becomes NULL through the database foreign-key rule.
            cursor.execute("DELETE FROM foods WHERE owner_user_id=%s", (user_id,))
            cursor.execute("DELETE FROM users WHERE id=%s RETURNING id", (user_id,))
            deleted = cursor.fetchone()
        connection.commit()
    if deleted is None:
        raise HTTPException(status_code=404, detail="Account not found.")

    # Images are private files owned by this account. Do not follow arbitrary paths.
    for image_url in image_paths:
        file_name = Path(image_url).name
        if file_name.startswith(f"{user_id}_"):
            try:
                (food_image_dir / file_name).unlink(missing_ok=True)
            except OSError:
                _logger.warning("Could not remove deleted account image: %s", file_name)
    return {"deleted": True}


@router.get("/me")
def me(user_id: str = Depends(require_user_id)):
    with connect() as connection:
        return _user_payload(connection, user_id)
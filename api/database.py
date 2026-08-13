"""PostgreSQL connection helpers. Login is added later; current calls use the guest user."""
from __future__ import annotations
import os
from pathlib import Path
from dotenv import load_dotenv
import psycopg
from psycopg.rows import dict_row

ROOT = Path(__file__).resolve().parents[1]
load_dotenv(ROOT / '.env')
DATABASE_URL = os.getenv('DATABASE_URL')

def connect() -> psycopg.Connection:
    if not DATABASE_URL:
        raise RuntimeError('DATABASE_URL is missing.')
    return psycopg.connect(DATABASE_URL, row_factory=dict_row)

def guest_user_id(connection: psycopg.Connection) -> str:
    with connection.cursor() as cursor:
        cursor.execute("SELECT id FROM users WHERE provider = 'guest' AND provider_subject = 'local-default'")
        user = cursor.fetchone()
        if user is None:
            cursor.execute("INSERT INTO users (provider, provider_subject, display_name) VALUES ('guest', 'local-default', '임시 사용자') RETURNING id")
            user = cursor.fetchone()
    return str(user['id'])

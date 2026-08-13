"""Create the database named by DATABASE_URL when it does not exist."""
from __future__ import annotations

import os
from pathlib import Path

import psycopg
from psycopg.conninfo import conninfo_to_dict, make_conninfo
from psycopg import sql
from dotenv import load_dotenv

ROOT = Path(__file__).resolve().parents[1]
load_dotenv(ROOT / '.env')
url = os.environ.get('DATABASE_URL')
if not url:
    raise SystemExit('DATABASE_URL is missing.')
params = conninfo_to_dict(url)
database_name = params.pop('dbname', None) or params.pop('database', None)
if not database_name:
    raise SystemExit('DATABASE_URL must include a database name.')
params['dbname'] = 'postgres'
with psycopg.connect(make_conninfo(**params), autocommit=True) as connection:
    with connection.cursor() as cursor:
        cursor.execute('SELECT 1 FROM pg_database WHERE datname = %s', (database_name,))
        if cursor.fetchone() is None:
            cursor.execute(sql.SQL('CREATE DATABASE {}').format(sql.Identifier(database_name)))
            print(f'Created database: {database_name}')
        else:
            print(f'Database already exists: {database_name}')

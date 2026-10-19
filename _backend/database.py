import psycopg2
from psycopg2.extras import RealDictCursor
import os
from dotenv import load_dotenv
from fastapi import HTTPException

load_dotenv()

def get_db_connection():
    """Создает и возвращает подключение к PostgreSQL"""
    try:
        conn = psycopg2.connect(
            host=os.getenv("DB_HOST"),
            port=os.getenv("DB_PORT"),
            dbname=os.getenv("DB_NAME"),
            user=os.getenv("DB_USER"),
            password=os.getenv("DB_PASSWORD")
        )
        return conn
    except Exception as e:
        print(f"Ошибка подключения к БД: {e}")
        raise HTTPException(status_code=500, detail="Ошибка подключения к базе данных")
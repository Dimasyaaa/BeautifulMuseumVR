from fastapi import APIRouter, HTTPException
from typing import List, Optional
import sys
import os
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from database import get_db_connection
from models import Exhibit, UserProgress, QuizAnswer 
from psycopg2.extras import RealDictCursor

router = APIRouter(prefix="/api", tags=["Godot API"])

# ЭКСПОНАТЫ
@router.get("/exhibits", response_model=List[dict])
def get_exhibits(category: Optional[str] = None):
    """Получить список всех экспонатов (с фильтрацией по категории)"""
    conn = get_db_connection()
    cursor = conn.cursor(cursor_factory=RealDictCursor)
    if category:
        cursor.execute("SELECT * FROM exhibits WHERE category = %s ORDER BY id", (category,))
    else:
        cursor.execute("SELECT * FROM exhibits ORDER BY id")
    exhibits = cursor.fetchall()
    cursor.close()
    conn.close()
    return [dict(e) for e in exhibits]

@router.get("/exhibits/{exhibit_id}")
def get_single_exhibit(exhibit_id: int):
    """Получить один экспонат по ID (для кнопки 'Подробнее')"""
    conn = get_db_connection()
    cursor = conn.cursor(cursor_factory=RealDictCursor)
    cursor.execute("SELECT * FROM exhibits WHERE id = %s", (exhibit_id,))
    exhibit = cursor.fetchone()
    cursor.close()
    conn.close()
    
    if not exhibit:
        raise HTTPException(status_code=404, detail="Экспонат не найден")
    return dict(exhibit)

# ПРОГРЕСС ПОЛЬЗОВАТЕЛЯ
@router.get("/progress/{user_id}")
def get_progress(user_id: str):
    """Получить полный прогресс пользователя"""
    conn = get_db_connection()
    cursor = conn.cursor(cursor_factory=RealDictCursor)
    cursor.execute("SELECT exhibit_id, is_viewed, is_favorite, points, visit_time FROM user_progress WHERE user_id = %s", (user_id,))
    progress = cursor.fetchall()
    cursor.close()
    conn.close()
    
    result = {}
    for row in progress:
        result[str(row["exhibit_id"])] = {
            "is_viewed": row["is_viewed"],
            "is_favorite": row["is_favorite"],
            "points": row["points"],
            "visit_time": row["visit_time"].isoformat() if row["visit_time"] else None
        }
    return {"user_id": user_id, "data": result}

@router.post("/progress")
def update_progress(progress: UserProgress):
    """Сохранить прогресс по одному экспонату"""
    conn = get_db_connection()
    cursor = conn.cursor()
    cursor.execute('''
        INSERT INTO user_progress (user_id, exhibit_id, is_viewed, is_favorite, points, visit_time)
        VALUES (%s, %s, %s, %s, %s, CURRENT_TIMESTAMP)
        ON CONFLICT (user_id, exhibit_id) 
        DO UPDATE SET 
            is_viewed = EXCLUDED.is_viewed OR user_progress.is_viewed,
            is_favorite = EXCLUDED.is_favorite OR user_progress.is_favorite,
            points = GREATEST(user_progress.points, EXCLUDED.points),
            visit_time = CURRENT_TIMESTAMP,
            updated_at = CURRENT_TIMESTAMP
    ''', (progress.user_id, progress.exhibit_id, progress.is_viewed, progress.is_favorite, progress.points))
    conn.commit()
    cursor.close()
    conn.close()
    return {"status": "success", "message": "Прогресс сохранен"}

@router.post("/progress/batch")
def update_progress_batch(progress_list: List[UserProgress]):
    """Массовое сохранение прогресса при выходе из сцены"""
    conn = get_db_connection()
    cursor = conn.cursor()
    
    for progress in progress_list:
        cursor.execute('''
            INSERT INTO user_progress (user_id, exhibit_id, is_viewed, is_favorite, points, visit_time)
            VALUES (%s, %s, %s, %s, %s, CURRENT_TIMESTAMP)
            ON CONFLICT (user_id, exhibit_id) 
            DO UPDATE SET 
                is_viewed = EXCLUDED.is_viewed OR user_progress.is_viewed,
                is_favorite = EXCLUDED.is_favorite OR user_progress.is_favorite,
                points = GREATEST(user_progress.points, EXCLUDED.points),
                visit_time = CURRENT_TIMESTAMP,
                updated_at = CURRENT_TIMESTAMP
        ''', (progress.user_id, progress.exhibit_id, progress.is_viewed, progress.is_favorite, progress.points))
    
    conn.commit()
    cursor.close()
    conn.close()
    return {"status": "success", "updated_count": len(progress_list)}

@router.get("/users/{user_id}/favorites")
def get_user_favorites(user_id: str):
    """Быстрый список ID экспонатов в избранном (для подсветки рамок при старте)"""
    conn = get_db_connection()
    cursor = conn.cursor(cursor_factory=RealDictCursor)
    cursor.execute("SELECT exhibit_id FROM user_progress WHERE user_id = %s AND is_favorite = true", (user_id,))
    favorites = cursor.fetchall()
    cursor.close()
    conn.close()
    
    return [row["exhibit_id"] for row in favorites]

# СПИСОК ПОЛЬЗОВАТЕЛЕЙ (экран выбора профиля в VR-меню)
@router.get("/users", response_model=List[dict])
def list_users():
    """Список всех пользователей с числом просмотренных картин (для MainMenu)"""
    conn = get_db_connection()
    cursor = conn.cursor(cursor_factory=RealDictCursor)
    cursor.execute('''
        SELECT
            u.user_id,
            u.username,
            u.total_points,
            u.last_visit,
            (SELECT COUNT(*) FROM user_progress p
             WHERE p.user_id = u.user_id AND p.is_viewed = true) AS viewed_count
        FROM users u
        ORDER BY u.last_visit DESC NULLS LAST
    ''')
    users = cursor.fetchall()
    cursor.close()
    conn.close()
    return [dict(u) for u in users]

# ПОЛЬЗОВАТЕЛИ
@router.post("/users/register")
def register_user(user_id: str, username: Optional[str] = None):
    """Регистрация нового пользователя или обновление существующего"""
    conn = get_db_connection()
    cursor = conn.cursor()
    cursor.execute('''
        INSERT INTO users (user_id, username, last_visit)
        VALUES (%s, %s, CURRENT_TIMESTAMP)
        ON CONFLICT (user_id) 
        DO UPDATE SET 
            username = EXCLUDED.username,
            last_visit = CURRENT_TIMESTAMP
    ''', (user_id, username))
    conn.commit()
    cursor.close()
    conn.close()
    return {"status": "success", "user_id": user_id}

@router.get("/users/{user_id}/exists")
def check_user_exists(user_id: str):
    """Проверить, существует ли пользователь"""
    conn = get_db_connection()
    cursor = conn.cursor(cursor_factory=RealDictCursor)
    cursor.execute("SELECT user_id, username FROM users WHERE user_id = %s", (user_id,))
    user = cursor.fetchone()
    cursor.close()
    conn.close()
    
    if user:
        return {"exists": True, "user_id": user["user_id"], "username": user["username"]}
    return {"exists": False}

# ВИКТОРИНА
@router.get("/quiz/questions")
def get_quiz_questions(exhibit_id: Optional[int] = None):
    """Получить вопросы для викторины"""
    conn = get_db_connection()
    cursor = conn.cursor(cursor_factory=RealDictCursor)
    
    if exhibit_id:
        cursor.execute("SELECT * FROM quiz_questions WHERE exhibit_id = %s", (exhibit_id,))
    else:
        cursor.execute("SELECT * FROM quiz_questions ORDER BY id")
    
    questions = cursor.fetchall()
    cursor.close()
    conn.close()
    return [dict(q) for q in questions]

@router.post("/quiz/answer")
def submit_quiz_answer(answer: QuizAnswer):
    """Проверить ответ и сохранить результат"""
    conn = get_db_connection()
    cursor = conn.cursor(cursor_factory=RealDictCursor)
    
    cursor.execute("SELECT correct_answer, points FROM quiz_questions WHERE id = %s", (answer.question_id,))
    question = cursor.fetchone()
    
    if not question:
        cursor.close()
        conn.close()
        raise HTTPException(status_code=404, detail="Вопрос не найден")
    
    is_correct = answer.selected_answer.upper() == question["correct_answer"]
    points_earned = question["points"] if is_correct else 0
    
    cursor.execute('''
        INSERT INTO quiz_results (user_id, question_id, selected_answer, is_correct, points_earned)
        VALUES (%s, %s, %s, %s, %s)
        ON CONFLICT (user_id, question_id) 
        DO UPDATE SET 
            selected_answer = EXCLUDED.selected_answer,
            is_correct = EXCLUDED.is_correct,
            points_earned = EXCLUDED.points_earned
    ''', (answer.user_id, answer.question_id, answer.selected_answer.upper(), is_correct, points_earned))
    
    if is_correct:
        cursor.execute('''
            UPDATE users SET total_points = total_points + %s WHERE user_id = %s
        ''', (points_earned, answer.user_id))
    
    conn.commit()
    cursor.close()
    conn.close()
    
    return {
        "is_correct": is_correct,
        "points_earned": points_earned,
        "correct_answer": question["correct_answer"]
    }

@router.get("/quiz/leaderboard")
def get_leaderboard(limit: int = 10):
    """Таблица лидеров"""
    conn = get_db_connection()
    cursor = conn.cursor(cursor_factory=RealDictCursor)
    cursor.execute('''
        SELECT user_id, username, total_points 
        FROM users 
        ORDER BY total_points DESC 
        LIMIT %s
    ''', (limit,))
    leaders = cursor.fetchall()
    cursor.close()
    conn.close()
    return [dict(u) for u in leaders]

@router.get("/quiz/user/{user_id}/stats")
def get_user_quiz_stats(user_id: str):
    """Статистика пользователя по викторине"""
    conn = get_db_connection()
    cursor = conn.cursor(cursor_factory=RealDictCursor)
    
    cursor.execute('''
        SELECT 
            COUNT(*) as total_answered,
            SUM(CASE WHEN is_correct THEN 1 ELSE 0 END) as correct_answers,
            SUM(points_earned) as total_quiz_points
        FROM quiz_results
        WHERE user_id = %s
    ''', (user_id,))
    
    stats = cursor.fetchone()
    cursor.close()
    conn.close()
    
    return {
        "user_id": user_id,
        "total_answered": stats["total_answered"] or 0,
        "correct_answers": stats["correct_answers"] or 0,
        "total_quiz_points": stats["total_quiz_points"] or 0
    }
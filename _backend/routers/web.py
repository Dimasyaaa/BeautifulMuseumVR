from fastapi import APIRouter, Request, Form, Depends
from fastapi.responses import HTMLResponse, RedirectResponse
from fastapi.templating import Jinja2Templates
import sys, os
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from database import get_db_connection
from psycopg2.extras import RealDictCursor

router = APIRouter(tags=["Web Admin"])
templates = Jinja2Templates(directory="templates")

# Dashboard
@router.get("/", response_class=HTMLResponse)
async def dashboard(request: Request):
    conn = get_db_connection()
    cursor = conn.cursor(cursor_factory=RealDictCursor)
    
    cursor.execute("SELECT COUNT(*) as total FROM exhibits")
    total_exhibits = cursor.fetchone()["total"]
    
    cursor.execute("SELECT COUNT(*) as total FROM users")
    total_users = cursor.fetchone()["total"]
    
    cursor.execute("SELECT COUNT(*) as total FROM user_progress WHERE is_viewed = true")
    total_views = cursor.fetchone()["total"]
    
    cursor.close()
    conn.close()
    
    return templates.TemplateResponse(
        request=request,
        name="dashboard.html",
        context={"total_exhibits": total_exhibits, "total_users": total_users, "total_views": total_views}
    )

# Список экспонатов
@router.get("/admin/exhibits", response_class=HTMLResponse)
async def list_exhibits(request: Request, category: str = "", search: str = ""):
    conn = get_db_connection()
    cursor = conn.cursor(cursor_factory=RealDictCursor)
    
    query = "SELECT * FROM exhibits WHERE 1=1"
    params = []
    if category:
        query += " AND category = %s"
        params.append(category)
    if search:
        query += " AND (title ILIKE %s OR author ILIKE %s)"
        params.extend([f"%{search}%", f"%{search}%"])
    
    query += " ORDER BY id DESC"
    cursor.execute(query, params)
    exhibits = cursor.fetchall()
    cursor.close()
    conn.close()
    
    return templates.TemplateResponse(
        request=request,
        name="exhibits.html",
        context={"exhibits": exhibits, "current_category": category, "current_search": search}
    )

# Форма добавления
@router.get("/admin/exhibits/new", response_class=HTMLResponse)
async def new_exhibit_form(request: Request):
    return templates.TemplateResponse(request=request, name="exhibit_form.html", context={"exhibit": None})

@router.post("/admin/exhibits/new")
async def create_exhibit(
    title: str = Form(...), author: str = Form(...), year: int = Form(...),
    description: str = Form(...), image_url: str = Form(...),
    audio_url: str = Form(""), category: str = Form("main_hall")
):
    conn = get_db_connection()
    cursor = conn.cursor()
    cursor.execute('''
        INSERT INTO exhibits (title, author, year, description, image_url, audio_url, category)
        VALUES (%s, %s, %s, %s, %s, %s, %s)
    ''', (title, author, year, description, image_url, audio_url, category))
    conn.commit()
    cursor.close()
    conn.close()
    return RedirectResponse(url="/admin/exhibits", status_code=303)

# Удаление экспоната
@router.post("/admin/exhibits/{exhibit_id}/delete")
async def delete_exhibit(exhibit_id: int):
    conn = get_db_connection()
    cursor = conn.cursor()
    cursor.execute("DELETE FROM exhibits WHERE id = %s", (exhibit_id,))
    conn.commit()
    cursor.close()
    conn.close()
    return RedirectResponse(url="/admin/exhibits", status_code=303)

# Редактирование экспоната 
@router.get("/admin/exhibits/{exhibit_id}/edit", response_class=HTMLResponse)
async def edit_exhibit_form(request: Request, exhibit_id: int):
    conn = get_db_connection()
    cursor = conn.cursor(cursor_factory=RealDictCursor)
    cursor.execute("SELECT * FROM exhibits WHERE id = %s", (exhibit_id,))
    exhibit = cursor.fetchone()
    cursor.close()
    conn.close()
    
    if not exhibit:
        return RedirectResponse(url="/admin/exhibits", status_code=303)
    
    return templates.TemplateResponse(
        request=request,
        name="exhibit_form.html",
        context={"exhibit": exhibit, "is_edit": True}
    )

@router.post("/admin/exhibits/{exhibit_id}/edit")
async def update_exhibit(
    exhibit_id: int,
    title: str = Form(...), author: str = Form(...), year: int = Form(...),
    description: str = Form(...), image_url: str = Form(...),
    audio_url: str = Form(""), category: str = Form("main_hall")
):
    conn = get_db_connection()
    cursor = conn.cursor()
    cursor.execute('''
        UPDATE exhibits 
        SET title=%s, author=%s, year=%s, description=%s, image_url=%s, audio_url=%s, category=%s
        WHERE id=%s
    ''', (title, author, year, description, image_url, audio_url, category, exhibit_id))
    conn.commit()
    cursor.close()
    conn.close()
    return RedirectResponse(url="/admin/exhibits", status_code=303)

# Страница пользователей
@router.get("/admin/users", response_class=HTMLResponse)
async def list_users(request: Request):
    conn = get_db_connection()
    cursor = conn.cursor(cursor_factory=RealDictCursor)
    
    cursor.execute('''
        SELECT 
            u.*,
            (SELECT COUNT(*) FROM user_progress WHERE user_id = u.user_id AND is_viewed = true) as total_views,
            (SELECT COUNT(*) FROM user_progress WHERE user_id = u.user_id AND is_favorite = true) as total_favorites
        FROM users u
        ORDER BY u.last_visit DESC
    ''')
    users = cursor.fetchall()
    
    cursor.close()
    conn.close()
    
    return templates.TemplateResponse(
        request=request,
        name="users.html",
        context={"users": users}
    )

@router.get("/admin/users/{user_id}/progress", response_class=HTMLResponse)
async def user_progress(request: Request, user_id: str, filter: str = ""):
    conn = get_db_connection()
    cursor = conn.cursor(cursor_factory=RealDictCursor)
    
    cursor.execute("SELECT * FROM users WHERE user_id = %s", (user_id,))
    user = cursor.fetchone()
    
    # Добавляем фильтр по избранному
    query = '''
        SELECT up.*, e.title, e.author, e.image_url
        FROM user_progress up
        JOIN exhibits e ON up.exhibit_id = e.id
        WHERE up.user_id = %s
    '''
    params = [user_id]
    
    if filter == 'favorites':
        query += " AND up.is_favorite = true"
        
    query += " ORDER BY up.visit_time DESC"
    
    cursor.execute(query, params)
    progress = cursor.fetchall()
    
    cursor.close()
    conn.close()
    
    return templates.TemplateResponse(
        request=request,
        name="user_progress.html",
        context={"user": user, "progress": progress}
    )

# Управление вопросами викторины
@router.get("/admin/quiz", response_class=HTMLResponse)
async def list_questions(request: Request):
    conn = get_db_connection()
    cursor = conn.cursor(cursor_factory=RealDictCursor)
    
    cursor.execute('''
        SELECT q.*, e.title as exhibit_title
        FROM quiz_questions q
        JOIN exhibits e ON q.exhibit_id = e.id
        ORDER BY q.id
    ''')
    questions = cursor.fetchall()
    
    cursor.execute("SELECT id, title FROM exhibits ORDER BY title")
    exhibits = cursor.fetchall()
    
    cursor.close()
    conn.close()
    
    return templates.TemplateResponse(
        request=request,
        name="quiz_questions.html",
        context={"questions": questions, "exhibits": exhibits}
    )

@router.post("/admin/quiz/new")
async def create_question(
    exhibit_id: int = Form(...),
    question: str = Form(...),
    option_a: str = Form(...),
    option_b: str = Form(...),
    option_c: str = Form(...),
    option_d: str = Form(...),
    correct_answer: str = Form(...),
    points: int = Form(10)
):
    conn = get_db_connection()
    cursor = conn.cursor()
    cursor.execute('''
        INSERT INTO quiz_questions (exhibit_id, question, option_a, option_b, option_c, option_d, correct_answer, points)
        VALUES (%s, %s, %s, %s, %s, %s, %s, %s)
    ''', (exhibit_id, question, option_a, option_b, option_c, option_d, correct_answer.upper(), points))
    conn.commit()
    cursor.close()
    conn.close()
    return RedirectResponse(url="/admin/quiz", status_code=303)

@router.post("/admin/quiz/{question_id}/delete")
async def delete_question(question_id: int):
    conn = get_db_connection()
    cursor = conn.cursor()
    cursor.execute("DELETE FROM quiz_questions WHERE id = %s", (question_id,))
    conn.commit()
    cursor.close()
    conn.close()
    return RedirectResponse(url="/admin/quiz", status_code=303)

# Таблица лидеров
@router.get("/admin/leaderboard", response_class=HTMLResponse)
async def leaderboard(request: Request):
    conn = get_db_connection()
    cursor = conn.cursor(cursor_factory=RealDictCursor)
    
    cursor.execute('''
        SELECT user_id, username, total_points, 
               (SELECT COUNT(*) FROM quiz_results WHERE user_id = u.user_id AND is_correct = true) as correct_answers
        FROM users u
        ORDER BY total_points DESC
    ''')
    leaders = cursor.fetchall()
    
    cursor.close()
    conn.close()
    
    return templates.TemplateResponse(
        request=request,
        name="leaderboard.html",
        context={"leaders": leaders}
    )

# --- Управление пользователями (CRUD) ---

@router.get("/admin/users/new", response_class=HTMLResponse)
async def new_user_form(request: Request):
    """Форма создания нового пользователя"""
    return templates.TemplateResponse(
        request=request,
        name="user_form.html",
        context={"user": None, "is_edit": False}
    )

@router.post("/admin/users/new")
async def create_user(
    user_id: str = Form(...),
    username: str = Form(""),
    total_points: int = Form(0)
):
    """Создание нового пользователя"""
    conn = get_db_connection()
    cursor = conn.cursor()
    cursor.execute('''
        INSERT INTO users (user_id, username, total_points, last_visit)
        VALUES (%s, %s, %s, CURRENT_TIMESTAMP)
        ON CONFLICT (user_id) DO NOTHING
    ''', (user_id, username if username else None, total_points))
    conn.commit()
    cursor.close()
    conn.close()
    return RedirectResponse(url="/admin/users", status_code=303)

@router.get("/admin/users/{user_id}/edit", response_class=HTMLResponse)
async def edit_user_form(request: Request, user_id: str):
    """Форма редактирования пользователя"""
    conn = get_db_connection()
    cursor = conn.cursor(cursor_factory=RealDictCursor)
    cursor.execute("SELECT * FROM users WHERE user_id = %s", (user_id,))
    user = cursor.fetchone()
    cursor.close()
    conn.close()
    
    if not user:
        return RedirectResponse(url="/admin/users", status_code=303)
    
    return templates.TemplateResponse(
        request=request,
        name="user_form.html",
        context={"user": user, "is_edit": True}
    )

@router.post("/admin/users/{user_id}/edit")
async def update_user(
    user_id: str,
    username: str = Form(""),
    total_points: int = Form(0)
):
    """Обновление данных пользователя"""
    conn = get_db_connection()
    cursor = conn.cursor()
    cursor.execute('''
        UPDATE users 
        SET username = %s, total_points = %s
        WHERE user_id = %s
    ''', (username if username else None, total_points, user_id))
    conn.commit()
    cursor.close()
    conn.close()
    return RedirectResponse(url="/admin/users", status_code=303)

@router.post("/admin/users/{user_id}/delete")
async def delete_user(user_id: str):
    """Удаление пользователя и всех связанных данных"""
    conn = get_db_connection()
    cursor = conn.cursor()
    # Удаляем связанные записи (прогресс и результаты викторин)
    cursor.execute("DELETE FROM quiz_results WHERE user_id = %s", (user_id,))
    cursor.execute("DELETE FROM user_progress WHERE user_id = %s", (user_id,))
    cursor.execute("DELETE FROM users WHERE user_id = %s", (user_id,))
    conn.commit()
    cursor.close()
    conn.close()
    return RedirectResponse(url="/admin/users", status_code=303)
    
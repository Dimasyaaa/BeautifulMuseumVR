from pydantic import BaseModel
from typing import Optional

# Схемы для Экспонатов
class ExhibitBase(BaseModel):
    title: str
    author: str
    year: int
    description: str
    image_url: str
    audio_url: Optional[str] = None
    category: str = "main_hall"

class ExhibitCreate(ExhibitBase):
    pass

class Exhibit(ExhibitBase):
    id: int

# Схемы для Прогресса (для Godot API)
class UserProgress(BaseModel):
    user_id: str
    exhibit_id: int
    is_viewed: bool = False
    is_favorite: bool = False
    points: int = 0
    
# Схемы для Викторины 
class QuizQuestion(BaseModel):
    id: Optional[int] = None
    exhibit_id: int
    question: str
    option_a: str
    option_b: str
    option_c: str
    option_d: str
    correct_answer: str
    points: int = 10

class QuizAnswer(BaseModel):
    user_id: str
    question_id: int
    selected_answer: str  # 'A', 'B', 'C' или 'D'
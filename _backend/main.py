from fastapi import FastAPI
from fastapi.staticfiles import StaticFiles
import os

# Импортируем роутеры
from routers import api, web

# Инициализация приложения
app = FastAPI(
    title="VR Museum Backend",
    description="API для VR-приложения и веб-админка для управления музеем"
)

# Подключаем статику
os.makedirs("static", exist_ok=True)
app.mount("/static", StaticFiles(directory="static"), name="static")

# Подключаем роутеры
app.include_router(api.router)
app.include_router(web.router)

if __name__ == "__main__":
    import uvicorn
    print("Запуск VR Museum Backend...")
    print("Веб-админка: https://richly-obsolete-removed.ngrok-free.dev/")
    print("API Документация: https://richly-obsolete-removed.ngrok-free.dev/docs")
    uvicorn.run("main:app", host="0.0.0.0", port=8000, reload=True)
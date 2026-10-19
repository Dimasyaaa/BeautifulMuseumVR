extends Node
## ApiClient — единая точка всех HTTP-запросов к бэкенду VR-музея.
## Автолоад. Использует пул HTTPRequest, чтобы можно было делать
## несколько одновременных запросов без конфликтов сигналов.
##
## Все методы асинхронные: await-ят сигнал request_completed и
## возвращают распарсенный результат (Dictionary/Array) или бросают
## ошибку через push_warning + возвращают null, чтобы приложение
## никогда не падало из-за сети.

signal request_failed(context: String, reason: String)

#const BASE_URL := "http://127.0.0.1:8000"
#const BASE_URL := "http://192.168.89.132:8000"
const BASE_URL := "https://richly-obsolete-removed.ngrok-free.dev"

var _pool: Array[HTTPRequest] = []


func _ready() -> void:
	# Создаём пул из нескольких HTTPRequest для параллельных запросов
	for i in 8:
		var http := HTTPRequest.new()
		http.name = "HTTPRequest_%d" % i
		add_child(http)
		_pool.append(http)


## Возвращает свободный HTTPRequest из пула.
func _get_free_http() -> HTTPRequest:
	for http in _pool:
		if not http.get_meta("busy", false):
			http.set_meta("busy", true)
			return http
	# Если все заняты — создаём ещё один на лету (редкий случай)
	var http := HTTPRequest.new()
	add_child(http)
	http.set_meta("busy", true)
	_pool.append(http)
	return http


## Освобождает HTTPRequest после завершения запроса.
func _release_http(http: HTTPRequest) -> void:
	http.set_meta("busy", false)


## Ядро: выполняет GET-запрос и возвращает распарсенный JSON (Variant).
## Возвращает null при ошибке (сеть/HTTP/JSON).
func _http_get(path: String, context: String = "") -> Variant:
	var http := _get_free_http()
	var url := BASE_URL + path
	var err := http.request(url)
	if err != OK:
		push_error("ApiClient: не удалось отправить GET %s (код %d)" % [url, err])
		_release_http(http)
		request_failed.emit(context, "request_error_%d" % err)
		return null

	var result: Array = await http.request_completed
	_release_http(http)

	var response_code: int = result[1]
	var body: PackedByteArray = result[3]
	if response_code != 200:
		push_warning("ApiClient: GET %s -> HTTP %d" % [url, response_code])
		request_failed.emit(context, "http_%d" % response_code)
		return null

	var parsed: Variant = _parse_json(body, context)
	return parsed


## Ядро: выполняет POST-запрос с JSON-телом и возвращает распарсенный ответ.
func _http_post(path: String, payload: Variant, context: String = "") -> Variant:
	var http := _get_free_http()
	var url := BASE_URL + path
	var headers := PackedStringArray(["Content-Type: application/json"])
	var body_text := JSON.stringify(payload)
	var err := http.request(url, headers, HTTPClient.METHOD_POST, body_text)
	if err != OK:
		push_error("ApiClient: не удалось отправить POST %s (код %d)" % [url, err])
		_release_http(http)
		request_failed.emit(context, "request_error_%d" % err)
		return null

	var result: Array = await http.request_completed
	_release_http(http)

	var response_code: int = result[1]
	var resp_body: PackedByteArray = result[3]
	if response_code < 200 or response_code >= 300:
		push_warning("ApiClient: POST %s -> HTTP %d" % [url, response_code])
		request_failed.emit(context, "http_%d" % response_code)
		return null

	var parsed: Variant = _parse_json(resp_body, context)
	return parsed


## Парсит JSON из буфера. При ошибке — предупреждение + null.
func _parse_json(body: PackedByteArray, context: String) -> Variant:
	if body.is_empty():
		return null
	var text := body.get_string_from_utf8()
	var parsed: Variant = JSON.parse_string(text)
	if parsed == null:
		push_warning("ApiClient: не удалось распарсить JSON (%s)" % context)
		request_failed.emit(context, "json_parse_error")
		return null
	return parsed


# ─────────────────────────────────────────────────────────────────
#  Публичные методы под конкретные эндпоинты
# ─────────────────────────────────────────────────────────────────

## GET /api/exhibits?category=...  → массив экспонатов (Array) или [].
func get_exhibits(category: String = "") -> Array:
	var path := "/api/exhibits"
	if category != "":
		path += "?category=" + category.uri_encode()
	var data: Variant = await _http_get(path, "get_exhibits")
	if data is Array:
		return data as Array
	push_warning("ApiClient.get_exhibits: ожидался массив, получено %s" % typeof(data))
	return []


## GET /api/users — все пользователи из БД (экран выбора профиля MainMenu).
## Каждый элемент: {user_id, username, total_points, last_visit, viewed_count}.
func get_users() -> Array:
	var data: Variant = await _http_get("/api/users", "get_users")
	if data is Array:
		return data as Array
	push_warning("ApiClient.get_users: ожидался массив, получено %s" % typeof(data))
	return []


## GET /api/exhibits/{id} — один экспонат для кнопки «Подробнее».
func get_exhibit(exhibit_id: int) -> Dictionary:
	var data: Variant = await _http_get("/api/exhibits/%d" % exhibit_id, "get_exhibit")
	if data is Dictionary:
		return data as Dictionary
	return {}


## POST /api/progress — сохранить прогресс по одному экспонату.
func post_progress(user_id: String, exhibit_id: int, is_viewed: bool, is_favorite: bool, points: int) -> bool:
	var payload := {
		"user_id": user_id,
		"exhibit_id": exhibit_id,
		"is_viewed": is_viewed,
		"is_favorite": is_favorite,
		"points": points,
	}
	var data: Variant = await _http_post("/api/progress", payload, "post_progress")
	return data != null


## POST /api/progress/batch — массовое сохранение при выходе.
## items: Array[Dictionary] с полями user_id/exhibit_id/is_viewed/is_favorite/points.
func post_progress_batch(items: Array) -> bool:
	var data: Variant = await _http_post("/api/progress/batch", items, "post_progress_batch")
	return data != null


## GET /api/users/{user_id}/favorites — список ID избранных (Array).
func get_favorites(user_id: String) -> Array:
	var data: Variant = await _http_get("/api/users/%s/favorites" % user_id.uri_encode(), "get_favorites")
	if data is Array:
		return data as Array
	return []


## POST /api/users/register?user_id=...&username=... (query-параметры).
func register_user(user_id: String, username: String) -> bool:
	var query := "?user_id=%s&username=%s" % [user_id.uri_encode(), username.uri_encode()]
	var data: Variant = await _http_post("/api/users/register" + query, {}, "register_user")
	return data != null


## GET /api/users/{user_id}/exists — проверить существование пользователя.
func user_exists(user_id: String) -> bool:
	var data: Variant = await _http_get("/api/users/%s/exists" % user_id.uri_encode(), "user_exists")
	if data is Dictionary and data.has("exists"):
		return bool(data["exists"])
	return false


## GET /api/quiz/questions?exhibit_id={id} — массив вопросов.
func get_quiz_questions(exhibit_id: int) -> Array:
	var data: Variant = await _http_get("/api/quiz/questions?exhibit_id=%d" % exhibit_id, "get_quiz_questions")
	if data is Array:
		return data as Array
	return []


## POST /api/quiz/answer — отправить ответ, вернуть ответ сервера (Dictionary).
func post_quiz_answer(user_id: String, question_id: int, selected_answer: String) -> Dictionary:
	var payload := {
		"user_id": user_id,
		"question_id": question_id,
		"selected_answer": selected_answer,
	}
	var data: Variant = await _http_post("/api/quiz/answer", payload, "post_quiz_answer")
	if data is Dictionary:
		return data as Dictionary
	return {}

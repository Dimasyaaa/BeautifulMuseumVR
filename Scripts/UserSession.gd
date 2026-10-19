extends Node
## UserSession — автолоад. Хранит текущего пользователя и переживает
## перезапуск приложения. user_id сохраняется в user://session.cfg
## (ConfigFile), поэтому «избранное» и прогресс подгружаются при
## следующем запуске.
##
## Логика первого запуска: если сохранённого user_id нет — генерируем
## его (pico_<timestamp>), регистрируем через ApiClient и сохраняем.

signal user_ready(user_id: String, username: String)

const SAVE_PATH := "user://session.cfg"
const SECTION := "session"
const KEY_USER_ID := "user_id"
const KEY_USERNAME := "username"

var user_id: String = ""
var username: String = ""
var is_registered: bool = false


func _ready() -> void:
	_load_or_create_user()


## Загружает пользователя из файла или создаёт нового при первом запуске.
func _load_or_create_user() -> void:
	var cfg := ConfigFile.new()
	var err := cfg.load(SAVE_PATH)
	if err == OK:
		user_id = cfg.get_value(SECTION, KEY_USER_ID, "")
		username = cfg.get_value(SECTION, KEY_USERNAME, "")

	if user_id != "":
		is_registered = true
		print("UserSession: загружен пользователь %s (%s)" % [user_id, username])
		user_ready.emit(user_id, username)
		return

	# Первый запуск — создаём пользователя-«гостя» с авто-ID.
	# Имя можно будет задать позже через экран ввода (name_entry).
	user_id = "pico_%d" % int(Time.get_unix_time_from_system())
	username = "Гость"
	_register_and_save(user_id, username)


## Регистрирует пользователя на сервере и сохраняет локально.
func _register_and_save(new_id: String, new_name: String) -> void:
	user_id = new_id
	username = new_name
	var ok: bool = await ApiClient.register_user(user_id, username)
	is_registered = ok  # даже если сервер недоступен, работаем офлайн с локальным ID
	if not ok:
		push_warning("UserSession: регистрация не удалась (сервер недоступен), работаем офлайн с ID %s" % user_id)
	_save()
	print("UserSession: пользователь готов %s (%s), сервер_ок=%s" % [user_id, username, ok])
	user_ready.emit(user_id, username)


## Сохраняет текущие user_id/username в файл.
func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value(SECTION, KEY_USER_ID, user_id)
	cfg.set_value(SECTION, KEY_USERNAME, username)
	var err := cfg.save(SAVE_PATH)
	if err != OK:
		push_error("UserSession: не удалось сохранить сессию (код %d)" % err)


## Публичный метод: установить/сменить пользователя (из экрана ввода имени).
func set_user(new_id: String, new_name: String) -> void:
	await _register_and_save(new_id, new_name)


## Меняет только отображаемое имя существующего пользователя.
func set_username(new_name: String) -> void:
	username = new_name
	await ApiClient.register_user(user_id, username)
	_save()

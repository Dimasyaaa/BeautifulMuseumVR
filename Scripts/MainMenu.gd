class_name MainMenu
extends CanvasLayer

## MainMenu — экран приветствия и выбора профиля. Главная сцена проекта.
##
## • Список профилей загружается из БД через ApiClient.get_users().
## • Выбор профиля сохраняется в UserSession (переживает перезапуск).
## • Панель справа сверху: текущий аккаунт и счётчик просмотренных картин.
## • Счётчик обновляется при каждом входе в меню (прогресс из БД).
## • Кнопка «Войти в музей» открывает зал (Scenes/main.tscn).
## • При достижении 13 из 13 картин — автоматически запускает викторину.

const MAIN_SCENE_PATH: String = "res://Scenes/main.tscn"
const FALLBACK_TOTAL_EXHIBITS: int = 13

@onready var _user_list: VBoxContainer = $Root/CenterArea/CenterBox/UserList
@onready var _status_label: Label = $Root/CenterArea/CenterBox/StatusLabel
@onready var _btn_enter: Button = $Root/CenterArea/CenterBox/BtnEnter
@onready var _lbl_account_name: Label = $Root/TopRightBox/AccountPanel/AccountBox/LblAccountName
@onready var _lbl_account_id: Label = $Root/TopRightBox/AccountPanel/AccountBox/LblAccountId
@onready var _lbl_counter: Label = $Root/TopRightBox/AccountPanel/AccountBox/LblCounter
@onready var _lbl_points: Label = $Root/TopRightBox/AccountPanel/AccountBox/LblPoints

var _users: Array[Dictionary] = []
var _buttons: Array[Button] = []
var _button_group: ButtonGroup = ButtonGroup.new()
var _total_exhibits: int = FALLBACK_TOTAL_EXHIBITS
var _selected_user_id: String = ""

func _ready() -> void:
	_btn_enter.disabled = true
	_btn_enter.pressed.connect(_on_enter_pressed)
	_update_account_panel()

	# UserSession мог ещё не завершить первую регистрацию — дожидаемся сигнала.
	if UserSession.user_id == "":
		UserSession.user_ready.connect(_on_user_ready, CONNECT_ONE_SHOT)

	_load_data()


func _on_user_ready(p_user_id: String, _p_username: String) -> void:
	_update_account_panel()
	_preselect_saved_user()


## Загружает список профилей и общее число экспонатов из БД.
func _load_data() -> void:
	_status_label.text = "Загрузка пользователей…"

	var raw_users: Array = await ApiClient.get_users()
	_users.clear()
	for item: Variant in raw_users:
		if item is Dictionary:
			_users.append(item as Dictionary)
	_rebuild_user_list()

	var exhibits: Array = await ApiClient.get_exhibits("")
	_total_exhibits = exhibits.size() if not exhibits.is_empty() else FALLBACK_TOTAL_EXHIBITS

	_update_account_panel()
	_preselect_saved_user()

	if _users.is_empty():
		_status_label.text = "Не удалось получить список. Сервер запущен?"
	else:
		_status_label.text = "Выберите профиль для входа"


## Пересобирает список кнопок-профилей.
func _rebuild_user_list() -> void:
	for btn: Button in _buttons:
		btn.queue_free()
	_buttons.clear()

	for user: Dictionary in _users:
		var uid: String = str(user.get("user_id", ""))
		var uname: String = str(user.get("username", "Без имени"))
		var points: int = int(user.get("total_points", 0))

		var btn := Button.new()
		btn.text = "%s   ·   очков: %d" % [uname, points]
		btn.toggle_mode = true
		btn.button_group = _button_group
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.custom_minimum_size = Vector2(0.0, 56.0)
		btn.pressed.connect(_on_user_pressed.bind(uid))
		_user_list.add_child(btn)
		_buttons.append(btn)


## Выбор профиля: сохраняем в UserSession и обновляем панель аккаунта.
func _on_user_pressed(p_user_id: String) -> void:
	_selected_user_id = p_user_id
	var user: Dictionary = _find_user(p_user_id)
	var uname: String = str(user.get("username", ""))
	_status_label.text = "Вход в профиль «%s»…" % uname

	await UserSession.set_user(p_user_id, uname)

	_update_account_panel()
	_btn_enter.disabled = false
	_status_label.text = "Профиль выбран: %s" % uname


## Предвыделяет ранее сохранённый профиль (если он есть в списке).
func _preselect_saved_user() -> void:
	if UserSession.user_id == "":
		return
	for i: int in _buttons.size():
		if i >= _users.size():
			break
		if str(_users[i].get("user_id", "")) == UserSession.user_id:
			_buttons[i].button_pressed = true
			_selected_user_id = UserSession.user_id
			_btn_enter.disabled = false
			return


## Обновляет данные в панели аккаунта (правый верхний угол).
func _update_account_panel() -> void:
	_lbl_account_name.text = UserSession.username if UserSession.username != "" else "Гость"
	_lbl_account_id.text = UserSession.user_id if UserSession.user_id != "" else "—"

	var user: Dictionary = _find_user(UserSession.user_id)
	var viewed: int = int(user.get("viewed_count", 0))
	var points: int = int(user.get("total_points", 0))

	_lbl_counter.text = "Картин: %d из %d" % [viewed, _total_exhibits]
	_lbl_points.text = "Баллы: %d" % points
	if _total_exhibits > 0 and viewed >= _total_exhibits:
		_lbl_counter.text += "  ✅"


## Переход в зал.
func _on_enter_pressed() -> void:
	if UserSession.user_id == "":
		_status_label.text = "Сначала выберите профиль"
		return

	_status_label.text = "Загрузка музея…"
	_btn_enter.disabled = true
	var err: Error = get_tree().change_scene_to_file(MAIN_SCENE_PATH)
	if err != OK:
		_status_label.text = "Ошибка запуска сцены (код %d)" % err
		_btn_enter.disabled = false


## Возвращает словарь пользователя или пустой словарь.
func _find_user(p_user_id: String) -> Dictionary:
	if p_user_id == "":
		return {}
	for user: Dictionary in _users:
		if str(user.get("user_id", "")) == p_user_id:
			return user
	return {}

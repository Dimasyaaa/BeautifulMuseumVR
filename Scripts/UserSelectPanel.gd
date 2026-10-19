class_name UserSelectPanel
extends Node3D

## Панель выбора профиля перед лицом игрока (дочь XRCamera3D).
## Появляется при старте, скрывается после выбора профиля из БД.
## Взаимодействие — тот же механизм, что у InfoStand: VRButton + луч контроллера.

@onready var _title: Label3D = $Plate/TitleLabel
@onready var _status: Label3D = $Plate/StatusLabel

var _users: Array[Dictionary] = []
var _buttons: Array[VRButton] = []
var _selected: bool = false

const MAX_BUTTONS: int = 6


func _ready() -> void:
	visible = true
	_load_users()


## Загружает список профилей из БД и строит кнопки.
func _load_users() -> void:
	_status.text = "Загрузка профилей…"

	var raw: Array = await ApiClient.get_users()
	_users.clear()
	for item: Variant in raw:
		if item is Dictionary:
			_users.append(item as Dictionary)

	_rebuild_buttons()

	if _users.is_empty():
		_status.text = "Сервер недоступен. Запустите бэкенд."
	else:
		_status.text = "Наведите луч и нажмите trigger"


## Пересобирает список кнопок-профилей.
func _rebuild_buttons() -> void:
	for btn: VRButton in _buttons:
		btn.queue_free()
	_buttons.clear()

	var count: int = mini(_users.size(), MAX_BUTTONS)
	for i: int in count:
		var user: Dictionary = _users[i]
		var uname: String = str(user.get("username", "Без имени"))
		var points: int = int(user.get("total_points", 0))

		var btn := VRButton.new()
		btn.name = "BtnUser%d" % i
		btn.label_text = "%s   ·   очков: %d" % [uname, points]
		btn.button_size = Vector3(0.8, 0.09, 0.03)
		btn.body_color = Color(0.15, 0.3, 0.25)
		btn.hover_color = Color(0.3, 0.8, 0.55)
		btn.position = Vector3(0.0, 0.3 - i * 0.13, 0.02)
		btn.pressed.connect(_on_user_pressed.bind(str(user.get("user_id", "")), uname))
		$Plate.add_child(btn)
		_buttons.append(btn)


## Выбор профиля: сохраняем в UserSession и прячем панель.
func _on_user_pressed(p_user_id: String, p_username: String) -> void:
	if _selected:
		return
	_selected = true
	_status.text = "Вход в профиль «%s»…" % p_username

	await UserSession.set_user(p_user_id, p_username)
	_hide_panel()


## Скрывает панель и отключает коллизии кнопок, чтобы не перехватывали луч.
func _hide_panel() -> void:
	_set_collisions_active(self, false)
	visible = false
	print("UserSelectPanel: профиль выбран (%s), панель скрыта" % UserSession.user_id)


## Рекурсивно включает/выключает коллизии всех Area3D внутри панели.
func _set_collisions_active(node: Node, active: bool) -> void:
	if node is Area3D:
		node.set_deferred("monitoring", active)
		node.set_deferred("monitorable", active)
	for child: Node in node.get_children():
		_set_collisions_active(child, active)

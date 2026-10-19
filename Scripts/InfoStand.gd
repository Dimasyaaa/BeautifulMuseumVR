class_name InfoStand
extends Node3D

## Сигналы для внешней логики (если потребуется)
signal load_pressed()
signal details_pressed()
signal favorite_pressed()
signal listen_pressed()

# Ссылки на элементы интерфейса (инициализируются в _ready)
var _title: Label3D = null
var _meta: Label3D = null
var _status: Label3D = null
var _description: Label3D = null

# Ссылки на кнопки (предполагается использование класса VRButton)
var _btn_load: VRButton = null
var _btn_details: VRButton = null
var _btn_favorite: VRButton = null
var _btn_listen: VRButton = null

## Данные текущего экспоната
var _exhibit: Dictionary = {}
## Привязанная рама (ExhibitFrame)
var _frame: Node = null
var _description_open: bool = false

func _ready() -> void:
	# Рекурсивный поиск меток. Это надежнее жестких путей, 
	# так как работает при любом уровне вложенности внутри InfoStand.
	_title = _find_label("TitleLabel")
	_meta = _find_label("MetaLabel")
	_status = _find_label("StatusLabel")
	_description = _find_label("DescriptionLabel")

	# Поиск и подключение кнопок
	_btn_load = _find_button("BtnLoad")
	if _btn_load and _btn_load.has_signal("pressed"):
		_btn_load.pressed.connect(_on_load_pressed)

	_btn_details = _find_button("BtnDetails")
	if _btn_details and _btn_details.has_signal("pressed"):
		_btn_details.pressed.connect(_on_details_pressed)

	_btn_favorite = _find_button("BtnFavorite")
	if _btn_favorite and _btn_favorite.has_signal("pressed"):
		_btn_favorite.pressed.connect(_on_favorite_pressed)

	_btn_listen = _find_button("BtnListen")
	if _btn_listen and _btn_listen.has_signal("pressed"):
		_btn_listen.pressed.connect(_on_listen_pressed)
		
	# Скрываем описание при старте
	set_description_visible(false)

# ─────────────────────────────────────────────────────────────────
# Публичный интерфейс (вызывается из ExhibitFrame)
# ─────────────────────────────────────────────────────────────────

## Сохраняет данные экспоната и сбрасывает состояние описания
func set_exhibit_data(data: Dictionary) -> void:
	_exhibit = data
	_description_open = false
	set_description_visible(false)

func set_title(text: String) -> void:
	if _title: _title.text = text

func set_meta_text(text: String) -> void:
	if _meta: _meta.text = text

func set_status(text: String) -> void:
	if _status: _status.text = text

func set_favorite_highlight(active: bool) -> void:
	if _btn_favorite and _btn_favorite.has_method("set_favorite_style"):
		_btn_favorite.set_favorite_style(active)

func set_listen_visible(show: bool) -> void:
	if _btn_listen: _btn_listen.visible = show

## Устанавливает связь с конкретной рамой
func bind_frame(frame: Node) -> void:
	_frame = frame

# ─────────────────────────────────────────────────────────────────
# Обработчики кнопок (делегирование действий раме)
# ─────────────────────────────────────────────────────────────────

func _on_load_pressed() -> void:
	load_pressed.emit()
	if _frame != null and _frame.has_method("on_load_pressed"):
		_frame.on_load_pressed()

func _on_details_pressed() -> void:
	details_pressed.emit()
	if _exhibit.is_empty():
		set_status("Экспонат не задан")
		return
		
	_description_open = not _description_open
	set_description_visible(_description_open)
	set_status("Описание показано" if _description_open else "Описание скрыто")

func _on_favorite_pressed() -> void:
	favorite_pressed.emit()
	if _frame != null and _frame.has_method("on_favorite_pressed"):
		_frame.on_favorite_pressed()

func _on_listen_pressed() -> void:
	listen_pressed.emit()
	if _frame != null and _frame.has_method("on_listen_pressed"):
		_frame.on_listen_pressed()

# ─────────────────────────────────────────────────────────────────
# Внутренняя логика отображения
# ─────────────────────────────────────────────────────────────────

func set_description_visible(show: bool) -> void:
	if _description == null:
		return
		
	if show:
		_description.text = str(_exhibit.get("description", "Описание отсутствует"))
	else:
		_description.text = ""
		
	_description.visible = show

# ─────────────────────────────────────────────────────────────────
# Утилиты поиска (рекурсивный обход дочерних узлов)
# ─────────────────────────────────────────────────────────────────

func _find_label(node_name: String) -> Label3D:
	var n: Node = _find_node_by_name(self, node_name)
	return n as Label3D

func _find_button(node_name: String) -> VRButton:
	var n: Node = _find_node_by_name(self, node_name)
	return n as VRButton

func _find_node_by_name(root: Node, node_name: String) -> Node:
	if root.name == node_name:
		return root
		
	for child in root.get_children():
		var found: Node = _find_node_by_name(child, node_name)
		if found != null:
			return found
			
	return null

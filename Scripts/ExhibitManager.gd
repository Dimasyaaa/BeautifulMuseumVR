extends Node3D

## Категория экспонатов этого зала (должна совпадать с БД: main_hall или second_hall)
@export var hall_category: String = "main_hall"

## Опциональный контейнер для рам (если пусто — ищем во всей сцене)
@export var frames_container: NodePath = NodePath("")

var _frames: Array[ExhibitFrame] = []
var _loaded: bool = false

func _ready() -> void:
	# Собираем все рамы (сначала из группы, потом рекурсивно как fallback)
	_collect_frames()
	
	# Ждем инициализации пользователя
	if UserSession.user_id == "":
		await UserSession.user_ready
	
	# Загружаем экспозицию
	_load_hall()

func _notification(what: int) -> void:
	# Массовое сохранение прогресса при выходе
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_EXIT_TREE:
		_save_all_progress()

## Сбор всех рам ExhibitFrame из сцены
func _collect_frames() -> void:
	_frames.clear()
	
	# Метод 1: Ищем в группе exhibit_frames (если добавлены)
	var group_frames: Array = get_tree().get_nodes_in_group("exhibit_frames")
	for node in group_frames:
		if node is ExhibitFrame:
			_frames.append(node as ExhibitFrame)
	
	# Метод 2: Если группа пуста, делаем рекурсивный поиск по сцене
	if _frames.is_empty():
		print("ExhibitManager[%s]: группа exhibit_frames пуста, используем рекурсивный поиск" % name)
		var root: Node = self
		if frames_container != NodePath(""):
			root = get_node(frames_container)
		_scan_for_frames(root)
	
	print("ExhibitManager[%s]: найдено рам: %d" % [name, _frames.size()])

## Рекурсивный поиск рам в дереве сцены
func _scan_for_frames(node: Node) -> void:
	if node is ExhibitFrame:
		_frames.append(node as ExhibitFrame)
	for child in node.get_children():
		_scan_for_frames(child)

## Основная логика загрузки зала
func _load_hall() -> void:
	if _loaded:
		return
	_loaded = true

	# 1. Получаем список избранных экспонатов пользователя
	var favorites: Array = []
	if UserSession.user_id != "":
		favorites = await ApiClient.get_favorites(UserSession.user_id)
	
	var fav_set: Dictionary = {}
	for f in favorites:
		fav_set[int(f)] = true

	# 2. Загружаем экспонаты для этой категории
	var exhibits: Array = await ApiClient.get_exhibits(hall_category)
	if exhibits.is_empty():
		push_warning("ExhibitManager[%s]: экспонаты не получены (категория=%s). Проверь, запущен ли бэкенд." % [name, hall_category])
		return

	# 3. Распределяем экспонаты по рамам
	var count: int = min(_frames.size(), exhibits.size())
	for i in count:
		var frame: ExhibitFrame = _frames[i]
		var ex: Dictionary = exhibits[i]
		var eid: int = int(ex.get("id", 0))
		frame.setup_exhibit(ex, fav_set.has(eid))
	
	print("ExhibitManager[%s]: раздано экспонатов по рамам: %d из %d рам" % [name, count, _frames.size()])

## Вызывается главной кнопкой "Загрузить экспозицию"
func load_all_exhibits() -> void:
	print("ExhibitManager[%s]: запуск массовой загрузки экспонатов" % name)
	for frame in _frames:
		frame.on_load_pressed()

## Массовое сохранение прогресса всех рам
func _save_all_progress() -> void:
	if not _loaded or UserSession.user_id == "":
		return
	
	var items: Array = []
	for frame in _frames:
		var payload: Dictionary = frame.get_progress_payload(UserSession.user_id)
		if not payload.is_empty() and (payload["is_viewed"] or payload["is_favorite"]):
			items.append(payload)
	
	if items.is_empty():
		return
	
	ApiClient.post_progress_batch(items)
	print("ExhibitManager[%s]: batch-сохранение %d записей" % [name, items.size()])

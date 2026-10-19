class_name QuizPanel
extends Node3D

## Панель викторины перед лицом игрока (дочь XRCamera3D).
## Скрыта при старте. Как только просмотрены ВСЕ картины музея (13 из 13) —
## сама показывает вопросы из БД по очереди (VRButton + луч контроллера,
## тот же механизм, что у InfoStand).

signal quiz_finished

const TOTAL_FALLBACK: int = 13
@onready var _question_label: Label3D = $Plate/QuestionLabel
@onready var _result_label: Label3D = $Plate/ResultLabel
@onready var _buttons: Array[VRButton] = [$Plate/BtnA, $Plate/BtnB, $Plate/BtnC, $Plate/BtnD]

var _questions: Array[Dictionary] = []
var _current: int = -1
var _viewed_ids: Dictionary = {}
var _total: int = TOTAL_FALLBACK
var _quiz_started: bool = false
var _waiting: bool = false


func _ready() -> void:
	visible = false
	_set_buttons_clickable(false)

	var letters: Array[String] = ["A", "B", "C", "D"]
	for i: int in _buttons.size():
		_buttons[i].pressed.connect(_on_answer_pressed.bind(letters[i]))

	_connect_frames.call_deferred()

	# Общее число экспонатов из БД (fallback — 13)
	var exhibits: Array = await ApiClient.get_exhibits("")
	if not exhibits.is_empty():
		_total = exhibits.size()


## Подписывается на сигнал загрузки всех рам-экспонатов в сцене.
func _connect_frames() -> void:
	var root: Node = get_tree().current_scene
	if root == null:
		root = get_tree().root
	var frames: Array[ExhibitFrame] = _collect_frames(root)
	for frame: ExhibitFrame in frames:
		frame.exhibit_loaded.connect(_on_exhibit_loaded)
	print("QuizPanel: подключено к %d рамам" % frames.size())


## Рекурсивный поиск всех ExhibitFrame.
func _collect_frames(node: Node) -> Array[ExhibitFrame]:
	var out: Array[ExhibitFrame] = []
	if node is ExhibitFrame:
		out.append(node as ExhibitFrame)
	for child: Node in node.get_children():
		out.append_array(_collect_frames(child))
	return out


## Картина просмотрена — обновляем счётчик, при 100% запускаем викторину.
func _on_exhibit_loaded(exhibit_id: int) -> void:
	if _quiz_started:
		return
	_viewed_ids[exhibit_id] = true
	print("QuizPanel: просмотрено %d из %d" % [_viewed_ids.size(), _total])
	if _viewed_ids.size() >= _total:
		start_quiz()


## Запуск викторины: тянем все вопросы из БД и показываем по очереди.
func start_quiz() -> void:
	if _quiz_started:
		return
	_quiz_started = true

	visible = true
	_question_label.text = "Загрузка викторины…"
	_result_label.text = ""
	_set_buttons_clickable(false)

	_questions.clear()
	var raw: Array = await ApiClient.get_quiz_questions(0)
	for item: Variant in raw:
		if item is Dictionary:
			_questions.append(item as Dictionary)

	if _questions.is_empty():
		_question_label.text = "Вопросы не загружены.\nПроверьте сервер и БД."
		await get_tree().create_timer(3.0).timeout
		visible = false
		return

	_current = -1
	_show_next_question()


## Показывает следующий вопрос или завершает викторину.
func _show_next_question() -> void:
	_current += 1
	if _current >= _questions.size():
		_finish_quiz()
		return

	var q: Dictionary = _questions[_current]
	_question_label.text = "Вопрос %d/%d\n\n%s" % [_current + 1, _questions.size(), str(q.get("question", ""))]

	var options: Array[String] = [
		str(q.get("option_a", "")),
		str(q.get("option_b", "")),
		str(q.get("option_c", "")),
		str(q.get("option_d", "")),
	]
	for i: int in _buttons.size():
		_set_btn_text(_buttons[i], "%s) %s" % ["ABCD"[i], options[i]])

	_waiting = false
	_set_buttons_clickable(true)


## Обработчик нажатия кнопки-ответа: отправляем на сервер, показываем результат.
func _on_answer_pressed(letter: String) -> void:
	if _waiting or _current < 0 or _current >= _questions.size():
		return
	_waiting = true
	_set_buttons_clickable(false)

	var q: Dictionary = _questions[_current]
	var resp: Dictionary = await ApiClient.post_quiz_answer(
		UserSession.user_id, int(q.get("id", 0)), letter)

	if resp.is_empty():
		_result_label.text = "Ошибка связи с сервером"
	else:
		var correct: bool = bool(resp.get("is_correct", false))
		var pts: int = int(resp.get("points_earned", 0))
		if correct:
			_result_label.text = "Верно! +%d баллов" % pts
		else:
			_result_label.text = "Неверно. Правильный ответ: %s" % str(resp.get("correct_answer", "?"))

	await get_tree().create_timer(2.5).timeout
	_result_label.text = ""
	_show_next_question()


## Финал викторины.
func _finish_quiz() -> void:
	_question_label.text = "Викторина завершена!\nСпасибо за участие."
	quiz_finished.emit()
	await get_tree().create_timer(3.0).timeout
	visible = false


## Включает/выключает кликабельность кнопок (через коллизии Area3D).
func _set_buttons_clickable(active: bool) -> void:
	for btn: VRButton in _buttons:
		btn.set_deferred("monitoring", active)
		btn.set_deferred("monitorable", active)


## Меняет текст на кнопке с переносом длинных вариантов.
func _set_btn_text(btn: VRButton, text: String) -> void:
	var lbl := btn.get_node_or_null("Label") as Label3D
	if lbl:
		lbl.text = text
		lbl.pixel_size = 0.0009
		lbl.width = 950.0
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

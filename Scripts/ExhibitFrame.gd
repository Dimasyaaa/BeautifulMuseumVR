class_name ExhibitFrame
extends Node3D

signal status_changed(text: String)
signal exhibit_loaded(exhibit_id: int)

@export var exhibit_index: int = 0
@export var force_exhibit_id: int = 0

var exhibit: Dictionary = {}
var _canvas: Node3D = null
var _info_panel: InfoStand = null
var _is_favorite: bool = false
var _is_loaded: bool = false
var _http: HTTPRequest = null
var _frame_mat: StandardMaterial3D = null
var _pending_request_type: String = "image"
var _is_requesting: bool = false

const REQUEST_USER_AGENT: String = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"
const REQUEST_ACCEPT: String = "image/avif,image/webp,image/apng,image/*,*/*;q=0.8"

func _ready() -> void:
	_canvas = get_node_or_null("Canvas")
	if _canvas == null:
		_canvas = _find_node_by_name(self, "Canvas")
		if _canvas == null:
			push_error("ExhibitFrame: Не найден узел 'Canvas' в %s" % name)

	_info_panel = get_node_or_null("InfoStand") as InfoStand
	if _info_panel != null:
		_info_panel.bind_frame(self)

	status_changed.connect(_on_status_changed)

	_http = HTTPRequest.new()
	_http.timeout = 30.0
	add_child(_http)
	_http.request_completed.connect(_on_http_completed)

func setup_exhibit(exhibit_data: Dictionary, favorite: bool) -> void:
	exhibit = exhibit_data
	_is_favorite = favorite
	_is_loaded = false
	
	if _info_panel and not exhibit.is_empty():
		_info_panel.set_exhibit_data(exhibit)
		var yr: Variant = exhibit.get("year", "")
		var yr_str: String = str(int(yr)) if (yr is float or yr is int) else str(yr)
		_info_panel.set_title(str(exhibit.get("title", "")))
		_info_panel.set_meta_text("%s, %s" % [str(exhibit.get("author", "")), yr_str])
		_info_panel.set_favorite_highlight(_is_favorite)

func on_load_pressed() -> void:
	if _canvas == null or exhibit.is_empty() or _is_loaded:
		return
	
	var url: String = str(exhibit.get("image_url", ""))
	if url == "":
		if _info_panel: _info_panel.set_status("Нет URL")
		return
	
	if _is_requesting:
		return
	
	if _info_panel: _info_panel.set_status("Загрузка…")
	
	var headers := PackedStringArray([
		"User-Agent: " + REQUEST_USER_AGENT,
		"Accept: " + REQUEST_ACCEPT,
		"ngrok-skip-browser-warning: true"
	])
	
	_pending_request_type = "image"
	_is_requesting = true
	var err: int = _http.request(url, headers, HTTPClient.METHOD_GET, "")
	if err != OK:
		_is_requesting = false
		if _info_panel: _info_panel.set_status("Ошибка сети")

func on_listen_pressed() -> void:
	var url: String = str(exhibit.get("audio_url", ""))
	if url == "":
		if _info_panel: _info_panel.set_status("Аудио недоступно")
		return
	
	if _is_requesting:
		return
		
	if _info_panel: _info_panel.set_status("Загрузка аудио…")
	
	_pending_request_type = "audio"
	_is_requesting = true
	var headers := PackedStringArray([
		"User-Agent: " + REQUEST_USER_AGENT,
		"ngrok-skip-browser-warning: true"
	])
	
	var err: int = _http.request(url, headers, HTTPClient.METHOD_GET, "")
	if err != OK:
		_is_requesting = false
		if _info_panel: _info_panel.set_status("Ошибка сети")
		_pending_request_type = "image"

func _on_http_completed(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
	_is_requesting = false
	
	if _pending_request_type == "audio":
		_pending_request_type = "image"
		_handle_audio_body(result, response_code, body)
		return

	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		if _info_panel: _info_panel.set_status("Ошибка загрузки")
		return
	
	var image: Image = await _decode_image(body)
	if image == null:
		if _info_panel: _info_panel.set_status("Ошибка формата")
		return
	
	image.flip_y()
	var tex: Texture2D = ImageTexture.create_from_image(image)
	_apply_texture(tex)
	
	_is_loaded = true
	if _info_panel: _info_panel.set_status("Загружено")
	_mark_viewed()

func _handle_audio_body(result: int, response_code: int, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		if _info_panel: _info_panel.set_status("Ошибка аудио")
		return
	
	var stream := await _decode_audio_stream(body)
	if stream == null:
		push_warning("Не удалось декодировать аудиофайл")
		if _info_panel: _info_panel.set_status("Ошибка формата аудио")
		return
	
	var player := AudioStreamPlayer3D.new()
	player.name = "AudioGuidePlayer"
	add_child(player)
	
	player.stream = stream
	player.unit_size = 5.0
	player.volume_db = 0.0
	player.play()
	
	if _info_panel: _info_panel.set_status("Воспроизведение...")
	
	player.finished.connect(func(): 
		player.queue_free()
		if _info_panel: _info_panel.set_status("Готово")
	)

func _decode_audio_stream(data: PackedByteArray) -> AudioStream:
	var stream_mp3 = AudioStreamMP3.new()
	stream_mp3.data = data
	
	if stream_mp3.data.size() > 0:
		return stream_mp3
		
	var unique_id = str(Time.get_ticks_msec())
	var temp_path = "user://temp_audio_" + unique_id + ".mp3"
	
	var file = FileAccess.open(temp_path, FileAccess.WRITE)
	if file:
		file.store_buffer(data)
		file.close()
		await get_tree().process_frame 
		
		var loaded_stream = ResourceLoader.load(temp_path)
		if loaded_stream and loaded_stream is AudioStream:
			return loaded_stream
			
	push_warning("Все способы декодирования аудио провалились")
	return null

func _decode_image(body: PackedByteArray) -> Image:
	if body.size() < 12:
		push_warning("Слишком маленький размер файла: " + str(body.size()) + " байт")
		return null
	
	if body.size() < 10000:
		push_warning("Подозрительно маленький файл (" + str(body.size()) + " байт). Возможно, это HTML-страница ошибки.")
		var text_content = body.get_string_from_utf8()
		if text_content.begins_with("<!DOCTYPE") or text_content.begins_with("<html"):
			push_warning("ПОДТВЕРЖДЕНО: Получена HTML-страница вместо картинки!")
		return null

	var image: Image = Image.new()
	
	if image.load_jpg_from_buffer(body) == OK:
		return image
	
	image = Image.new()
	if image.load_png_from_buffer(body) == OK:
		return image
	
	image = Image.new()
	if image.load_webp_from_buffer(body) == OK:
		return image

	push_warning("Прямая загрузка из буфера не сработала, пробуем через файл...")
	
	var unique_id = str(Time.get_ticks_msec())
	var temp_path = "user://temp_image_" + unique_id + ".jpg"
	
	var file = FileAccess.open(temp_path, FileAccess.WRITE)
	if file:
		file.store_buffer(body)
		file.close()
		
		await get_tree().process_frame
		
		var img2: Image = Image.new()
		if img2.load(temp_path) == OK:
			push_warning("Успешно загружено через Image.load()!")
			return img2
	
	push_warning("Все способы декодирования изображения провалились. Размер: " + str(body.size()) + " байт")
	return null

func _apply_texture(tex: Texture2D) -> void:
	if _frame_mat == null:
		_frame_mat = StandardMaterial3D.new()
		
	_frame_mat.albedo_texture = tex
	_frame_mat.albedo_color = Color(1, 1, 1, 1)
	_frame_mat.roughness = 0.5
	_frame_mat.metallic = 0.0
	_frame_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_frame_mat.vertex_color_use_as_albedo = false

	if _canvas is MeshInstance3D:
		_canvas.material_override = _frame_mat
	elif _canvas is Sprite3D:
		_canvas.texture = tex
		_canvas.material_override = _frame_mat

func on_favorite_pressed() -> void:
	if exhibit.is_empty(): return
	
	_is_favorite = not _is_favorite
	if _info_panel:
		_info_panel.set_status("В избранном" if _is_favorite else "Убрано")
		_info_panel.set_favorite_highlight(_is_favorite)
		
	var eid: int = exhibit.get("id", 0)
	if eid > 0 and UserSession.user_id != "":
		ApiClient.post_progress(UserSession.user_id, eid, _is_loaded, _is_favorite, 0)
	
	if _frame_mat != null and _is_loaded:
		_frame_mat.emission_enabled = _is_favorite
		_frame_mat.emission = Color(1.0, 0.85, 0.4) if _is_favorite else Color.BLACK
		_frame_mat.emission_energy = 0.3 if _is_favorite else 0.0

func _mark_viewed() -> void:
	var eid: int = exhibit.get("id", 0)
	if eid > 0 and UserSession.user_id != "":
		ApiClient.post_progress(UserSession.user_id, eid, true, _is_favorite, 0)
	if eid > 0:
		exhibit_loaded.emit(eid)

func _on_status_changed(text: String) -> void:
	if _info_panel:
		_info_panel.set_status(text)

func _find_node_by_name(root: Node, node_name: String) -> Node:
	if root.name == node_name: return root
	for child in root.get_children():
		var found: Node = _find_node_by_name(child, node_name)
		if found != null: return found
	return null

func get_progress_payload(user_id: String) -> Dictionary:
	var eid: int = exhibit.get("id", 0)
	if eid <= 0: return {}
	return {
		"user_id": user_id,
		"exhibit_id": eid,
		"is_viewed": _is_loaded,
		"is_favorite": _is_favorite,
		"points": 0
	}

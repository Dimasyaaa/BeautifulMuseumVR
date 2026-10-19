class_name VRButton
extends Area3D
## VRButton — VR-кнопка на Area3D, автономная.
##
## При добавлении в сцену (script = VRButton.gd) в _ready() сама создаёт:
##   • CollisionShape3D (BoxShape под button_size) на слое 21 (pointable);
##   • ButtonMesh — видимую плиту-кнопку;
##   • Label3D "Label" — подпись из label_text.
##
## Ловит события указателя от луча контроллера (XRToolsFunctionPointer):
## при наведении — подсветка, при нажатии триггера — сигнал pressed().
##
## Настройки задаются в инспекторе (authoring-friendly): button_size, label_text,
## body_color, hover_color.

signal pressed()

@export var label_text: String = "OK"
@export var button_size: Vector3 = Vector3(0.30, 0.07, 0.035)
@export var body_color: Color = Color(0.18, 0.22, 0.28)
@export var hover_color: Color = Color(0.35, 0.65, 0.9)

var _hovered: bool = false
var _mesh: MeshInstance3D = null


func _ready() -> void:
	# Слой 21 = "pointable" в godot-xr-tools; луч контроллера слушает его (collision_mask bit 21).
	collision_layer = 1 << 20
	collision_mask = 0

	# Коллизия (если не задана вручную)
	if get_node_or_null("CollisionShape3D") == null:
		var col := CollisionShape3D.new()
		col.name = "CollisionShape3D"
		var box := BoxShape3D.new()
		box.size = button_size
		col.shape = box
		add_child(col)

	# Визуальная плита кнопки
	if get_node_or_null("ButtonMesh") == null:
		_mesh = MeshInstance3D.new()
		_mesh.name = "ButtonMesh"
		var bm := BoxMesh.new()
		bm.size = button_size
		_mesh.mesh = bm
		var mat := StandardMaterial3D.new()
		mat.albedo_color = body_color
		_mesh.material_override = mat
		add_child(_mesh)

	# Подпись кнопки (если не задана вручную)
	if get_node_or_null("Label") == null:
		var label := Label3D.new()
		label.name = "Label"
		label.position = Vector3(0, 0, button_size.z * 0.5 + 0.004)
		label.pixel_size = 0.00055
		label.outline_size = 6
		label.outline_modulate = Color(0, 0, 0, 0.7)
		label.modulate = Color(1, 1, 1)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.text = label_text
		add_child(label)


## Ловим события указателя от луча контроллера.
func pointer_event(event: XRToolsPointerEvent) -> void:
	match event.event_type:
		XRToolsPointerEvent.Type.ENTERED:
			_hovered = true
			_set_highlight(true)
		XRToolsPointerEvent.Type.EXITED:
			_hovered = false
			_set_highlight(false)
		XRToolsPointerEvent.Type.PRESSED:
			pressed.emit()
			_press_flash()


func _set_highlight(on: bool) -> void:
	if _mesh and _mesh.material_override:
		var mat := _mesh.material_override as StandardMaterial3D
		mat.albedo_color = hover_color if on else body_color
		mat.emission_enabled = on
		if on:
			mat.emission = hover_color * 0.8
			mat.emission_energy = 0.5


func set_favorite_style(active: bool) -> void:
	## Подсветка кнопки «В избранное» золотом при активном состоянии.
	if _mesh and _mesh.material_override:
		var mat := _mesh.material_override as StandardMaterial3D
		if active:
			mat.albedo_color = Color(0.9, 0.7, 0.2)
			mat.emission_enabled = true
			mat.emission = Color(1.0, 0.8, 0.25)
			mat.emission_energy = 0.6
		else:
			mat.albedo_color = body_color
			mat.emission_enabled = false


func _press_flash() -> void:
	if _mesh:
		var tween := create_tween()
		tween.tween_property(_mesh, "scale", Vector3(1.1, 0.5, 1.1), 0.06)
		tween.tween_property(_mesh, "scale", Vector3.ONE, 0.08)

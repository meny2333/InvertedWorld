extends Node

@export var cylinder_mapper: Node3D
@export var autoplay: bool = false
@onready var _tp_success_player: AudioStreamPlayer = AudioStreamPlayer.new()


var tp_count: int = 0
var is_pending: bool = false
var elapsed_time: float = 0.0
var pending_is_odd: bool = false
var pending_angle_offset: float = PI

const SIGNAL_WINDOW: float = 0.3
const AUTOPLAY_DELAY: float = 0.15
const TP_SUCCESS_SFX: AudioStream = preload("./rotate.ogg")

func _ready():
	if _tp_success_player.get_parent() == null:
		add_child(_tp_success_player)
	_tp_success_player.stream = TP_SUCCESS_SFX
	_tp_success_player.bus = "Master"

	if not cylinder_mapper:
		push_error("CylinderTP: 需要指定 cylinder_mapper 引用！")
		return

func _process(delta):
	if not is_pending:
		return

	elapsed_time += delta


	if autoplay and elapsed_time >= AUTOPLAY_DELAY:
		_complete_tp("autoplay")
		return


	if elapsed_time >= SIGNAL_WINDOW:
		if not autoplay:
			_abort_tp("Signal timeout: no tilt detected within 0.3s")


func flip_to_opposite_side():
	_start_tp_sequence(PI)


func flip_to_opposite_side_custom(angle_offset: float):
	_start_tp_sequence(angle_offset)


func _start_tp_sequence(angle_offset: float):
	if is_pending:
		push_warning("CylinderTP: 已有正在进行的 TP 流程，忽略此次调用")
		return

	tp_count += 1
	is_pending = true
	elapsed_time = 0.0
	pending_is_odd = (tp_count % 2 == 1)
	pending_angle_offset = angle_offset

	var expected_dir = "RIGHT (奇)" if pending_is_odd else "LEFT (偶)"
	print("TP #%d 启动 | 期望信号: %s | Autoplay: %s" % [tp_count, expected_dir, autoplay])


func _on_camera_tilted_left():
	if not is_pending:
		return


	if not pending_is_odd:
		_complete_tp("tilted_left")
	else:
		_abort_tp("Wrong signal: TP#%d (奇) expects RIGHT, got LEFT" % tp_count)


func _on_camera_tilted_right():
	if not is_pending:
		return


	if pending_is_odd:
		_complete_tp("tilted_right")
	else:
		_abort_tp("Wrong signal: TP#%d (偶) expects LEFT, got RIGHT" % tp_count)


func _complete_tp(source: String):
	if not is_pending:
		return

	is_pending = false
	print("TP #%d 执行成功 [来源: %s]" % [tp_count, source])
	_play_tp_success_sfx()


	_execute_flip_logic(pending_angle_offset, pending_is_odd)

func _play_tp_success_sfx() -> void :
	if not is_instance_valid(_tp_success_player):
		return
	if _tp_success_player.stream == null:
		_tp_success_player.stream = TP_SUCCESS_SFX



func _abort_tp(reason: String):
	if not is_pending:
		return

	is_pending = false
	print("超时死亡")


	if cylinder_mapper and cylinder_mapper.mainline:
		if cylinder_mapper.mainline.has_method("die"):
			cylinder_mapper.mainline.die()
		else:
			push_error("mainline 没有 die() 方法")
	else:
		push_error("cylinder_mapper 或 mainline 未设置，无法执行 die()")


func _execute_flip_logic(angle_offset: float, is_odd: bool):
	if not cylinder_mapper:
		return


	if cylinder_mapper.engage_flag and cylinder_mapper.mainline and cylinder_mapper.is_drawing and cylinder_mapper.current_cylinder_line:
		cylinder_mapper.call("_sync_mapping_now")
		if cylinder_mapper.target_transform:
			cylinder_mapper.call("_force_set_current_line_end", cylinder_mapper.target_transform.origin)

		var current_material = cylinder_mapper.current_cylinder_line.get_surface_override_material(0)
		if current_material and current_material is ShaderMaterial:
			var now_time = Time.get_ticks_msec() * 0.001
			current_material.set_shader_parameter("segment_end_time", now_time)
			current_material.set_shader_parameter("current_time", now_time)
			current_material.set_shader_parameter("is_active_line", false)

		cylinder_mapper.is_drawing = false
		cylinder_mapper.current_cylinder_line = null
		cylinder_mapper.has_last_drawn_end_position = false


	cylinder_mapper.current_angle += angle_offset


	if cylinder_mapper.engage_flag and cylinder_mapper.mainline:
		var forward = - cylinder_mapper.mainline.transform.basis.z
		var virtual_position = cylinder_mapper.cylinder_axis_point + cylinder_mapper.cylinder_axis * cylinder_mapper.current_axial_progress
		cylinder_mapper.map_position_to_cylinder(virtual_position, forward)
		cylinder_mapper.last_mapped_position = cylinder_mapper.target_transform.origin
		cylinder_mapper.has_last_mapped_position = true
		cylinder_mapper.has_last_drawn_end_position = false


	if cylinder_mapper.map_trails:
		cylinder_mapper.is_drawing = true
		if cylinder_mapper.has_method("create_new_cylinder_line_with_tp"):
			cylinder_mapper.call("create_new_cylinder_line_with_tp", is_odd)
		else:

			cylinder_mapper.call("create_new_cylinder_line")

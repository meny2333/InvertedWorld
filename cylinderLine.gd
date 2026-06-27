extends Node3D

const CYLINDER_BEND_SHADER: = preload("res://cylinder_bend.gdshader")

@export var enable: bool = true:
    set(value):
        var was_enabled = enable
        enable = value
        if ready_called and enable != was_enabled:
            if enable:
                engage()
            else:
                disengage()


@export var mainline: CharacterBody3D
@export var camera: Camera3D
@export var cylinder_tail_parent: Node3D

@export_group("Cylinder Settings")
@export var cylinder_reference_node: Node3D
@export var auto_update_cylinder: bool = true
@export var cylinder_radius: float = 14.5
@export var cylinder_center_offset: Vector3 = Vector3.ZERO
@export var cylinder_axis_direction: Vector3 = Vector3(1, 0, -1)

@export_group("Transform Offsets")
@export var position_offset: Vector3 = Vector3.ZERO
@export var rotation_offset: Vector3 = Vector3.ZERO
@export var initial_angle_degrees: float = 0.0

@export_group("Update Settings")
@export var update_per_frame: bool = true

@export_group("Spiral Motion Settings")
@export_enum("Fixed Angular Speed", "Fixed Pitch") var spiral_mode: int = 1
@export var spiral_angular_speed: float = 1.0
@export var spiral_pitch: float = 15.0
@export var spiral_enabled: bool = true
@export var use_independent_speed: bool = false
@export var forward_speed: float = 5.0

@export_group("Trail Settings")
@export var map_trails: bool = true
@export var trail_color: Color = Color.WHITE
@export var trail_emission: bool = false
@export var trail_emission_color: Color = Color.WHITE
@export var trail_emission_energy: float = 1.0
@export var min_segment_length: float = 0.01
@export var join_overlap: float = 0.45

@export_group("Angle Detection")
@export var angle_detection_enabled: bool = false
@export var target_angle_degrees: float = 90.0


signal angle_reached(target_angle: float, current_angle: float)


var cylinder_axis_point: Vector3
var cylinder_axis: Vector3
var last_mainline_position: Vector3
var current_angle: float = 0.0
var current_axial_progress: float = 0.0
var target_transform: Transform3D
var reference_direction: Vector3
var perpendicular_direction: Vector3
var current_cylinder_line: MeshInstance3D = null
var line_start_position: Vector3
var is_drawing: bool = false
var mainline_tail_node: Node3D = null
var last_mapped_position: Vector3
var has_last_mapped_position: bool = false
var last_drawn_end_position: Vector3
var has_last_drawn_end_position: bool = false
var cylinder_bend_shader: Shader
var cylinder_bend_material: ShaderMaterial
var rotation_offset_basis: Basis
var spiral_direction: float = 1.0
var ready_called: bool = false
var engage_flag: bool = false
var resources_initialized: bool = false
var last_cylinder_reference_position: Vector3
var _cached_local_rotation: Basis
var _cached_two_pi_div_pitch: float
var _movement_threshold_squared: float = 0.0001
var _signals_connected: bool = false
var _pending_new_line: bool = false
var _pending_on_sky: bool = false
var _pending_cut_position: Vector3
var _has_pending_cut_position: bool = false
var current_tangent_direction: Vector3 = Vector3.ZERO
var last_segment_direction: Vector3 = Vector3.ZERO
var has_last_segment_direction: bool = false
var _turn_pending: bool = false
var _turn_prev_tangent: Vector3 = Vector3.ZERO
var _has_turn_prev_tangent: bool = false
var _pending_prev_tangent: Vector3 = Vector3.ZERO
var _has_pending_join_tangents: bool = false


var _angle_already_triggered: bool = false


var is_odd_tp_mode: bool = false

var segment_start_time: float = 0.0


var _trigger_activated: bool = false
var _trigger_checkpoint_index: int = -1

func _get_shader_time_seconds() -> float:
    return Time.get_ticks_msec() * 0.001

func _set_line_active_state(line_node: MeshInstance3D, is_active: bool) -> void :
    if not line_node or not is_instance_valid(line_node):
        return
    var line_material = line_node.get_surface_override_material(0)
    if line_material and line_material is ShaderMaterial:
        line_material.set_shader_parameter("is_active_line", is_active)

func _freeze_line_fade_time(line_node: MeshInstance3D) -> void :
    if not line_node or not is_instance_valid(line_node):
        return
    var line_material = line_node.get_surface_override_material(0)
    if line_material and line_material is ShaderMaterial:
        var now_time = _get_shader_time_seconds()
        line_material.set_shader_parameter("segment_end_time", now_time)
        line_material.set_shader_parameter("current_time", now_time)
        line_material.set_shader_parameter("is_active_line", false)

func _ready():
    ready_called = true
    _cached_local_rotation = Basis.from_euler(Vector3(deg_to_rad(90), deg_to_rad(90), 0))
    if spiral_pitch > 0.001:
        _cached_two_pi_div_pitch = TAU / spiral_pitch

    call_deferred("_init_resources")

    if not Engine.is_editor_hint():
        LevelManager.add_revive_listener(_on_revive_reset)

func _init_resources():
    if resources_initialized:
        return
    if not mainline:
        return

    cylinder_bend_shader = CYLINDER_BEND_SHADER

    if not camera:
        camera = get_viewport().get_camera_3d()
    if not cylinder_tail_parent:
        cylinder_tail_parent = Node3D.new()
        cylinder_tail_parent.name = "CylinderTail"
        get_tree().current_scene.add_child(cylinder_tail_parent)

    _update_offset_transform()
    setup_cylinder()
    last_cylinder_reference_position = cylinder_axis_point
    create_base_material()

    var scene_root = get_tree().current_scene
    if scene_root and scene_root.has_node("tail"):
        mainline_tail_node = scene_root.get_node("tail")


    _warmup_shader()

    resources_initialized = true

func _warmup_shader():
    "创建临时网格强制编译着色器，避免运行时卡顿"
    if not cylinder_bend_material or not cylinder_tail_parent:
        return


    var variants: Array[Dictionary] = [
        {
            "is_odd_tp": false, 
            "use_emission": trail_emission, 
            "is_active_line": false
        }, 
        {
            "is_odd_tp": true, 
            "use_emission": true, 
            "is_active_line": true
        }
    ]

    for variant in variants:
        var temp_mesh = MeshInstance3D.new()
        var box_mesh = BoxMesh.new()
        box_mesh.size = Vector3(0.01, 0.01, 0.01)
        temp_mesh.mesh = box_mesh

        var temp_material = cylinder_bend_material.duplicate()
        temp_material.set_shader_parameter("is_odd_tp", variant["is_odd_tp"])
        temp_material.set_shader_parameter("use_emission", variant["use_emission"])
        temp_material.set_shader_parameter("is_active_line", variant["is_active_line"])
        temp_material.set_shader_parameter("line_start_position", Vector3.ZERO)
        temp_material.set_shader_parameter("line_end_position", Vector3(0.01, 0.0, 0.0))
        temp_material.set_shader_parameter("mesh_z_size", box_mesh.size.z)
        temp_material.set_shader_parameter("reference_direction", reference_direction)
        temp_material.set_shader_parameter("perpendicular_direction", perpendicular_direction)
        temp_material.set_shader_parameter("current_time", 0.01)
        temp_material.set_shader_parameter("segment_start_time", 0.0)
        temp_material.set_shader_parameter("segment_end_time", 0.01)
        temp_material.set_shader_parameter("fade_duration", 1.0)
        temp_material.set_shader_parameter("trail_head_color", Vector3(0.8, 0.9, 1.0))
        temp_material.set_shader_parameter("trail_tail_color", Vector3(0.1, 0.2, 0.4))
        temp_material.set_shader_parameter("odd_tp_emission_energy", ODD_TP_EMISSION_ENERGY)

        temp_mesh.set_surface_override_material(0, temp_material)
        cylinder_tail_parent.add_child(temp_mesh)
        temp_mesh.global_position = Vector3(0, -10000, 0)
        await get_tree().process_frame
        temp_mesh.queue_free()

func _update_offset_transform():
    rotation_offset_basis = Basis.from_euler(Vector3(
        deg_to_rad(rotation_offset.x), 
        deg_to_rad(rotation_offset.y), 
        deg_to_rad(rotation_offset.z)
    ))

func _exit_tree():
    if not Engine.is_editor_hint():
        LevelManager.remove_revive_listener(_on_revive_reset)
    if _signals_connected:
        _disconnect_signals()

func _connect_player_signals():
    "连接player所有信号（onturn、new_line1、on_sky）"
    if not mainline or _signals_connected:
        return
    if mainline.has_signal("onturn") and not mainline.onturn.is_connected(_on_mainline_turn):
        mainline.onturn.connect(_on_mainline_turn)
    if mainline.has_signal("new_line1") and not mainline.new_line1.is_connected(_on_mainline_new_line):
        mainline.new_line1.connect(_on_mainline_new_line)
    if mainline.has_signal("on_sky") and not mainline.on_sky.is_connected(_on_mainline_on_sky):
        mainline.on_sky.connect(_on_mainline_on_sky)
    _signals_connected = true

func _disconnect_signals():
    if not mainline or not _signals_connected:
        return
    if mainline.has_signal("onturn") and mainline.onturn.is_connected(_on_mainline_turn):
        mainline.onturn.disconnect(_on_mainline_turn)
    if mainline.has_signal("new_line1") and mainline.new_line1.is_connected(_on_mainline_new_line):
        mainline.new_line1.disconnect(_on_mainline_new_line)
    if mainline.has_signal("on_sky") and mainline.on_sky.is_connected(_on_mainline_on_sky):
        mainline.on_sky.disconnect(_on_mainline_on_sky)
    _signals_connected = false

func engage():
    if not ready_called:
        return
    if not resources_initialized:
        _init_resources()
    if not resources_initialized:
        return
    engage_flag = true


    if not _signals_connected:
        _connect_player_signals()

    current_angle = deg_to_rad(initial_angle_degrees)
    initialize_mapping()
    if map_trails and has_last_mapped_position:
        is_drawing = true
        create_new_cylinder_line()


    _deferred_calibrate()

func _enter_tree():
    if mainline and engage_flag and not _signals_connected:
        _connect_player_signals()
        _deferred_calibrate()

func _deferred_calibrate() -> void :
    "延迟校准螺旋方向：等待 player 开始移动后再执行"
    if not mainline or not is_instance_valid(mainline):
        return

    get_tree().create_timer(1.0).timeout.connect(_on_calibrate_timer)

func _on_calibrate_timer() -> void :
    if not engage_flag or not mainline or not is_instance_valid(mainline):
        return
    _calibrate_spiral_direction()

func _calibrate_spiral_direction():
    "根据mainline当前朝向校准螺旋方向，确保与运动方向一致"
    if not mainline:
        return

    var radial = get_radial_direction_from_angle(current_angle)
    var expected_tangent = cylinder_axis.cross(radial).normalized()


    if spiral_direction < 0:
        expected_tangent = - expected_tangent

    var actual_forward = - mainline.transform.basis.z


    if actual_forward.dot(expected_tangent) < 0:
        spiral_direction = - spiral_direction

func disengage():
    if not engage_flag:
        return
    engage_flag = false
    _disconnect_signals()
    stop_drawing_trails()

func stop_drawing_trails():
    is_drawing = false
    _freeze_line_fade_time(current_cylinder_line)
    current_cylinder_line = null
    has_last_drawn_end_position = false
    has_last_segment_direction = false



func set_enable_trigger(new_enable: bool = true) -> void :
    "SetEnableTrigger — 激活/关闭圆柱线系统，记录复活状态。\r\n\t复活后自动重置为禁用状态，等待下一次触发。"

    _trigger_activated = true
    _trigger_checkpoint_index = LevelManager.checkpoint_count
    enable = new_enable

func _on_revive_reset() -> void :
    "复活回调：如果经过了本触发器所在的 checkpoint，重置为禁用状态并清除已有轨迹"
    if not _trigger_activated:
        return
    LevelManager.CompareCheckpointIndex(_trigger_checkpoint_index, func():
        if _trigger_activated:
            enable = false

            if cylinder_tail_parent:
                for child in cylinder_tail_parent.get_children():
                    if is_instance_valid(child):
                        child.queue_free()
            _trigger_activated = false
            _trigger_checkpoint_index = -1
    )

func manual_clear_trails():
    clear_cylinder_trails()

func setup_cylinder():
    var reference_position: Vector3
    if cylinder_reference_node and is_instance_valid(cylinder_reference_node):
        reference_position = cylinder_reference_node.global_position
    elif camera:
        reference_position = camera.global_position
    else:
        return

    cylinder_axis_point = reference_position + cylinder_center_offset
    cylinder_axis = cylinder_axis_direction.normalized()

    reference_direction = Vector3.UP.cross(cylinder_axis)
    if reference_direction.length_squared() < 1e-06:
        reference_direction = Vector3.RIGHT.cross(cylinder_axis)
    reference_direction = reference_direction.normalized()

    perpendicular_direction = cylinder_axis.cross(reference_direction).normalized()

func create_base_material():
    cylinder_bend_material = ShaderMaterial.new()
    cylinder_bend_material.shader = cylinder_bend_shader
    cylinder_bend_material.set_shader_parameter("cylinder_axis_point", cylinder_axis_point)
    cylinder_bend_material.set_shader_parameter("cylinder_axis", cylinder_axis)
    cylinder_bend_material.set_shader_parameter("cylinder_radius", cylinder_radius)
    cylinder_bend_material.set_shader_parameter("albedo_color", trail_color)
    cylinder_bend_material.set_shader_parameter("use_emission", trail_emission)
    cylinder_bend_material.set_shader_parameter("emission_color", trail_emission_color)
    cylinder_bend_material.set_shader_parameter("emission_energy", trail_emission_energy)

    cylinder_bend_material.set_shader_parameter("start_extend", 0.0)
    cylinder_bend_material.set_shader_parameter("end_extend", 0.0)
    cylinder_bend_material.set_shader_parameter("discard_start_cap", false)
    cylinder_bend_material.set_shader_parameter("discard_end_cap", false)
    cylinder_bend_material.set_shader_parameter("is_active_line", false)
    cylinder_bend_material.set_shader_parameter("segment_start_time", 0.0)
    cylinder_bend_material.set_shader_parameter("segment_end_time", 0.0)

func initialize_mapping():
    if not mainline or not engage_flag:
        return

    last_mainline_position = mainline.global_position
    var to_mainline = mainline.global_position - cylinder_axis_point
    current_axial_progress = to_mainline.dot(cylinder_axis)
    var virtual_position = cylinder_axis_point + cylinder_axis * current_axial_progress
    map_position_to_cylinder(virtual_position, - mainline.transform.basis.z)

func _on_mainline_turn():
    if not engage_flag:
        return

    _sync_mapping_now()
    _turn_prev_tangent = last_segment_direction if has_last_segment_direction else current_tangent_direction
    _has_turn_prev_tangent = true
    _turn_pending = true
    spiral_direction = - spiral_direction

func _on_mainline_new_line():
    if not engage_flag:
        return
    _sync_mapping_now()
    if target_transform:
        _pending_cut_position = target_transform.origin
        _has_pending_cut_position = true

        var prev_point: Vector3 = last_drawn_end_position if has_last_drawn_end_position else last_mapped_position
        var d: Vector3 = _pending_cut_position - prev_point
        var prev_dir: Vector3 = Vector3.ZERO
        if d.length_squared() > 1e-06:
            prev_dir = d.normalized()
        elif _turn_pending and _has_turn_prev_tangent:
            prev_dir = _turn_prev_tangent
            _turn_pending = false
            _has_turn_prev_tangent = false
        elif has_last_segment_direction:
            prev_dir = last_segment_direction
        else:
            prev_dir = current_tangent_direction
        _pending_prev_tangent = prev_dir
        _has_pending_join_tangents = true
    _pending_new_line = true

func _on_mainline_on_sky():
    if not engage_flag:
        return
    _sync_mapping_now()
    if target_transform:
        _pending_cut_position = target_transform.origin
        _has_pending_cut_position = true
    _has_pending_join_tangents = false
    _turn_pending = false
    _pending_on_sky = true

func _sync_mapping_now() -> void :
    if not mainline or not is_instance_valid(mainline):
        return

    if auto_update_cylinder:
        _auto_update_cylinder_position()
    if not use_independent_speed:
        var current_pos: Vector3 = mainline.global_position
        var to_mainline: Vector3 = current_pos - cylinder_axis_point
        current_axial_progress = to_mainline.dot(cylinder_axis)
    var forward: Vector3 = - mainline.transform.basis.z
    var virtual_position: Vector3 = cylinder_axis_point + cylinder_axis * current_axial_progress
    map_position_to_cylinder(virtual_position, forward)

func _force_set_current_line_end(pos: Vector3) -> void :
    if not current_cylinder_line or not is_instance_valid(current_cylinder_line):
        return
    var line_material = current_cylinder_line.get_surface_override_material(0)
    if line_material and line_material is ShaderMaterial:
        line_material.set_shader_parameter("line_end_position", pos)
    last_drawn_end_position = pos
    has_last_drawn_end_position = true

func _process(delta):
    if not engage_flag or not mainline:
        return

    if auto_update_cylinder:
        _auto_update_cylinder_position()

    if update_per_frame:
        var current_pos = mainline.global_position
        var forward = - mainline.transform.basis.z
        var axial_movement: float

        if use_independent_speed:
            axial_movement = forward_speed * delta
        else:
            var movement = current_pos - last_mainline_position
            axial_movement = movement.dot(cylinder_axis)

        if spiral_enabled:
            if spiral_mode == 0:
                update_spiral_motion_angular_speed(axial_movement, forward, delta)
            else:
                update_spiral_motion_fixed_pitch(axial_movement, forward)

        if current_pos.distance_squared_to(last_mainline_position) > _movement_threshold_squared:
            last_mainline_position = current_pos

    if map_trails and is_drawing and current_cylinder_line and is_instance_valid(current_cylinder_line):
        update_cylinder_trail()


    _update_all_trails_time(_get_shader_time_seconds())


    if angle_detection_enabled:
        _check_angle_detection()


    if _pending_on_sky:
        _pending_on_sky = false
        _pending_new_line = false
        _cut_current_segment_at_target()
        _has_pending_cut_position = false
        is_drawing = false
        _freeze_line_fade_time(current_cylinder_line)
        current_cylinder_line = null
        has_last_drawn_end_position = false
    elif _pending_new_line:
        _pending_new_line = false
        _cut_current_segment_at_target()
        _has_pending_cut_position = false
        if map_trails:
            is_drawing = true
            create_new_cylinder_line()

func _cut_current_segment_at_target() -> void :
    var p: Vector3
    if _has_pending_cut_position:
        p = _pending_cut_position
    elif target_transform:
        p = target_transform.origin
    else:
        return
    _force_set_current_line_end(p)


    if _has_pending_join_tangents and join_overlap > 0.0 and current_cylinder_line and is_instance_valid(current_cylinder_line):
        var mat = current_cylinder_line.get_surface_override_material(0)
        if mat and mat is ShaderMaterial:
            mat.set_shader_parameter("end_extend", 0.0)
            mat.set_shader_parameter("discard_end_cap", false)
    last_drawn_end_position = p
    has_last_drawn_end_position = true
    last_mapped_position = p
    has_last_mapped_position = true

func _auto_update_cylinder_position():
    var reference_position: Vector3
    if cylinder_reference_node and is_instance_valid(cylinder_reference_node):
        reference_position = cylinder_reference_node.global_position
    elif camera:
        reference_position = camera.global_position
    else:
        return

    var new_axis_point = reference_position + cylinder_center_offset
    if new_axis_point.distance_squared_to(last_cylinder_reference_position) > 1e-06:
        cylinder_axis_point = new_axis_point
        last_cylinder_reference_position = new_axis_point
        if cylinder_bend_material:
            cylinder_bend_material.set_shader_parameter("cylinder_axis_point", cylinder_axis_point)
        _update_all_trails_cylinder_params()

func _update_all_trails_cylinder_params():
    if not cylinder_tail_parent:
        return

    var children = cylinder_tail_parent.get_children()
    for child in children:
        if child is MeshInstance3D:
            var line_material = child.get_surface_override_material(0)
            if line_material and line_material is ShaderMaterial:
                line_material.set_shader_parameter("cylinder_axis_point", cylinder_axis_point)
                line_material.set_shader_parameter("cylinder_axis", cylinder_axis)
                line_material.set_shader_parameter("cylinder_radius", cylinder_radius)
                line_material.set_shader_parameter("reference_direction", reference_direction)
                line_material.set_shader_parameter("perpendicular_direction", perpendicular_direction)

func update_spiral_motion_angular_speed(axial_movement: float, forward_direction: Vector3, delta: float):
    current_axial_progress += axial_movement
    current_angle += spiral_angular_speed * spiral_direction * delta
    var virtual_position = cylinder_axis_point + cylinder_axis * current_axial_progress
    map_position_to_cylinder(virtual_position, forward_direction)

func update_spiral_motion_fixed_pitch(axial_movement: float, forward_direction: Vector3):
    current_axial_progress += axial_movement
    if spiral_pitch > 0.001:
        var angle_increment = axial_movement * _cached_two_pi_div_pitch
        current_angle += angle_increment * spiral_direction
    var virtual_position = cylinder_axis_point + cylinder_axis * current_axial_progress
    map_position_to_cylinder(virtual_position, forward_direction)

func map_position_to_cylinder(mainline_pos: Vector3, _forward_direction: Vector3):
    var to_mainline = mainline_pos - cylinder_axis_point
    var axial_distance = to_mainline.dot(cylinder_axis)
    var axial_position = cylinder_axis_point + cylinder_axis * axial_distance
    var radial_direction = get_radial_direction_from_angle(current_angle)
    var surface_position = axial_position + radial_direction * cylinder_radius
    surface_position += position_offset

    var tangent_direction = cylinder_axis.cross(radial_direction).normalized()
    if spiral_direction < 0:
        tangent_direction = - tangent_direction
    current_tangent_direction = tangent_direction

    var rotation_basis = Basis()
    rotation_basis.z = - tangent_direction
    rotation_basis.y = cylinder_axis
    rotation_basis.x = rotation_basis.y.cross(rotation_basis.z).normalized()
    rotation_basis = rotation_basis.orthonormalized()
    rotation_basis = rotation_offset_basis * rotation_basis

    target_transform = Transform3D()
    target_transform.origin = surface_position
    target_transform.basis = rotation_basis * _cached_local_rotation
    last_mapped_position = surface_position
    has_last_mapped_position = true


const ODD_TP_ALBEDO_COLOR: = Color(0.1, 0.2, 0.4)
const ODD_TP_EMISSION_COLOR: = Color(0.2, 0.6, 1.0)
const ODD_TP_EMISSION_ENERGY: = 2.0

func create_new_cylinder_line_with_tp(is_odd_tp: bool = false):

    is_odd_tp_mode = is_odd_tp
    _create_cylinder_line_internal()

func _create_cylinder_line_internal():
    if not engage_flag or not cylinder_tail_parent:
        return
    if not has_last_mapped_position:
        return

    _freeze_line_fade_time(current_cylinder_line)

    current_cylinder_line = MeshInstance3D.new()
    var box_mesh = BoxMesh.new()
    box_mesh.size = Vector3(1, 1, 1)
    box_mesh.subdivide_width = 2
    box_mesh.subdivide_height = 2
    box_mesh.subdivide_depth = 20
    current_cylinder_line.mesh = box_mesh

    var line_material = cylinder_bend_material.duplicate()



    if is_odd_tp_mode:

        segment_start_time = _get_shader_time_seconds()


        var current_time = segment_start_time

        line_material.set_shader_parameter("is_odd_tp", true)
        line_material.set_shader_parameter("use_emission", true)
        line_material.set_shader_parameter("segment_start_time", segment_start_time)
        line_material.set_shader_parameter("segment_end_time", current_time)

        line_material.set_shader_parameter("fade_duration", 0.5)

        line_material.set_shader_parameter("trail_head_color", Vector3(0.8, 0.9, 1.0))

        line_material.set_shader_parameter("trail_tail_color", Vector3(
            ODD_TP_ALBEDO_COLOR.r, 
            ODD_TP_ALBEDO_COLOR.g, 
            ODD_TP_ALBEDO_COLOR.b
        ))
        line_material.set_shader_parameter("odd_tp_emission_energy", ODD_TP_EMISSION_ENERGY)
        line_material.set_shader_parameter("is_active_line", true)


        _update_all_trails_time(current_time)
    else:
        line_material.set_shader_parameter("is_odd_tp", false)
        line_material.set_shader_parameter("is_active_line", false)


    var join_pos: Vector3 = last_drawn_end_position if has_last_drawn_end_position else last_mapped_position
    line_start_position = join_pos
    line_material.set_shader_parameter("line_start_position", line_start_position)
    var initial_end: Vector3 = join_pos
    if current_tangent_direction.length_squared() > 1e-06:
        initial_end = join_pos + current_tangent_direction.normalized() * 0.001
    line_material.set_shader_parameter("line_end_position", initial_end)
    line_material.set_shader_parameter("start_extend", join_overlap if _has_pending_join_tangents else 0.0)
    line_material.set_shader_parameter("end_extend", 0.0)

    line_material.set_shader_parameter("discard_start_cap", false)
    line_material.set_shader_parameter("discard_end_cap", false)
    last_drawn_end_position = join_pos
    has_last_drawn_end_position = true
    line_material.set_shader_parameter("mesh_z_size", box_mesh.size.z)
    _has_pending_join_tangents = false
    line_material.set_shader_parameter("reference_direction", reference_direction)
    line_material.set_shader_parameter("perpendicular_direction", perpendicular_direction)

    current_cylinder_line.set_surface_override_material(0, line_material)
    current_cylinder_line.global_transform = Transform3D.IDENTITY
    current_cylinder_line.name = "CylinderLine"
    current_cylinder_line.extra_cull_margin = 16384.0
    current_cylinder_line.visibility_range_end_margin = 0.0
    cylinder_tail_parent.add_child(current_cylinder_line)

func create_new_cylinder_line():
    _create_cylinder_line_internal()

func update_cylinder_trail():
    if not engage_flag or not current_cylinder_line or not is_instance_valid(current_cylinder_line):
        return

    var current_pos: Vector3 = target_transform.origin
    var min_sq: = min_segment_length * min_segment_length


    var from_start_sq: = current_pos.distance_squared_to(line_start_position)
    if from_start_sq < min_sq:
        if from_start_sq <= 0.0:
            return
        var last_end0: Vector3 = last_drawn_end_position if has_last_drawn_end_position else line_start_position
        var early_mat = current_cylinder_line.get_surface_override_material(0)
        if early_mat and early_mat is ShaderMaterial:
            early_mat.set_shader_parameter("line_end_position", current_pos)
            var dd0: Vector3 = current_pos - last_end0
            if dd0.length_squared() > 1e-06:
                last_segment_direction = dd0.normalized()
                has_last_segment_direction = true
            last_drawn_end_position = current_pos
            has_last_drawn_end_position = true
        last_mapped_position = current_pos
        return

    var last_end: Vector3 = last_drawn_end_position if has_last_drawn_end_position else line_start_position
    if current_pos.distance_squared_to(last_end) < min_sq:
        return

    var line_material = current_cylinder_line.get_surface_override_material(0)
    if line_material and line_material is ShaderMaterial:
        line_material.set_shader_parameter("line_end_position", current_pos)


    if is_odd_tp_mode:
        if line_material and line_material is ShaderMaterial:
            line_material.set_shader_parameter("segment_end_time", _get_shader_time_seconds())

    var dd: Vector3 = current_pos - last_end
    if dd.length_squared() > 1e-06:
        last_segment_direction = dd.normalized()
        has_last_segment_direction = true
    last_drawn_end_position = current_pos
    has_last_drawn_end_position = true
    last_mapped_position = current_pos

func _update_all_trails_time(current_time: float):
    "更新所有已存在线条的当前时间参数"
    if not cylinder_tail_parent:
        return

    var children = cylinder_tail_parent.get_children()
    for child in children:
        if child is MeshInstance3D:
            var mat = child.get_surface_override_material(0)
            if mat and mat is ShaderMaterial:
                mat.set_shader_parameter("current_time", current_time)

@warning_ignore("shadowed_variable")
func get_radial_direction_from_angle(angle: float) -> Vector3:
    var cos_a = cos(angle)
    var sin_a = sin(angle)
    return (reference_direction * cos_a + perpendicular_direction * sin_a).normalized()

func project_vector_to_cylinder_plane(vec: Vector3) -> Vector3:
    var projection_on_axis = vec.dot(cylinder_axis) * cylinder_axis
    var projected = vec - projection_on_axis
    return projected.normalized() if projected.length_squared() > 1e-06 else Vector3.ZERO

func project_point_to_cylinder_plane(point: Vector3) -> Vector3:
    var to_point = point - cylinder_axis_point
    var projection_on_axis = to_point.dot(cylinder_axis)
    return point - cylinder_axis * projection_on_axis

func get_mapping_info() -> Dictionary:
    return {
        "enabled": enable, 
        "engaged": engage_flag, 
        "spiral_mode": "固定角速度" if spiral_mode == 0 else "固定螺距", 
        "speed_mode": "独立速度" if use_independent_speed else "跟随mainline", 
        "forward_speed": forward_speed, 
        "spiral_direction": "顺时针" if spiral_direction > 0 else "逆时针", 
        "angle_degrees": rad_to_deg(current_angle), 
        "angle_radians": current_angle, 
        "axial_progress": current_axial_progress, 
        "surface_position": target_transform.origin, 
        "cylinder_axis_point": cylinder_axis_point, 
        "cylinder_reference": "自定义节点" if cylinder_reference_node else "相机", 
        "auto_update": auto_update_cylinder, 
        "cylinder_radius": cylinder_radius, 
        "spiral_pitch": spiral_pitch, 
        "spiral_angular_speed": spiral_angular_speed, 
        "position_offset": position_offset, 
        "rotation_offset": rotation_offset, 
        "initial_angle_degrees": initial_angle_degrees, 
        "distance_to_axis": target_transform.origin.distance_to(
            cylinder_axis_point + cylinder_axis * current_axial_progress
        ) if engage_flag else 0.0, 
        "is_drawing": is_drawing, 
        "active_lines": cylinder_tail_parent.get_child_count() if cylinder_tail_parent else 0, 
        "current_line_length": (target_transform.origin - line_start_position).length() if is_drawing and has_last_mapped_position else 0.0
    }

func clear_cylinder_trails():
    if not cylinder_tail_parent:
        return

    var children = cylinder_tail_parent.get_children()
    for child in children:
        if is_instance_valid(child):
            child.queue_free()

    if children.size() > 0:
        await get_tree().process_frame
    has_last_drawn_end_position = false
    has_last_segment_direction = false

func _check_angle_detection() -> void :
    if not engage_flag or _angle_already_triggered:
        return

    var target_angle_rad: float = deg_to_rad(target_angle_degrees)


    var normalized_current: float = fmod(current_angle, TAU)
    if normalized_current < 0:
        normalized_current += TAU

    var normalized_target: float = fmod(target_angle_rad, TAU)
    if normalized_target < 0:
        normalized_target += TAU


    var has_reached: bool = false
    if spiral_direction > 0:
        has_reached = normalized_current >= normalized_target
    else:
        has_reached = normalized_current <= normalized_target

    if has_reached:
        print("rea")
        _angle_already_triggered = true
        angle_reached.emit(target_angle_degrees, rad_to_deg(current_angle))
        enable = false
        mainline.position.y += -935
        mainline.new_line()

func reset_angle_detection() -> void :
    _angle_already_triggered = false

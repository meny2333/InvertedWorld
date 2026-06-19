extends Node3D

@export var path_3d_array: Array[Path3D] = []
@export var camera: Camera3D
@export var brick_parent: Node3D

@export var brick_length: float = 1.0
@export var brick_width: float = 0.5
@export var gap: float = 0.05
@export var enable: bool = false
@export var delay_between_bricks: float = 0.01

@export var cylinder_radius: float = 14.5
@export var cylinder_center_offset: Vector3 = Vector3.ZERO
@export var cylinder_axis_direction: Vector3 = Vector3(1, 0, -1)

@export var available_brick_scenes: Array[PackedScene] = []

@export var brick_fly_duration: float = 0.5


@export_group("Global Offset")
@export var global_offset: Vector3 = Vector3.ZERO


@export_group("Preprocessing")
@export var preprocess_enabled: bool = false
@export_enum("Time:0", "Distance:1") var preprocess_mode: int = 0
@export var preprocess_time: float = 5.0
@export var preprocess_distance: float = 50.0

var path_progresses: Array[float] = []
var path_row_indices: Array[int] = []
var path_active: Array[bool] = []
var path_completed: Array[bool] = []
var last_spawn_time: float = 0.0
var path_calculators: Array[PathFollow3D] = []
var all_bricks: Array[Node3D] = []


var preprocess_completed: bool = false
var previous_enable: bool = false

func _ready():
    setup_path_calculators()

    path_progresses.resize(path_3d_array.size())
    path_row_indices.resize(path_3d_array.size())
    path_active.resize(path_3d_array.size())
    path_completed.resize(path_3d_array.size())

    for i in range(path_3d_array.size()):
        path_progresses[i] = 0.0
        path_row_indices[i] = 0
        path_active[i] = (i == 0)
        path_completed[i] = false

    if not brick_parent:
        brick_parent = self

func setup_path_calculators():
    path_calculators.clear()
    for path in path_3d_array:
        if path:
            var path_follow = PathFollow3D.new()
            path.add_child(path_follow)
            path_follow.loop = false
            path_follow.rotation_mode = PathFollow3D.ROTATION_ORIENTED
            path_calculators.append(path_follow)

func _process(delta):

    if enable and not previous_enable:

        if preprocess_enabled and not preprocess_completed:
            preprocess_bricks()

    previous_enable = enable

    if enable:
        last_spawn_time += delta
        if last_spawn_time >= delay_between_bricks:
            spawn_brick()
            last_spawn_time = 0.0

func preprocess_bricks():
    "预处理：根据模式提前铺设砖块（无动画）"
    if not preprocess_enabled:
        return

    var target_progress: float = 0.0


    if preprocess_mode == 0:

        var total_bricks = preprocess_time / delay_between_bricks
        target_progress = floor(total_bricks) * (brick_length + gap)
    else:
        target_progress = preprocess_distance


    var temp_last_spawn_time = last_spawn_time


    var total_brick_length = brick_length + gap
    var num_bricks = int(target_progress / total_brick_length)


    var current_path_idx = 0
    for i in range(path_3d_array.size()):
        if path_active[i]:
            current_path_idx = i
            break


    var bricks_laid = 0
    for i in range(num_bricks):
        if current_path_idx >= path_3d_array.size():
            break


        var current_path = path_3d_array[current_path_idx]
        if current_path:
            var path_length = current_path.curve.get_baked_length()
            if path_progresses[current_path_idx] > path_length:
                path_completed[current_path_idx] = true

                current_path_idx += 1
                if current_path_idx >= path_3d_array.size():
                    break
                path_active[current_path_idx] = true

        spawn_brick_instant(current_path_idx)
        bricks_laid += 1


        path_row_indices[current_path_idx] += 1
        path_progresses[current_path_idx] += total_brick_length


    last_spawn_time = temp_last_spawn_time
    preprocess_completed = true

    print("预处理完成：铺设了 ", bricks_laid, " 块砖")

func spawn_brick_instant(active_path_index: int):
    "立即生成砖块（无动画），用于预处理"
    var current_path = path_3d_array[active_path_index]
    if not current_path:
        return

    if available_brick_scenes.is_empty():
        return

    var selected_scene = available_brick_scenes.pick_random()
    var brick = selected_scene.instantiate()
    brick_parent.add_child(brick)
    all_bricks.append(brick)

    var current_progress = path_progresses[active_path_index]


    var path_calculator = path_calculators[active_path_index]
    path_calculator.progress = current_progress


    var is_right_side = (path_row_indices[active_path_index] %2 == 0)
    var offset_amount = brick_width / 2.0 if is_right_side else - brick_width / 2.0


    path_calculator.h_offset = 0.0
    var base_target_pos = path_calculator.global_position


    var cylinder_axis_point = camera.global_position + cylinder_center_offset
    var cylinder_axis = cylinder_axis_direction.normalized()

    var to_brick = base_target_pos - cylinder_axis_point
    var projection_length = to_brick.dot(cylinder_axis)
    var foot_point = cylinder_axis_point + cylinder_axis * projection_length
    var radial_direction = (base_target_pos - foot_point).normalized()
    var tangent_direction = cylinder_axis.cross(radial_direction).normalized()


    var target_pos = base_target_pos + tangent_direction * offset_amount


    target_pos += global_offset


    to_brick = target_pos - cylinder_axis_point
    projection_length = to_brick.dot(cylinder_axis)
    foot_point = cylinder_axis_point + cylinder_axis * projection_length
    radial_direction = (target_pos - foot_point).normalized()
    tangent_direction = cylinder_axis.cross(radial_direction).normalized()


    var rotation_basis = Basis()
    rotation_basis.z = - tangent_direction
    rotation_basis.y = cylinder_axis
    rotation_basis.x = rotation_basis.y.cross(rotation_basis.z).normalized()
    rotation_basis = rotation_basis.orthonormalized()


    var local_rotation = Basis.from_euler(Vector3(deg_to_rad(90), deg_to_rad(90), 0))


    var target_global_transform = Transform3D()
    target_global_transform.origin = target_pos
    target_global_transform.basis = rotation_basis * local_rotation


    var target_local = brick_parent.global_transform.affine_inverse() * target_global_transform
    brick.transform = target_local

func spawn_brick():
    "常规生成砖块（带动画）"
    var active_path_index = -1

    for i in range(path_3d_array.size()):
        if path_active[i] and not path_completed[i]:
            active_path_index = i
            break

    if active_path_index == -1:
        enable = false
        return

    var current_path = path_3d_array[active_path_index]
    if not current_path:
        path_completed[active_path_index] = true
        activate_next_path(active_path_index)
        return

    var path_length = current_path.curve.get_baked_length()
    var current_progress = path_progresses[active_path_index]

    if current_progress > path_length:
        path_completed[active_path_index] = true
        activate_next_path(active_path_index)
        return

    if available_brick_scenes.is_empty():
        return

    var selected_scene = available_brick_scenes.pick_random()
    var brick = selected_scene.instantiate()
    brick_parent.add_child(brick)
    all_bricks.append(brick)


    brick.global_transform = camera.global_transform
    brick.translate(Vector3(0, 0, -100.0))
    brick.global_position += global_offset


    var path_calculator = path_calculators[active_path_index]
    path_calculator.progress = current_progress


    var is_right_side = (path_row_indices[active_path_index] %2 == 0)
    var offset_amount = brick_width / 2.0 if is_right_side else - brick_width / 2.0


    path_calculator.h_offset = 0.0
    var base_target_pos = path_calculator.global_position


    var cylinder_axis_point = camera.global_position + cylinder_center_offset
    var cylinder_axis = cylinder_axis_direction.normalized()

    var to_brick = base_target_pos - cylinder_axis_point
    var projection_length = to_brick.dot(cylinder_axis)
    var foot_point = cylinder_axis_point + cylinder_axis * projection_length
    var radial_direction = (base_target_pos - foot_point).normalized()
    var tangent_direction = cylinder_axis.cross(radial_direction).normalized()


    var target_pos = base_target_pos + tangent_direction * offset_amount


    target_pos += global_offset


    to_brick = target_pos - cylinder_axis_point
    projection_length = to_brick.dot(cylinder_axis)
    foot_point = cylinder_axis_point + cylinder_axis * projection_length
    radial_direction = (target_pos - foot_point).normalized()
    tangent_direction = cylinder_axis.cross(radial_direction).normalized()


    var rotation_basis = Basis()
    rotation_basis.z = - tangent_direction
    rotation_basis.y = cylinder_axis
    rotation_basis.x = rotation_basis.y.cross(rotation_basis.z).normalized()
    rotation_basis = rotation_basis.orthonormalized()


    var local_rotation = Basis.from_euler(Vector3(deg_to_rad(90), deg_to_rad(90), 0))


    var target_global_transform = Transform3D()
    target_global_transform.origin = target_pos
    target_global_transform.basis = rotation_basis * local_rotation


    var target_local = brick_parent.global_transform.affine_inverse() * target_global_transform


    var tween = create_tween()
    tween.set_trans(Tween.TRANS_CUBIC)
    tween.set_ease(Tween.EASE_OUT)
    tween.tween_property(brick, "transform", target_local, brick_fly_duration)

    path_row_indices[active_path_index] += 1
    path_progresses[active_path_index] += brick_length + gap

func activate_next_path(current_index: int):
    var next_index = current_index + 1
    if next_index < path_3d_array.size():
        if not path_active[next_index]:
            path_active[next_index] = true

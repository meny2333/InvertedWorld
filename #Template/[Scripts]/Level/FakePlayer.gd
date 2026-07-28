<<<<<<< HEAD
@tool
class_name FakePlayer
extends CharacterBody3D

## 假线系统 — 沿预设路径自动移动的假玩家（与 Unity FakePlayer.cs 一致）

enum State {
	Moving,
	Stopped
}

## ========== Exports ==========
@export var speed: float = 12.0
@export var characterMaterial: StandardMaterial3D
@export var startPosition: Vector3 = Vector3.ZERO
@export var firstDirection: Vector3 = Vector3(0, 90, 0)
@export var secondDirection: Vector3 = Vector3.ZERO
@export var poolSize: int = 100
@export var isWall: bool = false
@export var drawDirection: bool = false

## ========== State ==========
var state: State = State.Stopped
var playing: bool:
	get:
		return state == State.Moving

## ========== Internals ==========
var current_tail: MeshInstance3D
var _tail_position: Vector3
var _tail_holder: Node3D
var _tail_pool: Array[MeshInstance3D] = []
var _mesh_instance: MeshInstance3D
var _on_floor: bool = true
var _was_on_floor: bool = true

func _ready() -> void:
	if Engine.is_editor_hint():
		return

	# 自动创建碰撞体（必须有才能用 is_on_floor）
	var collision := get_node_or_null("CollisionShape3D") as CollisionShape3D
	if not collision:
		collision = CollisionShape3D.new()
		collision.name = "CollisionShape3D"
		collision.shape = BoxShape3D.new()
		collision.shape.size = Vector3(0.3, 0.3, 0.3)
		add_child(collision)
	# 碰撞层：自身 layer1，检测 layer2(地板)
	collision_layer = 1
	collision_mask = 2

	_mesh_instance = $MeshInstance3D
	if _mesh_instance and characterMaterial:
		_mesh_instance.set_surface_override_material(0, characterMaterial)

	_tail_holder = Node3D.new()
	_tail_holder.name = name + "TailHolder"
	get_tree().current_scene.add_child.call_deferred(_tail_holder)

	firstDirection = firstDirection
	secondDirection = secondDirection
	rotation_degrees = firstDirection

	state = State.Stopped
	_create_initial_tail()

func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return

	match state:
		State.Moving:
			var forward := global_transform.basis * Vector3.FORWARD * speed
			velocity.x = forward.x
			velocity.z = forward.z
			if not is_on_floor():
				velocity.y -= 9.8 * delta
			move_and_slide()

			_on_floor = is_on_floor()
			if current_tail and _on_floor:
				var midpoint := (_tail_position + global_position) * 0.5
				midpoint.y = global_position.y
				current_tail.global_position = midpoint

				var distance := _tail_position.distance_to(global_position)
				current_tail.scale = Vector3(1, 1, distance)
				current_tail.look_at(global_position, Vector3.UP)

			if _was_on_floor != _on_floor:
				_was_on_floor = _on_floor
				if _on_floor:
					_create_tail()
			if not _on_floor:
				current_tail = null

			if LevelManager.GameState == LevelManager.GameStatus.Died or LevelManager.GameState == LevelManager.GameStatus.Moving:
				state = State.Stopped

## 转向
func turn() -> void:
	rotation_degrees = secondDirection if rotation_degrees == firstDirection else firstDirection
	_create_tail()

## 创建新的线段（从池中获取或新建）
func _create_tail() -> void:
	var now_q := global_transform.basis.get_rotation_quaternion()
	var tail_half := 0.5

	if current_tail:
		var last_q := current_tail.global_transform.basis.get_rotation_quaternion()
		var angle := last_q.angle_to(now_q)
		if angle >= 0.0 and angle <= deg_to_rad(90.0):
			tail_half = 0.5 * tan(angle * 0.5)
		else:
			tail_half = -0.5 * tan((deg_to_rad(180.0) - angle) * 0.5)
		var end := _tail_position + last_q * Vector3.FORWARD * (_tail_position.distance_to(global_position) + tail_half)
		var mid := (_tail_position + end) * 0.5
		mid.y = global_position.y
		current_tail.global_position = mid
		current_tail.scale = Vector3(1, 1, _tail_position.distance_to(end))
		current_tail.look_at(global_position, Vector3.UP)

	_tail_position = global_position + now_q * Vector3.BACK * abs(tail_half)

	if _tail_pool.size() < poolSize:
		current_tail = _create_tail_segment()
		_tail_holder.add_child(current_tail)
		_tail_pool.append(current_tail)
	else:
		current_tail = _tail_pool.pop_front()
		_tail_pool.append(current_tail)

## 创建初始线段
func _create_initial_tail() -> void:
	_tail_position = global_position + transform.basis * Vector3.BACK * 0.5
	if _tail_pool.size() < poolSize:
		current_tail = _create_tail_segment()
		_tail_holder.add_child(current_tail)
		_tail_pool.append(current_tail)

func _create_tail_segment() -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = "FakeTail"
	# 使用角色自己的 mesh，与 Player 尾线逻辑一致
	if _mesh_instance:
		mi.mesh = _mesh_instance.mesh
		if characterMaterial:
			mi.set_surface_override_material(0, characterMaterial)
	return mi

## 清除所有线段并重置池
func clear_pool() -> void:
	for tail in _tail_pool:
		if is_instance_valid(tail):
			tail.queue_free()
	_tail_pool.clear()
	current_tail = null

## 保存当前状态用于复位
func get_reset_data() -> Dictionary:
	return {
		"playing": playing,
		"speed": speed,
		"position": global_position,
		"rotation": rotation_degrees
	}

## 从保存的数据恢复状态
func set_reset_data(data: Dictionary) -> void:
	speed = data.get("speed", 12.0)
	global_position = data.get("position", startPosition)
	rotation_degrees = data.get("rotation", firstDirection)
	state = State.Moving if data.get("playing", false) else State.Stopped
	clear_pool()
	_create_initial_tail()
=======
@tool
class_name FakePlayer
extends CharacterBody3D

## 假线系统 — 沿预设方向自动移动的线控玩家（与 Unity FakePlayer.cs 一致）

enum State {
	Moving,
	Stopped
}

## ========== Exports ==========
@export var speed: float = 12.0
@export var characterMaterial: StandardMaterial3D
@export var startPosition: Vector3 = Vector3.ZERO
@export var firstDirection: Vector3 = Vector3(0, 90, 0)
@export var secondDirection: Vector3 = Vector3.ZERO
@export var poolSize: int = 100
## 当 isWall = true 时，FakePlayer 的碰撞层设为 BaseWall (3)，
## 真实 Player 碰到会死亡。false 时不参与碰撞（纯预览）。
@export var isWall: bool = false
@export var drawDirection: bool = false

@export_group("TurnTrigger")
@export var createTurnTrigger: bool = true
@export var synchronismWithPlayer: bool = false
@export var createKey: Key = KEY_P
@export var triggerRotation: Vector3 = Vector3(0, 45, 0)
@export var triggerScale: Vector3 = Vector3(4, 3, 0.1)

## ========== State ==========
var state: State = State.Stopped
var playing: bool = false

## ========== Internals ==========
var _current_tail: MeshInstance3D
var _tail_position: Vector3
var _tail_holder: Node3D
var _tail_pool: Array[MeshInstance3D] = []
var _mesh_instance: MeshInstance3D

var _trigger_holder: Node3D
var _trigger_id: int = 0

var _previous_frame_is_grounded: bool = true
var _last_key_state: bool = false
var _last_clicked_state: bool = false

func _ready() -> void:
	if Engine.is_editor_hint():
		return

	var collision: CollisionShape3D = get_node_or_null("CollisionShape3D") as CollisionShape3D
	if not collision:
		collision = CollisionShape3D.new()
		collision.name = "CollisionShape3D"
		collision.shape = BoxShape3D.new()
		collision.shape.size = Vector3(0.3, 0.3, 0.3)
		add_child(collision)

	_mesh_instance = $MeshInstance3D
	if _mesh_instance and characterMaterial:
		_mesh_instance.set_surface_override_material(0, characterMaterial)

	_tail_holder = Node3D.new()
	_tail_holder.name = name + "-TailHolder"
	get_tree().current_scene.add_child.call_deferred(_tail_holder)
	add_to_group("fake_players")

	if createTurnTrigger:
		_trigger_holder = Node3D.new()
		_trigger_holder.name = "FakePlayerTriggerHolder"
		get_tree().current_scene.add_child.call_deferred(_trigger_holder)

	global_position = startPosition
	rotation_degrees = firstDirection
	state = State.Stopped
	_setup_collision_layers()
	call_deferred("_create_tail")

## 根据 isWall 配置碰撞层
## 本体不设置障碍物层，由 _setup_tail_collision 在 tail 上设置
func _setup_collision_layers() -> void:
	pass

## 给单个 tail 设置/移除障碍物碰撞
func _setup_tail_collision(tail: MeshInstance3D) -> void:
	var body: StaticBody3D = tail.get_node_or_null("TailObstacle") as StaticBody3D
	if body:
		body.queue_free()
	if isWall:
		body = StaticBody3D.new()
		body.name = "TailObstacle"
		body.collision_layer = 1 << 2  # BaseWall
		body.collision_mask = 0
		var col: CollisionShape3D = CollisionShape3D.new()
		col.shape = BoxShape3D.new()
		col.shape.size = Vector3(1,1,1)
		body.add_child(col)
		tail.add_child(body)

func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return

	match state:
		State.Moving:
			var forward: Vector3 = transform.basis * Vector3.BACK
			velocity.x = forward.x * speed
			velocity.z = forward.z * speed
			if not is_on_floor():
				velocity.y -= 9.8 * delta
			move_and_slide()

			if _current_tail and is_on_floor():
				var midpoint: Vector3 = (_tail_position + global_position) * 0.5
				_current_tail.global_position = midpoint
				var distance: float = _tail_position.distance_to(global_position)
				_current_tail.scale = Vector3(1, 1, distance)
				if distance > 0.001:
					_current_tail.look_at(global_position, Vector3.UP)

			var is_grounded_now: bool = is_on_floor()
			if _previous_frame_is_grounded != is_grounded_now:
				_previous_frame_is_grounded = is_grounded_now
				if is_grounded_now:
					_create_tail()
				else:
					_current_tail = null

			if LevelManager.GameState == LevelManager.GameStatus.Moving or LevelManager.GameState == LevelManager.GameStatus.Died:
				state = State.Stopped

func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return

	match state:
		State.Moving:
			if not synchronismWithPlayer:
				var key_pressed: bool = Input.is_key_pressed(createKey)
				if key_pressed and not _last_key_state:
					turn()
					_create_turn_trigger()
				_last_key_state = key_pressed
			else:
				var clicked: bool = LevelManager.Clicked
				if clicked and not _last_clicked_state:
					turn()
					_create_turn_trigger()
				_last_clicked_state = clicked

func turn() -> void:
	rotation_degrees = secondDirection if rotation_degrees.is_equal_approx(firstDirection) else firstDirection
	_create_tail()

func _create_tail() -> void:
	var now_q: Quaternion = global_transform.basis.get_rotation_quaternion()
	var tail_half: float = 0.5

	if _current_tail:
		var last_q: Quaternion = _current_tail.global_transform.basis.get_rotation_quaternion()
		var angle: float = last_q.angle_to(now_q)
		if angle >= 0.0 and angle <= deg_to_rad(90.0):
			tail_half = 0.5 * tan(angle * 0.5)
		else:
			tail_half = -0.5 * tan((deg_to_rad(180.0) - angle) * 0.5)
		var end: Vector3 = _tail_position + last_q * Vector3.FORWARD * (_tail_position.distance_to(global_position) + tail_half)
		var mid: Vector3 = (_tail_position + end) * 0.5
		mid.y = global_position.y
		_current_tail.global_position = mid
		_current_tail.scale = Vector3(1, 1, _tail_position.distance_to(end))
		if _tail_position.distance_to(end) > 0.001:
			_current_tail.look_at(global_position, Vector3.UP)

	_tail_position = global_position + now_q * Vector3.FORWARD * abs(tail_half)

	if _tail_pool.size() < poolSize:
		_current_tail = _create_tail_segment()
		_tail_holder.add_child(_current_tail)
		_current_tail.global_position = global_position
		_tail_pool.append(_current_tail)
		_setup_tail_collision(_current_tail)
	else:
		_current_tail = _tail_pool.pop_front()
		_tail_pool.append(_current_tail)
		_current_tail.global_position = global_position
		_setup_tail_collision(_current_tail)

func _create_tail_segment() -> MeshInstance3D:
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.name = "FakeTail"
	if _mesh_instance:
		mi.mesh = _mesh_instance.mesh
		if characterMaterial:
			mi.set_surface_override_material(0, characterMaterial)
	return mi

func clear_pool() -> void:
	for tail in _tail_pool:
		if is_instance_valid(tail):
			tail.queue_free()
	_tail_pool.clear()
	_current_tail = null

func get_reset_data() -> Dictionary:
	return {
		"playing": playing,
		"speed": speed,
		"position": global_position,
		"rotation": rotation_degrees
	}

func set_reset_data(data: Dictionary) -> void:
	speed = data.get("speed", 12.0)
	global_position = data.get("position", startPosition)
	rotation_degrees = data.get("rotation", firstDirection)
	state = State.Stopped  # 复活后强制停止，等待玩家启动
	clear_pool()
	_create_tail()

func _create_turn_trigger() -> void:
	if not _trigger_holder:
		return
	
	var area: Area3D = Area3D.new()
	area.name = "FakePlayerTurnTrigger %d" % _trigger_id
	_trigger_id += 1

	var collision: CollisionShape3D = CollisionShape3D.new()
	collision.shape = BoxShape3D.new()
	collision.shape.size = Vector3(1, 1, 1)
	area.add_child(collision)

	var trigger: FakePlayerTrigger = FakePlayerTrigger.new()
	trigger.targetPlayer = self
	trigger.type = FakePlayerTrigger.SetType.Turn
	area.add_child(trigger)

	_trigger_holder.add_child(area)
	area.global_position = global_position
	area.rotation_degrees = triggerRotation
	area.scale = triggerScale
>>>>>>> upstream/main

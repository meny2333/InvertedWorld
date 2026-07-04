extends Node3D
## ChangeTailParent 纯组件触发器
## 玩家进入后等待下一次点击，清除之前的 tail 并将 tail holder 重设到新 parent

@export_group("目标设置")
@export var new_parent: NodePath

var _waiting := false

func trigger(body: Node3D) -> void:
	if not body is CharacterBody3D:
		return
	_waiting = true

func _process(_delta: float) -> void:
	if not _waiting:
		return
	if not is_instance_valid(Player.instance):
		_waiting = false
		return
	if Input.is_action_just_pressed("turn"):
		_waiting = false
		_apply_change()

func _apply_change() -> void:
	var player := Player.instance

	# 清除之前的 tail（复用 Player._clear_tail 逻辑）
	if player.has_method("_clear_tail"):
		player._clear_tail()

	# 查找现有 PlayerTailHolder
	var tree := player.get_tree()
	var old_holder := tree.current_scene.get_node_or_null("PlayerTailHolder") as Node3D

	# 创建或查找新的 parent
	var new_holder: Node3D = null
	if new_parent.is_empty():
		# 不指定 parent 时，新建一个同级 holder
		new_holder = Node3D.new()
		new_holder.name = "PlayerTailHolder"
		tree.current_scene.add_child(new_holder)
	else:
		var target := tree.current_scene.get_node_or_null(new_parent) as Node3D
		if target:
			if target.name == "PlayerTailHolder":
				new_holder = target
			else:
				# 在目标 parent 下创建新的 PlayerTailHolder
				new_holder = Node3D.new()
				new_holder.name = "PlayerTailHolder"
				target.add_child(new_holder)
		else:
			push_warning("[ChangeTailParent] 找不到目标 parent: ", new_parent)
			return

	# 若旧 holder 与新 holder 不是同一个，移除旧 holder
	if old_holder and is_instance_valid(old_holder) and new_holder != old_holder:
		old_holder.queue_free()

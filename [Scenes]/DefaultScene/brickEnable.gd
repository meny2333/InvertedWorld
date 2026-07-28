extends Node3D
## BrickEnableTrigger - 砖块生成器启用触发组件
## 由父节点 BaseTrigger 触发，并通过 Checkpoint 的全局复活流程回滚状态。

@export var brick: Node3D

var _checkpoint_index: int = -1
var _state_before_trigger: bool = false

func _ready() -> void:
	if not Engine.is_editor_hint():
		LevelManager.add_revive_listener(_on_revive)

## 由父节点 BaseTrigger 调用的入口方法
func trigger(body: Node3D) -> void:
	if not body is CharacterBody3D or not is_instance_valid(brick):
		return

	var current_state: bool = bool(brick.get("enable"))
	var current_checkpoint_index: int = LevelManager.checkpoint_count
	if _checkpoint_index != current_checkpoint_index:
		_checkpoint_index = current_checkpoint_index
		_state_before_trigger = current_state

	brick.set("enable", not current_state)

func _on_revive() -> void:
	if _checkpoint_index < 0 or not is_instance_valid(brick):
		return

	LevelManager.CompareCheckpointIndex(_checkpoint_index, func() -> void:
		if not is_instance_valid(brick):
			return
		brick.set("enable", _state_before_trigger)
		_checkpoint_index = -1
	)

func _exit_tree() -> void:
	if not Engine.is_editor_hint():
		LevelManager.remove_revive_listener(_on_revive)

extends Node3D
## CylinderEnableTrigger - 圆柱线启用触发组件
## 由父节点 BaseTrigger 触发，调用引用的 cylinderLine 启用/关闭圆柱线系统。
## 与 cylinderLine.gd 的 set_enable_trigger 协作；复活时由 cylinderLine 自行回滚。

@export var cylinder_line: NodePath
@export var enable: bool = true

## 由父节点 BaseTrigger 调用的入口方法
func trigger(body: Node3D) -> void:
	print("[CylinderEnableTrigger] trigger by ", body, " enable=", enable)
	if body is CharacterBody3D:
		_apply()

func _apply() -> void:
	var line := get_node_or_null(cylinder_line)
	print("[CylinderEnableTrigger] line node = ", line, " path=", cylinder_line)
	if line and line.has_method("set_enable_trigger"):
		print("[CylinderEnableTrigger] BEFORE set_enable_trigger: enable=", line.enable,
			" ready_called=", line.ready_called,
			" resources_initialized=", line.resources_initialized,
			" engage_flag=", line.engage_flag,
			" mainline=", line.mainline,
			" cylinder_tail_parent=", line.cylinder_tail_parent,
			" tail_child_count=", (line.cylinder_tail_parent.get_child_count() if line.cylinder_tail_parent else -1),
			" is_drawing=", line.is_drawing,
			" has_last_mapped_position=", line.has_last_mapped_position)
		line.set_enable_trigger(enable)
		print("[CylinderEnableTrigger] AFTER  set_enable_trigger: enable=", line.enable,
			" engage_flag=", line.engage_flag,
			" is_drawing=", line.is_drawing,
			" current_cylinder_line=", line.current_cylinder_line,
			" cylinder_tail_parent=", line.cylinder_tail_parent,
			" tail_child_count=", (line.cylinder_tail_parent.get_child_count() if line.cylinder_tail_parent else -1))
		if line.cylinder_tail_parent:
			for c in line.cylinder_tail_parent.get_children():
				print("    child: ", c.name, " visible=", c.visible, " global_pos=", c.global_position)

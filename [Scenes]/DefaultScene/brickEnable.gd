extends Node3D
## CylinderEnableTrigger - 圆柱线启用触发组件
## 由父节点 BaseTrigger 触发，调用引用的 cylinderLine 启用/关闭圆柱线系统。
## 与 cylinderLine.gd 的 set_enable_trigger 协作；复活时由 cylinderLine 自行回滚。

@export var brick: Node3D

## 由父节点 BaseTrigger 调用的入口方法
func trigger(body: Node3D) -> void:
	if body is CharacterBody3D:
		brick.enable = !brick.enable

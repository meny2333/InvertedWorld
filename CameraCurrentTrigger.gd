extends BaseTrigger
class_name CameraCurrentTrigger





@export var to_camera: NodePath

var _from_camera_path: NodePath
var _checkpoint_index: int = 0

func _ready() -> void :
    super._ready()
    LevelManager.add_revive_listener(_on_revive)

func _on_triggered(_body: Node3D) -> void :
    _checkpoint_index = LevelManager.checkpoint_count
    _save_current_camera()
    _apply(_from_camera_path, to_camera)

func _save_current_camera() -> void :
    var viewport = get_viewport()
    if viewport.get_camera_3d():
        _from_camera_path = viewport.get_camera_3d().get_path()
    else:
        _from_camera_path = NodePath()

func _apply(from_path: NodePath, to_path: NodePath) -> void :
    var from_cam = get_node_or_null(from_path) as Camera3D if from_path else null
    var to_cam = get_node_or_null(to_path) as Camera3D if to_path else null

    if from_cam:
        from_cam.current = false
    if to_cam:
        to_cam.current = true

    if debug_mode:
        print("[CameraCurrentTrigger] ", name, " 切换: ", from_path, " → ", to_path)

func _on_revive() -> void :
    LevelManager.CompareCheckpointIndex(_checkpoint_index, func():
        _apply(to_camera, _from_camera_path)

        if debug_mode:
            print("[CameraCurrentTrigger] ", name, " 复活恢复: ", to_camera, " → ", _from_camera_path)
    )

func _exit_tree() -> void :
    if not Engine.is_editor_hint():
        LevelManager.remove_revive_listener(_on_revive)

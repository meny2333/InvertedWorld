extends Camera3D


signal tilted_left
signal tilted_right

@export_group("Rotation Settings")
@export var tilt_angle_degrees: = 180.0
@export var tilt_duration: = 0.1
@export var return_duration: = 1.0

@export_group("Input Settings")
@export var gyro_rotation_threshold: = 3.0
@export var gyro_cooldown: = 0.5
@export var gyro_right_is_negative: = true
@export_group("Debug Settings")
@export var enable_gyro_debug: = false
@export var gyro_debug_interval: = 0.2


var is_tilting: = false
var original_rotation_z: = 0.0
var gyro_cooldown_timer: = 0.0
var gyro_debug_timer: = 0.0
var last_key_left: = false
var last_key_right: = false

func _ready():

    original_rotation_z = rotation.z

func _input(event):

    if is_tilting:
        return


    if event is InputEventKey:
        if event.pressed and not event.echo:
            match event.keycode:
                KEY_LEFT, KEY_A:
                    _execute_tilt(1)
                KEY_RIGHT, KEY_D:
                    _execute_tilt(-1)

func _process(delta):

    if is_tilting:
        return


    _print_gyro_debug(delta)


    if gyro_cooldown_timer > 0:
        gyro_cooldown_timer -= delta
        return


    var gyro: = Input.get_gyroscope()
    var z_value: = gyro.z
    var right_value: = - z_value if gyro_right_is_negative else z_value


    if right_value > gyro_rotation_threshold:
        _execute_tilt(-1)
        gyro_cooldown_timer = gyro_cooldown
    elif right_value < - gyro_rotation_threshold:
        _execute_tilt(1)
        gyro_cooldown_timer = gyro_cooldown

func _print_gyro_debug(delta: float) -> void :
    if not enable_gyro_debug:
        return

    gyro_debug_timer -= delta
    if gyro_debug_timer > 0:
        return
    gyro_debug_timer = gyro_debug_interval

    var gyro: = Input.get_gyroscope()
    var right_value: = - gyro.z if gyro_right_is_negative else gyro.z
    print(
        "[GyroDebug] gyro=", gyro, 
        " gyro_rot_threshold=", gyro_rotation_threshold, 
        " gyro_right_value=", right_value, 
        " cooldown=", max(gyro_cooldown_timer, 0.0)
    )



func _execute_tilt(direction: int):
    is_tilting = true


    if direction == 1:
        tilted_left.emit()
        print("Tilted Left Signal Emitted")
    else:
        tilted_right.emit()
        print("Tilted Right Signal Emitted")



    var target_rotation = rotation.z + deg_to_rad(tilt_angle_degrees * direction)


    var tween = create_tween()
    tween.set_trans(Tween.TRANS_QUAD)
    tween.set_ease(Tween.EASE_IN_OUT)


    tween.tween_property(self, "rotation:z", target_rotation, tilt_duration)


    tween.tween_property(self, "rotation:z", original_rotation_z, return_duration)


    tween.finished.connect( func():
        is_tilting = false
        rotation.z = original_rotation_z
        print("Tilt animation completed, reset to original")
    )

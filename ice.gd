@tool
extends MeshInstance3D


@export var reference_animation_player: AnimationPlayer

@export var appear_time: int = 0

@export var emission_color: Color = Color(1, 1, 1, 1)

@export var base_color: Color = Color(1, 1, 1, 1)

@export var alpha_curve: Curve

@export var emission_curve: Curve


@export_group("Preview")
@export_enum("Idle", "Play") var preview_action: int = 0:
    set(value):
        if value == 1:
            _start_preview()
        preview_action = 0


const ALPHA_DURATION: float = 1.0
const EMISSION_DURATION: float = 0.25
var animation_duration: float:
    get:
        return max(ALPHA_DURATION, EMISSION_DURATION)


var is_playing: bool = false
var is_reset: bool = true


var is_previewing: bool = false
var preview_time: float = 0.0


var mat_override: StandardMaterial3D

func _ready():

    if material_override != null:

        mat_override = material_override.duplicate()
    elif mesh != null and mesh.surface_get_material(0) != null:

        mat_override = mesh.surface_get_material(0).duplicate()
    else:

        mat_override = StandardMaterial3D.new()


    material_override = mat_override


    _update_material_properties(0.0, 0.0)

func _process(delta):

    if is_previewing:
        _process_preview(delta)
        return


    if Engine.is_editor_hint():
        return

    if reference_animation_player == null or alpha_curve == null or emission_curve == null or !reference_animation_player.is_playing():
        return

    var reference_time = reference_animation_player.current_animation_position
    var start_time = float(appear_time) / 60.0
    var time_since_start = reference_time - start_time


    if not is_reset and time_since_start < 0.0:
        _update_material_properties(0.0, 0.0)
        is_reset = true
        return
    elif is_reset and time_since_start >= 0.0:
        is_reset = false


    if time_since_start >= 0.0 and time_since_start <= animation_duration:
        is_playing = true
        var normalized_alpha_time = clamp(time_since_start / ALPHA_DURATION, 0.0, 1.0)
        var normalized_emission_time = clamp(time_since_start / EMISSION_DURATION, 0.0, 1.0)
        _update_material_properties(normalized_alpha_time, normalized_emission_time)
    elif is_playing:

        _update_material_properties(1.0, 1.0)
        is_playing = false

func _start_preview():

    if mat_override == null:
        _ready()

    is_previewing = true
    preview_time = 0.0
    print("开始预览动画效果")

func _process_preview(delta):
    preview_time += delta

    if preview_time <= animation_duration:
        var normalized_alpha_time = clamp(preview_time / ALPHA_DURATION, 0.0, 1.0)
        var normalized_emission_time = clamp(preview_time / EMISSION_DURATION, 0.0, 1.0)
        _update_material_properties(normalized_alpha_time, normalized_emission_time)
    else:

        _update_material_properties(1.0, 1.0)
        is_previewing = false
        print("预览结束")

func _update_material_properties(normalized_alpha_time: float, normalized_emission_time: float):

    if mat_override == null:
        return


    var alpha = alpha_curve.sample_baked(normalized_alpha_time) if alpha_curve != null else 1.0
    var emission_intensity = emission_curve.sample_baked(normalized_emission_time) if emission_curve != null else 1.0


    var final_base_color = Color(base_color.r, base_color.g, base_color.b, alpha)
    var final_emission_color = emission_color * emission_intensity


    mat_override.albedo_color = final_base_color
    mat_override.emission_enabled = true
    mat_override.emission = final_emission_color


    visible = alpha > 0.001

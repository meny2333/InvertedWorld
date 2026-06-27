extends MeshInstance3D


@export var preset: int = 0


static var gradient_cache = {}

func _ready():

    if not gradient_cache.has(preset):
        gradient_cache[preset] = _init_gradient()


    var material = get_surface_override_material(0)

    if material == null:
        material = get_active_material(0)

    if material != null:
        material = material.duplicate()
    else:

        material = StandardMaterial3D.new()


    var t = randf()
    var color = gradient_cache[preset].sample(t)


    if preset != 0:
        if randi() % 4 == 0:
            color.a = 0.4


    material.albedo_color = color


    set_surface_override_material(0, material)

func _init_gradient() -> Gradient:
    var gradient = Gradient.new()
    match preset:
        0:

            gradient.add_point(0.0, Color(0.341, 0.276, 0.792, 1.0))
            gradient.add_point(1.0, Color(0.651, 0.804, 0.164, 1.0))
        _:

            gradient.add_point(0.383, Color(0.799, 0.792, 0.771, 1.0))
            gradient.add_point(0.386, Color(0.805, 0.735, 0.117, 1.0))
            gradient.add_point(0.677, Color(0.565, 0.722, 0.561, 1.0))
            gradient.add_point(0.764, Color(0.702, 0.447, 0.576, 1.0))
            gradient.add_point(0.777, Color(0.126, 0.129, 0.137, 1.0))
            gradient.add_point(1.0, Color(0.003, 0.003, 0.004, 1.0))
    return gradient

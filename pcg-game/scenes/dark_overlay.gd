extends CanvasLayer


@export var light_radius: float = 0.13   # tweak for bigger / smaller light
@export var softness:     float = 0.07   # tweak for harder / softer edge

@onready var rect: ColorRect = $ColorRect

var player: Node2D = null   

func _ready() -> void:
	rect.anchor_right  = 1.0
	rect.anchor_bottom = 1.0
	rect.offset_right  = 0.0
	rect.offset_bottom = 0.0

func _process(_delta: float) -> void:
	if player == null:
		return

	var mat: ShaderMaterial = rect.material as ShaderMaterial
	if mat == null:
		return

	var vp      := get_viewport()
	var cam     := vp.get_camera_2d()
	var vp_size := vp.get_visible_rect().size

	var screen_pos: Vector2
	if cam:
		screen_pos = player.global_position - cam.get_screen_center_position() + vp_size * 0.5
	else:
		screen_pos = player.global_position

	var uv := screen_pos / vp_size

	mat.set_shader_parameter("light_pos",    uv)
	mat.set_shader_parameter("light_radius", light_radius)
	mat.set_shader_parameter("softness",     softness)

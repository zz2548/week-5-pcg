extends CharacterBody2D

var move_speed:       float
var detection_radius: float
var damage:           int = 1

enum State { ROAM, CHASE }
var state: State = State.ROAM

var roam_target:    Vector2 = Vector2.ZERO
var roam_timer:     float   = 0.0
const ROAM_INTERVAL = 2.5

var player:    Node2D           = null
var generator: DungeonGenerator = null

var hit_flash_timer: float = 0.0
const HIT_FLASH_DURATION   = 0.15

func _ready() -> void:
	var players = get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		player = players[0]

	var generators = get_tree().get_nodes_in_group("generator")
	if generators.size() > 0:
		generator = generators[0]

	move_speed       = randf_range(30.0, 70.0)
	detection_radius = randf_range(60.0, 140.0)

	var s = randf_range(0.8, 1.4)
	scale = Vector2(s, s)

	$ColorRect.color = Color(
		randf_range(0.3, 0.6),
		randf_range(0.5, 0.85),
		randf_range(0.3, 0.55)
	)

	_pick_roam_target()

func _physics_process(delta: float) -> void:
	_update_state()
	match state:
		State.ROAM:  _do_roam(delta)
		State.CHASE: _do_chase(delta)
	move_and_slide()
	_update_flash(delta)


func _update_state() -> void:
	if player == null:
		return
	var dist = global_position.distance_to(player.global_position)
	if dist <= detection_radius:
		state = State.CHASE
	elif state == State.CHASE and dist > detection_radius * 1.5:
		state = State.ROAM
		_pick_roam_target()

func _do_roam(delta: float) -> void:
	roam_timer -= delta
	if roam_timer <= 0.0 or global_position.distance_to(roam_target) < 8.0:
		_pick_roam_target()
	var dir = (roam_target - global_position).normalized()
	velocity = dir * move_speed * 0.5

func _do_chase(_delta: float) -> void:
	if player == null:
		return
	var dir = (player.global_position - global_position).normalized()
	velocity = dir * move_speed


func _pick_roam_target() -> void:
	roam_timer = ROAM_INTERVAL
	if generator == null:
		roam_target = global_position + Vector2(randf_range(-80, 80), randf_range(-80, 80))
		return
	var tile_size = 16
	var cx = int(global_position.x / tile_size)
	var cy = int(global_position.y / tile_size)
	var candidates = []
	for dy in range(-5, 6):
		for dx in range(-5, 6):
			var nx = cx + dx
			var ny = cy + dy
			if nx >= 0 and nx < generator.width and ny >= 0 and ny < generator.height:
				if generator.grid[ny][nx] == generator.FLOOR:
					candidates.append(Vector2(
						nx * tile_size + tile_size / 2,
						ny * tile_size + tile_size / 2
					))
	if candidates.size() > 0:
		roam_target = candidates[randi() % candidates.size()]
	else:
		roam_target = global_position


func _update_flash(delta: float) -> void:
	if hit_flash_timer > 0.0:
		hit_flash_timer -= delta
		$ColorRect.modulate = Color.WHITE
	else:
		$ColorRect.modulate = Color(1, 1, 1, 1)

func flash_hit() -> void:
	hit_flash_timer = HIT_FLASH_DURATION

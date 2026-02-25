extends CharacterBody2D

@onready var anim: AnimatedSprite2D = $AnimatedSprite2D
@onready var hit_up: Area2D = $AttackHitboxUp
@onready var hit_mid: Area2D = $AttackHitboxMid
@onready var hit_down: Area2D = $AttackHitboxDown

@export var touch_damage_range := 14.0
@export var touch_damage_cd := 0.35
var touch_cd_timer := 0.0

var move_speed: float
var detection_radius: float
var damage: int = 1

@export var max_hp: int = 5
var hp: int

# Feel tuning
@export var attack_range: float = 22.0
@export var attack_stop_range: float = 26.0
# Cooldown must be longer than the attack animation so the zombie is forced
# into CHASE for at least one full movement cycle before it can re-attack.
# Previously 0.8 was shorter than the animation in some cases, causing the
# zombie to flip back into ATTACK on the first frame after CHASE resumed.
@export var attack_cooldown: float = 1.2
var attack_cd_timer: float = 0.0

# Hit timing (up -> mid -> down)
@export var t_up: float   = 0.05
@export var t_mid: float  = 0.12
@export var t_down: float = 0.20
@export var t_end: float  = 0.28

enum State { ROAM, CHASE, ATTACK, HURT, DEAD }
var state: State = State.ROAM

enum AttackStyle { ONLY_ATTACK1, ONLY_ATTACK2, RANDOM }
@export var attack_style: AttackStyle = AttackStyle.RANDOM

var roam_target: Vector2 = Vector2.ZERO
var roam_timer: float    = 0.0
const ROAM_INTERVAL      = 2.5

# Pathfinding — path is recalculated every PATH_INTERVAL seconds.
# Storing the path as a waypoint list avoids recalculating every frame.
var path:          PackedVector2Array = []
var path_index:    int   = 0
var path_timer:    float = 0.0
const PATH_INTERVAL: float = 0.4   # recalculate path this often (seconds)
const TILE_SIZE:    int   = 16

var player: Node2D         = null
var generator: DungeonGenerator = null

var hurt_timer: float = 0.0
const HURT_DURATION: float = 0.4   # how long the hurt stun lasts

var hit_flash_timer: float = 0.0
const HIT_FLASH_DURATION   = 0.15

# Prevent multiple hits during ONE swing
var swing_hit_ids := {}

# Used to cancel old timers when a new swing starts
var hit_phase := 0


func _ready() -> void:
	hp = max_hp
	add_to_group("zombies")

	var players = get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		player = players[0]

	var generators = get_tree().get_nodes_in_group("generator")
	if generators.size() > 0:
		generator = generators[0]

	move_speed       = randf_range(35.0, 70.0)
	detection_radius = randf_range(80.0, 160.0)

	_pick_roam_target()
	anim.play("idle")

	_disable_all_hitboxes()
	hit_up.body_entered.connect(_on_hitbox_body_entered)
	hit_mid.body_entered.connect(_on_hitbox_body_entered)
	hit_down.body_entered.connect(_on_hitbox_body_entered)


func _physics_process(delta: float) -> void:
	if state == State.DEAD:
		return

	touch_cd_timer    = max(0.0, touch_cd_timer - delta)
	attack_cd_timer   = max(0.0, attack_cd_timer - delta)

	# Touch damage — applied regardless of attack state so the zombie
	# still hurts when it walks into the player during chase/roam.
	if player != null and touch_cd_timer <= 0.0:
		if global_position.distance_to(player.global_position) <= touch_damage_range:
			if player.has_method("take_damage") and player.take_damage(damage):
				touch_cd_timer = touch_damage_cd

	match state:
		State.ATTACK:
			# Hold position during the swing; cancel hitboxes if player backs away.
			velocity = Vector2.ZERO
			if player != null:
				if global_position.distance_to(player.global_position) > attack_stop_range:
					_disable_all_hitboxes()
			move_and_slide()
			_update_flash(delta)
			# All animations are set to loop=true in the scene, so
			# animation_finished never fires.  Drive the state exit from the
			# cooldown timer instead: once it hits zero the swing is over.
			if attack_cd_timer <= 0.0:
				_disable_all_hitboxes()
				state = State.CHASE

		State.HURT:
			velocity = Vector2.ZERO
			move_and_slide()
			_update_flash(delta)
			# hurt animation loops, so exit via timer instead.
			hurt_timer -= delta
			if hurt_timer <= 0.0:
				state = State.CHASE

		State.ROAM:
			_do_roam(delta)
			_set_facing_from_velocity()
			_play_if_not("idle")
			move_and_slide()
			_update_flash(delta)
			_update_state()

		State.CHASE:
			_do_chase(delta)
			_set_facing_from_velocity()
			_play_if_not("idle")
			move_and_slide()
			_update_flash(delta)
			_update_state()


func _update_state() -> void:
	# Only called from ROAM and CHASE — never from ATTACK or HURT, which manage
	# their own transitions via animation callbacks and the cooldown timer.
	if player == null:
		return

	var dist: float = global_position.distance_to(player.global_position)

	if dist <= detection_radius:
		# Only start a new attack if the cooldown has fully expired.
		# This guarantees the zombie spends at least (attack_cooldown) seconds
		# in CHASE before it can swing again, so it visibly re-approaches
		# the player rather than spinning in place.
		if dist <= attack_range and attack_cd_timer <= 0.0:
			_start_attack()
		else:
			state = State.CHASE
	elif dist > detection_radius * 1.5:
		state = State.ROAM
		_pick_roam_target()


func _do_roam(delta: float) -> void:
	# During roam, path toward a random nearby floor tile, refreshing every
	# ROAM_INTERVAL seconds or when the destination is reached.
	roam_timer -= delta
	path_timer -= delta
	if roam_timer <= 0.0 or (path.size() > 0 and path_index >= path.size()):
		_pick_roam_target()
	_follow_path(delta, move_speed * 0.5)


func _do_chase(delta: float) -> void:
	# During chase, recalculate the path to the player every PATH_INTERVAL
	# seconds so the zombie re-routes around walls as the player moves.
	path_timer -= delta
	if path_timer <= 0.0 or path.is_empty():
		_request_path_to(player.global_position)
	_follow_path(delta, move_speed)


func _follow_path(delta: float, speed: float) -> void:
	# Advance along the current waypoint list.  Each waypoint is a world-space
	# pixel position at the centre of a tile; we step toward it and pop it when
	# within TILE_SIZE / 2 to avoid overshooting.
	if path.is_empty() or path_index >= path.size():
		velocity = Vector2.ZERO
		return
	var target: Vector2 = path[path_index]
	var diff:   Vector2 = target - global_position
	if diff.length() < TILE_SIZE / 2.0:
		path_index += 1
		if path_index >= path.size():
			velocity = Vector2.ZERO
			return
		target = path[path_index]
		diff   = target - global_position
	velocity = diff.normalized() * speed


func _request_path_to(world_target: Vector2) -> void:
	# Convert world positions to grid cells, ask AStarGrid2D for a cell path,
	# then convert each cell back to a world-space pixel centre.
	path_timer = PATH_INTERVAL
	if generator == null or generator.astar == null:
		return
	var from_cell := Vector2i(
		int(global_position.x / TILE_SIZE),
		int(global_position.y / TILE_SIZE)
	)
	var to_cell := Vector2i(
		int(world_target.x / TILE_SIZE),
		int(world_target.y / TILE_SIZE)
	)
	# Clamp to grid bounds so out-of-range positions don't crash AStarGrid2D.
	from_cell.x = clampi(from_cell.x, 0, generator.width  - 1)
	from_cell.y = clampi(from_cell.y, 0, generator.height - 1)
	to_cell.x   = clampi(to_cell.x,   0, generator.width  - 1)
	to_cell.y   = clampi(to_cell.y,   0, generator.height - 1)

	var cell_path: Array[Vector2i] = generator.astar.get_id_path(from_cell, to_cell)
	path       = PackedVector2Array()
	path_index = 0
	for cell in cell_path:
		path.append(Vector2(
			cell.x * TILE_SIZE + TILE_SIZE / 2.0,
			cell.y * TILE_SIZE + TILE_SIZE / 2.0
		))


func _pick_roam_target() -> void:
	roam_timer = ROAM_INTERVAL
	if generator == null:
		roam_target = global_position + Vector2(randf_range(-80, 80), randf_range(-80, 80))
		_request_path_to(roam_target)
		return
	var cx: int = int(global_position.x / TILE_SIZE)
	var cy: int = int(global_position.y / TILE_SIZE)
	var candidates: Array = []
	for dy in range(-6, 7):
		for dx in range(-6, 7):
			var nx: int = cx + dx
			var ny: int = cy + dy
			if nx >= 0 and nx < generator.width and ny >= 0 and ny < generator.height:
				if generator.grid[ny][nx] == generator.FLOOR:
					candidates.append(Vector2(
						nx * TILE_SIZE + TILE_SIZE / 2.0,
						ny * TILE_SIZE + TILE_SIZE / 2.0
					))
	if candidates.size() > 0:
		roam_target = candidates[randi() % candidates.size()]
	else:
		roam_target = global_position
	_request_path_to(roam_target)


func _set_facing_from_velocity() -> void:
	if velocity.x < -0.1:
		anim.flip_h = true
	elif velocity.x > 0.1:
		anim.flip_h = false


func _play_if_not(name: String) -> void:
	if anim.animation != name:
		anim.play(name)


# ── Attack ────────────────────────────────────────────────────────────────────

func _start_attack() -> void:
	if player == null:
		return

	state           = State.ATTACK
	attack_cd_timer = attack_cooldown
	velocity        = Vector2.ZERO

	anim.flip_h = (player.global_position.x < global_position.x)

	swing_hit_ids.clear()
	_disable_all_hitboxes()
	_update_hitboxes_offset()

	match attack_style:
		AttackStyle.ONLY_ATTACK1:
			anim.play("attack1")
		AttackStyle.ONLY_ATTACK2:
			anim.play("attack2")
		AttackStyle.RANDOM:
			anim.play("attack1" if randi() % 2 == 0 else "attack2")

	_start_swing_phases()


func _disable_all_hitboxes() -> void:
	hit_up.monitoring  = false
	hit_mid.monitoring = false
	hit_down.monitoring = false


func _enable_only(which: Area2D) -> void:
	_disable_all_hitboxes()
	which.monitoring = true


func _update_hitboxes_offset() -> void:
	var forward_x: int = 10 if not anim.flip_h else -10
	hit_up.position   = Vector2(0, -12)
	hit_mid.position  = Vector2(forward_x, 0)
	hit_down.position = Vector2(0, 12)


func _start_swing_phases() -> void:
	hit_phase += 1
	var my_phase: int = hit_phase

	_call_later(t_up,   my_phase, hit_up)
	_call_later(t_mid,  my_phase, hit_mid)
	_call_later(t_down, my_phase, hit_down)
	_call_later_disable(t_end, my_phase)


func _call_later(t: float, phase_id: int, which: Area2D) -> void:
	get_tree().create_timer(t).timeout.connect(func():
		if state != State.ATTACK:
			return
		if phase_id != hit_phase:
			return
		_enable_only(which)
	)


func _call_later_disable(t: float, phase_id: int) -> void:
	get_tree().create_timer(t).timeout.connect(func():
		if phase_id != hit_phase:
			return
		_disable_all_hitboxes()
	)


func _on_hitbox_body_entered(body: Node) -> void:
	if state != State.ATTACK:
		return
	if not body.is_in_group("player"):
		return

	var id: int = body.get_instance_id()
	if swing_hit_ids.has(id):
		return
	swing_hit_ids[id] = true

	if body.has_method("take_damage"):
		body.take_damage(damage)


# ── Damage / Death ────────────────────────────────────────────────────────────

func take_damage(amount: int) -> void:
	if state == State.DEAD:
		return

	hp -= amount
	flash_hit()

	if hp <= 0:
		state    = State.DEAD
		velocity = Vector2.ZERO
		_disable_all_hitboxes()
		anim.play("die")
		# die animation loops so animation_finished never fires; free after
		# one full cycle (4 frames at speed 5 = 0.8 s).
		get_tree().create_timer(0.8).timeout.connect(queue_free)
		return

	state = State.HURT
	hurt_timer = HURT_DURATION
	_disable_all_hitboxes()
	anim.play("hurt")
	print("zombie hp:", hp)


func _update_flash(delta: float) -> void:
	if hit_flash_timer > 0.0:
		hit_flash_timer -= delta
		anim.modulate = Color.WHITE
	else:
		anim.modulate = Color(1, 1, 1, 1)


func flash_hit() -> void:
	hit_flash_timer = HIT_FLASH_DURATION


func _on_animated_sprite_2d_animation_finished() -> void:
	# All animations in zombie1.tscn have loop=true, so this signal never fires.
	# State transitions are driven by attack_cd_timer (ATTACK), hurt_timer (HURT),
	# and a one-shot Timer (DEAD/die).  This handler is kept only because the
	# signal connection exists in the scene file.
	pass

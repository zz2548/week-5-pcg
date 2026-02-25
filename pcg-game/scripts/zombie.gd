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
@export var attack_range: float = 22.0          # increase slightly
@export var attack_stop_range: float = 26.0     # if player walks out, cancel hitboxes
@export var attack_cooldown: float = 0.8
var attack_cd_timer: float = 0.0

# Hit timing (up -> mid -> down)
@export var t_up: float = 0.05
@export var t_mid: float = 0.12
@export var t_down: float = 0.20
@export var t_end: float = 0.28

enum State { ROAM, CHASE, ATTACK, HURT, DEAD }
var state: State = State.ROAM

enum AttackStyle { ONLY_ATTACK1, ONLY_ATTACK2, RANDOM }
@export var attack_style: AttackStyle = AttackStyle.RANDOM

var roam_target: Vector2 = Vector2.ZERO
var roam_timer: float = 0.0
const ROAM_INTERVAL = 2.5

var player: Node2D = null
var generator: DungeonGenerator = null

var hit_flash_timer: float = 0.0
const HIT_FLASH_DURATION = 0.15

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

	move_speed = randf_range(35.0, 70.0)
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
		
	touch_cd_timer = max(0.0, touch_cd_timer - delta)

	if player != null and touch_cd_timer <= 0.0:
		if global_position.distance_to(player.global_position) <= touch_damage_range:
			if player.has_method("take_damage") and player.take_damage(damage):
				touch_cd_timer = touch_damage_cd

	attack_cd_timer = max(0.0, attack_cd_timer - delta)

	# If attacking, we keep the zombie still (axe swing) and just wait.
	# But we also cancel hitboxes if player is far (feels less "stupid radius")
	if state == State.ATTACK:
		velocity = Vector2.ZERO
		move_and_slide()
		_update_flash(delta)

		if player != null:
			var dist = global_position.distance_to(player.global_position)
			if dist > attack_stop_range:
				_disable_all_hitboxes()

		return

	if state == State.HURT:
		velocity = Vector2.ZERO
		move_and_slide()
		_update_flash(delta)
		return

	_update_state()

	match state:
		State.ROAM:
			_do_roam(delta)
			_set_facing_from_velocity()
			_play_if_not("idle")
		State.CHASE:
			_do_chase()
			_set_facing_from_velocity()
			_play_if_not("idle")

	move_and_slide()
	_update_flash(delta)


func _update_state() -> void:
	if player == null:
		return

	var dist = global_position.distance_to(player.global_position)

	if dist <= detection_radius:
		# If close enough and cooldown ready -> attack
		if dist <= attack_range and attack_cd_timer <= 0.0:
			_start_attack()
		else:
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


func _do_chase() -> void:
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


func _set_facing_from_velocity() -> void:
	# Only right sprites, so flip for left
	if velocity.x < -0.1:
		anim.flip_h = true
	elif velocity.x > 0.1:
		anim.flip_h = false


func _play_if_not(name: String) -> void:
	if anim.animation != name:
		anim.play(name)


# ---------- Attack ----------

func _start_attack() -> void:
	if player == null:
		return

	state = State.ATTACK
	attack_cd_timer = attack_cooldown
	velocity = Vector2.ZERO

	# Face player
	anim.flip_h = (player.global_position.x < global_position.x)

	# Prepare hitboxes
	swing_hit_ids.clear()
	_disable_all_hitboxes()
	_update_hitboxes_offset()

	# Play attack animation by type
	match attack_style:
		AttackStyle.ONLY_ATTACK1:
			anim.play("attack1")
		AttackStyle.ONLY_ATTACK2:
			anim.play("attack2")
		AttackStyle.RANDOM:
			anim.play("attack1" if randi() % 2 == 0 else "attack2")

	# Run swing phases (up -> mid -> down)
	_start_swing_phases()


func _disable_all_hitboxes() -> void:
	hit_up.monitoring = false
	hit_mid.monitoring = false
	hit_down.monitoring = false


func _enable_only(which: Area2D) -> void:
	_disable_all_hitboxes()
	which.monitoring = true


func _update_hitboxes_offset() -> void:
	# Adjust to match axe swing positions
	var forward_x := 10
	if anim.flip_h:
		forward_x = -10

	hit_up.position = Vector2(0, -12)
	hit_mid.position = Vector2(forward_x, 0)
	hit_down.position = Vector2(0, 12)


func _start_swing_phases() -> void:
	hit_phase += 1
	var my_phase := hit_phase

	# Enable Up slightly after attack starts
	_call_later(t_up, my_phase, hit_up)
	_call_later(t_mid, my_phase, hit_mid)
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

	# only one hit per swing
	var id := body.get_instance_id()
	if swing_hit_ids.has(id):
		return
	swing_hit_ids[id] = true

	if body.has_method("take_damage"):
		body.take_damage(damage)


# ---------- Damage / Death ----------

func take_damage(amount: int) -> void:
	if state == State.DEAD:
		return

	hp -= amount
	flash_hit()

	if hp <= 0:
		state = State.DEAD
		velocity = Vector2.ZERO
		_disable_all_hitboxes()
		anim.play("die")
		queue_free()
		return

	state = State.HURT
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
	if anim.animation == "hurt":
		state = State.CHASE
	elif anim.animation == "attack1" or anim.animation == "attack2":
		_disable_all_hitboxes()
		state = State.CHASE
	elif anim.animation == "die":
		queue_free()

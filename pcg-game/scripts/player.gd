extends CharacterBody2D

const SPEED = 120.0
const MAX_HP = 3

var hp: int = MAX_HP
var invincible_timer: float = 0.0
const INVINCIBLE_DURATION = 1.0

@onready var anim: AnimatedSprite2D = $AnimatedSprite2D

var attacking := false
var dead := false

signal died
signal hp_changed(new_hp: int)

func _ready() -> void:
	$Camera2D.zoom = Vector2(3.0, 3.0)
	anim.play("idle")

func _physics_process(delta: float) -> void:
	if dead:
		return

	# Movement
	var dir = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	velocity = dir * SPEED
	move_and_slide()

	# Flip for left (since you only have right-facing sprites)
	if dir.x < 0:
		anim.flip_h = true
	elif dir.x > 0:
		anim.flip_h = false

	# Invincibility blinking
	if invincible_timer > 0.0:
		invincible_timer -= delta
		anim.visible = fmod(invincible_timer, 0.2) > 0.1
	else:
		anim.visible = true

	# Don't override attack/damage animations while they are playing
	if attacking:
		return
	if anim.animation == "damage" and anim.is_playing():
		return
	if anim.animation == "die" and anim.is_playing():
		return

	# Idle / Walk
	if dir.length() == 0:
		if anim.animation != "idle":
			anim.play("idle")
	else:
		if anim.animation != "walk":
			anim.play("walk")

func _input(event: InputEvent) -> void:
	if dead:
		return

	# Make sure you have an input action named "attack" in Project Settings -> Input Map
	if event.is_action_pressed("attack") and not attacking:
		attacking = true
		anim.play("attack")

func take_damage(amount: int) -> bool:
	if dead:
		return false
	if invincible_timer > 0.0:
		return false

	hp -= amount
	invincible_timer = INVINCIBLE_DURATION
	emit_signal("hp_changed", hp)

	if hp <= 0:
		dead = true
		anim.play("die")
		emit_signal("died")
	else:
		# Play hit animation
		anim.play("damage")

	return true

func _on_animated_sprite_2d_animation_finished() -> void:
	# When attack ends, allow movement animations again
	if anim.animation == "attack":
		attacking = false

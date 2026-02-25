extends CharacterBody2D

const SPEED = 105.0
const MAX_HP = 10


var facing := Vector2.RIGHT
var hp: int = MAX_HP
var invincible_timer: float = 0.0
const INVINCIBLE_DURATION = 1.0

@onready var anim: AnimatedSprite2D = $AnimatedSprite2D
@onready var attack_hitbox: Area2D = $AttackHitbox

@export var attack_damage: int = 2
@export var attack_window: float = 0.15

var dead := false
var locked_anim := ""        # "", "attack", "damage", "die"
var attack_timer := 0.0
var hit_ids := {}

signal died
signal hp_changed(new_hp: int)

func _ready() -> void:
	$Camera2D.zoom = Vector2(3.0, 3.0)
	anim.play("idle")

	attack_hitbox.monitoring = false
	attack_hitbox.body_entered.connect(_on_attack_hitbox_body_entered)

func _physics_process(delta: float) -> void:
	if dead:
		return

	# attack window
	if attack_timer > 0.0:
		attack_timer -= delta
		if attack_timer <= 0.0:
			attack_hitbox.monitoring = false

	# movement
	var dir = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	velocity = dir * SPEED
	move_and_slide()
	
	if dir.length() > 0.1:
		facing = dir.normalized()
	
	# flip
	if dir.x < 0:
		anim.flip_h = true
	elif dir.x > 0:
		anim.flip_h = false

	# invincibility blink
	if invincible_timer > 0.0:
		invincible_timer -= delta
		anim.visible = fmod(invincible_timer, 0.2) > 0.1
	else:
		anim.visible = true

	# don't override locked anims
	if locked_anim != "":
		return

	# idle/walk
	anim.play("walk" if dir.length() > 0 else "idle")

func _input(event: InputEvent) -> void:
	if dead:
		return

	if event.is_action_pressed("attack") and locked_anim != "die" and locked_anim != "attack":
		locked_anim = "attack"
		anim.play("attack")

		# enable hitbox briefly
		hit_ids.clear()
		_update_attack_hitbox_offset()
		attack_hitbox.monitoring = true
		attack_timer = attack_window
		call_deferred("_apply_attack_damage")

func _update_attack_hitbox_offset() -> void:
	var ax := absf(facing.x)
	var ay := absf(facing.y)

	if ax >= ay:
		# left/right
		attack_hitbox.position = Vector2(10, 0) if facing.x >= 0 else Vector2(-10, 0)
		anim.flip_h = (facing.x < 0)
	else:
		# up/down
		attack_hitbox.position = Vector2(0, 10) if facing.y >= 0 else Vector2(0, -10)
		
	print("hitbox global pos:", attack_hitbox.global_position)

func _on_attack_hitbox_body_entered(body: Node) -> void:
	# zombies are in group "zombies" (your zombie.gd already does add_to_group("zombies"))
	if not body.is_in_group("zombies"):
		return

	var id := body.get_instance_id()
	if hit_ids.has(id):
		return
	hit_ids[id] = true

	if body.has_method("take_damage"):
		body.take_damage(attack_damage)

func take_damage(amount: int) -> bool:
	if dead or invincible_timer > 0.0:
		return false

	hp -= amount
	invincible_timer = INVINCIBLE_DURATION
	emit_signal("hp_changed", hp)

	if hp <= 0:
		dead = true
		locked_anim = "die"
		anim.play("die")
		emit_signal("died")
	else:
		locked_anim = "damage"
		anim.play("damage")

	return true

func _on_animated_sprite_2d_animation_finished() -> void:
	# IMPORTANT: attack/damage must be One Shot (Loop OFF) or this won't fire
	if anim.animation == "attack" and locked_anim == "attack":
		locked_anim = ""
		attack_hitbox.monitoring = false
	if anim.animation == "damage" and locked_anim == "damage":
		locked_anim = ""
		
func _apply_attack_damage() -> void:
	for b in attack_hitbox.get_overlapping_bodies():
		if b.is_in_group("zombies") and b.has_method("take_damage"):
			b.take_damage(attack_damage)
	print("attack overlaps:", attack_hitbox.get_overlapping_bodies().size())

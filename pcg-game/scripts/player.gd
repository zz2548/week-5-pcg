extends CharacterBody2D

const SPEED = 120.0
const MAX_HP = 3

var hp: int = MAX_HP
var invincible_timer: float = 0.0
const INVINCIBLE_DURATION = 1.0

var _sprite: CanvasItem = null

signal died
signal hp_changed(new_hp: int)

func _ready() -> void:
	$Camera2D.zoom = Vector2(3.0, 3.0)
	_sprite = $"ColorRect(placeholder for player sprite)"

func _physics_process(delta: float) -> void:
	var dir = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	velocity = dir * SPEED
	move_and_slide()

	if invincible_timer > 0.0:
		invincible_timer -= delta
		if _sprite:
			_sprite.visible = fmod(invincible_timer, 0.2) > 0.1
	else:
		if _sprite:
			_sprite.visible = true

func take_damage(amount: int) -> bool:
	if invincible_timer > 0.0:
		return false
	hp -= amount
	invincible_timer = INVINCIBLE_DURATION
	emit_signal("hp_changed", hp)
	if hp <= 0:
		emit_signal("died")
	return true

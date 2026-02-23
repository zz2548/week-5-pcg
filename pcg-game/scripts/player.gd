extends CharacterBody2D

const SPEED = 120.0

func _physics_process(delta):
	var dir = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	velocity = dir * SPEED
	move_and_slide()

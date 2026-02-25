extends Area2D

@onready var anim := $AnimatedSprite2D as AnimatedSprite2D

# Add an AudioStreamPlayer child named "PickupSound" in the scene
# and assign your sound file to its Stream property.
@onready var pickup_sound: AudioStreamPlayer2D = $PickupSound if has_node("PickupSound") else null

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	anim.play("idle")

	var tween = create_tween().set_loops()
	tween.tween_property(anim, "position:y", -4.0, 0.6).set_trans(Tween.TRANS_SINE)
	tween.tween_property(anim, "position:y",  4.0, 0.6).set_trans(Tween.TRANS_SINE)

func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		# Play the sound before freeing the node.
		# Reparent it to the scene root so it survives queue_free(),
		# then let it clean itself up once it finishes playing.
		if pickup_sound != null:
			pickup_sound.reparent(get_tree().current_scene)
			pickup_sound.play()
			pickup_sound.finished.connect(pickup_sound.queue_free)

		for main in get_tree().get_nodes_in_group("main"):
			main._on_key_collected()
		queue_free()

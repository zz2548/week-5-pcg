extends Area2D

@onready var anim := $AnimatedSprite2D as AnimatedSprite2D

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	anim.play("idle")

	var tween = create_tween().set_loops()
	tween.tween_property(anim, "position:y", -4.0, 0.6).set_trans(Tween.TRANS_SINE)
	tween.tween_property(anim, "position:y",  4.0, 0.6).set_trans(Tween.TRANS_SINE)

func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		for main in get_tree().get_nodes_in_group("main"):
			main._on_key_collected()
		queue_free()

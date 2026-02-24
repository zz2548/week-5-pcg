extends Area2D


func _ready() -> void:
	body_entered.connect(_on_body_entered)

	var rect = ColorRect.new()
	rect.size = Vector2(10, 10)
	rect.position = Vector2(-5, -5)
	rect.color = Color(1.0, 0.9, 0.1)
	rect.name = "ColorRect"
	add_child(rect)

	var col = CollisionShape2D.new()
	var shape = RectangleShape2D.new()
	shape.size = Vector2(10, 10)
	col.shape = shape
	add_child(col)

	var tween = create_tween().set_loops()
	tween.tween_property(rect, "position:y", -9.0, 0.6).set_trans(Tween.TRANS_SINE)
	tween.tween_property(rect, "position:y", -1.0, 0.6).set_trans(Tween.TRANS_SINE)

func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		for main in get_tree().get_nodes_in_group("main"):
			main._on_key_collected()
		queue_free()

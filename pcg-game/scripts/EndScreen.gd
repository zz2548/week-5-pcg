extends CanvasLayer

@onready var title: Label = $Box/TitleLabel
@onready var subtitle: Label = $Box/SubtitleLabel

var can_restart := true

func show_lose() -> void:
	visible = true
	title.text = "YOU DIED"
	subtitle.text = "Press Space to Restart"
	can_restart = true

func show_win() -> void:
	visible = true
	title.text = "YOU ESCAPED!"
	subtitle.text = "Press Space to Restart"
	can_restart = true

func _ready() -> void:
	visible = false

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if can_restart and event.is_action_pressed("ui_accept"):
		get_tree().reload_current_scene()

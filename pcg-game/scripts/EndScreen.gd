extends CanvasLayer

@onready var title: Label = $Box/TitleLabel
@onready var subtitle: Label = $Box/SubtitleLabel

var can_restart := true

func show_lose() -> void:
	visible = true
	title.text = "YOU DIED"
	subtitle.text = "Press R to Restart" # change R to your chosen key
	can_restart = true

func show_win() -> void:
	visible = true
	title.text = "YOU ESCAPED!"
	subtitle.text = "Press R to Restart"
	can_restart = true

func _ready() -> void:
	visible = false

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if can_restart and event is InputEventKey:
		if event.pressed and event.keycode == KEY_R:
			get_tree().paused = false
			get_tree().reload_current_scene()

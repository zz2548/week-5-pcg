extends CanvasLayer


@onready var key_label:  Label = $KeyLabel
@onready var exit_label: Label = $ExitLabel

func _ready() -> void:
	exit_label.text = ""

func update_keys(collected: int, total: int) -> void:
	key_label.text = "Keys: %d / %d" % [collected, total]

func show_exit_unlocked() -> void:
	exit_label.text = "EXIT UNLOCKED — reach the green square!"
	exit_label.modulate = Color(0.2, 1.0, 0.3)

func show_hint(text: String) -> void:
	exit_label.text = text

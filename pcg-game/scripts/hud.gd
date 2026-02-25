extends CanvasLayer

@onready var key_label:  Label = $KeyLabel
@onready var exit_label: Label = $ExitLabel

var hearts: Array = []

func _ready() -> void:
	exit_label.text = ""
	hearts = [$HeartContainer/Heart1, $HeartContainer/Heart2]

func update_health(new_hp: int, _max: int = 2) -> void:
	for i in hearts.size():
		hearts[i].color = Color(0.86, 0.06, 0.06) if i < new_hp else Color(0.2, 0.2, 0.2)

func update_keys(collected: int, total: int) -> void:
	key_label.text = "Keys: %d / %d" % [collected, total]

func show_exit_unlocked() -> void:
	exit_label.text = "EXIT UNLOCKED — reach the green square!"
	exit_label.modulate = Color(0.2, 1.0, 0.3)

func show_hint(text: String) -> void:
	exit_label.text = text

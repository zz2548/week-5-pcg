extends Node2D

const TILE_SIZE   = 16
const KEYS_NEEDED = 5
const ZOMBIE_SCENE := preload("res://scenes/zombie1.tscn")

@onready var tilemap      = $TileMap
@onready var player       = $Player
@onready var dark_overlay = $DarkOverlay
@onready var hud          = $HUD
@export var zombie_type1_scene: PackedScene
@export var zombie_type2_scene: PackedScene
@onready var end_screen = $EndScreen

var generator:      DungeonGenerator
var keys_collected: int  = 0
var exit_unlocked:  bool = false
var exit_node:      Area2D = null


const KEY_SCENE := preload("res://scenes/key.tscn")


func _ready() -> void:
	randomize()
	
	add_to_group("main")
	player.add_to_group("player")

	generator = DungeonGenerator.new()
	generator.width  = 80
	generator.height = 45
	generator.generate_instant()
	generator.add_to_group("generator")
	add_child(generator)

	_render_tilemap()
	_spawn_player()
	_spawn_zombies()
	_spawn_keys()
	_spawn_exit()

	dark_overlay.player = player

	player.died.connect(_on_player_died)
	player.hp_changed.connect(_on_hp_changed)

	hud.update_keys(0, KEYS_NEEDED)
	hud.show_hint("Find all %d keys to unlock the exit!" % KEYS_NEEDED)

func _render_tilemap() -> void:
	tilemap.clear()
	var floor_variants = [
		Vector2i(2,2), Vector2i(3,2), Vector2i(4,2),
		Vector2i(2,3), Vector2i(3,3), Vector2i(4,3),
		Vector2i(2,4), Vector2i(3,4), Vector2i(4,4),
	]
	var wall_variants = [
		Vector2i(1,1), Vector2i(2,1), Vector2i(3,1), Vector2i(4,1), Vector2i(5,1),
		Vector2i(1,2), Vector2i(5,2),
		Vector2i(1,3), Vector2i(5,3),
		Vector2i(1,4), Vector2i(5,4),
		Vector2i(1,5), Vector2i(2,5), Vector2i(3,5), Vector2i(4,5), Vector2i(5,5),
	]
	for y in generator.height:
		for x in generator.width:
			if generator.grid[y][x] == generator.FLOOR:
				var atlas = floor_variants[randi() % floor_variants.size()]
				tilemap.set_cell(0, Vector2i(x, y), 0, atlas)
			else:
				var atlas = wall_variants[randi() % wall_variants.size()]
				tilemap.set_cell(0, Vector2i(x, y), 0, atlas)

func _spawn_player() -> void:
	player.position = Vector2(
		generator.player_pos.x * TILE_SIZE + TILE_SIZE / 2,
		generator.player_pos.y * TILE_SIZE + TILE_SIZE / 2
	)


func _spawn_zombies() -> void:
	for y in generator.height:
		for x in generator.width:
			if generator.objects[y][x] == generator.OBJ_ENEMY:
				_create_zombie(Vector2(
					x * TILE_SIZE + TILE_SIZE / 2,
					y * TILE_SIZE + TILE_SIZE / 2
				))

func _create_zombie(pos: Vector2) -> void:
	var zombie = ZOMBIE_SCENE.instantiate() as CharacterBody2D
	zombie.position = pos
	add_child(zombie)


func _spawn_keys() -> void:
	var item_cells = []
	for y in generator.height:
		for x in generator.width:
			if generator.objects[y][x] == generator.OBJ_ITEM:
				item_cells.append(Vector2(
					x * TILE_SIZE + TILE_SIZE / 2,
					y * TILE_SIZE + TILE_SIZE / 2
				))
	item_cells.shuffle()

	var to_spawn = min(KEYS_NEEDED, item_cells.size())
	for i in to_spawn:
		_create_key(item_cells[i])

	if to_spawn < KEYS_NEEDED:
		var floor_cells = generator.get_cells_of_type(generator.FLOOR)
		floor_cells.shuffle()
		var extra = KEYS_NEEDED - to_spawn
		for i in min(extra, floor_cells.size()):
			var cell = floor_cells[i]
			_create_key(Vector2(
				cell.x * TILE_SIZE + TILE_SIZE / 2,
				cell.y * TILE_SIZE + TILE_SIZE / 2
			))

func _create_key(pos: Vector2) -> void:
	var key = KEY_SCENE.instantiate()
	key.position = pos
	add_child(key)

func _spawn_exit() -> void:
	exit_node = Area2D.new()
	exit_node.position = Vector2(
		generator.shop_pos.x * TILE_SIZE + TILE_SIZE / 2,
		generator.shop_pos.y * TILE_SIZE + TILE_SIZE / 2
	)

	var rect = ColorRect.new()
	rect.size = Vector2(14, 14)
	rect.position = Vector2(-7, -7)
	rect.color = Color(0.8, 0.1, 0.1)
	rect.name = "ExitRect"
	exit_node.add_child(rect)

	var col = CollisionShape2D.new()
	var shape = RectangleShape2D.new()
	shape.size = Vector2(14, 14)
	col.shape = shape
	exit_node.add_child(col)

	exit_node.body_entered.connect(_on_exit_entered)
	exit_node.monitoring = true
	add_child(exit_node)


func _physics_process(_delta: float) -> void:
	for zombie in get_tree().get_nodes_in_group("zombies"):
		var dist = zombie.global_position.distance_to(player.global_position)



func _on_key_collected() -> void:
	keys_collected += 1
	hud.update_keys(keys_collected, KEYS_NEEDED)
	if keys_collected >= KEYS_NEEDED:
		_unlock_exit()

func _unlock_exit() -> void:
	exit_unlocked = true
	hud.show_exit_unlocked()
	if exit_node and exit_node.has_node("ExitRect"):
		exit_node.get_node("ExitRect").color = Color(0.2, 1.0, 0.3)

func _on_exit_entered(body: Node2D) -> void:
	if body.is_in_group("player") and exit_unlocked:
		_on_player_won()

func _on_player_died() -> void:
	get_tree().paused = true
	end_screen.show_lose()

func _on_hp_changed(new_hp: int) -> void:
	print("HP: ", new_hp)

func _on_player_won() -> void:
	get_tree().paused = true
	end_screen.show_win()       

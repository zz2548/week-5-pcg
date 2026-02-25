extends Node2D

const TILE_SIZE   = 16
const KEYS_NEEDED = 5

const ZOMBIE_SCENE := preload("res://scenes/zombie1.tscn")
const KEY_SCENE    := preload("res://scenes/key.tscn")

@onready var tilemap      = $TileMap
@onready var player       = $Player
@onready var dark_overlay = $DarkOverlay
@onready var hud          = $HUD
@onready var end_screen   = $EndScreen

var generator:      DungeonGenerator
var keys_collected: int  = 0
var exit_unlocked:  bool = false
var exit_node:      Area2D = null
var astar:          AStarGrid2D = null

# =============================================================================
# READY — generate, render, spawn
# =============================================================================

func _ready() -> void:
	randomize()

	add_to_group("main")
	player.add_to_group("player")

	# ── Step 1: generate the dungeon ─────────────────────────────────────────
	# DungeonGenerator.generate_instant() runs the full MarkovJunior pipeline
	# and writes all spawn positions into generator.objects[y][x].
	# main.gd never decides where anything goes — it only reads the results.
	generator = DungeonGenerator.new()
	generator.width             = 160
	generator.height            = 90
	generator.max_rooms         = 50
	generator.markov_iterations = 40
	generator.generate_instant()
	generator.add_to_group("generator")
	add_child(generator)

	# ── Build AStarGrid2D from the dungeon grid ───────────────────────────────
	# One cell per tile; floor cells are walkable, walls are solid.
	# Stored on the generator node so zombies can retrieve it via the group.
	# Diagonal movement is disabled so zombies navigate axis-aligned corridors
	# cleanly without trying to cut corners through wall geometry.
	astar = AStarGrid2D.new()
	astar.region = Rect2i(0, 0, generator.width, generator.height)
	astar.cell_size = Vector2(TILE_SIZE, TILE_SIZE)
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	astar.update()
	for y in generator.height:
		for x in generator.width:
			if generator.grid[y][x] != generator.FLOOR:
				astar.set_point_solid(Vector2i(x, y), true)
	generator.astar = astar

	# ── Step 2: render tiles ─────────────────────────────────────────────────
	_render_tilemap()

	# ── Step 3: place everything the generator decided on ────────────────────
	# Each spawn function reads the generator's object layer or named positions
	# and instantiates the appropriate scene.  No placement logic lives here.
	_spawn_player()
	_spawn_objects()   # iterates objects[y][x] once for all enemies and keys
	_spawn_exit()

	# ── HUD and signals ───────────────────────────────────────────────────────
	dark_overlay.player = player
	player.died.connect(_on_player_died)
	player.hp_changed.connect(_on_hp_changed)

	hud.update_keys(0, KEYS_NEEDED)
	hud.show_hint("Find all %d keys to unlock the exit!" % KEYS_NEEDED)
	call_deferred("_init_hud_health")

# =============================================================================
# TILEMAP
# =============================================================================

func _render_tilemap() -> void:
	# Reads generator.grid and sets tile atlas coordinates for every cell.
	# Floor and wall tiles each have a small variant pool to break up repetition.
	tilemap.clear()
	var floor_variants: Array = [
		Vector2i(2,2), Vector2i(3,2), Vector2i(4,2),
		Vector2i(2,3), Vector2i(3,3), Vector2i(4,3),
		Vector2i(2,4), Vector2i(3,4), Vector2i(4,4),
	]
	var wall_variants: Array = [
		Vector2i(1,1), Vector2i(2,1), Vector2i(3,1), Vector2i(4,1), Vector2i(5,1),
		Vector2i(1,2), Vector2i(5,2),
		Vector2i(1,3), Vector2i(5,3),
		Vector2i(1,4), Vector2i(5,4),
		Vector2i(1,5), Vector2i(2,5), Vector2i(3,5), Vector2i(4,5), Vector2i(5,5),
	]
	for y in generator.height:
		for x in generator.width:
			if generator.grid[y][x] == generator.FLOOR:
				tilemap.set_cell(0, Vector2i(x, y), 0, floor_variants[randi() % floor_variants.size()])
			else:
				tilemap.set_cell(0, Vector2i(x, y), 0, wall_variants[randi() % wall_variants.size()])

# =============================================================================
# SPAWNING
# =============================================================================

func _spawn_player() -> void:
	# Positions the pre-existing Player node at the cell the generator chose.
	player.position = Vector2(
		generator.player_pos.x * TILE_SIZE + TILE_SIZE / 2.0,
		generator.player_pos.y * TILE_SIZE + TILE_SIZE / 2.0
	)


func _spawn_objects() -> void:
	# Single pass over the generator's object layer — each marked cell spawns
	# the corresponding scene.  Adding new object types only requires adding a
	# new OBJ_ constant in DungeonGenerator and a matching branch here.
	for y in generator.height:
		for x in generator.width:
			var world_pos := Vector2(
				x * TILE_SIZE + TILE_SIZE / 2.0,
				y * TILE_SIZE + TILE_SIZE / 2.0
			)
			match generator.objects[y][x]:
				generator.OBJ_ENEMY:
					_create_zombie(world_pos)
				generator.OBJ_ITEM:
					_create_key(world_pos)


func _create_zombie(pos: Vector2) -> void:
	var zombie := ZOMBIE_SCENE.instantiate() as CharacterBody2D
	zombie.position = pos
	add_child(zombie)


func _create_key(pos: Vector2) -> void:
	var key := KEY_SCENE.instantiate()
	key.position = pos
	add_child(key)


func _spawn_exit() -> void:
	# Builds a minimal Area2D at generator.exit_pos to detect when the player
	# steps on the exit tile.  The ColorRect acts as a visible marker;
	# it turns green when all keys are collected (_unlock_exit).
	exit_node = Area2D.new()
	exit_node.position = Vector2(
		generator.exit_pos.x * TILE_SIZE + TILE_SIZE / 2.0,
		generator.exit_pos.y * TILE_SIZE + TILE_SIZE / 2.0
	)

	var rect := ColorRect.new()
	rect.size     = Vector2(14, 14)
	rect.position = Vector2(-7, -7)
	rect.color    = Color(0.8, 0.1, 0.1)
	rect.name     = "ExitRect"
	exit_node.add_child(rect)

	var col   := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(14, 14)
	col.shape  = shape
	exit_node.add_child(col)

	exit_node.body_entered.connect(_on_exit_entered)
	exit_node.monitoring = true
	add_child(exit_node)

# =============================================================================
# GAME STATE — keys, exit, win / lose
# =============================================================================

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


func _init_hud_health() -> void:
	hud.update_health(player.hp, player.MAX_HP)


func _on_hp_changed(new_hp: int) -> void:
	hud.update_health(new_hp, player.MAX_HP)


func _on_player_won() -> void:
	get_tree().paused = true
	end_screen.show_win()

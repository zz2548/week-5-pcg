extends Node2D

const TILE_SIZE = 16
const FLOOR_ATLAS = Vector2i(2, 2)  # your floor tile coords
const WALL_ATLAS  = Vector2i(1, 1)  # your wall tile coords

@onready var tilemap = $TileMap
@onready var player  = $Player

var generator: DungeonGenerator  # we'll make this next

func _ready():
	generator = DungeonGenerator.new()
	generator.width = 80
	generator.height = 45
	generator.generate_instant()  # runs all phases at once, no animation
	
	_render_tilemap()
	_spawn_player()

func _render_tilemap():
	tilemap.clear()
	for y in generator.height:
		for x in generator.width:
			var atlas = FLOOR_ATLAS if generator.grid[y][x] == generator.FLOOR else WALL_ATLAS
			tilemap.set_cell(0, Vector2i(x, y), 0, atlas)

func _spawn_player():
	player.position = Vector2(generator.player_pos.x * TILE_SIZE + TILE_SIZE / 2, 
							  generator.player_pos.y * TILE_SIZE + TILE_SIZE / 2)

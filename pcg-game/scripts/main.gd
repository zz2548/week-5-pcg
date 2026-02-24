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

func _spawn_player():
	player.position = Vector2(generator.player_pos.x * TILE_SIZE + TILE_SIZE / 2, 
							  generator.player_pos.y * TILE_SIZE + TILE_SIZE / 2)

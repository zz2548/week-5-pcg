# DungeonGenerator.gd
class_name DungeonGenerator
extends Node
# Derived from https://github.com/mxgmn/MarkovJunior/blob/main/models/DungeonGrowth.xml
# Pure data class — no visuals. Call generate_instant() then read grid, objects, player_pos, shop_pos.


# -- Configuration ------------------------------------------------------------
@export var width: int = 80
@export var height: int = 45
@export var max_rooms: int = 25
@export var barrel_chance: float    = 0.04
@export var explosive_chance: float = 0.35
@export var item_chance: float      = 0.02
@export var enemy_chance: float     = 0.015

# -- Terrain cell values ------------------------------------------------------
const WALL   = 1
const BORDER = 2
const PATH   = 4
const FLOOR  = 5

# -- Object values ------------------------------------------------------------
const OBJ_NONE      = 0 
const OBJ_BARREL    = 1
const OBJ_EXPLOSIVE = 2
const OBJ_ITEM      = 3
const OBJ_ENEMY     = 4
const OBJ_SHOPPOINT = 5
const OBJ_PLAYER    = 6

# -- Output data --------------------------------------------------------------
var grid: Array    = []   # 2D Array[y][x] of terrain values
var objects: Array = []   # 2D Array[y][x] of object values
var rooms: Array   = []   # Array of Vector2i room centers
var player_pos: Vector2i
var shop_pos: Vector2i

# -- Room templates — 1 = floor, 0 = skip ------------------------------------
const ROOM_TEMPLATES = [
	# Rectangles
	[[1,1],[1,1]],
	[[1,1,1],[1,1,1],[1,1,1]],
	[[1,1,1,1,1],[1,1,1,1,1],[1,1,1,1,1],[1,1,1,1,1],[1,1,1,1,1]],
	[[1,1,1,1,1,1],[1,1,1,1,1,1],[1,1,1,1,1,1]],
	[[1,1,1],[1,1,1],[1,1,1],[1,1,1],[1,1,1],[1,1,1]],
	[[1,1,1,1,1,1,1,1],[1,1,1,1,1,1,1,1],[1,1,1,1,1,1,1,1],[1,1,1,1,1,1,1,1]],
	[[1,1,1,1,1,1,1]],
	[[1],[1],[1],[1],[1],[1],[1]],
	[[1,1],[1,1],[1,1],[1,1],[1,1],[1,1]],
	# Plus / Cross
	[[0,1,0],[1,1,1],[0,1,0]],
	[[0,1,1,1,0],[1,1,1,1,1],[1,1,1,1,1],[1,1,1,1,1],[0,1,1,1,0]],
	[[0,0,1,1,1,0,0],[0,0,1,1,1,0,0],[1,1,1,1,1,1,1],[1,1,1,1,1,1,1],[1,1,1,1,1,1,1],[0,0,1,1,1,0,0],[0,0,1,1,1,0,0]],
	[[0,1,1,0],[1,1,1,1],[1,1,1,1],[0,1,1,0],[0,1,1,0]],
	[[0,0,1,1,0,0],[1,1,1,1,1,1],[1,1,1,1,1,1],[0,0,1,1,0,0]],
	# L-shapes
	[[1,1,0],[1,1,0],[1,1,1]],
	[[1,1,0,0],[1,1,0,0],[1,1,0,0],[1,1,1,1],[1,1,1,1]],
	[[1,1,1,0],[1,1,1,0],[1,1,1,1],[1,1,1,1]],
	[[1,0,0,0],[1,0,0,0],[1,0,0,0],[1,0,0,0],[1,1,1,1]],
	# T-shapes
	[[1,1,1],[0,1,1],[0,1,1]],
	[[1,1,1,1,1],[0,1,1,1,0],[0,1,1,1,0],[0,1,1,1,0]],
	[[1,1,1,1,1,1,1],[0,0,1,1,1,0,0],[0,0,1,1,1,0,0]],
	[[1,1,1,1,1],[0,0,1,0,0],[0,0,1,0,0]],
	# Z / S
	[[1,1,1,0],[0,1,1,0],[0,1,1,1]],
	[[0,1,1,1],[0,1,1,0],[1,1,1,0]],
	[[1,1,1,1,0,0],[0,1,1,1,0,0],[0,0,1,1,1,1]],
	[[1,1,0],[1,1,0],[0,1,1],[0,1,1]],
	# U-shapes
	[[1,1,0,1,1],[1,1,0,1,1],[1,1,1,1,1]],
	[[1,1,1,1],[1,1,0,0],[1,1,0,0],[1,1,1,1]],
	[[1,1,0,0,1,1],[1,1,0,0,1,1],[1,1,0,0,1,1],[1,1,1,1,1,1]],
	[[1,0,1],[1,0,1],[1,1,1]],
	# Donuts / Rings
	[[1,1,1,1,1],[1,0,0,0,1],[1,0,0,0,1],[1,0,0,0,1],[1,1,1,1,1]],
	[[1,1,1,1,1,1,1],[1,0,0,0,0,0,1],[1,0,0,0,0,0,1],[1,0,0,0,0,0,1],[1,0,0,0,0,0,1],[1,0,0,0,0,0,1],[1,1,1,1,1,1,1]],
	[[1,1,1,1,1,1,1],[1,1,1,1,1,1,1],[1,1,0,0,0,1,1],[1,1,0,0,0,1,1],[1,1,0,0,0,1,1],[1,1,1,1,1,1,1],[1,1,1,1,1,1,1]],
	[[0,1,1,1,1,1,0],[1,1,0,0,0,1,1],[1,1,0,0,0,1,1],[0,1,1,1,1,1,0]],
	[[1,1,1],[1,0,1],[1,1,1]],
	# Diagonal / Steps
	[[1,1,1,0,0],[1,1,1,0,0],[0,1,1,1,0],[0,0,1,1,1],[0,0,1,1,1]],
	[[1,1,0,0,0],[1,1,1,0,0],[0,1,1,1,0],[0,0,1,1,1]],
	[[1,1,1,0,0,0],[1,1,1,1,0,0],[0,1,1,1,1,0],[0,0,1,1,1,1]],
	# Octagon / Diamond
	[[0,1,1,1,0],[1,1,1,1,1],[1,1,1,1,1],[1,1,1,1,1],[0,1,1,1,0]],
	[[0,0,1,1,1,0,0],[0,1,1,1,1,1,0],[1,1,1,1,1,1,1],[1,1,1,1,1,1,1],[1,1,1,1,1,1,1],[0,1,1,1,1,1,0],[0,0,1,1,1,0,0]],
	[[0,0,1,0,0],[0,1,1,1,0],[1,1,1,1,1],[0,1,1,1,0],[0,0,1,0,0]],
	[[0,1,1,1,0],[1,1,1,1,1],[1,1,1,1,1],[1,1,1,1,1],[0,1,1,1,0]],
	# Irregular / Organic
	[[0,1,1,1,0],[1,1,1,1,1],[1,1,1,1,0],[0,1,1,0,0]],
	[[1,1,1,0,0],[1,1,1,1,0],[0,1,1,1,1],[0,0,1,1,1]],
	[[1,1,1,1,1,0],[1,1,1,1,1,1],[0,1,1,1,1,1],[0,0,1,1,1,0]],
	[[1,1,1,1,1],[1,0,1,0,1],[1,1,1,1,1],[1,0,1,0,1],[1,1,1,1,1]],
	[[1,0,1,0,1],[1,1,1,1,1],[1,1,1,1,1]],
	[[1,1,0,1,1],[1,1,1,1,1],[1,1,0,1,1]],
	[[0,0,1,0,0],[0,1,1,1,0],[1,1,1,1,1],[0,1,1,1,0],[0,1,0,1,0]],
	[[1,0,0,0,1],[1,1,0,1,1],[1,1,1,1,1],[1,1,0,1,1],[1,0,0,0,1]],
	[[1,1,0,0,0],[1,1,1,1,0],[0,1,1,1,0],[0,1,1,1,1],[0,0,0,1,1]],
	[[1,0,1,0,1],[0,1,0,1,0],[1,0,1,0,1],[0,1,0,1,0],[1,0,1,0,1]],
	[[0,1,1,0],[1,1,1,1],[1,1,1,1],[0,1,1,0]],
]

# =============================================================================
# Public API
# =============================================================================

func generate_instant():
	_init_grid()
	_place_all_rooms()
	_connect_all_rooms()
	_finalize()
	_cull()
	_populate()

# =============================================================================
# Phases
# =============================================================================

func _init_grid():
	grid = []
	objects = []
	rooms = []
	for y in height:
		grid.append([])
		objects.append([])
		for x in width:
			grid[y].append(WALL)
			objects[y].append(OBJ_NONE)
	grid[height / 2][width / 2] = BORDER

func _place_all_rooms():
	var placed = 0
	var attempts = 0
	while placed < max_rooms and attempts < max_rooms * 50:
		attempts += 1
		var border_cells = get_cells_of_type(BORDER)
		if border_cells.is_empty():
			break
		var anchor = border_cells[randi() % border_cells.size()]
		var template = ROOM_TEMPLATES[randi() % ROOM_TEMPLATES.size()].duplicate(true)
		var rotations = randi() % 4
		for _r in rotations:
			template = rotate_template_90(template)
		var th = template.size()
		var tw = template[0].size()
		var offsets = [
			Vector2i(0, 0), Vector2i(-tw / 2, -th / 2),
			Vector2i(-tw + 1, 0), Vector2i(0, -th + 1),
			Vector2i(-tw + 1, -th + 1),
		]
		var offset = offsets[randi() % offsets.size()]
		var tx = clamp(anchor.x + offset.x, 1, width - tw - 1)
		var ty = clamp(anchor.y + offset.y, 1, height - th - 1)
		if can_place_template(template, tx, ty):
			place_template(template, tx, ty)
			rooms.append(get_template_center(template, tx, ty))
			placed += 1

func _connect_all_rooms():
	if rooms.size() < 2:
		return
	var connected = [0]
	var unconnected = []
	for i in range(1, rooms.size()):
		unconnected.append(i)
	while unconnected.size() > 0:
		var best_from = -1
		var best_to   = -1
		var best_dist = INF
		for i in connected:
			for j in unconnected:
				var d = rooms[i].distance_to(rooms[j])
				if d < best_dist:
					best_dist = d
					best_from = i
					best_to   = j
		if best_dist > 4:
			var a: Vector2i = rooms[best_from]
			var b: Vector2i = rooms[best_to]
			var x = a.x
			var y = a.y
			while x != b.x:
				if grid[y][x] != FLOOR:
					grid[y][x] = PATH
				x += 1 if b.x > x else -1
			while y != b.y:
				if grid[y][x] != FLOOR:
					grid[y][x] = PATH
				y += 1 if b.y > y else -1
		connected.append(best_to)
		unconnected.erase(best_to)

func _finalize():
	for y in height:
		for x in width:
			match grid[y][x]:
				PATH:   grid[y][x] = FLOOR
				BORDER: grid[y][x] = WALL

func _cull():
	for y in height:
		for x in width:
			if grid[y][x] == FLOOR:
				if count_neighbors(x, y, FLOOR) == 0:
					grid[y][x] = WALL

func _populate():
	var floor_cells = get_cells_of_type(FLOOR)
	floor_cells.shuffle()
	var center = Vector2i(width / 2, height / 2)

	# player spawns nearest to center
	player_pos = _closest_floor_to(center, floor_cells)
	objects[player_pos.y][player_pos.x] = OBJ_PLAYER

	# shop spawns farthest from center
	shop_pos = _farthest_floor_from(center, floor_cells)
	objects[shop_pos.y][shop_pos.x] = OBJ_SHOPPOINT

	# scatter everything else
	for cell in floor_cells:
		if objects[cell.y][cell.x] != OBJ_NONE:
			continue
		var roll = randf()
		if roll < barrel_chance:
			objects[cell.y][cell.x] = OBJ_EXPLOSIVE if randf() < explosive_chance else OBJ_BARREL
		elif roll < barrel_chance + item_chance:
			objects[cell.y][cell.x] = OBJ_ITEM
		elif roll < barrel_chance + item_chance + enemy_chance:
			objects[cell.y][cell.x] = OBJ_ENEMY

# =============================================================================
# Template helpers
# =============================================================================

func rotate_template_90(template: Array) -> Array:
	var h = template.size()
	var w = template[0].size()
	var rotated = []
	for col in range(w):
		rotated.append([])
		for row in range(h - 1, -1, -1):
			rotated[col].append(template[row][col])
	return rotated

func can_place_template(template: Array, tx: int, ty: int) -> bool:
	for row in range(template.size()):
		for col in range(template[row].size()):
			if template[row][col] == 0:
				continue
			var x = tx + col
			var y = ty + row
			if x <= 0 or x >= width - 1 or y <= 0 or y >= height - 1:
				return false
			if grid[y][x] == FLOOR or grid[y][x] == PATH:
				return false
	return true

func place_template(template: Array, tx: int, ty: int):
	for row in range(template.size()):
		for col in range(template[row].size()):
			if template[row][col] == 0:
				continue
			grid[ty + row][tx + col] = FLOOR
	for row in range(-1, template.size() + 1):
		for col in range(-1, template[0].size() + 1):
			var x = tx + col
			var y = ty + row
			if x > 0 and x < width - 1 and y > 0 and y < height - 1:
				if grid[y][x] == WALL:
					grid[y][x] = BORDER

func get_template_center(template: Array, tx: int, ty: int) -> Vector2i:
	return Vector2i(tx + template[0].size() / 2, ty + template.size() / 2)

# =============================================================================
# General helpers
# =============================================================================

func get_cells_of_type(value: int) -> Array:
	var result = []
	for y in height:
		for x in width:
			if grid[y][x] == value:
				result.append(Vector2i(x, y))
	return result

func count_neighbors(x: int, y: int, value: int) -> int:
	var count = 0
	for dy in [-1, 0, 1]:
		for dx in [-1, 0, 1]:
			if dx == 0 and dy == 0:
				continue
			var nx = x + dx
			var ny = y + dy
			if nx < 0 or nx >= width or ny < 0 or ny >= height:
				if value == WALL:
					count += 1
			else:
				if grid[ny][nx] == value:
					count += 1
	return count

func _closest_floor_to(target: Vector2i, floor_cells: Array) -> Vector2i:
	var best = floor_cells[0]
	var best_dist = INF
	for cell in floor_cells:
		var d = target.distance_to(cell)
		if d < best_dist:
			best_dist = d
			best = cell
	return best

func _farthest_floor_from(target: Vector2i, floor_cells: Array) -> Vector2i:
	var best = floor_cells[0]
	var best_dist = -INF
	for cell in floor_cells:
		var d = target.distance_to(cell)
		if d > best_dist:
			best_dist = d
			best = cell
	return best

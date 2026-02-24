class_name DungeonGenerator
extends Node

@export var width: int = 80
@export var height: int = 45
@export var max_rooms: int = 25
@export var barrel_chance: float    = 0.04
@export var explosive_chance: float = 0.35
@export var item_chance: float      = 0.02
@export var enemy_chance: float     = 0.015
@export var enemy_safe_radius: int  = 10
@export var item_safe_radius: int   = 25

const WALL   = 1
const BORDER = 2
const PATH   = 4
const FLOOR  = 5

const OBJ_NONE      = 0
const OBJ_BARREL    = 1
const OBJ_EXPLOSIVE = 2
const OBJ_ITEM      = 3
const OBJ_ENEMY     = 4
const OBJ_SHOPPOINT = 5
const OBJ_PLAYER    = 6

var grid: Array    = []
var objects: Array = []
var rooms: Array   = []
var player_pos: Vector2i
var shop_pos: Vector2i

const ROOM_TEMPLATES = [
	[[1,1],[1,1]],
	[[1,1,1],[1,1,1],[1,1,1]],
	[[1,1,1,1,1],[1,1,1,1,1],[1,1,1,1,1],[1,1,1,1,1],[1,1,1,1,1]],
	[[1,1,1,1,1,1],[1,1,1,1,1,1],[1,1,1,1,1,1]],
	[[1,1,1],[1,1,1],[1,1,1],[1,1,1],[1,1,1],[1,1,1]],
	[[1,1,1,1,1,1,1,1],[1,1,1,1,1,1,1,1],[1,1,1,1,1,1,1,1],[1,1,1,1,1,1,1,1]],
	[[1,1,1,1,1,1,1]],
	[[1],[1],[1],[1],[1],[1],[1]],
	[[1,1],[1,1],[1,1],[1,1],[1,1],[1,1]],
	[[0,1,0],[1,1,1],[0,1,0]],
	[[0,1,1,1,0],[1,1,1,1,1],[1,1,1,1,1],[1,1,1,1,1],[0,1,1,1,0]],
	[[0,0,1,1,1,0,0],[0,0,1,1,1,0,0],[1,1,1,1,1,1,1],[1,1,1,1,1,1,1],[1,1,1,1,1,1,1],[0,0,1,1,1,0,0],[0,0,1,1,1,0,0]],
	[[0,1,1,0],[1,1,1,1],[1,1,1,1],[0,1,1,0],[0,1,1,0]],
	[[0,0,1,1,0,0],[1,1,1,1,1,1],[1,1,1,1,1,1],[0,0,1,1,0,0]],
	[[1,1,0],[1,1,0],[1,1,1]],
	[[1,1,0,0],[1,1,0,0],[1,1,0,0],[1,1,1,1],[1,1,1,1]],
	[[1,1,1,0],[1,1,1,0],[1,1,1,1],[1,1,1,1]],
	[[1,0,0,0],[1,0,0,0],[1,0,0,0],[1,0,0,0],[1,1,1,1]],
	[[1,1,1],[0,1,1],[0,1,1]],
	[[1,1,1,1,1],[0,1,1,1,0],[0,1,1,1,0],[0,1,1,1,0]],
	[[1,1,1,1,1,1,1],[0,0,1,1,1,0,0],[0,0,1,1,1,0,0]],
	[[1,1,1,1,1],[0,0,1,0,0],[0,0,1,0,0]],
	[[1,1,1,0],[0,1,1,0],[0,1,1,1]],
	[[0,1,1,1],[0,1,1,0],[1,1,1,0]],
	[[1,1,1,1,0,0],[0,1,1,1,0,0],[0,0,1,1,1,1]],
	[[1,1,0],[1,1,0],[0,1,1],[0,1,1]],
	[[1,1,0,1,1],[1,1,0,1,1],[1,1,1,1,1]],
	[[1,1,1,1],[1,1,0,0],[1,1,0,0],[1,1,1,1]],
	[[1,1,0,0,1,1],[1,1,0,0,1,1],[1,1,0,0,1,1],[1,1,1,1,1,1]],
	[[1,0,1],[1,0,1],[1,1,1]],
	[[1,1,1,1,1],[1,0,0,0,1],[1,0,0,0,1],[1,0,0,0,1],[1,1,1,1,1]],
	[[1,1,1,1,1,1,1],[1,0,0,0,0,0,1],[1,0,0,0,0,0,1],[1,0,0,0,0,0,1],[1,0,0,0,0,0,1],[1,0,0,0,0,0,1],[1,1,1,1,1,1,1]],
	[[1,1,1,1,1,1,1],[1,1,1,1,1,1,1],[1,1,0,0,0,1,1],[1,1,0,0,0,1,1],[1,1,0,0,0,1,1],[1,1,1,1,1,1,1],[1,1,1,1,1,1,1]],
	[[0,1,1,1,1,1,0],[1,1,0,0,0,1,1],[1,1,0,0,0,1,1],[0,1,1,1,1,1,0]],
	[[1,1,1],[1,0,1],[1,1,1]],
	[[1,1,1,0,0],[1,1,1,0,0],[0,1,1,1,0],[0,0,1,1,1],[0,0,1,1,1]],
	[[1,1,0,0,0],[1,1,1,0,0],[0,1,1,1,0],[0,0,1,1,1]],
	[[1,1,1,0,0,0],[1,1,1,1,0,0],[0,1,1,1,1,0],[0,0,1,1,1,1]],
	[[0,1,1,1,0],[1,1,1,1,1],[1,1,1,1,1],[1,1,1,1,1],[0,1,1,1,0]],
	[[0,0,1,1,1,0,0],[0,1,1,1,1,1,0],[1,1,1,1,1,1,1],[1,1,1,1,1,1,1],[1,1,1,1,1,1,1],[0,1,1,1,1,1,0],[0,0,1,1,1,0,0]],
	[[0,0,1,0,0],[0,1,1,1,0],[1,1,1,1,1],[0,1,1,1,0],[0,0,1,0,0]],
	[[0,1,1,1,0],[1,1,1,1,1],[1,1,1,1,1],[1,1,1,1,1],[0,1,1,1,0]],
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

func generate_instant():
	_init_grid()
	_place_all_rooms()
	_connect_all_rooms()
	_finalize()
	_cull()
	_populate()

func _init_grid():
	grid = []
	objects = []
	rooms = []
	for y in height:
		grid.append([])
		objects.append([])
		for _x in width:
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
	var center = Vector2i(width / 2, height / 2)

	player_pos = _best_open_spawn_near(center, floor_cells)
	objects[player_pos.y][player_pos.x] = OBJ_PLAYER

	shop_pos = _farthest_floor_from(player_pos, floor_cells)
	objects[shop_pos.y][shop_pos.x] = OBJ_SHOPPOINT

	const NUM_KEYS         = 5
	const GUARD_RADIUS     = 15
	const GUARDS_PER_KEY   = 2

	var zone_cols = 3
	var zone_rows = 2
	var zone_w = width  / zone_cols
	var zone_h = height / zone_rows

	var far_cells: Array = []
	for cell in floor_cells:
		if cell.distance_to(player_pos) >= item_safe_radius:
			far_cells.append(cell)
	far_cells.shuffle()

	var placed_key_positions: Array = []
	for row in range(zone_rows):
		for col in range(zone_cols):
			if placed_key_positions.size() >= NUM_KEYS:
				break
			var zone_x0 = col * zone_w
			var zone_y0 = row * zone_h
			var zone_x1 = zone_x0 + zone_w
			var zone_y1 = zone_y0 + zone_h
			var best_cell = Vector2i(-1, -1)
			var best_open = -1
			for cell in far_cells:
				if cell.x < zone_x0 or cell.x >= zone_x1:
					continue
				if cell.y < zone_y0 or cell.y >= zone_y1:
					continue
				var too_close = false
				for kp in placed_key_positions:
					if cell.distance_to(kp) < 12:
						too_close = true
						break
				if too_close:
					continue
				var openness = _count_open_floor_nearby(cell, 2)
				if openness > best_open:
					best_open = openness
					best_cell = cell
			if best_cell != Vector2i(-1, -1):
				objects[best_cell.y][best_cell.x] = OBJ_ITEM
				placed_key_positions.append(best_cell)

	for kp in placed_key_positions:
		var guards_placed = 0
		var nearby: Array = []
		for cell in floor_cells:
			var d = cell.distance_to(kp)
			if d >= 3 and d <= GUARD_RADIUS:
				if cell.distance_to(player_pos) >= enemy_safe_radius:
					if objects[cell.y][cell.x] == OBJ_NONE:
						nearby.append(cell)
		nearby.shuffle()
		for cell in nearby:
			if guards_placed >= GUARDS_PER_KEY:
				break
			objects[cell.y][cell.x] = OBJ_ENEMY
			guards_placed += 1

	floor_cells.shuffle()
	for cell in floor_cells:
		if objects[cell.y][cell.x] != OBJ_NONE:
			continue
		var roll = randf()
		if roll < barrel_chance:
			objects[cell.y][cell.x] = OBJ_EXPLOSIVE if randf() < explosive_chance else OBJ_BARREL

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

func _count_open_floor_nearby(cell: Vector2i, r: int) -> int:
	var count = 0
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var nx = cell.x + dx
			var ny = cell.y + dy
			if nx >= 0 and nx < width and ny >= 0 and ny < height:
				if grid[ny][nx] == FLOOR:
					count += 1
	return count

func _best_open_spawn_near(target: Vector2i, floor_cells: Array) -> Vector2i:
	var best_cell = floor_cells[0]
	var best_score = -1
	for cell in floor_cells:
		if cell.distance_to(target) > 15:
			continue
		var openness = _count_open_floor_nearby(cell, 3)
		if openness > best_score:
			best_score = openness
			best_cell = cell
	return best_cell

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

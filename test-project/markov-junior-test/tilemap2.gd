# Derived from https://github.com/mxgmn/MarkovJunior/blob/main/models/DungeonGrowth.xml
extends Node2D

@export var width: int = 80
@export var height: int = 45
@export var max_rooms: int = 25
@export var step_delay: float = 0.03

const TILE_SIZE = 12

# Cell values
const EMPTY  = 0
const WALL   = 1  # W
const BORDER = 2  # B = frontier
const PATH   = 4  # U = corridor being carved
const FLOOR  = 5  # P = finalized floor

# MJ-style colors
const COLOR_WALL   = Color(0.08, 0.08, 0.12)
const COLOR_FLOOR  = Color(0.85, 0.78, 0.60)
const COLOR_BORDER = Color(0.20, 0.45, 0.80)
const COLOR_PATH   = Color(0.90, 0.65, 0.20)
const COLOR_BG     = Color(0.05, 0.05, 0.08)

# Room templates — 1 = floor, 0 = empty (don't stamp)
const ROOM_TEMPLATES = [

	# ── Rectangles ────────────────────────────────────────────────────────────
	# Tiny 2x2
	[[1,1],[1,1]],
	# Small square
	[[1,1,1],[1,1,1],[1,1,1]],
	# Medium square
	[[1,1,1,1,1],[1,1,1,1,1],[1,1,1,1,1],[1,1,1,1,1],[1,1,1,1,1]],
	# Wide short
	[[1,1,1,1,1,1],[1,1,1,1,1,1],[1,1,1,1,1,1]],
	# Tall narrow
	[[1,1,1],[1,1,1],[1,1,1],[1,1,1],[1,1,1],[1,1,1]],
	# Large hall
	[[1,1,1,1,1,1,1,1],[1,1,1,1,1,1,1,1],[1,1,1,1,1,1,1,1],[1,1,1,1,1,1,1,1]],
	# Corridor stub H
	[[1,1,1,1,1,1,1]],
	# Corridor stub V
	[[1],[1],[1],[1],[1],[1],[1]],
	# Single wide corridor
	[[1,1],[1,1],[1,1],[1,1],[1,1],[1,1]],

	# ── Plus / Cross ──────────────────────────────────────────────────────────
	# Tiny plus
	[
		[0,1,0],
		[1,1,1],
		[0,1,0],
	],
	# Medium plus
	[
		[0,1,1,1,0],
		[1,1,1,1,1],
		[1,1,1,1,1],
		[1,1,1,1,1],
		[0,1,1,1,0],
	],
	# Large plus
	[
		[0,0,1,1,1,0,0],
		[0,0,1,1,1,0,0],
		[1,1,1,1,1,1,1],
		[1,1,1,1,1,1,1],
		[1,1,1,1,1,1,1],
		[0,0,1,1,1,0,0],
		[0,0,1,1,1,0,0],
	],
	# Asymmetric cross (taller)
	[
		[0,1,1,0],
		[1,1,1,1],
		[1,1,1,1],
		[0,1,1,0],
		[0,1,1,0],
	],
	# Fat cross (wider arms)
	[
		[0,0,1,1,0,0],
		[1,1,1,1,1,1],
		[1,1,1,1,1,1],
		[0,0,1,1,0,0],
	],

	# ── L-shapes ──────────────────────────────────────────────────────────────
	# Small L
	[
		[1,1,0],
		[1,1,0],
		[1,1,1],
	],
	# Large L
	[
		[1,1,0,0],
		[1,1,0,0],
		[1,1,0,0],
		[1,1,1,1],
		[1,1,1,1],
	],
	# Fat L
	[
		[1,1,1,0],
		[1,1,1,0],
		[1,1,1,1],
		[1,1,1,1],
	],
	# Long L
	[
		[1,0,0,0],
		[1,0,0,0],
		[1,0,0,0],
		[1,0,0,0],
		[1,1,1,1],
	],

	# ── T-shapes ──────────────────────────────────────────────────────────────
	# Small T
	[
		[1,1,1],
		[0,1,1],
		[0,1,1],
	],
	# Medium T
	[
		[1,1,1,1,1],
		[0,1,1,1,0],
		[0,1,1,1,0],
		[0,1,1,1,0],
	],
	# Wide T
	[
		[1,1,1,1,1,1,1],
		[0,0,1,1,1,0,0],
		[0,0,1,1,1,0,0],
	],
	# Stubby T
	[
		[1,1,1,1,1],
		[0,0,1,0,0],
		[0,0,1,0,0],
	],

	# ── Z / S shapes ─────────────────────────────────────────────────────────
	# Z
	[
		[1,1,1,0],
		[0,1,1,0],
		[0,1,1,1],
	],
	# S
	[
		[0,1,1,1],
		[0,1,1,0],
		[1,1,1,0],
	],
	# Wide Z
	[
		[1,1,1,1,0,0],
		[0,1,1,1,0,0],
		[0,0,1,1,1,1],
	],
	# Tall Z
	[
		[1,1,0],
		[1,1,0],
		[0,1,1],
		[0,1,1],
	],

	# ── U-shapes ──────────────────────────────────────────────────────────────
	# U open top
	[
		[1,1,0,1,1],
		[1,1,0,1,1],
		[1,1,1,1,1],
	],
	# U open side
	[
		[1,1,1,1],
		[1,1,0,0],
		[1,1,0,0],
		[1,1,1,1],
	],
	# Deep U
	[
		[1,1,0,0,1,1],
		[1,1,0,0,1,1],
		[1,1,0,0,1,1],
		[1,1,1,1,1,1],
	],
	# Thin U
	[
		[1,0,1],
		[1,0,1],
		[1,1,1],
	],

	# ── Donuts / Rings ────────────────────────────────────────────────────────
	# Small ring
	[
		[1,1,1,1,1],
		[1,0,0,0,1],
		[1,0,0,0,1],
		[1,0,0,0,1],
		[1,1,1,1,1],
	],
	# Large ring
	[
		[1,1,1,1,1,1,1],
		[1,0,0,0,0,0,1],
		[1,0,0,0,0,0,1],
		[1,0,0,0,0,0,1],
		[1,0,0,0,0,0,1],
		[1,0,0,0,0,0,1],
		[1,1,1,1,1,1,1],
	],
	# Thick ring
	[
		[1,1,1,1,1,1,1],
		[1,1,1,1,1,1,1],
		[1,1,0,0,0,1,1],
		[1,1,0,0,0,1,1],
		[1,1,0,0,0,1,1],
		[1,1,1,1,1,1,1],
		[1,1,1,1,1,1,1],
	],
	# Oval ring
	[
		[0,1,1,1,1,1,0],
		[1,1,0,0,0,1,1],
		[1,1,0,0,0,1,1],
		[0,1,1,1,1,1,0],
	],
	# Tiny ring
	[
		[1,1,1],
		[1,0,1],
		[1,1,1],
	],

	# ── Diagonal / Steps ─────────────────────────────────────────────────────
	# Step right-down
	[
		[1,1,1,0,0],
		[1,1,1,0,0],
		[0,1,1,1,0],
		[0,0,1,1,1],
		[0,0,1,1,1],
	],
	# Staircase
	[
		[1,1,0,0,0],
		[1,1,1,0,0],
		[0,1,1,1,0],
		[0,0,1,1,1],
	],
	# Wide staircase
	[
		[1,1,1,0,0,0],
		[1,1,1,1,0,0],
		[0,1,1,1,1,0],
		[0,0,1,1,1,1],
	],

	# ── Octagon / Diamond ────────────────────────────────────────────────────
	# Octagon
	[
		[0,1,1,1,0],
		[1,1,1,1,1],
		[1,1,1,1,1],
		[1,1,1,1,1],
		[0,1,1,1,0],
	],
	# Large octagon
	[
		[0,0,1,1,1,0,0],
		[0,1,1,1,1,1,0],
		[1,1,1,1,1,1,1],
		[1,1,1,1,1,1,1],
		[1,1,1,1,1,1,1],
		[0,1,1,1,1,1,0],
		[0,0,1,1,1,0,0],
	],
	# Diamond
	[
		[0,0,1,0,0],
		[0,1,1,1,0],
		[1,1,1,1,1],
		[0,1,1,1,0],
		[0,0,1,0,0],
	],
	# Fat diamond
	[
		[0,1,1,1,0],
		[1,1,1,1,1],
		[1,1,1,1,1],
		[1,1,1,1,1],
		[0,1,1,1,0],
	],

	# ── Irregular / organic ───────────────────────────────────────────────────
	# Blob 1
	[
		[0,1,1,1,0],
		[1,1,1,1,1],
		[1,1,1,1,0],
		[0,1,1,0,0],
	],
	# Blob 2
	[
		[1,1,1,0,0],
		[1,1,1,1,0],
		[0,1,1,1,1],
		[0,0,1,1,1],
	],
	# Irregular hall
	[
		[1,1,1,1,1,0],
		[1,1,1,1,1,1],
		[0,1,1,1,1,1],
		[0,0,1,1,1,0],
	],
	# Notched square (pillars)
	[
		[1,1,1,1,1],
		[1,0,1,0,1],
		[1,1,1,1,1],
		[1,0,1,0,1],
		[1,1,1,1,1],
	],
	# Comb
	[
		[1,0,1,0,1],
		[1,1,1,1,1],
		[1,1,1,1,1],
	],
	# H-shape
	[
		[1,1,0,1,1],
		[1,1,1,1,1],
		[1,1,0,1,1],
	],
	# Arrow
	[
		[0,0,1,0,0],
		[0,1,1,1,0],
		[1,1,1,1,1],
		[0,1,1,1,0],
		[0,1,0,1,0],
	],
	# Bowtie
	[
		[1,0,0,0,1],
		[1,1,0,1,1],
		[1,1,1,1,1],
		[1,1,0,1,1],
		[1,0,0,0,1],
	],
	# Pinwheel
	[
		[1,1,0,0,0],
		[1,1,1,1,0],
		[0,1,1,1,0],
		[0,1,1,1,1],
		[0,0,0,1,1],
	],
	# Spine
	[
		[1,0,1,0,1],
		[1,1,1,1,1],
		[1,0,1,0,1],
	],
	# Hourglass
	[
		[1,1,1,1,1],
		[0,1,1,1,0],
		[0,0,1,0,0],
		[0,1,1,1,0],
		[1,1,1,1,1],
	],
	# Propeller
	[
		[1,1,0,0,1],
		[1,1,1,0,0],
		[0,1,1,1,0],
		[0,0,1,1,1],
		[1,0,0,1,1],
	],
	# Checkerboard chunk
	[
		[1,0,1,0,1],
		[0,1,0,1,0],
		[1,0,1,0,1],
		[0,1,0,1,0],
		[1,0,1,0,1],
	],
	# Fat cross with corners
	[
		[0,1,1,0],
		[1,1,1,1],
		[1,1,1,1],
		[0,1,1,0],
	],
]

var grid: Array = []
var rooms: Array = []  # Array of Vector2i centers

enum Phase { PLACING_ROOMS, CONNECTING_ROOMS, FINALIZING, CULLING, DONE }
var current_phase: Phase = Phase.DONE
var _timer: float = 0.0
var _room_attempts: int = 0
var _room_placed: int = 0
var _corridor_path: Array = []
var _corridor_index: int = 0

func _ready():
	start_generation()

func _input(event):
	if event.is_action_pressed("ui_accept"):
		start_generation()

func start_generation():
	grid = []
	rooms = []
	_room_attempts = 0
	_room_placed = 0
	_corridor_path = []
	_corridor_index = 0

	for y in height:
		grid.append([])
		for x in width:
			grid[y].append(WALL)
	grid[height / 2][width / 2] = BORDER

	current_phase = Phase.PLACING_ROOMS
	queue_redraw()

func _process(delta):
	if current_phase == Phase.DONE:
		return
	_timer += delta
	if _timer < step_delay:
		return
	_timer = 0.0

	match current_phase:
		Phase.PLACING_ROOMS:    _step_place_rooms()
		Phase.CONNECTING_ROOMS: _step_connect_rooms()
		Phase.FINALIZING:       _step_finalize()
		Phase.CULLING:          _step_cull()

	queue_redraw()

func _draw():
	draw_rect(Rect2(0, 0, width * TILE_SIZE, height * TILE_SIZE), COLOR_BG)
	for y in height:
		for x in width:
			var color: Color
			match grid[y][x]:
				FLOOR:  color = COLOR_FLOOR
				BORDER: color = COLOR_BORDER
				PATH:   color = COLOR_PATH
				WALL:   color = COLOR_WALL
				_:      color = COLOR_BG
			draw_rect(
				Rect2(x * TILE_SIZE + 1, y * TILE_SIZE + 1, TILE_SIZE - 1, TILE_SIZE - 1),
				color
			)

# ── Room placement: one attempt per tick ─────────────────────────────────────
func _step_place_rooms():
	if _room_placed >= max_rooms or _room_attempts >= max_rooms * 50:
		_build_corridor_list()
		current_phase = Phase.CONNECTING_ROOMS
		return

	_room_attempts += 1

	var border_cells = get_cells_of_type(BORDER)
	if border_cells.is_empty():
		_build_corridor_list()
		current_phase = Phase.CONNECTING_ROOMS
		return

	var anchor = border_cells[randi() % border_cells.size()]

	# pick and randomly rotate a template
	var template = ROOM_TEMPLATES[randi() % ROOM_TEMPLATES.size()].duplicate(true)
	var rotations = randi() % 4
	for _r in rotations:
		template = rotate_template_90(template)

	var th = template.size()
	var tw = template[0].size()

	var offsets = [
		Vector2i(0, 0),
		Vector2i(-tw / 2, -th / 2),
		Vector2i(-tw + 1, 0),
		Vector2i(0, -th + 1),
		Vector2i(-tw + 1, -th + 1),
	]
	var offset = offsets[randi() % offsets.size()]
	var tx = clamp(anchor.x + offset.x, 1, width - tw - 1)
	var ty = clamp(anchor.y + offset.y, 1, height - th - 1)

	if can_place_template(template, tx, ty):
		place_template(template, tx, ty)
		rooms.append(get_template_center(template, tx, ty))
		_room_placed += 1

# ── Corridor carving ──────────────────────────────────────────────────────────
func _build_corridor_list():
	_corridor_path = []
	if rooms.size() < 2:
		return

	var connected = [0]  # start from first room
	var unconnected = range(1, rooms.size())

	while unconnected.size() > 0:
		var best_from = -1
		var best_to = -1
		var best_dist = INF

		# find the shortest connection between any connected and unconnected room
		for i in connected:
			for j in unconnected:
				var d = rooms[i].distance_to(rooms[j])
				if d < best_dist:
					best_dist = d
					best_from = i
					best_to = j

		# skip if rooms are already touching (no corridor needed)
		if best_dist > 4:
			var a: Vector2i = rooms[best_from]
			var b: Vector2i = rooms[best_to]
			var x = a.x
			var y = a.y
			while x != b.x:
				_corridor_path.append(Vector2i(x, y))
				x += 1 if b.x > x else -1
			while y != b.y:
				_corridor_path.append(Vector2i(x, y))
				y += 1 if b.y > y else -1

		connected.append(best_to)
		unconnected.erase(best_to)

	_corridor_index = 0

func _step_connect_rooms():
	if _corridor_index >= _corridor_path.size():
		current_phase = Phase.FINALIZING
		return
	for _i in 3:
		if _corridor_index >= _corridor_path.size():
			break
		var cell: Vector2i = _corridor_path[_corridor_index]
		_corridor_index += 1
		# only carve through wall/border, leave existing floor untouched
		if grid[cell.y][cell.x] == WALL or grid[cell.y][cell.x] == BORDER:
			grid[cell.y][cell.x] = PATH

func _step_finalize():
	for y in height:
		for x in width:
			match grid[y][x]:
				PATH:   grid[y][x] = FLOOR
				BORDER: grid[y][x] = WALL
	current_phase = Phase.CULLING

func _step_cull():
	for y in height:
		for x in width:
			if grid[y][x] == FLOOR:
				if count_neighbors(x, y, FLOOR) == 0:
					grid[y][x] = WALL
	current_phase = Phase.DONE

# ── Template helpers ──────────────────────────────────────────────────────────
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

# ── General helpers ───────────────────────────────────────────────────────────
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

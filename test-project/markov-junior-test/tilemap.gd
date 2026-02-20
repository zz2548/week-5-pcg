# Derived from https://github.com/mxgmn/MarkovJunior/blob/main/models/Cave.xml

extends TileMap

@export var width: int = 80
@export var height: int = 45
@export var noise_probability: float = 0.435
@export var smooth_iterations: int = 5  # CA runs fixed steps since we can't detect stability easily

var grid: Array = []

func _input(event):
	if event.is_action_pressed("ui_accept"):
		generate()
		
func _ready():
	generate()

func generate():
	phase1_fill()
	phase2_noise()
	phase3_smooth()
	phase4_fix_diagonals()
	render()

# ── Phase 1: Fill everything with A (floor = 1) ──────────────────────────────
func phase1_fill():
	grid = []
	for y in height:
		grid.append([])
		for x in width:
			grid[y].append(1)  # A = alive = floor

# ── Phase 2: Random noise, flip A→D with p=0.435 ─────────────────────────────
func phase2_noise():
	for y in height:
		for x in width:
			if randf() < noise_probability:
				grid[y][x] = 0  # D = dead = wall

# ── Phase 3: Cellular automaton smoothing ────────────────────────────────────
func phase3_smooth():
	for _i in smooth_iterations:
		var next = []
		for y in height:
			next.append([])
			for x in width:
				next[y].append(grid[y][x])

		for y in height:
			for x in width:
				var d_neighbors = count_neighbors(x, y, 0)  # count D (wall) neighbors
				var a_neighbors = count_neighbors(x, y, 1)  # count A (floor) neighbors

				if grid[y][x] == 1:  # A cell
					# rule: A→D if 5..8 D neighbors
					if d_neighbors >= 5:
						next[y][x] = 0
				elif grid[y][x] == 0:  # D cell
					# rule: D→A if 6..8 A neighbors
					if a_neighbors >= 6:
						next[y][x] = 1

		grid = next

# ── Phase 4: Fix diagonal-only connections ───────────────────────────────────
func phase4_fix_diagonals():
	# Pattern: AD / DA → AA / DA (fill top-right D)
	for y in height - 1:
		for x in width - 1:
			var tl = grid[y][x]
			var tr = grid[y][x+1]
			var bl = grid[y+1][x]
			var br = grid[y+1][x+1]

			# A D       A D
			# D A  -->  A A  (fill bottom-left and top-right)
			if tl == 1 and tr == 0 and bl == 0 and br == 1:
				grid[y][x+1] = 1
				grid[y+1][x] = 1

# ── Helper: count Moore neighbors of a given value ───────────────────────────
func count_neighbors(x: int, y: int, value: int) -> int:
	var count = 0
	for dy in [-1, 0, 1]:
		for dx in [-1, 0, 1]:
			if dx == 0 and dy == 0:
				continue
			var nx = x + dx
			var ny = y + dy
			# treat out-of-bounds as walls (D = 0)
			if nx < 0 or nx >= width or ny < 0 or ny >= height:
				if value == 0:
					count += 1
			else:
				if grid[ny][nx] == value:
					count += 1
	return count

# ── Render grid to TileMap ───────────────────────────────────────────────────
func render():
	clear()
	for y in height:
		for x in width:
			# set_cell(layer, coords, source_id, atlas_coords)
			# adjust source_id and atlas_coords to match your tileset
			# wall (D) = atlas coord (5,4), floor (A) = atlas coord (2,2)
			var atlas = Vector2i(5, 4) if grid[y][x] == 0 else Vector2i(2, 2)
			set_cell(0, Vector2i(x, y), 0, atlas)

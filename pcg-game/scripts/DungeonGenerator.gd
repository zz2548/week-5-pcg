# DungeonGenerator.gd
# Procedural dungeon generator modelled after the MarkovJunior XML sequence:
#
#   <sequence values="WRBUPY" origin="True" folder="DungeonGrowth">
#     <union symbol="?" values="BR"/>
#     <prl in="*****/*****/**W**/*****/*****" out="*****/*****/**B**/*****/*****"/>
#     <one> ... Room rules ... </one>
#     <one in="WUW/BBB" out="WRW/BBB"/>
#     <all in="U" out="P"/>
#     <markov>
#       <all> RY→UU, UR→UU, UY→UU, BU→WU, B*/*U→W*/*U </all>
#       <path from="R" to="Y" on="B" color="U" inertia="True" longest="True"/>
#       <one in="Y" out="W"/>
#       <one in="R" out="Y"/>
#     </markov>
#     <all> U→P, W→B </all>
#     <all in="BBB/BPB" out="***/*B*"/>
#     <all> BP→WP, B*/*P→W*/*P </all>
#   </sequence>
#
# Symbol mapping (XML → GDScript constant):
#   W  →  WALL   = 1   hard wall, never carved
#   B  →  BORDER = 2   frontier cell adjacent to placed rooms, carveable
#   P  →  PATH   = 4   legacy corridor cell (L-shaped pass, converted to FLOOR)
#   F  →  FLOOR  = 5   open walkable tile
#   R  →  SEED   = 6   room-edge connection seed ("R" in MJ path rule)
#   U  →  TRACE  = 7   corridor cell being actively carved ("U" in MJ)
#   Y  →  TARGET = 8   current pathfinding destination ("Y" in MJ)

class_name DungeonGenerator
extends Node

# ─── Exported tuning parameters ───────────────────────────────────────────────

@export var width:     int = 80
@export var height:    int = 45
@export var max_rooms: int = 25

# Inertia pathfinder tuning.
# Higher TURN_COST → straighter corridors (strong inertia).
# Lower  TURN_COST → more winding, maze-like corridors.
@export var turn_cost:     int = 8
@export var straight_cost: int = 1

# How many Markov path iterations to attempt before giving up.
@export var markov_iterations: int = 20

# ─── Tile-layer constants ──────────────────────────────────────────────────────

# These match main.gd / zombie.gd expectations exactly — do not renumber.
const WALL   = 1   # XML "W" — solid, never traversed
const BORDER = 2   # XML "B" — frontier, eligible for corridor carving
const PATH   = 4   # legacy L-corridor marker (pre-Markov pass); → FLOOR in _finalize
const FLOOR  = 5   # XML "P" (floor/open) — final walkable state

# New symbols used only during generation; never survive past _finalize.
const SEED   = 6   # XML "R" — room-edge seed, source for <path from="R" …>
const TRACE  = 7   # XML "U" — corridor being carved by <path … color="U">
const TARGET = 8   # XML "Y" — active pathfinding destination for <path … to="Y">

# ─── Object-layer constants ───────────────────────────────────────────────────
# Only the three object types the game actually uses are kept.
# Barrels, explosives, and the shop point have been removed.

const OBJ_NONE   = 0
const OBJ_ITEM   = 3   # key pickup
const OBJ_ENEMY  = 4   # zombie spawn point
const OBJ_PLAYER = 6   # player spawn point

# ─── State ────────────────────────────────────────────────────────────────────

var grid:       Array = []   # grid[y][x] → tile constant
var objects:    Array = []   # objects[y][x] → OBJ_ constant
var rooms:      Array = []   # Vector2i room centres, used by _populate
var player_pos: Vector2i     # set by _populate; read by main.gd to place the player
var exit_pos:   Vector2i     # set by _populate; read by main.gd to place the exit
var astar:      AStarGrid2D  # built by main.gd after generation; read by zombies

# ─── Room templates ───────────────────────────────────────────────────────────
# Mirrors the Room1–Room18 pattern files referenced by the XML <one> block.
# Each template is a 2-D array of 1 (floor) and 0 (skip).
# The MJ interpreter automatically rotates and reflects patterns; we replicate
# that by applying up to 3 × 90° rotations randomly in _place_all_rooms().

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

# =============================================================================
# PUBLIC ENTRY POINT
# =============================================================================

func generate_instant() -> void:
	# Mirrors the top-level <sequence> tag — each call below corresponds to
	# one child node of that sequence, executed in order.

	_init_grid()              # Allocate arrays; fill everything as WALL.

	_place_origin_border()    # <prl in="*****/*****/**W**/*****/*****"
							  #       out="*****/*****/**B**/*****/*****">
							  # Converts the single centre WALL cell to BORDER,
							  # seeding the entire room-placement process.

	_place_all_rooms()        # <one> block with Room1–Room18 rule files.
							  # Picks a random BORDER anchor, stamps a random
							  # room template, marks new frontier as BORDER.
							  # Repeats until max_rooms placed or budget spent.

	_promote_corridor_ends()  # <one in="WUW/BBB" out="WRW/BBB">
							  # Promotes BORDER cells on room doorway edges into
							  # SEED cells — priming them as corridor sources
							  # for the Markov path loop to depart from.

	_run_markov_path_loop()   # <markov> block — the core of MarkovJunior.
							  # Iterates: pick a SEED, find a TARGET, carve an
							  # inertia-weighted path through BORDER cells as
							  # TRACE, advance seeds, repeat until no valid
							  # seed→target pair remains or budget is exhausted.

	_trace_to_floor()         # <all in="U" out="P">
							  # Commits all TRACE cells written by the Markov
							  # loop to permanent FLOOR before finalisation.

	_finalize()               # <all U→P, W→B> (second all-pass in XML).
							  # Converts leftover PATH cells → FLOOR and any
							  # remaining BORDER/SEED/TARGET cells → WALL.

	_connect_orphans()        # Not in XML — connectivity safety net.
							  # BFS flood-fills from the largest floor region,
							  # then carves L-corridors from any isolated floor
							  # island back to the main body, guaranteeing the
							  # entire map is reachable from a single origin.

	_cull()                   # <all in="BBB/BPB" out="***/*B*">
							  # Removes single-tile isolated FLOOR cells that
							  # have no floor neighbours — orphan tiles.

	_trim_borders()           # <all BP→WP, B*/*P→W*/*P>
							  # Any BORDER cell directly adjacent to a FLOOR
							  # cell becomes WALL, tightening room outlines.

	_populate()               # Not in XML — game-logic layer.
							  # Places player spawn, exit, keys, and guard zombies.

# =============================================================================
# SEQUENCE STEP 1 — _init_grid
# =============================================================================

func _init_grid() -> void:
	# Allocates the grid and objects arrays and fills them with WALL / OBJ_NONE.
	# Every cell starts as WALL so that subsequent steps only need to carve
	# outward — no erasure pass is ever required.
	# The BORDER seed is NOT placed here — that is _place_origin_border()'s job,
	# keeping each step's responsibility clean and separately documented.
	grid    = []
	objects = []
	rooms   = []
	for y in height:
		grid.append([])
		objects.append([])
		for _x in width:
			grid[y].append(WALL)
			objects[y].append(OBJ_NONE)

# =============================================================================
# SEQUENCE STEP 2 — _place_origin_border
# XML: <prl in="*****/*****/**W**/*****/*****" out="*****/*****/**B**/*****/*****">
# =============================================================================

func _place_origin_border() -> void:
	# The XML's <prl> rule matches a 5×5 window with a WALL at the centre and
	# converts that centre cell to BORDER.  Applying it once to the grid centre
	# gives the single seed that bootstraps all subsequent room placement.
	# Every room placed by _place_all_rooms grows outward from this origin,
	# and every corridor carved by _run_markov_path_loop traces back to it.
	#
	# We clamp to [1, dim-2] to stay inside the safe inner region so that
	# place_template never attempts to write on the outer wall ring.
	var cx: int = clamp(width  / 2, 1, width  - 2)
	var cy: int = clamp(height / 2, 1, height - 2)
	grid[cy][cx] = BORDER

# =============================================================================
# SEQUENCE STEP 3 — _place_all_rooms
# XML: <one> block containing <rule file="Room1" …> … <rule file="Room18" …>
# =============================================================================

func _place_all_rooms() -> void:
	# The XML <one> node picks ONE matching rule uniformly at random and fires it,
	# then repeats until no rule matches.  We replicate this as a budget loop:
	#   • Pick a random BORDER cell as the anchor (the "?" wildcard in the rules).
	#   • Pick a random room template (Room1–Room18 pattern files).
	#   • Apply a random rotation (MJ automatically tries all 4 rotations).
	#   • Check can_place_template (MJ pattern-match check).
	#   • If it fits, stamp it — place_template writes FLOOR and new BORDERs.
	# Each successfully placed room expands the BORDER frontier outward, giving
	# subsequent iterations more anchors to attach the next room to.
	var placed:   int = 0
	var attempts: int = 0
	while placed < max_rooms and attempts < max_rooms * 50:
		attempts += 1
		var border_cells: Array = get_cells_of_type(BORDER)
		if border_cells.is_empty():
			break
		var anchor: Vector2i = border_cells[randi() % border_cells.size()]
		var template: Array  = ROOM_TEMPLATES[randi() % ROOM_TEMPLATES.size()].duplicate(true)
		# Random rotation — mirrors MJ's automatic symmetry search.
		var rotations: int = randi() % 4
		for _r in rotations:
			template = rotate_template_90(template)
		var th: int = template.size()
		var tw: int = template[0].size()
		# Try several offsets so the anchor can land anywhere in the template,
		# not only the top-left corner.  This lets rooms grow in all directions
		# from the frontier rather than always expanding to the bottom-right.
		var offsets: Array = [
			Vector2i(0, 0),
			Vector2i(-tw / 2, -th / 2),
			Vector2i(-tw + 1, 0),
			Vector2i(0, -th + 1),
			Vector2i(-tw + 1, -th + 1),
		]
		var offset: Vector2i = offsets[randi() % offsets.size()]
		var tx: int = clamp(anchor.x + offset.x, 1, width  - tw - 1)
		var ty: int = clamp(anchor.y + offset.y, 1, height - th - 1)
		if can_place_template(template, tx, ty):
			place_template(template, tx, ty)
			rooms.append(get_template_center(template, tx, ty))
			placed += 1

# =============================================================================
# SEQUENCE STEP 4 — _promote_corridor_ends
# XML: <one in="WUW/BBB" out="WRW/BBB">
# =============================================================================

func _promote_corridor_ends() -> void:
	# The XML pattern "WUW / BBB" matches a 3×2 window where the top row is
	# Wall-Trace-Wall and the bottom row is all BORDER, converting the centre-top
	# cell from TRACE (U) to SEED (R).  At this point in the pipeline TRACE
	# hasn't been written yet, so we approximate the intent directly:
	#
	# A BORDER cell that touches FLOOR on exactly ONE cardinal side is sitting
	# at a room doorway — wall behind it, open room ahead.  That geometry makes
	# it the ideal departure point for a corridor, so we mark it SEED.
	#
	# Requiring exactly one cardinal floor neighbour (rather than any floor
	# neighbour) keeps the seed count low and prevents the entire room perimeter
	# from flooding into SEEDs, which would produce far too many paths and leave
	# the frontier fragmented before the Markov loop can connect it.
	for y in range(1, height - 1):
		for x in range(1, width - 1):
			if grid[y][x] == BORDER:
				var cardinal_floor: int = 0
				for dir in [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]:
					var nx: int = x + dir.x
					var ny: int = y + dir.y
					if nx >= 0 and nx < width and ny >= 0 and ny < height:
						if grid[ny][nx] == FLOOR:
							cardinal_floor += 1
				if cardinal_floor == 1:
					grid[y][x] = SEED

# =============================================================================
# SEQUENCE STEP 5 — _run_markov_path_loop
# XML: <markov> block
# =============================================================================

func _run_markov_path_loop() -> void:
	# The <markov> node reruns its children as a group until no child fires.
	# Children in order:
	#
	#   1. <all> RY→UU, UR→UU, UY→UU   — flood existing traces into seeds/targets
	#      <all> BU→WU, B*/*U→W*/*U     — seal BORDER cells touched by corridors
	#   2. <path from="R" to="Y" on="B" color="U" inertia="True" longest="True">
	#      — carve one inertia-weighted path from a SEED to a TARGET through BORDERs
	#   3. <one in="Y" out="W">          — consume the TARGET marker
	#   4. <one in="R" out="Y">          — promote a SEED to the next TARGET
	#
	# We run up to markov_iterations cycles.  Each cycle:
	#   • Collects all current SEED cells (room doorway edges, XML "R").
	#   • Collects all current BORDER cells not adjacent to floor (XML "Y" pool).
	#   • Picks one SEED and finds its nearest valid TARGET.
	#   • Carves an inertia-weighted path through BORDER cells, writing TRACE.
	#   • Consumes the TARGET (→ WALL) and advances the SEED (→ FLOOR).
	#   • Exits early if no valid seed→target pair can be found.
	#
	# Note: _seal_reached_borders is intentionally omitted here.  Sealing borders
	# adjacent to each carved path was causing isolated BORDER pockets that the
	# loop could never reach, producing disconnected maze sections.  Border
	# cleanup is handled globally by _trim_borders at the end instead.
	for _i in markov_iterations:

		# Collect SEEDs (room doorway edges, XML "R") and candidate TARGETs.
		# TARGETs are BORDER cells with no floor neighbour — deep frontier cells
		# that no room has reached yet, corresponding to XML "Y" destinations.
		var seeds:   Array = []
		var targets: Array = []
		for y in height:
			for x in width:
				match grid[y][x]:
					SEED:
						seeds.append(Vector2i(x, y))
					BORDER:
						# Only deep frontier cells qualify as targets.
						# A BORDER cell already touching floor is a room edge,
						# not a meaningful destination for a new corridor.
						if not _has_neighbor_of_type(x, y, FLOOR):
							targets.append(Vector2i(x, y))

		# No SEEDs → no room doorways left to depart from; nothing to connect.
		if seeds.is_empty():
			break

		# No un-reached frontier → the map is already fully connected.
		if targets.is_empty():
			break

		# Pick one SEED at random and find its nearest reachable TARGET.
		# <path from="R" to="Y" …> in MJ selects source and destination similarly.
		var seed: Vector2i   = seeds[randi() % seeds.size()]
		var target: Vector2i = _find_nearest_target(seed, targets)
		if target == Vector2i(-1, -1):
			# No TARGET is reachable from this seed (all too close or unreachable).
			break

		# Carve the corridor — implements <path … color="U" inertia="True" longest="True">.
		# Returns an ordered list of cells from seed to target through BORDER space.
		var path: Array = _inertia_path(seed, target)
		if path.is_empty():
			# Pathfinder found no route — <path> rule did not fire; try next iteration.
			continue

		# Write TRACE (XML "U") along the carved path.
		# Only BORDER and SEED cells are overwritten — FLOOR and WALL are left intact.
		for cell in path:
			if grid[cell.y][cell.x] == BORDER or grid[cell.y][cell.x] == SEED:
				grid[cell.y][cell.x] = TRACE

		# <one in="Y" out="W"> — consume the TARGET.
		# The reached destination reverts to WALL; it has served its purpose and
		# should not become a dangling open cell or re-used as a future target.
		grid[target.y][target.x] = WALL

		# <one in="R" out="Y"> — advance the SEED to FLOOR.
		# In MJ this promotes the seed to a new TARGET for chaining; here we
		# simply commit it as walkable floor since the path already departs from
		# its location and no further chaining is needed within this iteration.
		grid[seed.y][seed.x] = FLOOR

# =============================================================================
# SEQUENCE STEP 6 — _trace_to_floor
# XML: <all in="U" out="P">  (first all-pass, immediately after the <markov> block)
# =============================================================================

func _trace_to_floor() -> void:
	# Converts every TRACE cell (XML "U") written by _run_markov_path_loop into
	# permanent FLOOR (XML "P").  This step must run before _finalize() so that
	# the subsequent BORDER → WALL pass does not accidentally destroy corridor
	# cells that are still carrying the TRACE marker.
	#
	# PATH cells written by any legacy L-corridor code are intentionally left
	# alone here; _finalize() handles those separately to keep the two corridor
	# systems independent and each step's responsibility clearly bounded.
	for y in height:
		for x in width:
			if grid[y][x] == TRACE:
				grid[y][x] = FLOOR

# =============================================================================
# SEQUENCE STEP 7 — _finalize
# XML: <all> U→P, W→B </all>  (second all-pass — cleans residual symbols)
# =============================================================================

func _finalize() -> void:
	# In the XML this pass converts any remaining U (TRACE) → P (FLOOR) and
	# W (WALL) → B (BORDER).  In our implementation _trace_to_floor() already
	# handled all TRACE cells, so the two jobs remaining here are:
	#   • PATH   → FLOOR  (legacy L-corridor cells, if any remain)
	#   • BORDER → WALL   (frontier cells never carved become solid wall)
	# SEED and TARGET should never survive this far, but they are defensively
	# converted to WALL in case an edge case leaves one behind.
	for y in height:
		for x in width:
			match grid[y][x]:
				PATH:   grid[y][x] = FLOOR
				BORDER: grid[y][x] = WALL
				SEED:   grid[y][x] = WALL
				TARGET: grid[y][x] = WALL

# =============================================================================
# CONNECTIVITY PASS — _connect_orphans
# Not in XML — post-finalize safety net to guarantee full map connectivity.
# =============================================================================

func _connect_orphans() -> void:
	# After _finalize, the grid contains only FLOOR and WALL.  In ideal runs the
	# Markov loop will have connected everything, but if any BORDER pockets were
	# walled off before the loop could reach them, isolated floor islands remain.
	#
	# This function guarantees a fully connected dungeon in three steps:
	#
	#   1. BFS flood-fill from an arbitrary floor cell to find the reachable set.
	#   2. Identify every floor cell NOT in that set — these are orphaned islands.
	#   3. For each orphan, find the nearest reachable floor cell and carve a
	#      direct L-shaped corridor between them, adding the new cells to the
	#      reachable set so that a chain of orphans is stitched together in one pass.
	#
	# The L-corridor approach mirrors the original _connect_all_rooms logic and
	# is intentionally simple — its only job is connectivity, not aesthetics.
	# The Markov-carved corridors already provide all the visual character.
	var floor_cells: Array = get_cells_of_type(FLOOR)
	if floor_cells.is_empty():
		return

	# ── Step 1: BFS flood-fill from the first floor cell ─────────────────────
	# visited tracks every floor cell reachable from the starting origin.
	# We use a Dictionary keyed on Vector2i for O(1) membership checks.
	var visited: Dictionary = {}
	var queue:   Array      = [floor_cells[0]]
	visited[floor_cells[0]] = true
	const CARDINAL: Array   = [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]

	while not queue.is_empty():
		var cur: Vector2i = queue.pop_front()
		for d in CARDINAL:
			var n: Vector2i = cur + d
			if n.x < 0 or n.x >= width or n.y < 0 or n.y >= height:
				continue
			if grid[n.y][n.x] == FLOOR and not visited.has(n):
				visited[n] = true
				queue.append(n)

	# ── Steps 2 & 3: find orphans and stitch them back ───────────────────────
	for cell in floor_cells:
		if visited.has(cell):
			continue   # already reachable — nothing to do

		# This cell is an orphan.  Find the nearest floor cell in the reachable
		# set by brute-force distance scan (acceptable at dungeon scale).
		var nearest:   Vector2i = floor_cells[0]
		var best_dist: float    = INF
		for v in visited.keys():
			var d: float = cell.distance_to(v)
			if d < best_dist:
				best_dist = d
				nearest   = v

		# Carve an L-shaped corridor: move horizontally first, then vertically.
		# Every cell written to FLOOR is immediately added to visited so that the
		# next orphan in the list can connect to this newly carved corridor rather
		# than hunting all the way back to the original flood-fill origin.
		var x: int = cell.x
		var y: int = cell.y
		while x != nearest.x:
			grid[y][x] = FLOOR
			visited[Vector2i(x, y)] = true
			x += 1 if nearest.x > x else -1
		while y != nearest.y:
			grid[y][x] = FLOOR
			visited[Vector2i(x, y)] = true
			y += 1 if nearest.y > y else -1

# =============================================================================
# SEQUENCE STEP 8 — _cull
# XML: <all in="BBB/BPB" out="***/*B*">
# =============================================================================

func _cull() -> void:
	# The XML 3×3 pattern "BBB / BPB" (all border surrounding a floor centre)
	# removes isolated single-tile floor cells by converting them back to wall.
	# We approximate this as: any FLOOR cell with zero FLOOR neighbours → WALL.
	# This catches stray 1×1 floor tiles that are technically walkable but have
	# no adjacent floor — unreachable in practice and visually noisy on the map.
	for y in height:
		for x in width:
			if grid[y][x] == FLOOR:
				if count_neighbors(x, y, FLOOR) == 0:
					grid[y][x] = WALL

# =============================================================================
# SEQUENCE STEP 9 — _trim_borders
# XML: <all BP→WP, B*/*P→W*/*P>
# =============================================================================

func _trim_borders() -> void:
	# The XML patterns "BP" (BORDER immediately right of FLOOR) and "B* / *P"
	# (BORDER one row above a FLOOR) convert those BORDER cells to WALL.
	# Net effect: any surviving BORDER cell that directly touches a FLOOR cell
	# becomes WALL, giving room outlines clean hard edges without stray frontier
	# markers bleeding into the walkable area.
	# At this stage BORDER should be rare — _finalize already swept most of them
	# to WALL — but _connect_orphans can expose new adjacencies that need trimming.
	for y in height:
		for x in width:
			if grid[y][x] == BORDER:
				if _has_neighbor_of_type(x, y, FLOOR):
					grid[y][x] = WALL

# =============================================================================
# SEQUENCE STEP 10 — _populate  (game logic, not in XML)
# =============================================================================

func _populate() -> void:
	# Writes spawn positions for the three game object types onto the object layer:
	#   • OBJ_PLAYER — one cell near the grid centre in the most open floor region.
	#   • OBJ_ITEM   — exactly 5 keys on free floor cells, always.
	#   • OBJ_ENEMY  — exactly 5 enemies on free floor cells, always.
	#
	# Keys and enemies are placed by shuffling all free floor cells and taking the
	# first 5 of each.  No zone logic, no distance filters — guaranteed counts.
	#
	# exit_pos is set to the floor cell farthest from player_pos so main.gd can
	# place the exit Area2D without needing any generation logic of its own.

	var floor_cells: Array = get_cells_of_type(FLOOR)
	if floor_cells.is_empty():
		return

	# ── Player ────────────────────────────────────────────────────────────────
	var center: Vector2i = Vector2i(width / 2, height / 2)
	player_pos = _best_open_spawn_near(center, floor_cells)
	objects[player_pos.y][player_pos.x] = OBJ_PLAYER

	# ── Exit ──────────────────────────────────────────────────────────────────
	# Placed as far from the player as possible so the player must traverse the
	# whole dungeon.  Stored in exit_pos for main.gd to read directly.
	exit_pos = _farthest_floor_from(player_pos, floor_cells)

	# ── Build free-cell pool ──────────────────────────────────────────────────
	# All floor cells not already claimed by the player spawn.
	# Shuffled once; keys and enemies both draw from this same ordered list,
	# so they never overlap each other or the player.
	var free: Array = []
	for cell in floor_cells:
		if objects[cell.y][cell.x] == OBJ_NONE:
			free.append(cell)
	free.shuffle()

	# ── Keys — exactly 5 ─────────────────────────────────────────────────────
	var keys_placed: int = 0
	for cell in free:
		if keys_placed >= 5:
			break
		if objects[cell.y][cell.x] != OBJ_NONE:
			continue
		objects[cell.y][cell.x] = OBJ_ITEM
		keys_placed += 1

	# ── Enemies — exactly 5 ──────────────────────────────────────────────────
	var enemies_placed: int = 0
	for cell in free:
		if enemies_placed >= 5:
			break
		if objects[cell.y][cell.x] != OBJ_NONE:
			continue
		objects[cell.y][cell.x] = OBJ_ENEMY
		enemies_placed += 1

# =============================================================================
# MARKOV PATHFINDER — _inertia_path
# XML: <path from="R" to="Y" on="B" color="U" inertia="True" longest="True">
# =============================================================================

func _inertia_path(start: Vector2i, goal: Vector2i) -> Array:
	# Inertia-weighted Dijkstra over BORDER (and SEED) cells.
	#
	# inertia="True"  is implemented by charging turn_cost when the direction
	#                 changes and only straight_cost when continuing straight.
	#                 This makes paths strongly prefer straight runs and only
	#                 turn when the detour is worth paying for — producing the
	#                 long straight corridors with occasional bends that MJ
	#                 generates with its inertia flag.
	#
	# longest="True"  is approximated by subtracting a small fraction of the
	#                 remaining distance-to-goal from the accumulated cost.
	#                 This biases the search toward routes that stay far from
	#                 the goal longer, producing winding corridors that explore
	#                 more of the map before terminating.
	#
	# Performance: instead of a sort-based priority queue (O(n log n) per pop),
	# we use bucket queues (Dial's algorithm).  The grid is only 80×45×4 = 14400
	# states so a flat PackedInt32Array for costs and came_from gives O(1)
	# lookup with no dictionary overhead — critical for keeping generation fast.
	#
	# State:  packed key = pos.y * width * 4 + pos.x * 4 + direction_index
	# Bucket: buckets[cost] = list of packed keys with that accumulated cost

	const DIRS: Array = [
		Vector2i( 1,  0),   # 0 = East
		Vector2i(-1,  0),   # 1 = West
		Vector2i( 0,  1),   # 2 = South
		Vector2i( 0, -1),   # 3 = North
	]

	var max_key: int            = height * width * 4
	var cost_arr:  PackedInt32Array = PackedInt32Array()
	var came_from: PackedInt32Array = PackedInt32Array()
	cost_arr.resize(max_key)
	came_from.resize(max_key)
	cost_arr.fill(999999)
	came_from.fill(-1)

	# Bucket array — index is the cost value, each slot holds a list of keys.
	# MAX_BUCKET caps the cost space; paths exceeding this are discarded as
	# unreachably expensive (shouldn't occur on a well-formed 80×45 grid).
	const MAX_BUCKET: int = 10000
	var buckets: Array = []
	buckets.resize(MAX_BUCKET)
	for i in MAX_BUCKET:
		buckets[i] = []

	# Seed all four initial direction-states from the start cell at cost 0.
	# This lets the path depart in any direction without paying a turn penalty.
	var min_bucket: int = 0
	for d in range(4):
		var k: int = _pack(start, d)
		cost_arr[k] = 0
		buckets[0].append(k)

	while min_bucket < MAX_BUCKET:
		# Advance min_bucket to the next non-empty slot — this is the O(1)
		# "find minimum" that makes bucket queues efficient.
		while min_bucket < MAX_BUCKET and buckets[min_bucket].is_empty():
			min_bucket += 1
		if min_bucket >= MAX_BUCKET:
			break

		var k:   int      = buckets[min_bucket].pop_back()
		var pos: Vector2i = Vector2i((k / 4) % width, (k / 4) / width)
		var cd:  int      = k % 4   # current (incoming) direction index

		if pos == goal:
			return _reconstruct_path(came_from, start, goal)

		# Lazy deletion: if a cheaper route to this state was already found and
		# processed, skip this stale entry rather than re-expanding it.
		if cost_arr[k] < min_bucket:
			continue

		for nd in range(4):
			var npos: Vector2i = pos + DIRS[nd]
			if npos.x < 0 or npos.x >= width or npos.y < 0 or npos.y >= height:
				continue
			# Only carve through BORDER or SEED cells.
			# FLOOR cells belong to existing rooms and must not be merged mid-path.
			# WALL cells are hard boundaries that corridors cannot pierce.
			var tile: int = grid[npos.y][npos.x]
			if tile != BORDER and tile != SEED:
				continue

			# inertia: turning costs significantly more than going straight.
			var step_cost: int     = straight_cost if nd == cd else turn_cost
			# longest: subtract a fraction of distance-to-goal to favour longer paths.
			var winding_bonus: int = -int(npos.distance_to(goal) * 0.3)
			var new_cost: int      = cost_arr[k] + step_cost + winding_bonus
			# Clamp to valid bucket range; winding_bonus can make costs go negative.
			new_cost = max(min_bucket, min(new_cost, MAX_BUCKET - 1))

			var nk: int = _pack(npos, nd)
			if new_cost < cost_arr[nk]:
				cost_arr[nk]  = new_cost
				came_from[nk] = k
				buckets[new_cost].append(nk)

	return []   # No path found — <path> rule does not fire this iteration.


func _reconstruct_path(came_from: PackedInt32Array, start: Vector2i, goal: Vector2i) -> Array:
	# Walks the came_from array backwards from goal to start, collecting each
	# cell position into an ordered array.  The result is reversed at the end
	# so it reads from start → goal, ready for TRACE writing in the caller.
	var path: Array    = []
	var current_key: int = -1

	# Find which direction-state first reached the goal cell.
	for d in range(4):
		var k: int = _pack(goal, d)
		if came_from[k] != -1:
			current_key = k
			break
	if current_key == -1:
		return []   # goal was never reached

	path.append(goal)
	while current_key != -1:
		var prev_k: int        = came_from[current_key]
		if prev_k == -1:
			break
		var prev_pos: Vector2i = Vector2i((prev_k / 4) % width, (prev_k / 4) / width)
		if prev_pos == start:
			break
		path.append(prev_pos)
		current_key = prev_k

	path.reverse()
	return path


func _pack(pos: Vector2i, dir: int) -> int:
	# Encodes a (grid position, direction) pair as a single integer index.
	# Used to address the flat cost_arr and came_from PackedInt32Arrays directly,
	# avoiding dictionary overhead entirely.
	# Maximum value: (height-1) * width * 4 + (width-1) * 4 + 3
	#              = 44 * 80 * 4 + 79 * 4 + 3 = 14397 — well within int range.
	return pos.y * width * 4 + pos.x * 4 + dir

# =============================================================================
# MARKOV HELPERS
# =============================================================================

func _find_nearest_target(from: Vector2i, candidates: Array) -> Vector2i:
	# Returns the nearest candidate cell that is at least 5 tiles from 'from'.
	# The minimum distance of 5 prevents trivially short corridors that would
	# connect a room doorway cell straight back to an adjacent room edge —
	# those connections add no navigational value and waste Markov iterations.
	var best:      Vector2i = Vector2i(-1, -1)
	var best_dist: float    = INF
	for c in candidates:
		var d: float = from.distance_to(c)
		if d >= 5.0 and d < best_dist:
			best_dist = d
			best      = c
	return best


func _has_neighbor_of_type(x: int, y: int, type: int) -> bool:
	# Returns true if any of the 8 surrounding cells (including diagonals)
	# equals 'type'.  Used by _promote_corridor_ends and _trim_borders to test
	# adjacency without allocating a temporary array of neighbours.
	for dy in [-1, 0, 1]:
		for dx in [-1, 0, 1]:
			if dx == 0 and dy == 0:
				continue
			var nx: int = x + dx
			var ny: int = y + dy
			if nx >= 0 and nx < width and ny >= 0 and ny < height:
				if grid[ny][nx] == type:
					return true
	return false

# =============================================================================
# TEMPLATE UTILITIES
# =============================================================================

func rotate_template_90(template: Array) -> Array:
	# Rotates a 2-D template array 90° clockwise.
	# The original row count becomes the new column count and vice versa.
	# MJ automatically tries all four rotations for each Room rule file;
	# we replicate this by calling this function 0–3 times randomly in
	# _place_all_rooms before attempting to stamp each template.
	var h: int = template.size()
	var w: int = template[0].size()
	var rotated: Array = []
	for col in range(w):
		rotated.append([])
		for row in range(h - 1, -1, -1):
			rotated[col].append(template[row][col])
	return rotated


func can_place_template(template: Array, tx: int, ty: int) -> bool:
	# Returns true only if every '1' cell in the template maps to a WALL or
	# BORDER cell on the grid — meaning the area is entirely unoccupied.
	# A cell that is already FLOOR or PATH means two rooms would overlap; reject.
	# Cells on or outside the outer wall ring (x ≤ 0, x ≥ width-1 etc.) are also
	# rejected to ensure a solid wall border always surrounds the dungeon.
	for row in range(template.size()):
		for col in range(template[row].size()):
			if template[row][col] == 0:
				continue
			var x: int = tx + col
			var y: int = ty + row
			if x <= 0 or x >= width - 1 or y <= 0 or y >= height - 1:
				return false
			if grid[y][x] == FLOOR or grid[y][x] == PATH:
				return false
	return true


func place_template(template: Array, tx: int, ty: int) -> void:
	# Stamps the template onto the grid in two passes:
	#
	#   Pass 1 — write FLOOR for every '1' cell in the template.
	#            This is the room interior: the XML "P" symbol.
	#
	#   Pass 2 — walk the 1-cell border ring around the entire template bounding
	#            box.  Any cell in that ring that is still WALL becomes BORDER.
	#            This BORDER ring is exactly what the XML Room rules produce as
	#            "B" output cells — the frontier that the next room or corridor
	#            will anchor to.
	for row in range(template.size()):
		for col in range(template[row].size()):
			if template[row][col] == 0:
				continue
			grid[ty + row][tx + col] = FLOOR
	for row in range(-1, template.size() + 1):
		for col in range(-1, template[0].size() + 1):
			var x: int = tx + col
			var y: int = ty + row
			if x > 0 and x < width - 1 and y > 0 and y < height - 1:
				if grid[y][x] == WALL:
					grid[y][x] = BORDER


func get_template_center(template: Array, tx: int, ty: int) -> Vector2i:
	# Returns the grid cell at the centre of the template's bounding box.
	# Stored in the rooms array and used by _populate to identify room locations.
	return Vector2i(tx + template[0].size() / 2, ty + template.size() / 2)

# =============================================================================
# GRID QUERY UTILITIES  (public — used by main.gd, zombie.gd, _populate)
# =============================================================================

func get_cells_of_type(value: int) -> Array:
	# Returns all grid positions whose tile equals 'value' as an Array of Vector2i.
	# Called frequently during generation (border cell collection, floor counts)
	# and at runtime by zombie.gd for roam-target selection.
	var result: Array = []
	for y in height:
		for x in width:
			if grid[y][x] == value:
				result.append(Vector2i(x, y))
	return result


func count_neighbors(x: int, y: int, value: int) -> int:
	# Counts how many of the 8 surrounding cells equal 'value'.
	# Out-of-bounds cells are treated as WALL so that edge and corner cells
	# correctly report wall-neighbour counts without bounds-check branching.
	# Used by _cull to identify isolated floor tiles with no floor neighbours.
	var count: int = 0
	for dy in [-1, 0, 1]:
		for dx in [-1, 0, 1]:
			if dx == 0 and dy == 0:
				continue
			var nx: int = x + dx
			var ny: int = y + dy
			if nx < 0 or nx >= width or ny < 0 or ny >= height:
				if value == WALL:
					count += 1
			else:
				if grid[ny][nx] == value:
					count += 1
	return count

# =============================================================================
# POPULATE HELPERS  (private)
# =============================================================================

func _count_open_floor_nearby(cell: Vector2i, r: int) -> int:
	# Counts FLOOR cells within a square of radius r centred on 'cell'.
	# Higher counts mean the cell sits in a spacious open area rather than a
	# tight corridor.  Used by _best_open_spawn_near (player placement) and
	# _populate's key placement loop to prefer large rooms over narrow passages.
	var count: int = 0
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var nx: int = cell.x + dx
			var ny: int = cell.y + dy
			if nx >= 0 and nx < width and ny >= 0 and ny < height:
				if grid[ny][nx] == FLOOR:
					count += 1
	return count


func _best_open_spawn_near(target: Vector2i, floor_cells: Array) -> Vector2i:
	# Returns the most open floor cell within 15 tiles of 'target'.
	# Used to place the player near the grid centre in an open area so they
	# aren't spawned in a 1-tile-wide corridor with no room to move.
	# If no cell within 15 tiles qualifies the function returns floor_cells[0]
	# as a safe fallback.
	var best_cell:  Vector2i = floor_cells[0]
	var best_score: int      = -1
	for cell in floor_cells:
		if cell.distance_to(target) > 15:
			continue
		var openness: int = _count_open_floor_nearby(cell, 3)
		if openness > best_score:
			best_score = openness
			best_cell  = cell
	return best_cell


func _farthest_floor_from(target: Vector2i, floor_cells: Array) -> Vector2i:
	# Returns the floor cell with the greatest straight-line distance from 'target'.
	# Used to place the exit as far from the player start as possible,
	# maximising the distance the player must travel to win.
	var best:      Vector2i = floor_cells[0]
	var best_dist: float    = -INF
	for cell in floor_cells:
		var d: float = target.distance_to(cell)
		if d > best_dist:
			best_dist = d
			best      = cell
	return best

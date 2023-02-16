extends Node

var game:Node


# self = Behavior.follow


const teleport_time = 3
const teleport_max_distance = 100


# PATHFIND GRID
var path_grid
var path_finder
var path_line


func _ready():
	game = get_tree().get_current_scene()
	path_line = Line2D.new()


func setup_pathfind():
	# get tiles
	var walls_rect = game.map.walls.get_used_rect()
	var walls_size =  walls_rect.size
	#setup grid
	var grid = Finder.GridGD.new().Grid
	path_grid = grid.new(walls_size.x, walls_size.y)
	# add tile walls
	for cell in game.map.walls.get_used_cells():
		game.maps.blocks.create_block(cell.x, cell.y)
		path_grid.setWalkableAt(cell.x, cell.y, false)
	# add building units
	for building in game.player_buildings:
		var pos = (building.global_position / game.map.tile_size).floor()
		path_grid.setWalkableAt(pos.x, pos.y, false)
	for building in game.enemy_buildings:
		var pos = (building.global_position / game.map.tile_size).floor()
		path_grid.setWalkableAt(pos.x, pos.y, false)
	for building in game.neutral_buildings:
		var pos = (building.global_position / game.map.tile_size).floor()
		path_grid.setWalkableAt(pos.x, pos.y, false)
	# setup finder
	path_finder = Finder.JumpPointFinder.new()
	
	game.map.add_child(path_line)


func find_path(g1, g2):
	var cell_size = game.map.tile_size
	var half = game.map.half_tile_size
	var p1 = (g1 / cell_size).floor()
	var p2 = (g2 / cell_size).floor()
	if in_limits(p1) and in_limits(p2):
		var solved_path = path_finder.findPath(p1.x, p1.y, p2.x, p2.y, path_grid.clone())
		# path to global_position
		var path = []
		for i in range(1, solved_path.size()):
			var item = solved_path[i]
		# int array[x,y] to float dict Vector2(x,y)
			path.append(Vector2(half + (item[0] * cell_size), half + (item[1] * cell_size)))
		return path


func in_limits(p):
	return ((p.x > 0 and p.y > 0) and (p.x < path_grid.width and p.y < path_grid.height)) 


func path(unit, new_path):
	var agent = unit.agent
	if new_path and not new_path.empty():
		var next_point = new_path.pop_front()
		agent.set_state("current_path", new_path)
		Behavior.advance.point(unit, next_point)


func smart(unit, path, cb):
	var agent = unit.agent
	if path and path.size():
		var new_path = unit.cut_path(path)
		var next_point = new_path.pop_front()
		agent.set_state("current_path", new_path)
		Behavior.advance.point(unit, next_point)


func resume(unit):
	var lane = unit.agent.get_state("lane")
	var new_path = game.maps.new_path(lane, unit.team)
	path(unit, new_path)


func next(unit):
	var agent = unit.agent
	path(unit, agent.get_state("current_path"))


func draw_path(unit):
	var should_draw = false
	var has_path = false
	
	if unit and unit.agent:
		has_path = unit.agent.get_state("has_path")
		should_draw = (has_path or unit.current_destiny or unit.objective)
	
	if should_draw:
		path_line.visible = true
		var pool = PoolVector2Array()
		# start
		pool.push_back(unit.global_position)
		 # end
		if has_path:
			var path = unit.agent.get_state("current_path")
			pool.append_array(path)
		elif unit.current_destiny:
			pool.push_back(unit.current_destiny)
		elif unit.objective:
			pool.push_back(unit.objective)
			
		if unit.team == "blue":
			path_line.default_color = Color(0.4,0.6,1, 0.3)
		else: path_line.default_color = Color(1,0.3,0.3, 0.3)
		path_line.points = pool
	# todo add line shader
	# https://www.reddit.com/r/godot/comments/btsrxc/shaders_for_line2d_are_tricky_does_anyone_use_them/
	else: path_line.visible = false


func change_lane(unit, point):
	var lane = game.utils.closer_lane(point)
	var path = lane.duplicate()
	if unit.team == "red": path.invert()
	var lane_start = path.pop_front()
	unit.agent.set_state("lane", lane)
	# unit.agent.set_state("order_behavior", "move")
	Behavior.move.smart(unit, lane_start)


func teleport(unit, point):
	var agent = unit.agent
	game.ui.controls_menu.teleport_button.disabled = true
	var building = game.utils.closer_building(point, unit.team)
	var distance = building.global_position.distance_to(point)
	game.ui.controls_menu.teleport_button.disabled = false
	game.ui.controls_menu.teleport_button.pressed = false
	Behavior.move.stop(unit)
	unit.agent.set_state("is_channeling", true)
	
	yield(get_tree().create_timer(teleport_time), "timeout")
	if unit.agent.get_state("is_channeling"):
		unit.agent.set_state("has_player_command", false)
		unit.agent.set_state("is_channeling", false)
		var new_position = point
		# prevent teleport into buildings
		var min_distance = 2 * building.collision_radius + unit.collision_radius
		if distance <= min_distance:
			var offset = (point - building.global_position).normalized()
			new_position = building.global_position + (offset * min_distance)
		# limit teleport range
		if distance > teleport_max_distance:
			var offset = (point - building.global_position).normalized()
			new_position = building.global_position + (offset * teleport_max_distance)

		unit.global_position = new_position
		unit.agent.set_state("lane", building.lane)
		agent.set_state("current_path", [])

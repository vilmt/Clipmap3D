class_name Terrain3DMeshHandler

var _lods: int
var _size: Vector2i
var _vertex_spacing: Vector2
var _material: ShaderMaterial
var _scenario: RID
var _visible: bool
var _cast_shadows: RenderingServer.ShadowCastingSetting
var _render_layer: int
var _amplitude: float = 0.1
var _height_map: HeightMap

var _clipmap_rids: Array
var _mesh_rids: Array[RID]

var _trim_a_ps: PackedVector3Array
var _trim_b_ps: PackedVector3Array
var _tile_ps_lod_0: PackedVector3Array

var _fill_a_ps: PackedVector3Array
var _fill_b_ps: PackedVector3Array
var _tile_ps: PackedVector3Array

var _offset_a_x: float
var _offset_b_x: float
var _offset_c_x: float

var _offset_a_z: float
var _offset_b_z: float
var _offset_c_z: float

var _edge_x_ps: PackedVector3Array
var _edge_z_ps: PackedVector3Array

var _last_target_p_2d := Vector2.ZERO

# TODO: clean! do this
var _offsets: Dictionary[MeshType, PackedVector3Array]

# TODO: refactor "standard", very unclear
enum MeshType {
	TILE,
	EDGE_A,
	EDGE_B,
	FILL_A,
	FILL_B,
	STANDARD_TRIM_A,
	STANDARD_TRIM_B,
	STANDARD_TILE,
	STANDARD_EDGE_A,
	STANDARD_EDGE_B
}

func update_height_map(height_map: HeightMap):
	if _height_map:
		_height_map.changed.disconnect(_on_height_map_changed)
	_height_map = height_map
	if _height_map:
		_height_map.changed.connect(_on_height_map_changed)
	_on_height_map_changed()

func _on_height_map_changed():
	update_amplitude(_height_map.amplitude)

func update_size(size: Vector2i):
	_size = size
	
	_generate_mesh_types()
	_generate_offsets()
	_generate_instances()

func update_lods(lods: int):
	_lods = lods
	
	_generate_instances()

func update_vertex_spacing(vertex_spacing: Vector2):
	_vertex_spacing = vertex_spacing
	if _material:
		_material.set_shader_parameter(&"vertex_spacing", vertex_spacing)

func update_material(material_rid: RID):
	for mesh_rid: RID in _mesh_rids:
		RenderingServer.mesh_surface_set_material(mesh_rid, 0, material_rid)
		
func update_scenario(scenario: RID):
	for lod_array in _clipmap_rids:
		for mesh_array in lod_array:
			for rid: RID in mesh_array:
				RenderingServer.instance_set_scenario(rid, scenario)

func update_visible(visible: bool):
	for lod_array in _clipmap_rids:
		for mesh_array in lod_array:
			for rid: RID in mesh_array:
				RenderingServer.instance_set_visible(rid, visible)

func update_render_layer(render_layer: int):
	for lod_array in _clipmap_rids:
		for mesh_array in lod_array:
			for rid: RID in mesh_array:
				RenderingServer.instance_set_layer_mask(rid, render_layer)

func update_cast_shadows(cast_shadows: RenderingServer.ShadowCastingSetting):
	for lod_array in _clipmap_rids:
		for mesh_array in lod_array:
			for rid: RID in mesh_array:
				RenderingServer.instance_geometry_set_cast_shadows_setting(rid, cast_shadows)

func update_amplitude(amplitude: float):
	_amplitude = amplitude
	for rid: RID in _mesh_rids:
		var aabb := RenderingServer.mesh_get_custom_aabb(rid) # TODO: remove this, probably expensive
		aabb.size.y = _amplitude
		RenderingServer.mesh_set_custom_aabb(rid, aabb)

func snap_to_target(target_position: Vector2, vertex_spacing: Vector2, force: bool = false) -> void:
	var target_p_2d := target_position
	
	var must_snap: bool = absf(_last_target_p_2d.x - target_p_2d.x) >= vertex_spacing.x or absf(_last_target_p_2d.y - target_p_2d.y) >= vertex_spacing.y
	
	if not (must_snap or force):
		return
	
	_last_target_p_2d = target_p_2d
	var snapped_p_2d: Vector2 = (target_p_2d / vertex_spacing).floor() * vertex_spacing
	
	for lod: int in _clipmap_rids.size():
		var snap: Vector2 = pow(2.0, float(lod) + 1.0) * vertex_spacing
		var lod_scale := Vector3(pow(2.0, lod) * vertex_spacing.x, 1.0, pow(2.0, lod) * vertex_spacing.y)
		
		var p_2d := (snapped_p_2d / snap).round() * snap
		
		var next_snap := pow(2.0, float(lod) + 2.0) * vertex_spacing
		
		var next_p_2d := (snapped_p_2d / next_snap).round() * next_snap
		
		# TODO: clean up this logic... vector elements being accessed with these indices is super confusing
		var test_p_2d := (Vector2i(((p_2d - next_p_2d) / snap).round()) + Vector2i.ONE).clampi(0, 2)
		
		var lod_array = _clipmap_rids[lod]
		
		for mesh_i in lod_array.size():
			var mesh_array = lod_array[mesh_i]
			for instance_i in mesh_array.size():
				var t := Transform3D.IDENTITY
				# TODO: clean up logic
				match mesh_i:
					MeshType.TILE:
						if lod == 0:
							t.origin = _tile_ps_lod_0[instance_i]
						else:
							t.origin = _tile_ps[instance_i]
					MeshType.EDGE_A:
						var edge_p_instance: Vector3 = _edge_x_ps[instance_i]
						t.origin.x = edge_p_instance[test_p_2d.x]
						t.origin.z -= _offset_a_z + (test_p_2d.y * 2.0)
					MeshType.EDGE_B:
						var edge_p_instance: Vector3 = _edge_z_ps[instance_i]
						t.origin.x -= _offset_a_x
						t.origin.z = edge_p_instance[test_p_2d.y]
					MeshType.FILL_A:
						if lod == 0:
							t.origin = _trim_a_ps[instance_i]
						else:
							t.origin = _fill_a_ps[instance_i]
					MeshType.FILL_B:
						if lod == 0:
							t.origin = _trim_b_ps[instance_i]
						else:
							t.origin = _fill_b_ps[instance_i]
				
				t = t.scaled(lod_scale)
				t.origin += Vector3(p_2d.x, 0.0, p_2d.y)
				RenderingServer.instance_set_transform(mesh_array[instance_i], t)
				RenderingServer.instance_teleport(mesh_array[instance_i])

func generate(terrain: Terrain3D) -> void:
	_size = terrain.mesh_size
	_lods = terrain.mesh_lods
	_scenario = terrain.get_world_3d().scenario
	_visible = terrain.is_visible_in_tree()
	_material = terrain.shader_material
	_cast_shadows = terrain.cast_shadows as RenderingServer.ShadowCastingSetting
	_render_layer = terrain.render_layer
	
	update_height_map(terrain.height_map)
	
	_generate_mesh_types()
	_generate_offsets()
	_generate_instances()

func clear():
	_clear_instances()
	_clear_mesh_types()
	
func _generate_instances() -> void:
	_clear_instances()
	for level: int in _lods:
		var lod_array: Array = []
		
		var tile_amount: int = 12
		if level == 0:
			tile_amount = 16
		
		# TODO: clean up duplicate code
		var tile_rids: Array = []
		for i: int in tile_amount:
			var instance_i := MeshType.TILE
			if level == 0:
				instance_i = MeshType.STANDARD_TILE
			tile_rids.append(RenderingServer.instance_create2(_mesh_rids[instance_i], _scenario))
		lod_array.append(tile_rids) # Index 0: TILE
		
		var edge_a_rids: Array = []
		for i: int in 2:
			var instance_i := MeshType.EDGE_A
			if level == 0:
				instance_i = MeshType.STANDARD_EDGE_A
			edge_a_rids.append(RenderingServer.instance_create2(_mesh_rids[instance_i], _scenario))
		lod_array.append(edge_a_rids) # Index 1: EDGE_A
		
		var edge_b_rids: Array = []
		for i: int in 2:
			var instance_i := MeshType.EDGE_B
			if level == 0:
				instance_i = MeshType.STANDARD_EDGE_B
			edge_b_rids.append(RenderingServer.instance_create2(_mesh_rids[instance_i], _scenario))
		lod_array.append(edge_b_rids) # Index 2: EDGE_B
		
		if level == 0:
			var trim_a_rids: Array[RID] = []
			for i: int in 2:
				var instance_i := MeshType.STANDARD_TRIM_A
				trim_a_rids.append(RenderingServer.instance_create2(_mesh_rids[instance_i], _scenario))
			lod_array.append(trim_a_rids) # Index 4: TRIM_A
			
			var trim_b_rids: Array[RID] = []
			for i: int in 2:
				var instance_i := MeshType.STANDARD_TRIM_B
				trim_b_rids.append(RenderingServer.instance_create2(_mesh_rids[instance_i], _scenario))
			lod_array.append(trim_b_rids) # Index 5: TRIM_B
		else:
			var fill_a_rids: Array[RID] = []
			for i: int in 2:
				var instance_i := MeshType.FILL_A
				fill_a_rids.append(RenderingServer.instance_create2(_mesh_rids[instance_i], _scenario))
			lod_array.append(fill_a_rids) # Index 4: FILL_A
			
			var fill_b_rids: Array[RID] = []
			for i: int in 2:
				var instance_i := MeshType.FILL_B
				fill_b_rids.append(RenderingServer.instance_create2(_mesh_rids[instance_i], _scenario))
			lod_array.append(fill_b_rids) # Index 4: FILL_B
		
		_clipmap_rids.append(lod_array)
	
	for lod_array in _clipmap_rids:
		for mesh_array in lod_array:
			for rid: RID in mesh_array:
				RenderingServer.instance_set_visible(rid, _visible)
				RenderingServer.instance_set_layer_mask(rid, _render_layer)
				RenderingServer.instance_geometry_set_cast_shadows_setting(rid, _cast_shadows)

func _generate_mesh_types():
	_clear_mesh_types()
	# 0 TILE - mesh_size x mesh_size tiles
	_mesh_rids.append(_generate_mesh(_size))
	# 1 EDGE_A - 2 by (mesh_size * 4 + 8) strips to bridge LOD transitions along Z axis
	_mesh_rids.append(_generate_mesh(Vector2i(2, _size.y * 4 + 8)))
	# 2 EDGE_B - (mesh_size * 4 + 4) by 2 strips to bridge LOD transitions along X axis
	_mesh_rids.append(_generate_mesh(Vector2i(_size.x * 4 + 4, 2)))
	# 3 FILL_A - 4 by mesh_size
	_mesh_rids.append(_generate_mesh(Vector2i(4, _size.y)))
	# 4 FILL_B - mesh_size by 4
	_mesh_rids.append(_generate_mesh(Vector2i(_size.x, 4)))
	# 5 STANDARD_TRIM_A - 2 by (mesh_size * 4 + 2) strips for LOD0 Z axis edge
	_mesh_rids.append(_generate_mesh(Vector2i(2, _size.y * 4 + 2), true))
	# 6 STANDARD_TRIM_B - (mesh_size * 4 + 2) by 2 strips for LOD0 X axis edge
	_mesh_rids.append(_generate_mesh(Vector2i(_size.x * 4 + 2, 2), true))
	# 7 STANDARD_TILE - mesh_size x mesh_size tiles
	_mesh_rids.append(_generate_mesh(_size, true))
	 # 8 STANDARD_EDGE_A - 2 by (mesh_size * 4 + 8) strips to bridge LOD transitions along Z axis
	_mesh_rids.append(_generate_mesh(Vector2i(2, _size.y * 4 + 8), true))
	# 9 STANDARD_EDGE_B - (mesh_size * 4 + 4) by 2 strips to bridge LOD transitions along X axis
	_mesh_rids.append(_generate_mesh(Vector2i(_size.x * 4 + 4, 2), true))
	
	for rid: RID in _mesh_rids:
		var aabb := RenderingServer.mesh_get_custom_aabb(rid) # TODO: remove this, probably expensive
		aabb.size.y = _amplitude
		RenderingServer.mesh_set_custom_aabb(rid, aabb)
	
func _generate_mesh(size: Vector2i, use_standard_grid: bool = false) -> RID:
	var mesh_arrays: Array = []
	mesh_arrays.resize(RenderingServer.ARRAY_MAX)
	
	var vertices := PackedVector3Array()
	for y: int in size.y + 1:
		for x: int in size.x + 1:
			vertices.append(Vector3(x, 0.0, y))
	mesh_arrays[RenderingServer.ARRAY_VERTEX] = vertices
	
	var indices := PackedInt32Array()
	for y: int in size.y:
		for x: int in size.x:
			var b_l: int = y * (size.x + 1) + x
			var b_r: int = b_l + 1
			var t_l: int = (y + 1) * (size.x + 1) + x
			var t_r: int = t_l + 1
			
			if (x + y) % 2 == 0 or use_standard_grid:
				indices.append(b_l)
				indices.append(t_r)
				indices.append(t_l)
				
				indices.append(b_l)
				indices.append(b_r)
				indices.append(t_r)
			else:
				indices.append(b_l)
				indices.append(b_r)
				indices.append(t_l)
				
				indices.append(t_l)
				indices.append(b_r)
				indices.append(t_r)
	mesh_arrays[RenderingServer.ARRAY_INDEX] = indices
	
	var normals := PackedVector3Array()
	normals.resize(vertices.size())
	normals.fill(Vector3.UP)
	mesh_arrays[RenderingServer.ARRAY_NORMAL] = normals
	
	var tangents := PackedFloat32Array()
	tangents.resize(vertices.size() * 4)
	tangents.fill(0.0)
	mesh_arrays[RenderingServer.ARRAY_TANGENT] = tangents
	
	var mesh := RenderingServer.mesh_create()
	RenderingServer.mesh_add_surface_from_arrays(mesh, RenderingServer.PRIMITIVE_TRIANGLES, mesh_arrays)
	RenderingServer.mesh_set_custom_aabb(mesh, AABB(Vector3.ZERO, Vector3(size.x, 0.1, size.y)))
	if _material:
		RenderingServer.mesh_surface_set_material(mesh, 0, _material.get_rid())
	
	return mesh
	
func _generate_offsets():
	_tile_ps_lod_0.clear()
	_trim_a_ps.clear()
	_trim_b_ps.clear()
	_edge_x_ps.clear()
	_edge_z_ps.clear()
	_fill_a_ps.clear()
	_fill_b_ps.clear()
	_tile_ps.clear()
	
	# LOD 0 Tiles: Full 4x4 Grid of mesh _size tiles
	_tile_ps_lod_0.append(Vector3(0, 0, _size.y))
	_tile_ps_lod_0.append(Vector3(_size.x, 0, _size.y))
	_tile_ps_lod_0.append(Vector3(_size.x, 0, 0))
	_tile_ps_lod_0.append(Vector3(_size.x, 0, -_size.y))
	_tile_ps_lod_0.append(Vector3(_size.x, 0, -_size.y * 2))
	_tile_ps_lod_0.append(Vector3(0, 0, -_size.y * 2))
	_tile_ps_lod_0.append(Vector3(-_size.x, 0, -_size.y * 2))
	_tile_ps_lod_0.append(Vector3(-_size.x * 2, 0, -_size.y * 2))
	_tile_ps_lod_0.append(Vector3(-_size.x * 2, 0, -_size.y))
	_tile_ps_lod_0.append(Vector3(-_size.x * 2, 0, 0))
	_tile_ps_lod_0.append(Vector3(-_size.x * 2, 0, _size.y))
	_tile_ps_lod_0.append(Vector3(-_size.x, 0, _size.y))
	
	# Inner tiles
	_tile_ps_lod_0.append(Vector3.ZERO)
	_tile_ps_lod_0.append(Vector3(-_size.x, 0, 0))
	_tile_ps_lod_0.append(Vector3(0, 0, -_size.y))
	_tile_ps_lod_0.append(Vector3(-_size.x, 0, -_size.y))

	# LOD 0 Trims: Fixed 2 unit wide ring around LOD0 tiles.
	_trim_a_ps.append(Vector3(_size.x * 2, 0, -_size.y * 2))
	_trim_a_ps.append(Vector3(-_size.x * 2 - 2, 0, -_size.y * 2 - 2))
	_trim_b_ps.append(Vector3(-_size.x * 2, 0, -_size.y * 2 - 2))
	_trim_b_ps.append(Vector3(-_size.x * 2 - 2, 0, _size.y * 2))

	# LOD 1+: 4x4 Ring of mesh _size tiles, with one 2 unit wide gap on each axis for fill meshes.
	_tile_ps.append(Vector3(2, 0, _size.y + 2))
	_tile_ps.append(Vector3(_size.x + 2, 0, _size.y + 2))
	_tile_ps.append(Vector3(_size.x + 2, 0, -2))
	_tile_ps.append(Vector3(_size.x + 2, 0, -_size.y - 2))
	_tile_ps.append(Vector3(_size.x + 2, 0, -_size.y * 2 - 2))
	_tile_ps.append(Vector3(-2, 0, -_size.y * 2 - 2))
	_tile_ps.append(Vector3(-_size.x - 2, 0, -_size.y * 2 - 2))
	_tile_ps.append(Vector3(-_size.x * 2 - 2, 0, -_size.y * 2 - 2))
	_tile_ps.append(Vector3(-_size.x * 2 - 2, 0, -_size.y + 2))
	_tile_ps.append(Vector3(-_size.x * 2 - 2, 0, +2))
	_tile_ps.append(Vector3(-_size.x * 2 - 2, 0, _size.y + 2))
	_tile_ps.append(Vector3(-_size.x + 2, 0, _size.y + 2))

	# Edge offsets set edge pair psitions to either both before, straddle, or both after
	# Depending on current LOD psition within the next LOD
	_offset_a_x = _size.x * 2.0 + 2.0
	_offset_b_x = _size.x * 2.0 + 4.0
	_offset_c_x = _size.x * 2.0 + 6.0
	
	_offset_a_z = _size.y * 2.0 + 2.0
	_offset_b_z = _size.y * 2.0 + 4.0
	_offset_c_z = _size.y * 2.0 + 6.0
	
	_edge_x_ps.append(Vector3(_offset_a_x, _offset_a_x, -_offset_b_x))
	_edge_x_ps.append(Vector3(_offset_b_x, -_offset_b_x, -_offset_c_x))
	
	_edge_z_ps.append(Vector3(_offset_a_z, _offset_a_z, -_offset_b_z))
	_edge_z_ps.append(Vector3(_offset_b_z, -_offset_b_z, -_offset_c_z))

	# Fills: Occupies the gaps between tiles for LOD1+ to complete the ring.
	_fill_a_ps.append(Vector3(_size.x - 2, 0, -_size.y * 2 - 2))
	_fill_a_ps.append(Vector3(-_size.x - 2, 0, _size.y + 2))
	_fill_b_ps.append(Vector3(_size.x + 2, 0, _size.y - 2))
	_fill_b_ps.append(Vector3(-_size.x * 2 - 2, 0, -_size.y - 2))

func _clear_instances():
	for lod_array in _clipmap_rids:
		for mesh_array in lod_array:
			for rid in mesh_array:
				RenderingServer.free_rid(rid)
	_clipmap_rids.clear()

func _clear_mesh_types():
	for rid: RID in _mesh_rids:
		RenderingServer.free_rid(rid)
	_mesh_rids.clear()

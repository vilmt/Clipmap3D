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

var _instance_rids: Array[RID]
var _instance_mesh_types: Array[MeshType]
var _mesh_rids: Dictionary[MeshType, RID]

var _mesh_ps: Dictionary[MeshType, PackedVector3Array]

var _offset_a_x: float
var _offset_b_x: float
var _offset_c_x: float

var _offset_a_z: float
var _offset_b_z: float
var _offset_c_z: float

var _last_target_p_2d := Vector2.ZERO

enum MeshType {
	CORE,
	TILE,
	EDGE_X,
	EDGE_Z,
	FILL_X,
	FILL_Z
}

const LOD_0_INSTANCES: int = 21
const LOD_X_INSTANCES: int = 20

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
	for mesh_rid: RID in _mesh_rids.values():
		RenderingServer.mesh_surface_set_material(mesh_rid, 0, material_rid)
		
func update_scenario(scenario: RID):
	for instance_rid: RID in _instance_rids:
		RenderingServer.instance_set_scenario(instance_rid, scenario)

func update_visible(visible: bool):
	for instance_rid: RID in _instance_rids:
		RenderingServer.instance_set_visible(instance_rid, visible)

func update_render_layer(render_layer: int):
	for instance_rid: RID in _instance_rids:
		RenderingServer.instance_set_layer_mask(instance_rid, render_layer)

func update_cast_shadows(cast_shadows: RenderingServer.ShadowCastingSetting):
	for instance_rid: RID in _instance_rids:
		RenderingServer.instance_geometry_set_cast_shadows_setting(instance_rid, cast_shadows)

func update_amplitude(amplitude: float):
	_amplitude = amplitude
	for rid: RID in _mesh_rids.values():
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
	
	var starting_i: int = 0
	var ending_i: int = LOD_0_INSTANCES
	
	for lod: int in _lods:
		# TODO: clean up
		var snap: Vector2 = pow(2.0, float(lod) + 1.0) * vertex_spacing
		var lod_scale := Vector3(pow(2.0, lod) * vertex_spacing.x, 1.0, pow(2.0, lod) * vertex_spacing.y)
		
		var p_2d := (snapped_p_2d / snap).round() * snap
		
		# TODO: edge offset logic: clean up
		var next_snap := pow(2.0, float(lod) + 2.0) * vertex_spacing
		var next_p_2d := (snapped_p_2d / next_snap).round() * next_snap
		var test_p_2d := (Vector2i(((p_2d - next_p_2d) / snap).round()) + Vector2i.ONE).clampi(0, 2)
		
		var instance_count: Dictionary[MeshType, int] = {}
		
		for i: int in range(starting_i, ending_i):
			var instance_rid := _instance_rids[i]
			var mesh_type := _instance_mesh_types[i]
			
			var count: int = instance_count.get(mesh_type, 0)
			if count == 0:
				instance_count[mesh_type] = 1
			else:
				instance_count[mesh_type] += 1
			
			var base_p: Vector3 = _mesh_ps[mesh_type][count]

			var t := Transform3D.IDENTITY
			# if edge, interpret components of p as offsets (refactor)
			if mesh_type == MeshType.EDGE_X:
				t.origin.x = base_p[test_p_2d.x]
				t.origin.z -= _offset_a_z + (test_p_2d.y * 2.0)
			elif mesh_type == MeshType.EDGE_Z:
				t.origin.x -= _offset_a_x
				t.origin.z = base_p[test_p_2d.y]
			else:
				t.origin = base_p
				
			t = t.scaled(lod_scale)
			t.origin += Vector3(p_2d.x, 0.0, p_2d.y)
			RenderingServer.instance_set_transform(instance_rid, t)
			RenderingServer.instance_teleport(instance_rid)
		
		starting_i = ending_i
		ending_i += LOD_X_INSTANCES

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

func _create_instance(mesh_type: MeshType):
	var rid := RenderingServer.instance_create2(_mesh_rids[mesh_type], _scenario)
	_instance_rids.append(rid)
	_instance_mesh_types.append(mesh_type)
	RenderingServer.instance_set_visible(rid, _visible)
	RenderingServer.instance_set_layer_mask(rid, _render_layer)
	RenderingServer.instance_geometry_set_cast_shadows_setting(rid, _cast_shadows)

func _generate_instances() -> void:
	_clear_instances()
	for lod: int in _lods:
		if lod == 0:
			_create_instance(MeshType.CORE)
		for i: int in 12:
			_create_instance(MeshType.TILE)
		for i: int in 2:
			_create_instance(MeshType.FILL_X)
		for i: int in 2:
			_create_instance(MeshType.FILL_Z)
		for i: int in 2:
			_create_instance(MeshType.EDGE_X)
		for i: int in 2:
			_create_instance(MeshType.EDGE_Z)
			
func _generate_mesh_types():
	_clear_mesh_types()
	
	_mesh_rids[MeshType.CORE] = _generate_mesh(_size * 2 + Vector2i.ONE * 4)
	_mesh_rids[MeshType.TILE] = _generate_mesh(_size)
	_mesh_rids[MeshType.FILL_X] = _generate_mesh(Vector2i(4, _size.y))
	_mesh_rids[MeshType.FILL_Z] = _generate_mesh(Vector2i(_size.x, 4))
	_mesh_rids[MeshType.EDGE_X] = _generate_mesh(Vector2i(2, _size.y * 4 + 8))
	_mesh_rids[MeshType.EDGE_Z] = _generate_mesh(Vector2i(_size.x * 4 + 4, 2))
	
func _generate_mesh(size: Vector2i) -> RID:
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
			
			indices.append(b_l)
			indices.append(t_r)
			indices.append(t_l)
				
			indices.append(b_l)
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
	RenderingServer.mesh_set_custom_aabb(mesh, AABB(Vector3.ZERO, Vector3(size.x, _amplitude, size.y)))
	if _material:
		RenderingServer.mesh_surface_set_material(mesh, 0, _material.get_rid())
	
	return mesh
	
func _generate_offsets():
	# TODO: calculate all offsets from center of mesh
	_mesh_ps.clear()

	_mesh_ps[MeshType.CORE] = PackedVector3Array()
	_mesh_ps[MeshType.CORE].append(Vector3(-_size.x - 2, 0.0, -_size.y - 2))
	
	_mesh_ps[MeshType.TILE] = PackedVector3Array()
	_mesh_ps[MeshType.TILE].append(Vector3(2, 0, _size.y + 2))
	_mesh_ps[MeshType.TILE].append(Vector3(_size.x + 2, 0, _size.y + 2))
	_mesh_ps[MeshType.TILE].append(Vector3(_size.x + 2, 0, -2))
	_mesh_ps[MeshType.TILE].append(Vector3(_size.x + 2, 0, -_size.y - 2))
	_mesh_ps[MeshType.TILE].append(Vector3(_size.x + 2, 0, -_size.y * 2 - 2))
	_mesh_ps[MeshType.TILE].append(Vector3(-2, 0, -_size.y * 2 - 2))
	_mesh_ps[MeshType.TILE].append(Vector3(-_size.x - 2, 0, -_size.y * 2 - 2))
	_mesh_ps[MeshType.TILE].append(Vector3(-_size.x * 2 - 2, 0, -_size.y * 2 - 2))
	_mesh_ps[MeshType.TILE].append(Vector3(-_size.x * 2 - 2, 0, -_size.y + 2))
	_mesh_ps[MeshType.TILE].append(Vector3(-_size.x * 2 - 2, 0, +2))
	_mesh_ps[MeshType.TILE].append(Vector3(-_size.x * 2 - 2, 0, _size.y + 2))
	_mesh_ps[MeshType.TILE].append(Vector3(-_size.x + 2, 0, _size.y + 2))
	
	_mesh_ps[MeshType.FILL_X] = PackedVector3Array()
	_mesh_ps[MeshType.FILL_X].append(Vector3(_size.x - 2, 0, -_size.y * 2 - 2))
	_mesh_ps[MeshType.FILL_X].append(Vector3(-_size.x - 2, 0, _size.y + 2))
	
	_mesh_ps[MeshType.FILL_Z] = PackedVector3Array()
	_mesh_ps[MeshType.FILL_Z].append(Vector3(_size.x + 2, 0, _size.y - 2))
	_mesh_ps[MeshType.FILL_Z].append(Vector3(-_size.x * 2 - 2, 0, -_size.y - 2))
	
	_offset_a_x = _size.x * 2.0 + 2.0
	_offset_b_x = _size.x * 2.0 + 4.0
	_offset_c_x = _size.x * 2.0 + 6.0
	
	_offset_a_z = _size.y * 2.0 + 2.0
	_offset_b_z = _size.y * 2.0 + 4.0
	_offset_c_z = _size.y * 2.0 + 6.0
	
	_mesh_ps[MeshType.EDGE_X] = PackedVector3Array()
	_mesh_ps[MeshType.EDGE_X].append(Vector3(_offset_a_x, _offset_a_x, -_offset_b_x))
	_mesh_ps[MeshType.EDGE_X].append(Vector3(_offset_b_x, -_offset_b_x, -_offset_c_x))
	
	_mesh_ps[MeshType.EDGE_Z] = PackedVector3Array()
	_mesh_ps[MeshType.EDGE_Z].append(Vector3(_offset_a_z, _offset_a_z, -_offset_b_z))
	_mesh_ps[MeshType.EDGE_Z].append(Vector3(_offset_b_z, -_offset_b_z, -_offset_c_z))

func _clear_instances():
	for instance_rid: RID in _instance_rids:
		RenderingServer.free_rid(instance_rid)
	_instance_rids.clear()
	_instance_mesh_types.clear()

func _clear_mesh_types():
	for rid: RID in _mesh_rids.values():
		RenderingServer.free_rid(rid)
	_mesh_rids.clear()

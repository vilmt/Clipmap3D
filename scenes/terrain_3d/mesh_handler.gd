class_name Terrain3DMeshHandler

# TODO: use same var names here and in terrain

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
var _mesh_aabbs: Dictionary[MeshType, AABB]
var _mesh_xzs: Dictionary[MeshType, PackedVector2Array]
var _edge_x_xzs: Dictionary[Vector2i, Vector2]
var _edge_z_xzs: Dictionary[Vector2i, Vector2]

var _last_p_xz := Vector2.ZERO

enum MeshType {
	CORE,
	TILE,
	FILL_X,
	FILL_Z,
	EDGE_X,
	EDGE_Z
}

const LOD_0_INSTANCES: int = 19
const LOD_X_INSTANCES: int = 18

const EPSILON := Vector2(0.00001, 0.00001) 

func update_height_map(height_map: HeightMap):
	if _height_map:
		_height_map.changed.disconnect(_on_height_map_changed)
	_height_map = height_map
	if _height_map:
		_height_map.changed.connect(_on_height_map_changed)

func _on_height_map_changed():
	update_amplitude(_height_map.amplitude)
	if _material and _height_map:
		_material.set_shader_parameter(&"map_origin", _height_map.origin)
		_material.set_shader_parameter(&"height_map", _height_map.get_texture())
		_material.set_shader_parameter(&"amplitude", _height_map.amplitude)

func update_size(size: Vector2i):
	_size = size
	
	_generate_mesh_types()
	_generate_offsets()
	_generate_instances()
	snap(_last_p_xz, true)
	
	if _material:
		_material.set_shader_parameter(&"mesh_size", size)

func update_lods(lods: int):
	_lods = lods
	
	_generate_instances()
	snap(_last_p_xz, true)

func update_vertex_spacing(vertex_spacing: Vector2):
	_vertex_spacing = vertex_spacing
	snap(_last_p_xz, true)
	
	if _material:
		_material.set_shader_parameter(&"vertex_spacing", vertex_spacing)

func update_amplitude(amplitude: float):
	_amplitude = amplitude
	for type: MeshType in MeshType.values():
		var aabb := _mesh_aabbs[type]
		aabb.size.y = _amplitude
		RenderingServer.mesh_set_custom_aabb(_mesh_rids[type], aabb)

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

func snap(p_xz: Vector2, force: bool = false) -> bool:
	var snapped_this = (p_xz / _vertex_spacing).floor() * _vertex_spacing
	var snapped_last = (_last_p_xz / _vertex_spacing).floor() * _vertex_spacing
	if snapped_this.is_equal_approx(snapped_last) and not force:
		return false
	
	_last_p_xz = p_xz
	
	if _material:
		_material.set_shader_parameter(&"mesh_origin", p_xz)
	
	var starting_i: int = 0
	var ending_i: int = LOD_0_INSTANCES
	
	for lod: int in _lods:
		var scale: Vector2 = _vertex_spacing * float(1 << lod)
		var next_scale: Vector2 = scale * 2.0
		
		var snapped_p_xz = (p_xz / scale).floor() * scale
		var edge := Vector2i((p_xz / scale).floor() - 2.0 * (p_xz / next_scale).floor())
		
		var instance_count: Dictionary[MeshType, int] = {}
		
		for i: int in range(starting_i, ending_i):
			var instance_rid := _instance_rids[i]
			var type := _instance_mesh_types[i]
			var count: int = instance_count.get(type, 0)
			
			var xz: Vector2
			match type:
				MeshType.EDGE_X:
					xz = _edge_x_xzs[edge]
				MeshType.EDGE_Z:
					xz = _edge_z_xzs[edge]
				_:
					xz = _mesh_xzs[type][count]
			
			var t := Transform3D(Basis(), Vector3(xz.x, 0.0, xz.y))
			t = t.scaled(Vector3(scale.x, 1.0, scale.y))
			t.origin += Vector3(snapped_p_xz.x, 0.0, snapped_p_xz.y)
			RenderingServer.instance_set_transform(instance_rid, t)
			RenderingServer.instance_teleport(instance_rid)
			
			if count == 0:
				instance_count[type] = 1
			else:
				instance_count[type] += 1
		
		starting_i = ending_i
		ending_i += LOD_X_INSTANCES
	return true

func generate(terrain: Terrain3D) -> void:
	_size = terrain.mesh_size
	_lods = terrain.mesh_lods
	_vertex_spacing = terrain.mesh_vertex_spacing
	_scenario = terrain.get_world_3d().scenario
	_visible = terrain.is_visible_in_tree()
	_material = terrain.shader_material
	_cast_shadows = terrain.cast_shadows as RenderingServer.ShadowCastingSetting
	_render_layer = terrain.render_layer
	if terrain.height_map:
		_height_map = terrain.height_map
		_amplitude = _height_map.amplitude
		_height_map.changed.connect(_on_height_map_changed)
	if _material:
		_material.set_shader_parameter(&"vertex_spacing", _vertex_spacing)
		_material.set_shader_parameter(&"mesh_size", _size)
		if _height_map:
			_material.set_shader_parameter(&"map_origin", _height_map.origin)
			_material.set_shader_parameter(&"height_map", _height_map.get_texture())
			_material.set_shader_parameter(&"amplitude", _height_map.amplitude)
	
	_generate_mesh_types()
	_generate_offsets()
	_generate_instances()
	
	_last_p_xz = terrain.get_target_p_2d()
	snap(_last_p_xz, true)

func clear():
	_clear_instances()
	_clear_mesh_types()

func _create_instance(type: MeshType):
	var rid := RenderingServer.instance_create2(_mesh_rids[type], _scenario)
	_instance_rids.append(rid)
	_instance_mesh_types.append(type)
	RenderingServer.instance_set_visible(rid, _visible)
	RenderingServer.instance_set_layer_mask(rid, _render_layer)
	RenderingServer.instance_geometry_set_cast_shadows_setting(rid, _cast_shadows)

func _generate_instances() -> void:
	_clear_instances()
	_create_instance(MeshType.CORE)
	for lod: int in _lods:
		for i: int in 12:
			_create_instance(MeshType.TILE)
		for i: int in 2:
			_create_instance(MeshType.FILL_X)
			_create_instance(MeshType.FILL_Z)
		_create_instance(MeshType.EDGE_X)
		_create_instance(MeshType.EDGE_Z)

func _generate_mesh_types():
	_clear_mesh_types()
	
	_generate_mesh(MeshType.CORE, _size * 2 + Vector2i.ONE)
	_generate_mesh(MeshType.TILE, _size)
	_generate_mesh(MeshType.FILL_X, Vector2i(1, _size.y))
	_generate_mesh(MeshType.FILL_Z, Vector2i(_size.x, 1))
	_generate_mesh(MeshType.EDGE_X, Vector2i(1, _size.y * 4 + 2))
	_generate_mesh(MeshType.EDGE_Z, Vector2i(_size.x * 4 + 1, 1))
	
func _generate_mesh(type: MeshType, size: Vector2i) -> void:
	var mesh_arrays: Array = []
	mesh_arrays.resize(RenderingServer.ARRAY_MAX)
	
	var vertices := PackedVector3Array()
	for z: int in size.y + 1:
		for x: int in size.x + 1:
			vertices.append(Vector3(float(x) - size.x / 2.0, 0.0, float(z) - size.y / 2.0))
	mesh_arrays[RenderingServer.ARRAY_VERTEX] = vertices
	
	var indices := PackedInt32Array()
	for z: int in size.y:
		for x: int in size.x:
			var b_l: int = z * (size.x + 1) + x
			var b_r: int = b_l + 1
			var t_l: int = (z + 1) * (size.x + 1) + x
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
	_mesh_rids[type] = mesh
	
	var aabb := AABB(Vector3(-size.x, 0.0, -size.y) / 2.0, Vector3(size.x, _amplitude, size.y))
	RenderingServer.mesh_set_custom_aabb(mesh, aabb)
	_mesh_aabbs[type] = aabb
	
	if _material:
		RenderingServer.mesh_surface_set_material(mesh, 0, _material.get_rid())

func _generate_offsets():
	_mesh_xzs.clear()
	_edge_x_xzs.clear()
	_edge_z_xzs.clear()

	_mesh_xzs[MeshType.CORE] = PackedVector2Array([Vector2(0.5, 0.5)])
	
	_mesh_xzs[MeshType.TILE] = PackedVector2Array([
		Vector2(_size.x * +1.5 + 1.0, _size.y * +1.5 + 1.0),
		Vector2(_size.x * +0.5 + 1.0, _size.y * +1.5 + 1.0),
		Vector2(_size.x * -0.5, _size.y * +1.5 + 1.0),
		Vector2(_size.x * -1.5, _size.y * +1.5 + 1.0),
		Vector2(_size.x * -1.5, _size.y * +0.5 + 1.0),
		Vector2(_size.x * -1.5, _size.y * -0.5),
		Vector2(_size.x * -1.5, _size.y * -1.5),
		Vector2(_size.x * -0.5, _size.y * -1.5),
		Vector2(_size.x * +0.5 + 1.0, _size.y * -1.5),
		Vector2(_size.x * +1.5 + 1.0, _size.y * -1.5),
		Vector2(_size.x * +1.5 + 1.0, _size.y * -0.5),
		Vector2(_size.x * +1.5 + 1.0, _size.y * +0.5 + 1.0),
	])
	
	_mesh_xzs[MeshType.FILL_X] = PackedVector2Array([
		Vector2(0.5, _size.y * 1.5 + 1.0),
		Vector2(0.5, _size.y * -1.5)
	])
	
	_mesh_xzs[MeshType.FILL_Z] = PackedVector2Array([
		Vector2(_size.x * 1.5 + 1.0, 0.5),
		Vector2(_size.x * -1.5, 0.5)
	])
	
	_edge_x_xzs = {
		Vector2i(0, 0): Vector2(_size.x * 2.0 + 1.5, 1.0),
		Vector2i(1, 0): Vector2(_size.x * -2.0 - 0.5, 1.0),
		Vector2i(0, 1): Vector2(_size.x * 2.0 + 1.5, 0.0),
		Vector2i(1, 1): Vector2(_size.x * -2.0 - 0.5, 0.0)
	}
	
	_edge_z_xzs = {
		Vector2i(0, 0): Vector2(0.5, _size.y * 2.0 + 1.5),
		Vector2i(1, 0): Vector2(0.5, _size.y * 2.0 + 1.5),
		Vector2i(0, 1): Vector2(0.5, _size.y * -2.0 - 0.5),
		Vector2i(1, 1): Vector2(0.5, _size.y * -2.0 - 0.5)
	}

func _clear_instances():
	for instance_rid: RID in _instance_rids:
		RenderingServer.free_rid(instance_rid)
	_instance_rids.clear()
	_instance_mesh_types.clear()

func _clear_mesh_types():
	for rid: RID in _mesh_rids.values():
		RenderingServer.free_rid(rid)
	_mesh_rids.clear()
	_mesh_aabbs.clear()

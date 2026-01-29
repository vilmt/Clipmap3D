@tool
class_name Clipmap3DMeshHandler

var _lod_count: int
var _tile_size: Vector2i
var _vertex_spacing: Vector2
var _texels_per_vertex: Vector2i
var _map_origins: Array[Vector2i]
var _material_rid: RID
var _scenario_rid: RID
var _visible: bool
var _cast_shadows: RenderingServer.ShadowCastingSetting
var _render_layer: int
var _height_amplitude: float = 0.1
var _height_maps_rid: RID
var _normal_maps_rid: RID
var _control_maps_rid: RID
var _albedo_textures_rid: RID
var _normal_textures_rid: RID

var _instance_rids: Array[RID]
var _instance_mesh_types: Array[MeshType]

var _mesh_rids: Dictionary[MeshType, RID]
var _mesh_aabbs: Dictionary[MeshType, AABB]
var _mesh_xzs: Dictionary[MeshType, PackedVector2Array]
var _edge_x_xzs: Dictionary[Vector2i, Vector2]
var _edge_z_xzs: Dictionary[Vector2i, Vector2]

var _last_p := Vector3.ZERO

var _meshes_dirty: bool = false
var _instances_dirty: bool = false

enum MeshType {
	CORE,
	TILE,
	FILL_X,
	FILL_Z,
	EDGE_X,
	EDGE_Z
}

const MAX_LOD_COUNT: int = 10
const LOD_0_INSTANCES: int = 19
const LOD_X_INSTANCES: int = 18

func get_mesh_vertices() -> Vector2i:
	return 4 * _tile_size + Vector2i.ONE * 3

func _rebuild():
	if _meshes_dirty:
		_generate_meshes()
		_generate_offsets()
		_instances_dirty = true
	if _instances_dirty:
		_create_instances()
		snap(_last_p, true)
	_meshes_dirty = false
	_instances_dirty = false

func _mark_instances_dirty():
	_instances_dirty = true
	_rebuild.call_deferred()

func _mark_meshes_dirty():
	_instances_dirty = true
	_meshes_dirty = true
	_rebuild.call_deferred()

func update_map_origins(map_origins: Array[Vector2i]):
	_map_origins = map_origins
	if _material_rid:
		RenderingServer.material_set_param(_material_rid, &"_map_origins", _map_origins)

func update_height_amplitude(height_amplitude: float):
	_height_amplitude = maxf(height_amplitude, 0.1)
	for type: MeshType in _mesh_rids.keys():
		var aabb := _mesh_aabbs[type]
		aabb.size.y = _height_amplitude
		RenderingServer.mesh_set_custom_aabb(_mesh_rids[type], aabb)

func update_texels_per_vertex(texels_per_vertex: Vector2i):
	_texels_per_vertex = texels_per_vertex
	if _material_rid:
		RenderingServer.material_set_param(_material_rid, &"_texels_per_vertex", _texels_per_vertex)

func update_map_rids(map_rids: Dictionary[Clipmap3DSource.MapType, RID]):
	_height_maps_rid = map_rids.get(Clipmap3DSource.MapType.HEIGHT, RID())
	_normal_maps_rid = map_rids.get(Clipmap3DSource.MapType.NORMAL, RID())
	_control_maps_rid = map_rids.get(Clipmap3DSource.MapType.CONTROL, RID())
	if _material_rid:
		RenderingServer.material_set_param(_material_rid, &"_height_maps", _height_maps_rid)
		RenderingServer.material_set_param(_material_rid, &"_normal_maps", _normal_maps_rid)
		RenderingServer.material_set_param(_material_rid, &"_control_maps", _control_maps_rid)

func update_texture_rids(texture_rids: Dictionary[Clipmap3DSource.TextureType, RID]):
	_albedo_textures_rid = texture_rids.get(Clipmap3DSource.TextureType.ALBEDO, RID())
	_normal_textures_rid = texture_rids.get(Clipmap3DSource.TextureType.NORMAL, RID())
	if _material_rid:
		RenderingServer.material_set_param(_material_rid, &"_albedo_textures", _albedo_textures_rid)
		RenderingServer.material_set_param(_material_rid, &"_normal_textures", _normal_textures_rid)

func _on_tile_size_changed(tile_size: Vector2i):
	_tile_size = tile_size
	_mark_meshes_dirty()
	
	if _material_rid:
		RenderingServer.material_set_param(_material_rid, &"_tile_size", tile_size)
		
func _on_lod_count_changed(lod_count: int):
	_lod_count = lod_count
	
	_mark_instances_dirty()

func _on_vertex_spacing_changed(vertex_spacing: Vector2):
	_vertex_spacing = vertex_spacing
	if _material_rid:
		RenderingServer.material_set_param(_material_rid, &"_vertex_spacing", vertex_spacing)
	snap(_last_p, true)

func update_material_rid(material_rid: RID):
	_material_rid = material_rid
	if _material_rid:
		RenderingServer.material_set_param(_material_rid, &"_height_maps", _height_maps_rid)
		RenderingServer.material_set_param(_material_rid, &"_normal_maps", _normal_maps_rid)
		RenderingServer.material_set_param(_material_rid, &"_control_maps", _control_maps_rid)
		RenderingServer.material_set_param(_material_rid, &"_albedo_textures", _albedo_textures_rid)
		RenderingServer.material_set_param(_material_rid, &"_normal_textures", _normal_textures_rid)
		RenderingServer.material_set_param(_material_rid, &"_tile_size", _tile_size)
		RenderingServer.material_set_param(_material_rid, &"_vertex_spacing", _vertex_spacing)
		RenderingServer.material_set_param(_material_rid, &"_target_position", _last_p)
		RenderingServer.material_set_param(_material_rid, &"_texels_per_vertex", _texels_per_vertex)
		RenderingServer.material_set_param(_material_rid, &"_map_origins", _map_origins)
	for mesh_rid: RID in _mesh_rids.values():
		RenderingServer.mesh_surface_set_material(mesh_rid, 0, _material_rid)
		
func update_scenario_rid(scenario_rid: RID):
	_scenario_rid = scenario_rid
	for instance_rid: RID in _instance_rids:
		RenderingServer.instance_set_scenario(instance_rid, _scenario_rid)

func update_visible(visible: bool):
	_visible = visible
	for instance_rid: RID in _instance_rids:
		RenderingServer.instance_set_visible(instance_rid, _visible)

func _on_render_layer_changed(render_layer: int):
	_render_layer = render_layer
	for instance_rid: RID in _instance_rids:
		RenderingServer.instance_set_layer_mask(instance_rid, _render_layer)

func _on_cast_shadows_changed(cast_shadows: RenderingServer.ShadowCastingSetting):
	_cast_shadows = cast_shadows
	for instance_rid: RID in _instance_rids:
		RenderingServer.instance_geometry_set_cast_shadows_setting(instance_rid, _cast_shadows)

func snap(p: Vector3, force: bool = false) -> bool:
	if p == _last_p and not force:
		return false
	_last_p = p
	
	if _material_rid:
		RenderingServer.material_set_param(_material_rid, &"_target_position", p)
	
	var starting_i: int = 0
	var ending_i: int = LOD_0_INSTANCES
	
	for lod: int in _lod_count:
		var scale: Vector2 = _vertex_spacing * float(1 << lod)
		var snapped_p_xz = (Vector2(p.x, p.z) / scale).floor()
		var edge := Vector2i(snapped_p_xz.posmod(2.0))
		snapped_p_xz *= scale
		
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
			t.origin += Vector3(snapped_p_xz.x, p.y, snapped_p_xz.y)
			RenderingServer.instance_set_transform(instance_rid, t)
			RenderingServer.instance_teleport(instance_rid)
			
			if count == 0:
				instance_count[type] = 1
			else:
				instance_count[type] += 1
		
		starting_i = ending_i
		ending_i += LOD_X_INSTANCES
	
	return true

func initialize(clipmap: Clipmap3D) -> void:
	_tile_size = clipmap.mesh_tile_size
	_lod_count = clipmap.mesh_lod_count
	_vertex_spacing = clipmap.mesh_vertex_spacing
	_cast_shadows = clipmap.cast_shadows as RenderingServer.ShadowCastingSetting
	_render_layer = clipmap.render_layer
	_last_p = clipmap.global_position
	
	clipmap.mesh_tile_size_changed.connect(_on_tile_size_changed)
	clipmap.mesh_lod_count_changed.connect(_on_lod_count_changed)
	clipmap.mesh_vertex_spacing_changed.connect(_on_vertex_spacing_changed)
	clipmap.cast_shadows_changed.connect(_on_cast_shadows_changed)
	clipmap.render_layer_changed.connect(_on_render_layer_changed)
	clipmap.target_position_changed.connect(snap)

func generate():
	_mark_meshes_dirty()

func clear():
	_clear_instances()
	_clear_meshes()

func _create_instance(type: MeshType):
	var rid := RenderingServer.instance_create2(_mesh_rids[type], _scenario_rid)
	_instance_rids.append(rid)
	_instance_mesh_types.append(type)
	RenderingServer.instance_set_visible(rid, _visible)
	RenderingServer.instance_set_layer_mask(rid, _render_layer)
	RenderingServer.instance_geometry_set_cast_shadows_setting(rid, _cast_shadows)

func _create_instances() -> void:
	_clear_instances()
	_create_instance(MeshType.CORE)
	for lod: int in _lod_count:
		for i: int in 12:
			_create_instance(MeshType.TILE)
		for i: int in 2:
			_create_instance(MeshType.FILL_X)
			_create_instance(MeshType.FILL_Z)
		_create_instance(MeshType.EDGE_X)
		_create_instance(MeshType.EDGE_Z)

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
	
	var aabb := AABB(Vector3(-size.x, 0.0, -size.y) / 2.0, Vector3(size.x, _height_amplitude, size.y))
	RenderingServer.mesh_set_custom_aabb(mesh, aabb)
	_mesh_aabbs[type] = aabb
	
	if _material_rid:
		RenderingServer.mesh_surface_set_material(mesh, 0, _material_rid)

func _generate_meshes():
	_clear_instances()
	_clear_meshes()
	
	_generate_mesh(MeshType.CORE, _tile_size * 2 + Vector2i.ONE)
	_generate_mesh(MeshType.TILE, _tile_size)
	_generate_mesh(MeshType.FILL_X, Vector2i(1, _tile_size.y))
	_generate_mesh(MeshType.FILL_Z, Vector2i(_tile_size.x, 1))
	_generate_mesh(MeshType.EDGE_X, Vector2i(1, _tile_size.y * 4 + 2))
	_generate_mesh(MeshType.EDGE_Z, Vector2i(_tile_size.x * 4 + 1, 1))

func _generate_offsets():
	_mesh_xzs.clear()
	_edge_x_xzs.clear()
	_edge_z_xzs.clear()

	_mesh_xzs[MeshType.CORE] = PackedVector2Array([Vector2(0.5, 0.5)])
	
	_mesh_xzs[MeshType.TILE] = PackedVector2Array([
		Vector2(_tile_size.x * +1.5 + 1.0, _tile_size.y * +1.5 + 1.0),
		Vector2(_tile_size.x * +0.5 + 1.0, _tile_size.y * +1.5 + 1.0),
		Vector2(_tile_size.x * -0.5, _tile_size.y * +1.5 + 1.0),
		Vector2(_tile_size.x * -1.5, _tile_size.y * +1.5 + 1.0),
		Vector2(_tile_size.x * -1.5, _tile_size.y * +0.5 + 1.0),
		Vector2(_tile_size.x * -1.5, _tile_size.y * -0.5),
		Vector2(_tile_size.x * -1.5, _tile_size.y * -1.5),
		Vector2(_tile_size.x * -0.5, _tile_size.y * -1.5),
		Vector2(_tile_size.x * +0.5 + 1.0, _tile_size.y * -1.5),
		Vector2(_tile_size.x * +1.5 + 1.0, _tile_size.y * -1.5),
		Vector2(_tile_size.x * +1.5 + 1.0, _tile_size.y * -0.5),
		Vector2(_tile_size.x * +1.5 + 1.0, _tile_size.y * +0.5 + 1.0),
	])
	
	_mesh_xzs[MeshType.FILL_X] = PackedVector2Array([
		Vector2(0.5, _tile_size.y * 1.5 + 1.0),
		Vector2(0.5, _tile_size.y * -1.5)
	])
	
	_mesh_xzs[MeshType.FILL_Z] = PackedVector2Array([
		Vector2(_tile_size.x * 1.5 + 1.0, 0.5),
		Vector2(_tile_size.x * -1.5, 0.5)
	])
	
	_edge_x_xzs = {
		Vector2i(0, 0): Vector2(_tile_size.x * 2.0 + 1.5, 1.0),
		Vector2i(1, 0): Vector2(_tile_size.x * -2.0 - 0.5, 1.0),
		Vector2i(0, 1): Vector2(_tile_size.x * 2.0 + 1.5, 0.0),
		Vector2i(1, 1): Vector2(_tile_size.x * -2.0 - 0.5, 0.0)
	}
	
	_edge_z_xzs = {
		Vector2i(0, 0): Vector2(0.5, _tile_size.y * 2.0 + 1.5),
		Vector2i(1, 0): Vector2(0.5, _tile_size.y * 2.0 + 1.5),
		Vector2i(0, 1): Vector2(0.5, _tile_size.y * -2.0 - 0.5),
		Vector2i(1, 1): Vector2(0.5, _tile_size.y * -2.0 - 0.5)
	}

func _clear_instances():
	for instance_rid: RID in _instance_rids:
		RenderingServer.free_rid(instance_rid)
	_instance_rids.clear()
	_instance_mesh_types.clear()

func _clear_meshes():
	for mesh_rid: RID in _mesh_rids.values():
		RenderingServer.free_rid(mesh_rid)
	_mesh_rids.clear()
	_mesh_aabbs.clear()

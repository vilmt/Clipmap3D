@tool
class_name Clipmap3DMeshHandler

var source: Clipmap3DSource:
	set(value):
		_disconnect_source()
		source = value
		_connect_source()

var lod_count: int:
	set(value):
		lod_count = value
		_mark_meshes_dirty()
		_apply_material_state()

var tile_size: Vector2i:
	set(value):
		tile_size = value
		_mark_meshes_dirty()
		_apply_material_state()

var vertex_spacing: Vector2:
	set(value):
		vertex_spacing = value
		_mark_meshes_dirty()
		_apply_material_state()

var material_rid: RID:
	set(value):
		material_rid = value
		_apply_mesh_state()
		_apply_material_state()

var scenario_rid: RID:
	set(value):
		scenario_rid = value
		_apply_mesh_state()

var visible: bool:
	set(value):
		visible = value
		_apply_mesh_state()
			
var cast_shadows: RenderingServer.ShadowCastingSetting:
	set(value):
		cast_shadows = value
		_apply_mesh_state()

var render_layer: int:
	set(value):
		render_layer = value
		_apply_mesh_state()

var target_position: Vector3:
	set(value):
		target_position = value
		_apply_material_state()
		_apply_instance_state()

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

var _instance_rids: Array[RID]
var _instance_mesh_types: Array[MeshType]

var _mesh_rids: Dictionary[MeshType, RID]
var _mesh_aabbs: Dictionary[MeshType, AABB]
var _mesh_xzs: Dictionary[MeshType, PackedVector2Array] # XZ offsets are fixed per mesh
var _edge_x_xzs: Dictionary[Vector2i, Vector2] # XZ offsets vary for edges
var _edge_z_xzs: Dictionary[Vector2i, Vector2]

var _built: bool = false
var _meshes_dirty: bool = false
var _instances_dirty: bool = false

func get_vertices() -> Vector2i:
	return 4 * tile_size + 3 * Vector2i.ONE

func _rebuild():
	if _meshes_dirty:
		_generate_meshes()
		_generate_offsets()
		_apply_mesh_state()
		_instances_dirty = true
	if _instances_dirty:
		_create_instances()
		_apply_instance_state()
	
	_meshes_dirty = false
	_instances_dirty = false

func _mark_instances_dirty():
	if not _built:
		return
	_instances_dirty = true
	_rebuild.call_deferred()

func _mark_meshes_dirty():
	if not _built:
		return
	_instances_dirty = true
	_meshes_dirty = true
	_rebuild.call_deferred()

func _snap() -> void:
	if not _built or _instance_rids.is_empty():
		return
	var world_xz := Vector2(target_position.x, target_position.z)
	
	var starting_i: int = 0
	var ending_i: int = LOD_0_INSTANCES
	
	for lod: int in lod_count:
		var scale: Vector2 = vertex_spacing * float(1 << lod)
		var vertex_xz := Vector2i((world_xz / scale).floor())
		var edge := vertex_xz.abs() % 2
		var world_xz_snapped := Vector2(vertex_xz) * scale
		
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
			t.origin += Vector3(world_xz_snapped.x, target_position.y, world_xz_snapped.y)
			RenderingServer.instance_set_transform(instance_rid, t)
			RenderingServer.instance_teleport(instance_rid)
			
			if count == 0:
				instance_count[type] = 1
			else:
				instance_count[type] += 1
		
		starting_i = ending_i
		ending_i += LOD_X_INSTANCES
	
func build():
	_built = true
	_mark_meshes_dirty()
	_apply_material_state()

func clear():
	_built = false
	_meshes_dirty = false
	_instances_dirty = false
	_clear_instances()
	_clear_meshes()

func _create_instance(type: MeshType):
	var rid := RenderingServer.instance_create2(_mesh_rids[type], scenario_rid)
	_instance_rids.append(rid)
	_instance_mesh_types.append(type)

func _create_instances() -> void:
	_clear_instances()
	_create_instance(MeshType.CORE)
	for lod: int in lod_count:
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
	
	var aabb := AABB(Vector3(-size.x, 0.0, -size.y) / 2.0, Vector3(size.x, 0.1, size.y))
	RenderingServer.mesh_set_custom_aabb(mesh, aabb)
	_mesh_aabbs[type] = aabb

func _generate_meshes():
	_clear_instances()
	_clear_meshes()
	
	_generate_mesh(MeshType.CORE, tile_size * 2 + Vector2i.ONE)
	_generate_mesh(MeshType.TILE, tile_size)
	_generate_mesh(MeshType.FILL_X, Vector2i(1, tile_size.y))
	_generate_mesh(MeshType.FILL_Z, Vector2i(tile_size.x, 1))
	_generate_mesh(MeshType.EDGE_X, Vector2i(1, tile_size.y * 4 + 2))
	_generate_mesh(MeshType.EDGE_Z, Vector2i(tile_size.x * 4 + 1, 1))

func _generate_offsets():
	_mesh_xzs.clear()
	_edge_x_xzs.clear()
	_edge_z_xzs.clear()

	_mesh_xzs[MeshType.CORE] = PackedVector2Array([Vector2(0.5, 0.5)])
	
	_mesh_xzs[MeshType.TILE] = PackedVector2Array([
		Vector2(tile_size.x * +1.5 + 1.0, tile_size.y * +1.5 + 1.0),
		Vector2(tile_size.x * +0.5 + 1.0, tile_size.y * +1.5 + 1.0),
		Vector2(tile_size.x * -0.5, tile_size.y * +1.5 + 1.0),
		Vector2(tile_size.x * -1.5, tile_size.y * +1.5 + 1.0),
		Vector2(tile_size.x * -1.5, tile_size.y * +0.5 + 1.0),
		Vector2(tile_size.x * -1.5, tile_size.y * -0.5),
		Vector2(tile_size.x * -1.5, tile_size.y * -1.5),
		Vector2(tile_size.x * -0.5, tile_size.y * -1.5),
		Vector2(tile_size.x * +0.5 + 1.0, tile_size.y * -1.5),
		Vector2(tile_size.x * +1.5 + 1.0, tile_size.y * -1.5),
		Vector2(tile_size.x * +1.5 + 1.0, tile_size.y * -0.5),
		Vector2(tile_size.x * +1.5 + 1.0, tile_size.y * +0.5 + 1.0),
	])
	
	_mesh_xzs[MeshType.FILL_X] = PackedVector2Array([
		Vector2(0.5, tile_size.y * 1.5 + 1.0),
		Vector2(0.5, tile_size.y * -1.5)
	])
	
	_mesh_xzs[MeshType.FILL_Z] = PackedVector2Array([
		Vector2(tile_size.x * 1.5 + 1.0, 0.5),
		Vector2(tile_size.x * -1.5, 0.5)
	])
	
	_edge_x_xzs = {
		Vector2i(0, 0): Vector2(tile_size.x * 2.0 + 1.5, 1.0),
		Vector2i(1, 0): Vector2(tile_size.x * -2.0 - 0.5, 1.0),
		Vector2i(0, 1): Vector2(tile_size.x * 2.0 + 1.5, 0.0),
		Vector2i(1, 1): Vector2(tile_size.x * -2.0 - 0.5, 0.0)
	}
	
	_edge_z_xzs = {
		Vector2i(0, 0): Vector2(0.5, tile_size.y * 2.0 + 1.5),
		Vector2i(1, 0): Vector2(0.5, tile_size.y * 2.0 + 1.5),
		Vector2i(0, 1): Vector2(0.5, tile_size.y * -2.0 - 0.5),
		Vector2i(1, 1): Vector2(0.5, tile_size.y * -2.0 - 0.5)
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

func _connect_source():
	if not source or source.changed.is_connected(_apply_material_state):
		return
	source.changed.connect(_apply_material_state)
	source.changed.connect(_apply_mesh_state)
	_apply_material_state()
	_apply_mesh_state()
	
func _disconnect_source():
	if not source or not source.changed.is_connected(_apply_material_state):
		return
	source.changed.disconnect(_apply_material_state)
	source.changed.disconnect(_apply_mesh_state)

func _apply_material_state():
	if not _built or not material_rid:
		return
	
	RenderingServer.material_set_param(material_rid, &"_vertex_spacing", vertex_spacing)
	RenderingServer.material_set_param(material_rid, &"_lod_count", lod_count)
	RenderingServer.material_set_param(material_rid, &"_tile_size", tile_size)
	RenderingServer.material_set_param(material_rid, &"_target_position", target_position)
	
	if source:
		RenderingServer.material_set_param(material_rid, &"_texels_per_vertex", source.texels_per_vertex)
		
		var map_rids := source.get_map_rids()
		RenderingServer.material_set_param(material_rid, &"_height_maps", map_rids.get(Clipmap3DSource.MapType.HEIGHT, RID()))
		RenderingServer.material_set_param(material_rid, &"_normal_maps", map_rids.get(Clipmap3DSource.MapType.NORMAL, RID()))
		RenderingServer.material_set_param(material_rid, &"_control_maps", map_rids.get(Clipmap3DSource.MapType.CONTROL, RID()))
		
		var texture_rids := source.get_texture_rids()
		RenderingServer.material_set_param(material_rid, &"_albedo_textures", texture_rids.get(Clipmap3DSource.TextureType.ALBEDO, RID()))
		RenderingServer.material_set_param(material_rid, &"_normal_textures", texture_rids.get(Clipmap3DSource.TextureType.NORMAL, RID()))
		
		var texture_remaps := source.get_texture_remaps()
		RenderingServer.material_set_param(material_rid, &"_albedo_remap", texture_remaps.get(Clipmap3DSource.TextureType.ALBEDO, PackedInt32Array()))
		RenderingServer.material_set_param(material_rid, &"_normal_remap", texture_remaps.get(Clipmap3DSource.TextureType.NORMAL, PackedInt32Array()))
		
		RenderingServer.material_set_param(material_rid, &"_uv_scales", source.get_uv_scales())
		RenderingServer.material_set_param(material_rid, &"_albedo_modulates", source.get_albedo_modulates())
		RenderingServer.material_set_param(material_rid, &"_roughness_offsets", source.get_roughness_offsets())
		RenderingServer.material_set_param(material_rid, &"_normal_depths", source.get_normal_depths())
		RenderingServer.material_set_param(material_rid, &"_flags", source.get_flags())
	else:
		RenderingServer.material_set_param(material_rid, &"_texels_per_vertex", Vector2i.ONE)
		
		RenderingServer.material_set_param(material_rid, &"_height_maps", RID())
		RenderingServer.material_set_param(material_rid, &"_normal_maps", RID())
		RenderingServer.material_set_param(material_rid, &"_control_maps", RID())
		
		RenderingServer.material_set_param(material_rid, &"_albedo_textures", RID())
		RenderingServer.material_set_param(material_rid, &"_normal_textures", RID())
		
		RenderingServer.material_set_param(material_rid, &"_albedo_remap", PackedInt32Array())
		RenderingServer.material_set_param(material_rid, &"_normal_remap", PackedInt32Array())
		
		RenderingServer.material_set_param(material_rid, &"_uv_scales", PackedVector2Array())
		RenderingServer.material_set_param(material_rid, &"_albedo_modulates", PackedColorArray())
		RenderingServer.material_set_param(material_rid, &"_roughness_offsets", PackedFloat32Array())
		RenderingServer.material_set_param(material_rid, &"_normal_depths", PackedFloat32Array())
		RenderingServer.material_set_param(material_rid, &"_flags", PackedInt32Array())

func _apply_instance_state():
	if not _built:
		return
	for instance_rid: RID in _instance_rids:
		RenderingServer.instance_set_scenario(instance_rid, scenario_rid)
		RenderingServer.instance_set_visible(instance_rid, visible)
		RenderingServer.instance_geometry_set_cast_shadows_setting(instance_rid, cast_shadows)
		RenderingServer.instance_set_layer_mask(instance_rid, render_layer)
		
	_snap()

func _apply_mesh_state():
	if not _built:
		return
	for mesh_rid: RID in _mesh_rids.values():
		RenderingServer.mesh_surface_set_material(mesh_rid, 0, material_rid)
	
	var height_amplitude: float = 0.1
	if source:
		height_amplitude = source.height_amplitude
	
	for type: MeshType in _mesh_rids.keys():
		var aabb := _mesh_aabbs[type]
		aabb.size.y = height_amplitude
		RenderingServer.mesh_set_custom_aabb(_mesh_rids[type], aabb)

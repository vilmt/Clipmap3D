@tool
class_name Clipmap3DMeshHandler

var lod_count: int:
	set(value):
		lod_count = value
		_meshes_need_rebuild = true
		_schedule_update()

var tile_size: Vector2i:
	set(value):
		tile_size = value
		_meshes_need_rebuild = true
		_schedule_update()

var vertex_spacing: Vector2:
	set(value):
		vertex_spacing = value
		_instances_need_update = true
		_schedule_update()

var material_rid: RID:
	set(value):
		material_rid = value
		_meshes_need_update = true
		_schedule_update()
		
var scenario_rid: RID:
	set(value):
		scenario_rid = value
		_instances_need_update = true
		_schedule_update()

var visible: bool:
	set(value):
		visible = value
		_instances_need_update = true
		_schedule_update()

var cast_shadows: RenderingServer.ShadowCastingSetting:
	set(value):
		cast_shadows = value
		_instances_need_update = true
		_schedule_update()
		
var render_layer: int:
	set(value):
		render_layer = value
		_instances_need_update = true
		_schedule_update()

var target_position: Vector3:
	set(value):
		target_position = value
		_instances_need_update = true
		_schedule_update()

var max_height: float:
	set(value):
		max_height = value

enum MeshType {
	CORE,
	TILE,
	FILL_X,
	FILL_Z,
	EDGE_X,
	EDGE_Z
}

const LOD_0_INSTANCE_COUNT: int = 19
const LOD_X_INSTANCE_COUNT: int = 18

var _mesh_rids: Dictionary[MeshType, RID]
var _mesh_aabbs: Dictionary[MeshType, AABB]

var _instance_rids: Array[RID]
var _instance_mesh_types: Array[MeshType]
var _instance_offsets: Dictionary[MeshType, PackedVector2Array]

# Edges have specific offsets depending on the parity of the target position
var _edge_x_offsets: Dictionary[Vector2i, Vector2]
var _edge_z_offsets: Dictionary[Vector2i, Vector2]

var _built: bool = false
var _meshes_need_rebuild: bool = false
var _meshes_need_update: bool = false
var _instances_need_update: bool = false

func build():
	_built = true
	_meshes_need_rebuild = true
	_meshes_need_update = true
	_instances_need_update = true
	_schedule_update()

func clear():
	_built = false
	_meshes_need_rebuild = false
	_meshes_need_update = false
	_instances_need_update = false
	_clear_instances()
	_clear_meshes()

func _schedule_update():
	_update.call_deferred()

func _update():
	if _meshes_need_rebuild:
		_clear_instances()
		_clear_meshes()
		
		_create_meshes()
		_create_instances()
		_calculate_instance_offsets()
		
		_meshes_need_update = true
		_instances_need_update = true
	if _meshes_need_update:
		_update_meshes()
	if _instances_need_update:
		_update_instances()
	
	_meshes_need_rebuild = false
	_meshes_need_update = false
	_instances_need_update = false

## Meshes

func _create_meshes():
	_create_mesh(MeshType.CORE, tile_size * 2 + Vector2i.ONE)
	_create_mesh(MeshType.TILE, tile_size)
	_create_mesh(MeshType.FILL_X, Vector2i(1, tile_size.y))
	_create_mesh(MeshType.FILL_Z, Vector2i(tile_size.x, 1))
	_create_mesh(MeshType.EDGE_X, Vector2i(1, tile_size.y * 4 + 2))
	_create_mesh(MeshType.EDGE_Z, Vector2i(tile_size.x * 4 + 1, 1))

func _update_meshes():
	if not _built:
		return
	for mesh_rid: RID in _mesh_rids.values():
		RenderingServer.mesh_surface_set_material(mesh_rid, 0, material_rid)
	
	for type: MeshType in _mesh_rids.keys():
		var aabb := _mesh_aabbs[type]
		aabb.size.y = max_height
		RenderingServer.mesh_set_custom_aabb(_mesh_rids[type], aabb)

func _clear_meshes():
	for mesh_rid: RID in _mesh_rids.values():
		if mesh_rid.is_valid():
			RenderingServer.free_rid(mesh_rid)
	_mesh_rids.clear()
	_mesh_aabbs.clear()

func _create_mesh(type: MeshType, size: Vector2i) -> void:
	var mesh_arrays: Array = []
	mesh_arrays.resize(RenderingServer.ARRAY_MAX)
	
	var vertices := PackedVector3Array()
	for z: int in size.y + 1:
		for x: int in size.x + 1:
			vertices.append(Vector3(float(x) - size.x * 0.5, 0.0, float(z) - size.y * 0.5))
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
	
	# TODO: check if this is necessary
	var tangents := PackedFloat32Array()
	tangents.resize(vertices.size() * 4)
	tangents.fill(0.0)
	mesh_arrays[RenderingServer.ARRAY_TANGENT] = tangents
	
	var mesh := RenderingServer.mesh_create()
	RenderingServer.mesh_add_surface_from_arrays(mesh, RenderingServer.PRIMITIVE_TRIANGLES, mesh_arrays)
	_mesh_rids[type] = mesh
	
	var aabb := AABB(Vector3(-size.x, 0.0, -size.y) * 0.5, Vector3(size.x, max_height, size.y))
	RenderingServer.mesh_set_custom_aabb(mesh, aabb)
	_mesh_aabbs[type] = aabb

## Instances

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

func _update_instances() -> void:
	if not _built:
		return
	
	for instance_rid: RID in _instance_rids:
		RenderingServer.instance_set_scenario(instance_rid, scenario_rid)
		RenderingServer.instance_set_visible(instance_rid, visible)
		RenderingServer.instance_geometry_set_cast_shadows_setting(instance_rid, cast_shadows)
		RenderingServer.instance_set_layer_mask(instance_rid, render_layer)
		
	# NOTE: XZ-only positions are collapsed to 2D for clean vector operations
	var world_position := Vector2(target_position.x, target_position.z)
	
	var instance_index_start: int = 0
	var instance_index_end: int = LOD_0_INSTANCE_COUNT
	
	for lod: int in lod_count:
		var lod_scale := vertex_spacing * float(1 << lod)
		var lod_position := (world_position / lod_scale).floor()
		var edge_parity := Vector2i(lod_position).abs() % 2
		
		var instance_count: Dictionary[MeshType, int] = {}
		
		for instance_index: int in range(instance_index_start, instance_index_end):
			var instance_rid := _instance_rids[instance_index]
			var type := _instance_mesh_types[instance_index]
			var count: int = instance_count.get(type, 0)
			var offset: Vector2
			match type:
				MeshType.EDGE_X:
					offset = _edge_x_offsets[edge_parity]
				MeshType.EDGE_Z:
					offset = _edge_z_offsets[edge_parity]
				_:
					offset = _instance_offsets[type][count]
			
			var instance_position := Vector3(lod_position.x + offset.x, target_position.y, lod_position.y + offset.y)
			var instance_transform := Transform3D(Basis.IDENTITY, instance_position).scaled(Vector3(lod_scale.x, 1.0, lod_scale.y))
			RenderingServer.instance_set_transform(instance_rid, instance_transform)
			RenderingServer.instance_teleport(instance_rid)
			
			if count == 0:
				instance_count[type] = 1
			else:
				instance_count[type] += 1
		
		instance_index_start = instance_index_end
		instance_index_end += LOD_X_INSTANCE_COUNT

func _clear_instances() -> void:
	for instance_rid: RID in _instance_rids:
		if instance_rid.is_valid():
			RenderingServer.free_rid(instance_rid)
	_instance_rids.clear()
	_instance_mesh_types.clear()

func _create_instance(type: MeshType) -> void:
	var instance_rid := RenderingServer.instance_create()
	RenderingServer.instance_set_base(instance_rid, _mesh_rids[type])
	_instance_rids.append(instance_rid)
	_instance_mesh_types.append(type)

func _calculate_instance_offsets() -> void:
	_instance_offsets.clear()
	_edge_x_offsets.clear()
	_edge_z_offsets.clear()

	_instance_offsets[MeshType.CORE] = PackedVector2Array([Vector2(0.5, 0.5)])
	
	_instance_offsets[MeshType.TILE] = PackedVector2Array([
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
	
	_instance_offsets[MeshType.FILL_X] = PackedVector2Array([
		Vector2(0.5, tile_size.y * 1.5 + 1.0),
		Vector2(0.5, tile_size.y * -1.5)
	])
	
	_instance_offsets[MeshType.FILL_Z] = PackedVector2Array([
		Vector2(tile_size.x * 1.5 + 1.0, 0.5),
		Vector2(tile_size.x * -1.5, 0.5)
	])
	
	_edge_x_offsets = {
		Vector2i(0, 0): Vector2(tile_size.x * 2.0 + 1.5, 1.0),
		Vector2i(1, 0): Vector2(tile_size.x * -2.0 - 0.5, 1.0),
		Vector2i(0, 1): Vector2(tile_size.x * 2.0 + 1.5, 0.0),
		Vector2i(1, 1): Vector2(tile_size.x * -2.0 - 0.5, 0.0)
	}
	
	_edge_z_offsets = {
		Vector2i(0, 0): Vector2(0.5, tile_size.y * 2.0 + 1.5),
		Vector2i(1, 0): Vector2(0.5, tile_size.y * 2.0 + 1.5),
		Vector2i(0, 1): Vector2(0.5, tile_size.y * -2.0 - 0.5),
		Vector2i(1, 1): Vector2(0.5, tile_size.y * -2.0 - 0.5)
	}

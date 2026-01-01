extends Node3D

const MAX_RINGS: int = 20

# TODO: specify smallest division instead of max lod. 

@export var amplitude: float = 100.0

## World size of chunks. Does not affect subdivisions or LODs.
@export var chunk_size := Vector2(64.0, 64.0)

## Index = ring LOD, value = ring thickness in chunks. Highest LOD determines subdivisions.
@export var lod_rings: PackedInt32Array = [2, 2, 3, 3, 4]

@export var chunk_material: ShaderMaterial

var _chunk_rids: Array[RID]
var _chunk_meshes: Array[Mesh]

func _ready():
	var lods := PackedInt32Array()
	lods.resize(MAX_RINGS)
	lods.fill(lod_rings.size() - 1)
	
	var i: int = 0
	for lod: int in lod_rings.size():
		var thickness := lod_rings[lod]
		for j: int in thickness:
			lods[i] = lod
			i += 1
	
	print(lods)
	
	if not chunk_material:
		push_error("Chunk material unassigned.")
		return
	
	chunk_material.set_shader_parameter(&"amplitude", amplitude)
	chunk_material.set_shader_parameter(&"chunk_size", chunk_size)
	chunk_material.set_shader_parameter(&"lods", lods)
	chunk_material.set_shader_parameter(&"max_lod", lod_rings.size() - 1)
	
	generate_terrain()

func _exit_tree() -> void:
	for rid: RID in _chunk_rids:
		RenderingServer.free_rid(rid)

func generate_terrain():
	var scenario := get_world_3d().scenario
	var max_lod := lod_rings.size() - 1
	
	var cumulative_thickness: int = 0
	
	for ring_lod: int in lod_rings.size():
		var ring_thickness := lod_rings[ring_lod]
		if ring_thickness <= 0:
			continue
		
		var vertices_per_chunk_edge := 1 << maxi(0, max_lod - ring_lod)
		
		if ring_lod == 0:
			# Central core plane mesh
			var ring_diameter: int = ring_thickness * 2 - 1
			var subdivisions := vertices_per_chunk_edge * ring_diameter - 1 
			var size := ring_diameter * chunk_size
			
			var bottom_corner := Vector3(-size.x, 0.0, -size.y) / 2.0
			var top_corner := Vector3(size.x, amplitude, size.y)
			var custom_aabb := AABB(bottom_corner, top_corner)
	
			var mesh := _create_chunk_mesh(size, Vector2i(subdivisions, subdivisions))
			
			var rid := RenderingServer.instance_create2(mesh, scenario)
			RenderingServer.instance_set_transform(rid, Transform3D(Basis.IDENTITY, Vector3.ZERO))
			RenderingServer.instance_set_custom_aabb(rid, custom_aabb)
			_chunk_rids.append(rid)
			
			cumulative_thickness += ring_diameter
		else:
			var tangential_length: int = cumulative_thickness + ring_thickness
			var radial_length: int = ring_thickness
			
			var tangential_offset: float = (cumulative_thickness - tangential_length) / 2.0
			var radial_offset: float = (cumulative_thickness + radial_length) / 2.0
			
			var z_chunks := Vector2i(tangential_length, radial_length)
			var x_chunks := Vector2i(radial_length, tangential_length)
			
			var z_size := Vector2(z_chunks) * chunk_size
			var x_size := Vector2(x_chunks) * chunk_size
			
			var z_bottom_corner := Vector3(-z_size.x, 0.0, -z_size.y) / 2.0
			var z_top_corner := Vector3(z_size.x, amplitude, z_size.y)
			var z_custom_aabb := AABB(z_bottom_corner, z_top_corner)
			
			var x_bottom_corner := Vector3(-x_size.x, 0.0, -x_size.y) / 2.0
			var x_top_corner := Vector3(x_size.x, amplitude, x_size.y)
			var x_custom_aabb := AABB(x_bottom_corner, x_top_corner)
			
			var z_coordinates := Vector2(-tangential_offset, radial_offset) * chunk_size
			var z_position := Vector3(z_coordinates.x, 0.0, z_coordinates.y)
			
			var x_coordinates := Vector2(radial_offset, tangential_offset) * chunk_size
			var x_position := Vector3(x_coordinates.x, 0.0, x_coordinates.y)
			
			var z_subdivisions := z_chunks * vertices_per_chunk_edge - Vector2i.ONE
			var x_subdivisions := x_chunks * vertices_per_chunk_edge - Vector2i.ONE
		
			var z_mesh := _create_chunk_mesh(z_size, z_subdivisions)
			
			var pos_z_rid := RenderingServer.instance_create2(z_mesh, scenario)
			RenderingServer.instance_set_transform(pos_z_rid, Transform3D(Basis.IDENTITY, z_position))
			RenderingServer.instance_set_custom_aabb(pos_z_rid, z_custom_aabb)
			_chunk_rids.append(pos_z_rid)
			var neg_z_rid := RenderingServer.instance_create2(z_mesh, scenario)
			RenderingServer.instance_set_transform(neg_z_rid, Transform3D(Basis(Vector3.UP, PI), -z_position))
			RenderingServer.instance_set_custom_aabb(neg_z_rid, z_custom_aabb)
			_chunk_rids.append(neg_z_rid)
			
			var x_mesh := _create_chunk_mesh(x_size, x_subdivisions)
			
			var pos_x_rid := RenderingServer.instance_create2(x_mesh, scenario)
			RenderingServer.instance_set_transform(pos_x_rid, Transform3D(Basis.IDENTITY, x_position))
			RenderingServer.instance_set_custom_aabb(pos_x_rid, x_custom_aabb)
			_chunk_rids.append(pos_x_rid)
			var neg_x_rid := RenderingServer.instance_create2(x_mesh, scenario)
			RenderingServer.instance_set_transform(neg_x_rid, Transform3D(Basis.IDENTITY, -x_position))
			RenderingServer.instance_set_custom_aabb(neg_x_rid, x_custom_aabb)
			_chunk_rids.append(neg_x_rid)

			cumulative_thickness += ring_thickness * 2

func _create_chunk_mesh(size: Vector2, subdivisions: Vector2i) -> Mesh:
	var mesh := PlaneMesh.new()
	mesh.size = size
	mesh.subdivide_width = subdivisions.x
	mesh.subdivide_depth = subdivisions.y
	mesh.material = chunk_material
	_chunk_meshes.append(mesh)
	return mesh

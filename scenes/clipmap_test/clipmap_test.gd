extends Node3D

const MAX_RINGS: int = 20

@export var amplitude: float = 100.0

@export var lod_0_vertex_resolution: int = 64

## World size of chunks. Does not affect subdivisions or LODs.
@export var chunk_size := Vector2(64.0, 64.0)

## Index = ring LOD, value = ring thickness in chunks.
@export var lod_rings: Array[int] = [1, 1, 1, 1, 1]

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
	chunk_material.set_shader_parameter(&"lod_0_vertex_resolution", lod_0_vertex_resolution)
	
	generate_terrain()

func _exit_tree() -> void:
	for rid: RID in _chunk_rids:
		RenderingServer.free_rid(rid)

func generate_terrain():
	var scenario := get_world_3d().scenario
	
	var cumulative_thickness: int = 0
	
	for ring_lod: int in lod_rings.size():
		var ring_thickness := lod_rings[ring_lod]
		if ring_thickness <= 0:
			continue
		
		var vertices_per_side: float = float(lod_0_vertex_resolution) / pow(2.0, float(ring_lod));
		#var vertices_per_chunk_edge := 1 << maxi(0, max_lod - ring_lod)
		
		if ring_lod == 0:
			var ring_diameter: int = ring_thickness * 2 - 1
			var subdivisions := roundi(vertices_per_side * ring_diameter - 1) 
			var size := ring_diameter * chunk_size
			
			var bottom_corner := Vector3(-size.x, 0.0, -size.y) / 2.0
			var top_corner := Vector3(size.x, amplitude, size.y)
			var custom_aabb := AABB(bottom_corner, top_corner)
			
			var mesh := PlaneMesh.new()
			mesh.size = size
			mesh.subdivide_width = subdivisions
			mesh.subdivide_depth = subdivisions
			mesh.material = chunk_material
			_chunk_meshes.append(mesh)
			
			var rid := RenderingServer.instance_create2(mesh, scenario)
			RenderingServer.instance_set_transform(rid, Transform3D.IDENTITY)
			RenderingServer.instance_set_custom_aabb(rid, custom_aabb)
			_chunk_rids.append(rid)
			
			cumulative_thickness += ring_diameter
		else:
			var radial_chunks: int = ring_thickness
			var tangential_chunks: int = cumulative_thickness + radial_chunks

			var radial_coordinate: float = cumulative_thickness * 0.5 + 0.5

			var radial_size: Vector2 = radial_chunks * chunk_size
			var tangential_size: Vector2 = tangential_chunks * chunk_size
			
			# rounding since there can be less than 1 vertex per side -> float
			var radial_subdivisions: int = roundi(radial_chunks * vertices_per_side - 1)
			var tangential_subdivisions: int = roundi(tangential_chunks * vertices_per_side - 1)
			
			_create_ring_axis(
				scenario,
				Vector3(0.0, 0.0, radial_coordinate * chunk_size.y),
				Vector2(tangential_size.x, radial_size.y),
				Vector2i(tangential_subdivisions, radial_subdivisions),
				Vector3(
					-(tangential_chunks - cumulative_thickness) * 0.5 * chunk_size.x, # rotate rather than mirror over xz
					0,
					(radial_chunks * 0.5 - 0.5) * chunk_size.y
				)
			)
			
			_create_ring_axis(
				scenario,
				Vector3(radial_coordinate * chunk_size.x, 0.0, 0.0),
				Vector2(radial_size.x, tangential_size.y),
				Vector2i(radial_subdivisions, tangential_subdivisions),
				Vector3(
					(radial_chunks * 0.5 - 0.5) * chunk_size.x,
					0,
					(tangential_chunks - cumulative_thickness) * 0.5 * chunk_size.y
				)
			)

			cumulative_thickness += ring_thickness * 2

func _create_ring_axis(scenario: RID, p: Vector3, s: Vector2, subdivisions: Vector2i, c: Vector3):
	var pos_mesh := PlaneMesh.new()
	pos_mesh.size = s
	pos_mesh.subdivide_width = subdivisions.x
	pos_mesh.subdivide_depth = subdivisions.y
	pos_mesh.center_offset = c
	pos_mesh.material = chunk_material
	_chunk_meshes.append(pos_mesh)
	
	var neg_mesh: PlaneMesh = pos_mesh.duplicate()
	neg_mesh.center_offset = -c
	_chunk_meshes.append(neg_mesh)
	
	var pos_aabb = AABB(Vector3(-s.x, 0.0, -s.y) / 2.0 + c, Vector3(s.x, amplitude, s.y))
	var neg_aabb = AABB(Vector3(-s.x, 0.0, -s.y) / 2.0 - c, Vector3(s.x, amplitude, s.y))
	
	var pos_rid := RenderingServer.instance_create2(pos_mesh, scenario)
	RenderingServer.instance_set_transform(pos_rid, Transform3D(Basis.IDENTITY, p))
	RenderingServer.instance_set_custom_aabb(pos_rid, pos_aabb)
	_chunk_rids.append(pos_rid)
	
	var neg_rid := RenderingServer.instance_create2(neg_mesh, scenario)
	RenderingServer.instance_set_transform(neg_rid, Transform3D(Basis.IDENTITY, -p))
	RenderingServer.instance_set_custom_aabb(neg_rid, neg_aabb)
	_chunk_rids.append(neg_rid)

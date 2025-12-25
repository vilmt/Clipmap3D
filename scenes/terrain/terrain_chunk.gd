@tool
extends MeshInstance3D
class_name TerrainChunk

func prepare_mesh(size: Vector2, subdivisions: int):
	mesh = PlaneMesh.new()
	mesh.size = size
	
	mesh.subdivide_width = subdivisions
	mesh.subdivide_depth = subdivisions

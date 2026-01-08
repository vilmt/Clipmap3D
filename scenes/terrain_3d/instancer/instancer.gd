@tool
class_name Terrain3DInstancer extends Node3D

@export var terrain: Terrain3D:
	set(value):
		if terrain == value:
			return
		if terrain:
			terrain.position_changed.disconnect(reposition)
		terrain = value
		if not is_node_ready():
			return
		if terrain:
			terrain.position_changed.connect(reposition)
		
@export var rows_and_columns := Vector2i.ONE:
	set(value):
		if rows_and_columns == value:
			return
		rows_and_columns = value
		if not is_node_ready():
			return
		for particles_rid: RID in _particles_rids:
			RenderingServer.particles_set_amount(particles_rid, rows_and_columns.x * rows_and_columns.y)
		if process_material:
			RenderingServer.material_set_param(process_material.get_rid(), &"rows_and_columns", rows_and_columns)

@export var instance_spacing := Vector2.ONE:
	set(value):
		if instance_spacing == value:
			return
		instance_spacing = value
		if not is_node_ready():
			return
		if process_material:
			RenderingServer.material_set_param(process_material.get_rid(), &"instance_spacing", instance_spacing)

@export_range(1, 240) var fixed_fps: int = 60:
	set(value):
		if fixed_fps == value:
			return
		fixed_fps = value
		if not is_node_ready():
			return
		for particles_rid: RID in _particles_rids:
			RenderingServer.particles_set_fixed_fps(particles_rid, fixed_fps)

@export var process_material: ShaderMaterial

@export var mesh: Mesh


var _particles_rids: Array[RID]
var _instance_rids: Array[RID]

func _ready() -> void:
	if not mesh:
		return
	var particles_rid := RenderingServer.particles_create()
	
	if process_material:
		print("set process material")
		var material_rid := process_material.get_rid()
		RenderingServer.material_set_param(material_rid, &"rows_and_columns", rows_and_columns)
		RenderingServer.material_set_param(material_rid, &"instance_spacing", instance_spacing)
		RenderingServer.particles_set_process_material(particles_rid, material_rid)
	
	RenderingServer.particles_set_amount(particles_rid, rows_and_columns.x * rows_and_columns.y)
	RenderingServer.particles_set_draw_passes(particles_rid, 1)
	RenderingServer.particles_set_draw_pass_mesh(particles_rid, 0, mesh.get_rid())
	RenderingServer.particles_set_lifetime(particles_rid, 1.0)
	RenderingServer.particles_set_explosiveness_ratio(particles_rid, 1.0)
	RenderingServer.particles_set_amount_ratio(particles_rid, 1.0)
	var size := Vector3(100, 100, 100)
	RenderingServer.particles_set_custom_aabb(particles_rid, AABB(-size / 2.0, size))
	RenderingServer.particles_set_fixed_fps(particles_rid, fixed_fps)
	RenderingServer.particles_set_emitting(particles_rid, true)
	
	var instance_rid := RenderingServer.instance_create2(particles_rid, get_world_3d().scenario)
	RenderingServer.instance_set_transform(instance_rid, Transform3D.IDENTITY)
	
	print("created")
	
	_particles_rids.append(particles_rid)
	_instance_rids.append(instance_rid)
	
	if terrain:
		terrain.position_changed.connect(reposition)

func _exit_tree() -> void:
	for rid: RID in _instance_rids + _particles_rids:
		RenderingServer.free_rid(rid)

func reposition(at: Vector3):
	if process_material:
		RenderingServer.material_set_param(process_material.get_rid(), &"camera_position", at)

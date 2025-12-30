@tool
extends Node3D

var rid: RID
var mesh := BoxMesh.new()

func _ready():
	rid = RenderingServer.instance_create()
	RenderingServer.instance_set_base(rid, mesh.get_rid())
	RenderingServer.instance_set_transform(rid, Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, 0.0)))
	
	if Engine.is_editor_hint():
		RenderingServer.instance_set_scenario(rid, EditorInterface.get_editor_viewport_3d().find_world_3d().scenario)
		#print(EditorInterface.get_editor_viewport_3d().find_world_3d())
	else:
		RenderingServer.instance_set_scenario(rid, get_world_3d().scenario)
		
func _exit_tree() -> void:
	RenderingServer.free_rid(rid)

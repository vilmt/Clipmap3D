extends Node

@export var clipmap: Clipmap3D
@export var material_a: ShaderMaterial
@export var material_b: ShaderMaterial

@onready var label: Label = $Label

const INTRO := "Current material: "

func _ready() -> void:
	label.text = INTRO + "A"

func _unhandled_key_input(event: InputEvent) -> void:
	if not clipmap:
		return
	
	if event.is_action_pressed("switch_material"):
		if clipmap.material == material_a:
			clipmap.material = material_b
			label.text = INTRO + "B"
		else:
			clipmap.material = material_a
			label.text = INTRO + "A"
